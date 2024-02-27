require "../../network/*"
require "../utilities/*"
require "random"

module Matter
  module MDNS
    class Server
      alias DNSCodec = Codec::DNSCodec

      include DNSCodec::Base
      include Utilities::DeepEqual

      PORT = 5353
      IPv4 = Socket::IPAddress.new("224.0.0.251", PORT)
      IPv6 = Socket::IPAddress.new("FF02::FB", PORT)

      def initialize(address : Socket::IPAddress = IPv4, buffer_size = 16, loopback = false, hops = 255)
        @multicast_server = Network::MulticastServer.new(address, buffer_size, loopback, hops)

        @records_generator = {} of String => (String) -> Array(DNSCodec::Record)

        @records = Utilities::Cache(Hash(String, Array(DNSCodec::Record))).new(
          ->(multicast_interface : String) do
            port_type_map = {} of String => Array(DNSCodec::Record)

            @records_generator.each do |announce_type_port, generator|
              port_type_map[announce_type_port] = generator.call(multicast_interface)
            end

            port_type_map
          end,
          # 15mn - also matches maximum commissioning window time.
          15 * 60 * 1000
        )

        @record_last_sent_as_multicast_answer = Hash(String, Int32).new

        spawn do
          # https://tools.ietf.org/html/rfc6762#section-17
          buffer = Slice(UInt8).new(9000)

          loop do
            break if @multicast_server.socket.closed?

            size, address = @multicast_server.socket.receive(buffer)
            break if size == 0

            message_slice = buffer[0..size].clone
            handle_dns_message(address, message_slice)

            # as per DNS-SD spec wait 20-120ms before sending more packets
            sleep (20 + (rand(100) / 1000.0).floor).seconds
          end
        end
      end

      def add_records_generator(port : Int32, type : AnnouncementType, generator : (String) -> Array(DNSCodec::Record))
        @records.clear
        @record_last_sent_as_multicast_answer.clear

        @records_generator[build_type_port_key(port, type)] = generator
      end

      def close
        @records.close
        @record_last_sent_as_multicast_answer.clear
        @multicast_server.close
      end

      private def build_type_port_key(type : AnnouncementType, port : Int32) : String
        "#{port}-#{type}"
      end

      private def key_for_port?(key : String, port : Int32) : Bool
        key.includes?("#{port}-")
      end

      private def handle_dns_message(address : Socket::IPAddress, message_slice : Slice(UInt8), interface : String = "default")
        interface_records = @records.get([@multicast_server.default_interface.to_s])

        # No need to process the DNS message if there are no records to serve
        return if interface_records.size == 0

        message = decode(message_slice)

        return if message.nil?
        return if message.message_type != DNSCodec::MessageType::Query && message.message_type != DNSCodec::MessageType::TruncatedQuery
        return if message.queries.size == 0

        interface_records.values.each do |port_records|
          answers = (message.queries.flat_map do |query|
            query_records(query, port_records)
          end)

          additional_records =
            message.queries.find { |query| query.record_type != DNSCodec::RecordType::A || query.record_type != DNSCodec::RecordType::AAAA } ? port_records.reject { |port_record| !answers.includes?(port_record) && port_record.record_type != DNSCodec::RecordType::PTR } : [] of DNSCodec::Record

          message.answers.each do |known_answer|
            answers = (answers.reject do |answer|
              deep_equal?(answer, known_answer)

              break if answers.size == 0
            end) || [] of DNSCodec::Record
          end

          next if answers.size == 0

          if additional_records.size > 0
            message.answers.each do |known_answer|
              additional_records = additional_records.reject { |additional_record| deep_equal?(additional_record, known_answer) }
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

          send_records(message, @multicast_server.default_interface, unicast_response ? address : nil)
        end
      end

      def announce_records_for_interface(interface : Socket::IPAddress | UInt32, record : Array(DNSCodec::Record))
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

      private def send_records(message : DNSCodec::Message, interface : Socket::IPAddress | UInt32, unicast_target : Socket::IPAddress? = nil)
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

              if unicast_target
                @multicast_server.socket.send(encoded_message_to_send, to: unicast_target)
              else
                @multicast_server.socket.send(encoded_message_to_send, to: interface.as(Socket::IPAddress))
              end
            end
          end
        end
      end

      private def build_dns_record_key(record : DNSCodec::Record, interface : String)
        "#{record.name}-#{record.record_class}-#{record.record_type}-#{interface}"
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
