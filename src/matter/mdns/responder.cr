require "dns"
require "./service_type"
require "./record_builder"
require "../network/constants"

module Matter
  module MDNS
    # mDNS Responder for advertising Matter services
    #
    # Handles:
    # - Service advertisement (announcements)
    # - Query responses
    # - Using Authority Section for authoritative records
    class Responder
      MDNS_PORT = 5353
      MDNS_IPV4 = Socket::IPAddress.new("224.0.0.251", MDNS_PORT)
      MDNS_IPV6 = Socket::IPAddress.new("ff02::fb", MDNS_PORT)

      DEFAULT_TTL = 120.seconds

      getter socket : UDPSocket
      getter port : Int32
      getter hostname : String
      getter ip_addresses : Array(Socket::IPAddress)

      @running : Bool
      @receive_fiber : Fiber?
      @receive_socket : UDPSocket?

      # Currently advertised services (for responding to queries)
      # Key: instance name, Value: {service_type, port, txt_records}
      @advertised_services : Hash(String, {ServiceType, Int32, Hash(String, String)})

      # Callback for received queries
      # Signature: (query : DNS::Packet, peer_address : Socket::IPAddress) -> Nil
      property on_query : Proc(DNS::Packet, Socket::IPAddress, Nil)?

      def initialize(@port : Int32 = MDNS_PORT, @hostname : String = "matter-device.local", @ip_addresses : Array(Socket::IPAddress) = [] of Socket::IPAddress)
        @socket = UDPSocket.new
        @socket.reuse_address = true
        @socket.reuse_port = true
        @socket.bind("0.0.0.0", 0) # Bind to ephemeral port for sending
        @running = false
        @receive_fiber = nil
        @receive_socket = nil
        @advertised_services = Hash(String, {ServiceType, Int32, Hash(String, String)}).new
      end

      # Start listening for mDNS queries
      def start : Nil
        return if @running

        # Setup receive socket for multicast
        @receive_socket = UDPSocket.new
        @receive_socket.not_nil!.reuse_address = true
        @receive_socket.not_nil!.reuse_port = true
        @receive_socket.not_nil!.bind("0.0.0.0", MDNS_PORT)
        @receive_socket.not_nil!.read_timeout = 100.milliseconds

        # Join multicast group
        begin
          @receive_socket.not_nil!.join_group(MDNS_IPV4)
        rescue ex
          puts "Warning: Could not join IPv4 multicast group: #{ex.message}"
        end

        @running = true
        @receive_fiber = spawn do
          receive_loop
        end
      end

      # Stop listening
      def stop : Nil
        @running = false
        sleep 200.milliseconds if @receive_fiber
        @receive_fiber = nil

        # Close receive socket
        if sock = @receive_socket
          sock.close unless sock.closed?
          @receive_socket = nil
        end
      end

      # Close responder
      def close : Nil
        stop
        @socket.close unless @socket.closed?
      end

      # Advertise commissioning service
      def advertise_commissioning(
        info : CommissioningInfo,
        port : Int32 = 5540,
        ttl : Time::Span = DEFAULT_TTL,
      ) : Nil
        service = ServiceNames::COMMISSIONING
        instance = ServiceNames.commissioning_instance(info.device_name)

        # Track this service for query responses
        @advertised_services[instance] = {ServiceType::Commissioning, port, info.to_txt_records}

        records = build_service_records(
          service: service,
          instance: instance,
          port: port,
          txt_records: info.to_txt_records,
          ttl: ttl
        )

        send_announcement(records)
      end

      # Advertise operational service
      def advertise_operational(
        info : OperationalInfo,
        port : Int32 = 5540,
        ttl : Time::Span = DEFAULT_TTL,
      ) : Nil
        service = ServiceNames::OPERATIONAL
        instance = ServiceNames.operational_instance(info.fabric_id, info.node_id)

        # Track this service for query responses
        @advertised_services[instance] = {ServiceType::Operational, port, info.to_txt_records}

        records = build_service_records(
          service: service,
          instance: instance,
          port: port,
          txt_records: info.to_txt_records,
          ttl: ttl
        )

        send_announcement(records)
      end

      # Send goodbye announcement (TTL=0) to remove service
      def send_goodbye(service_type : ServiceType, instance : String) : Nil
        service = ServiceNames.service_name(service_type)

        # Remove from advertised services
        @advertised_services.delete(instance)

        # Build PTR record with TTL=0
        ptr = RecordBuilder.build_ptr(service, instance, 0.seconds)

        packet = DNS::Packet.new(
          id: 0_u16,
          response: true,
          authoritative_answer: true,
          answers: [ptr]
        )

        send_multicast(packet)
      end

      # Respond to a specific query
      def respond_to_query(query : DNS::Packet, service_type : ServiceType, instance : String, port : Int32, txt_records : Hash(String, String)) : Nil
        service = ServiceNames.service_name(service_type)

        # Check if query is asking for our service
        matches = query.questions.any? do |q|
          q.name == service || q.name == instance || q.name == @hostname
        end

        return unless matches

        records = build_service_records(
          service: service,
          instance: instance,
          port: port,
          txt_records: txt_records,
          ttl: DEFAULT_TTL
        )

        send_announcement(records)
      end

      private def build_service_records(
        service : String,
        instance : String,
        port : Int32,
        txt_records : Hash(String, String),
        ttl : Time::Span,
      ) : Array(DNS::Packet::ResourceRecord)
        records = [] of DNS::Packet::ResourceRecord

        # PTR record: service -> instance
        records << RecordBuilder.build_ptr(service, instance, ttl)

        # SRV record: instance -> hostname:port (goes in authorities)
        records << RecordBuilder.build_srv(instance, port, @hostname, ttl)

        # TXT record: instance metadata (goes in authorities)
        records << RecordBuilder.build_txt(instance, txt_records, ttl)

        # A/AAAA records: hostname -> IP addresses (go in additionals)
        @ip_addresses.each do |ip|
          case ip.family
          when .inet?
            records << RecordBuilder.build_a(@hostname, ip, ttl)
          when .inet6?
            records << RecordBuilder.build_aaaa(@hostname, ip, ttl)
          end
        end

        records
      end

      private def send_announcement(records : Array(DNS::Packet::ResourceRecord)) : Nil
        # Split records into appropriate sections
        ptr_records = records.select { |r| r.type == RecordBuilder::TYPE_PTR }
        srv_txt_records = records.select { |r| r.type == RecordBuilder::TYPE_SRV || r.type == RecordBuilder::TYPE_TXT }
        ip_records = records.select { |r| r.type == RecordBuilder::TYPE_A || r.type == RecordBuilder::TYPE_AAAA }

        # Build mDNS announcement packet
        # PTR in answers, SRV/TXT in authorities (we're authoritative), A/AAAA in additionals
        packet = DNS::Packet.new(
          id: 0_u16,
          response: true,
          authoritative_answer: true, # Critical: We are authoritative
          answers: ptr_records,
          authorities: srv_txt_records, # Authority Section for authoritative records
          additionals: ip_records
        )

        send_multicast(packet)
      end

      private def send_multicast(packet : DNS::Packet) : Nil
        data = packet.to_slice

        # Send to IPv4 multicast
        begin
          @socket.send(data, MDNS_IPV4)
        rescue ex
          # Log error but continue
          puts "Error sending IPv4 multicast: #{ex.message}"
        end

        # Send to IPv6 multicast if we have IPv6 addresses
        if @ip_addresses.any? { |ip| ip.family.inet6? }
          begin
            @socket.send(data, MDNS_IPV6)
          rescue ex
            # Log error but continue
            puts "Error sending IPv6 multicast: #{ex.message}"
          end
        end
      end

      private def receive_loop : Nil
        return unless sock = @receive_socket

        buffer = Bytes.new(9000) # Max DNS packet size

        while @running
          begin
            bytes_read, peer_address = sock.receive(buffer)
            next if bytes_read == 0

            data = buffer[0, bytes_read]
            packet = DNS::Packet.from_slice(data)

            # Only process queries (not responses)
            next if packet.response?

            # Call user callback if set
            @on_query.try(&.call(packet, peer_address))

            # Process query and respond if it matches our services
            process_query(packet)
          rescue IO::TimeoutError
            # Normal - continue
          rescue ex : Exception
            puts "Error receiving mDNS packet: #{ex.message}"
          end
        end
      end

      private def process_query(query : DNS::Packet) : Nil
        # Check if any questions match our advertised services
        query.questions.each do |question|
          # Check for service type queries (PTR)
          if question.type == RecordBuilder::TYPE_PTR
            check_service_query(question.name)
            # Check for specific instance queries (SRV, TXT, A, AAAA)
          elsif question.type.in?(RecordBuilder::TYPE_SRV, RecordBuilder::TYPE_TXT, RecordBuilder::TYPE_A, RecordBuilder::TYPE_AAAA)
            check_instance_query(question.name)
            # Check for hostname queries
          elsif question.name == @hostname
            send_hostname_response
          end
        end
      end

      private def check_service_query(service_name : String) : Nil
        # Check if query matches our service types
        @advertised_services.each do |instance, (service_type, port, txt_records)|
          expected_service = ServiceNames.service_name(service_type)

          if service_name == expected_service
            # Respond with our service
            records = build_service_records(
              service: expected_service,
              instance: instance,
              port: port,
              txt_records: txt_records,
              ttl: DEFAULT_TTL
            )
            send_announcement(records)
          end
        end
      end

      private def check_instance_query(instance_name : String) : Nil
        # Check if query matches one of our advertised instances
        if service_info = @advertised_services[instance_name]?
          service_type, port, txt_records = service_info
          service = ServiceNames.service_name(service_type)

          # Respond with our instance
          records = build_service_records(
            service: service,
            instance: instance_name,
            port: port,
            txt_records: txt_records,
            ttl: DEFAULT_TTL
          )
          send_announcement(records)
        end
      end

      private def send_hostname_response : Nil
        # Send A/AAAA records for our hostname
        records = [] of DNS::Packet::ResourceRecord

        @ip_addresses.each do |ip|
          case ip.family
          when .inet?
            records << RecordBuilder.build_a(@hostname, ip, DEFAULT_TTL)
          when .inet6?
            records << RecordBuilder.build_aaaa(@hostname, ip, DEFAULT_TTL)
          end
        end

        return if records.empty?

        packet = DNS::Packet.new(
          id: 0_u16,
          response: true,
          authoritative_answer: true,
          answers: records
        )

        send_multicast(packet)
      end
    end
  end
end
