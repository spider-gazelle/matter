require "../network/*"
require "../utilities/*"
require "random"

module Matter
  module MDNS
    class Server
      Log = ::Log.for(self)

      alias DNSCodec = Codec::DNSCodec
      alias Interface = Socket::IPAddress | UInt32

      include DNSCodec::Base
      include Utilities::DeepEqual

      getter multicast_server : Network::MulticastServer

      def initialize(address : Socket::IPAddress = Network::MulticastServer::IPv4, buffer_size = 16, loopback = false, hops = 255)
        Log.debug { "Creating the multicast server" }

        # Assign the multicast server
        @multicast_server = Network::MulticastServer.new(address, buffer_size, loopback, hops)

        @records_generator = {} of String => (Interface) -> Array(DNSCodec::Record)

        @records = Utilities::Cache(Hash(String, Array(DNSCodec::Record))).new(
          ->(interface : Interface) do
            port_type_map = {} of String => Array(DNSCodec::Record)

            @records_generator.each do |announce_type_port, generator|
              port_type_map[announce_type_port] = generator.call(interface)
            end

            port_type_map
          end,
          # 15mn - also matches maximum commissioning window time.
          15 * 60 * 1000
        )

        @record_last_sent_as_multicast_answer = Hash(String, Int32).new

        Log.debug { "Listening to incomming packets" }

        spawn do
          # https://tools.ietf.org/html/rfc6762#section-17
          buffer = Slice(UInt8).new(9000)

          loop do
            break if multicast_server.socket.closed?

            size, address = multicast_server.socket.receive(buffer)
            break if size == 0

            message_slice = buffer[0..size].clone
            handle_dns_message(address, message_slice)

            # as per DNS-SD spec wait 20-120ms before sending more packets
            sleep (20 + (rand(100) / 1000.0).floor).seconds
          end
        end
      end

      def add_records_generator(port : Int32, type : AnnouncementType, generator : (Interface) -> Array(DNSCodec::Record))
        @records.clear
        @record_last_sent_as_multicast_answer.clear

        @records_generator[build_type_port_key(port, type)] = generator
      end

      def announce(interface : Interface, announced_net_port : Int32? = nil)
        records = @records.get(interface)

        Log.debug { "Getting records for #{interface} "}

        records.each do |key, value|
          if announced_net_port.nil? != true && key_for_port?(key, announced_net_port) != true
            next
          end

          # TODO: try to combine the messages to avoid sending multiple messages but keep under 1500 bytes per message
          announce_records_for_interface(interface, value)
        end
      end

      def expire_announcements(announced_net_port : Int32? = nil, type : AnnouncementType? = nil)
        @records.keys.map do |interface|
          records = @records.get(interface)

          records.each do |key, value|
            next unless announced_net_port.nil? && key_for_port?(key, announced_net_port)
            next unless announced_net_port.nil? && type.nil? && key == build_type_port_key(type, announced_net_port)

            instance_name = String.new

            value.each do |record|
              record.ttl = 0_u32

              if instance_name.nil? && record.record_type == DNSCodec::RecordType::TXT
                instance_name = record.name
              end
            end

            Log.debug { "Expiring records #{instance_name}, #{announced_net_port}, #{interface}" }

            announce_records_for_interface(interface, value)
            @records_generator.delete(key)
          end
        end

        @records.clear
        @record_last_sent_as_multicast_answer.clear
      end

      def close
        @records.close
        @record_last_sent_as_multicast_answer.clear
        multicast_server.close
      end

      private def build_type_port_key(port : Int32, type : AnnouncementType) : String
        "#{port}-#{type}"
      end

      private def key_for_port?(key : String, port : Int32) : Bool
        key.includes?("#{port}-")
      end

      private def build_dns_record_key(record : DNSCodec::Record, interface : Interface)
        "#{record.name}-#{record.record_class}-#{record.record_type}-#{interface}"
      end

      private def handle_dns_message(address : Socket::IPAddress, message_slice : Slice(UInt8))

        Log.debug { "Received a message from (#{address}), (#{message_slice.size})" }

        interface = address.family.inet? ? Network::Constants::DEFAULT_INTERFACE_IPV4 : Network::Constants::DEFAULT_INTERFACE_IPV6
        interface_records = @records.get(interface)

        # TODO: Return DNS message processing under this line to avoid load
        if interface_records.size == 0
          Log.info { "DROPPING: No records found for the interface, (#{interface})" }
          return
        end

        message = decode(message_slice)

        Log.debug { "Decoded a message (#{message.to_json})" }

        if message.nil?
          Log.info { "DROPPING: An exception occured while decoding the message" }
          return
        end

        if message.message_type != DNSCodec::MessageType::Query && message.message_type != DNSCodec::MessageType::TruncatedQuery
          Log.info { "DROPPING: Message type did not match" }
          return
        end

        if message.queries.size == 0
          Log.info { "DROPPING: No queries were present in the message" }
          return
        end

        interface_records.values.each do |port_records|
          answers = (message.queries.flat_map do |query|
            query_records(query, port_records)
          end)

          additional_records =
            message.queries.find { |query| query.record_type != DNSCodec::RecordType::A || query.record_type != DNSCodec::RecordType::AAAA } ? port_records.reject { |port_record| !answers.includes?(port_record) && port_record.record_type != DNSCodec::RecordType::PTR } : [] of DNSCodec::Record

          message.answers.each do |known_answer|
            answers = (answers.reject do |answer|
              deep_equal?(answer.to_h, known_answer.to_h)

              break if answers.size == 0
            end) || [] of DNSCodec::Record
          end

          next if answers.size == 0

          if additional_records.size > 0
            message.answers.each do |known_answer|
              additional_records = additional_records.reject { |additional_record| deep_equal?(additional_record.to_h, known_answer.to_h) }
            end
          end

          now = Time.local.to_unix_ms

          unicast_response = (message.queries.reject do |query|
            !query.unicast_response?
          end).size == 0

          answers_time_since_last_multicast = answers.map do |answer|
            {"timeSinceLastMulticast" => now - @record_last_sent_as_multicast_answer[build_dns_record_key(answer, interface)] || 0, "ttl" => answer.ttl}
          end

          if (unicast_response && (answers_time_since_last_multicast.reject do |answer_time|
               answer_time["timeSinceLastMulticast"] < (answer_time["ttl"] / 4) * 100
             end).size > 0)
            # If the query is for unicast response, still send as multicast if they were last sent as multicast longer then 1/4 of their ttl
            unicast_response = false
          end

          unless unicast_response
            answers = answers.reject do |answer|
              index = answers.index(answer)

              next if index.nil?
              answers_time_since_last_multicast[index]["timeSinceLastMulticast"] < 1000
            end

            next if answers.size == 0

            answers.each do |answer|
              @record_last_sent_as_multicast_answer[build_dns_record_key(answer, interface)]
            end
          end

          message = DNSCodec::Message.new(
            transaction_id: message.transaction_id,
            message_type: DNSCodec::MessageType::Response,
            queries: [] of DNSCodec::Query,
            answers: answers,
            authorities: [] of DNSCodec::Record,
            additional_records: additional_records)

          send_records(message, interface, unicast_response ? address : nil)
        end
      end

      private def send_records(message : DNSCodec::Message, interface : Interface, unicast_target : Socket::IPAddress? = nil)
        answers_to_send = [] of DNSCodec::Record + message.answers
        additional_records_to_send = [] of DNSCodec::Record + message.additional_records

        message_to_send = DNSCodec::Message.new(
          transaction_id: message.transaction_id,
          message_type: message.message_type,
          queries: [] of DNSCodec::Query,
          answers: [] of DNSCodec::Record,
          authorities: [] of DNSCodec::Record,
          additional_records: [] of DNSCodec::Record
        )

        empty_dns_message = encode(message_to_send)
        dns_message_size = empty_dns_message.size

        while true
          if answers_to_send.size > 0
            next_answer = answers_to_send.shift

            next_answer_encoded = encode_record(next_answer)
            dns_message_size += next_answer_encoded.size

            if dns_message_size > DNSCodec::MAX_MDNS_MESSAGE_SIZE
              encoded_message_to_send = encode(message_to_send)

              Log.debug { "Encoded the message and sending it to the interface" }

              if unicast_target
                multicast_server.socket.send(encoded_message_to_send, to: unicast_target)
              else
                multicast_server.socket.send(encoded_message_to_send, to: interface.as(Socket::IPAddress))
              end
            end
          else
            break
          end
        end

        additional_records_to_send.each do |additional_record|
          additional_record_encoded = encode_record(additional_record)
          dns_message_size += additional_record_encoded.size

          if dns_message_size > DNSCodec::MAX_MDNS_MESSAGE_SIZE
            break
          end

          message_to_send.additional_records.push(additional_record)
        end

        encoded_message_to_send = encode(message_to_send)

        if unicast_target
          multicast_server.socket.send(encoded_message_to_send, to: unicast_target)
        else
          multicast_server.socket.send(encoded_message_to_send, to: interface.as(Socket::IPAddress))
        end
      end

      private def announce_records_for_interface(interface : Interface, records : Array(DNSCodec::Record))
        Log.debug { "Announcing records (#{records.to_json}) for interface (#{interface})" }

        answers = records.reject { |record| record.record_type != DNSCodec::RecordType::PTR }
        additional_records = records.reject { |record| record.record_type == DNSCodec::RecordType::PTR }

        message = DNSCodec::Message.new(
          transaction_id: 0_u16,
          message_type: DNSCodec::MessageType::Response,
          queries: [] of DNSCodec::Query,
          answers: answers,
          authorities: [] of DNSCodec::Record,
          additional_records: additional_records)

        send_records(message, interface)
      end

      private def query_records(query : DNSCodec::Query, port_records : Array(DNSCodec::Record)) : Array(DNSCodec::Record)
        if query.record_type == DNSCodec::RecordType::ANY
          return port_records.reject { |port_record| port_record.name != query.name }
        end

        port_records.reject { |port_record| port_record.name != query.name && port_record != query.record_type }
      end
    end
  end
end
