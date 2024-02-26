module Matter
  module MDNS
    class Server
      alias DNSCodec = Codec::DNSCodec

      include DNSCodec::Base

      PORT = 5353
      IPv4 = Socket::IPAddress.new("224.0.0.251", PORT)
      IPv6 = Socket::IPAddress.new("FF02::FB", PORT)

      def initialize(@address : Socket::IPAddress = IPv4, buffer_size = 16, loopback = false, hops = 255)
        # Select the default interface
        @interface = @address.family.inet? ? Socket::IPAddress.new("0.0.0.0", 10222) : 0_u32

        @socket = UDPSocket.new @address.family
        @socket.reuse_address = true
        @socket.reuse_port = true
        @socket.bind(@address.family.inet? ? Socket::IPAddress::UNSPECIFIED : Socket::IPAddress::UNSPECIFIED6, @address.port)
        @socket.multicast_interface(@interface)
        @socket.join_group(@address)
        @socket.multicast_loopback = loopback
        @socket.multicast_hops = hops

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
            break if @socket.closed?

            size, address = @socket.receive(buffer)
            break if size == 0

            message_slice = buffer[0..size].clone
            handle_dns_message(address, message_slice)
          end
        end
      end

      def handle_dns_message(address : Socket::IPAddress, message_slice : Slice(UInt8))
        interface_records = @records.get(["default"])

        # No need to process the DNS message if there are no records to serve
        return if interface_records.size == 0

        message = decode(message_slice)

        return if message.nil?
        return if message.message_type != DNSCodec::MessageType::Query || message.message_type != DNSCodec::MessageType::TruncatedQuery
        return if message.queries.size == 0

        interface_records.values.each do |port_records|
          answers = message.queries.map do |query|
            query_records(query, port_records)
          end

          additional_records =
            message.queries.find { |query| query.record_type != DNSCodec::RecordType::A && query.record_type != DNSCodec::RecordType::AAAA } ? port_records.reject { |port_record| !answers.includes?(port_record) && port_record.record_type != DNSCodec::RecordType::PTR } : [] of DNSCodec::Record

          message.answers.each do |known_answer|
            answers = answers.reject do |answer|
              deep_equal?(answer, known_answer)

              break if answers.size == 0
            end
          end

          next if answers.size == 0

          if additional_records.size > 0
            message.answers.each do |known_answer|
              additional_records = additional_records.reject { |additional_record| deep_equal?(additional_record, known_answer) }
            end
          end
        end

        now = Time.local.to_unix_ms

        unicast_response = message.queries.reject(&.unicast_response?).size == 0

        # TODO: Implement ways to broadcast DNS messages which query our device.
      end

      private def query_records(query : DNSCodec::Query, port_records : Array(DNSCodec::Record))
        if query.record_type == DNSCodec::RecordType::ANY
          port_records.reject { |port_record| port_record.name != query.name }
        else
          port_records.reject { |port_record| port_record.name != query.name && port_record != query.record_type }
        end
      end
    end
  end
end
