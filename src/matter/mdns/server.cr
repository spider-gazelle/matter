require "dns"
require "log"
require "./multicast_socket"

module Matter
  module MDNS
    # RecordGenerator interface for generating DNS records dynamically
    #
    # Implementations provide the records to be advertised/responded for a service.
    abstract class RecordGenerator
      # Get all records for this service
      abstract def records : Array(DNS::Packet::ResourceRecord)

      # Get the service instance name (e.g., "A1B2C3D4._matterc._udp.local")
      abstract def instance_name : String

      # Check if this generator handles a specific query name
      def handles?(query_name : String) : Bool
        query_lowercase = query_name.downcase
        query_lowercase == instance_name.downcase || queries_handled.any? { |q| q.downcase == query_lowercase }
      end

      # Additional query names this generator responds to (PTR queries, subtypes)
      def queries_handled : Array(String)
        [] of String
      end
    end

    # mDNS Server for responding to queries and broadcasting announcements
    #
    # RFC 6762: Multicast DNS
    # - Responds to queries for registered services
    # - Broadcasts unsolicited announcements
    # - Implements response delays (20-120ms) to avoid collisions
    class Server
      Log = ::Log.for("matter.mdns.server")

      property socket : MulticastSocket
      @record_generators : Array(RecordGenerator) = [] of RecordGenerator
      @running : Bool = false
      @server_fiber : Fiber?

      # Response delay range per RFC 6762 §6
      RESPONSE_DELAY_MIN = 20.milliseconds
      RESPONSE_DELAY_MAX = 120.milliseconds

      def initialize(@socket : MulticastSocket)
        Log.info { "mDNS Server initialized" }
      end

      # Convenience constructor that creates its own socket
      def self.new(family : Socket::Family = Socket::Family::INET)
        socket = MulticastSocket.new(family)
        socket.join_multicast_group
        new(socket)
      end

      # Register a record generator
      #
      # @param generator The record generator to register
      def register(generator : RecordGenerator) : Nil
        @record_generators << generator
        Log.info { "Registered record generator for #{generator.instance_name}" }
      end

      # Unregister a record generator
      #
      # @param generator The record generator to unregister
      def unregister(generator : RecordGenerator) : Nil
        @record_generators.delete(generator)
        Log.info { "Unregistered record generator for #{generator.instance_name}" }
      end

      # Start the server (begins listening for queries)
      def start : Nil
        return if @running

        @running = true
        @server_fiber = spawn(name: "mDNS Server") { run_server }
        Log.info { "mDNS Server started" }
      end

      # Stop the server
      def stop : Nil
        return unless @running

        @running = false
        @server_fiber = nil
        Log.info { "mDNS Server stopped" }
      end

      # Check if server is running
      def running? : Bool
        @running
      end

      # Broadcast unsolicited announcement for all registered generators
      #
      # RFC 6762 §8.3: Announcing records
      def announce : Nil
        @record_generators.each do |generator|
          records = generator.records
          next if records.empty?

          packet = build_announcement_packet(records)
          send_packet(packet)

          Log.debug { "Announced #{records.size} records for #{generator.instance_name}" }
        end
      end

      # Send goodbye packets (TTL=0) for all registered generators
      #
      # RFC 6762 §10.1: Goodbye packets indicate records are being removed
      def send_goodbye : Nil
        @record_generators.each do |generator|
          records = generator.records
          next if records.empty?

          # Set TTL=0 for all records
          goodbye_records = records.map do |record|
            record.ttl = 0.seconds
            record
          end

          packet = build_announcement_packet(goodbye_records)
          send_packet(packet)

          Log.info { "Sent goodbye for #{generator.instance_name}" }
        end
      end

      # Main server loop - listens for queries and responds
      private def run_server : Nil
        buffer = Bytes.new(4096)

        while @running
          begin
            result = @socket.receive(buffer, timeout: 1.second)
            next unless result

            bytes_received, sender = result
            handle_query(buffer[0, bytes_received], sender)
          rescue ex : IO::Error
            Log.error(exception: ex) { "Error receiving mDNS query" }
          rescue ex
            Log.error(exception: ex) { "Unexpected error in mDNS server" }
          end
        end
      rescue ex
        Log.error(exception: ex) { "mDNS server fiber crashed" }
      end

      # Handle incoming query packet
      private def handle_query(data : Bytes, sender : Socket::IPAddress) : Nil
        packet = DNS::Packet.from_slice(data)

        # Only respond to queries (response? == false means it's a query)
        return if packet.response?

        Log.trace { "Query from #{sender}: #{packet.questions.size} questions" }

        # Check if we have answers for any questions
        answers = [] of DNS::Packet::ResourceRecord

        packet.questions.each do |question|
          query_name = question.name
          query_type = question.type

          @record_generators.each do |generator|
            next unless generator.handles?(query_name)

            # Find matching records
            matching_records = generator.records.select do |record|
              # Match by name and type
              record.name.downcase == query_name.downcase && record.type == query_type
            end

            answers.concat(matching_records)
          end
        end

        return if answers.empty?

        # RFC 6762 §6: Delay response by 20-120ms to avoid collisions
        delay_ms = rand(20..120)
        delay = delay_ms.milliseconds
        sleep delay

        # Send response
        response_packet = build_response_packet(packet, answers)
        send_packet(response_packet)

        Log.debug { "Responded to #{sender} with #{answers.size} answers (delay: #{delay.total_milliseconds.round(1)}ms)" }
      end

      # Build announcement packet (unsolicited multicast response)
      private def build_announcement_packet(records : Array(DNS::Packet::ResourceRecord)) : DNS::Packet
        # RFC 6762 §18.1: ID MUST be zero for multicast responses
        DNS::Packet.new(
          id: 0_u16,
          response: true,
          authoritative_answer: true,
          answers: records
        )
      end

      # Build response packet to a query
      private def build_response_packet(query : DNS::Packet, answers : Array(DNS::Packet::ResourceRecord)) : DNS::Packet
        # RFC 6762 §18.1: ID MUST be zero for multicast responses
        DNS::Packet.new(
          id: 0_u16,
          response: true,
          authoritative_answer: true,
          questions: query.questions,
          answers: answers
        )
      end

      # Send packet to multicast group
      private def send_packet(packet : DNS::Packet) : Nil
        data = packet.to_slice
        @socket.send_multicast(data)
      rescue ex
        Log.error(exception: ex) { "Error sending mDNS packet" }
      end

      # Close the server and cleanup
      def close : Nil
        stop
        @record_generators.clear
        @socket.close unless @socket.closed?
        Log.info { "mDNS Server closed" }
      end
    end
  end
end
