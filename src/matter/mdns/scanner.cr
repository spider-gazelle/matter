module Matter
  module MDNS
    class Scanner
      Log = ::Log.for(self)

      alias DNSCodec = Codec::DNSCodec
      alias Interface = Socket::IPAddress

      include DNSCodec::Base

      START_ANNOUNCE_INTERVAL_SECONDS = 1.5

      private getter? closing : Bool = false

      private getter server : Network::MulticastServer
      private getter active_announce_queries : Hash(String, DNSCodec::Query | DNSCodec::Record) = {} of String => DNSCodec::Query | DNSCodec::Record

      private getter query_timer : Channel(Bool) = Channel(Bool).new

      def initialize(address : Socket::IPAddress = Network::Constants::MDNS_ADDRESS_IPv4, buffer_size = 16, loopback = false, hops = 255)
        Log.debug { "Creating the multicast server" }

        # Assign the multicast server
        @server = Network::MulticastServer.new(address, buffer_size, loopback, hops)

        spawn do
          # https://tools.ietf.org/html/rfc6762#section-17
          buffer = Slice(UInt8).new(9000)

          loop do
            break if server.socket.closed?

            size, address = server.socket.receive(buffer)

            Log.debug { "Received a connection from (#{address})" }

            break if size == 0

            message_slice = buffer[0..size].clone
            handle_dns_message(address, message_slice)
          end
        end
      end

      private def handle_dns_message(address : Socket::IPAddress, message_slice : Slice(UInt8))
        interface = address.family.inet? ? Network::Constants::MDNS_ADDRESS_IPv4 : Network::Constants::MDNS_ADDRESS_IPv6

        return if closing?

        message = decode(message_slice)

        # The message cannot be parsed
        return if message.nil?

        return if message.message_type != DNSCodec::MessageType::Response || message.message_type != DNSCodec::MessageType::TruncatedResponse

        answers = message.answers + message.additional_records

        # Check if we got operational discovery records and handle them
        return if handle_operational_records(answers, get_active_query_earlier_answers)

        # Else check if we got commissionable discovery records and handle them
        handle_commissionable_records(answers, get_active_query_earlier_answers)
      end

      private def handle_operational_records(answers : Array(DNSCodec::Record), former_answers : Array(DNSCodec::Record)) : Bool
        records_handled = false

        operational_txt_record = answers.find { |answer| answer.record_type == DNSCodec::RecordType::TXT && answer.name.ends_with?(Constants::MATTER_SERVICE_QNAME) }

        unless operational_txt_record.nil?
          handle_operational_txt_record(operational_txt_record)
          records_handled = true
        end

        operational_srv_record =
          (answers.find { |answer| answer.record_type = DNSCodec::RecordType::SRV && answer.name.ends_with?(Constants::MATTER_SERVICE_QNAME) }) ||
            (former_answers.find { |answer| answer.record_type = DNSCodec::RecordType::SRV && answer.name.ends_with?(Constants::MATTER_SERVICE_QNAME) })

        unless operational_srv_record.nil?
          handle_operational_srv_record(operational_srv_record, answers, former_answers)
          records_handled = true
        end

        records_handled
      end

      private def handle_operational_txt_record(operational_record : DNSCodec::Record)
        if operational_record.ttl == 0

        end
      end

      # Remove a query from the list of active queries because discovery has finished or timed out and stop sending it
      # out. If it was the last query announcing will stop completely.
      private def remove_query(query_id : String)
        active_announce_queries.delete(query_id)

        if active_announce_queries.size == 0
          Log.debug { "Removing last query #{query_id} and stopping announce timer" }

          query_timer.send(true)
          @next_announce_interval_seconds = START_ANNOUNCE_INTERVAL_SECONDS
        else
          Log.debug { "Removing query #{query_id}" }
        end
      end

      private def get_active_query_earlier_answers
        active_announce_queries.values.flat_map { |query| query.answers }
      end
    end
  end
end
