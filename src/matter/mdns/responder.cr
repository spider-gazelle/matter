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

      DEFAULT_TTL           = 120.seconds
      ANNOUNCEMENT_INTERVAL = 30.seconds # Re-announce services every 30 seconds

      getter socket_ipv4 : UDPSocket?
      getter socket_ipv6 : UDPSocket?
      getter port : Int32
      getter hostname : String
      getter ip_addresses : Array(Socket::IPAddress)

      @running : Bool

      # Currently advertised services (for responding to queries)
      # Key: instance name, Value: {service_type, port, txt_records, commissioning_info}
      @advertised_services : Hash(String, {ServiceType, Int32, Hash(String, String), CommissioningInfo?})

      # Callback for received queries
      # Signature: (query : DNS::Packet, peer_address : Socket::IPAddress) -> Nil
      property on_query : Proc(DNS::Packet, Socket::IPAddress, Nil)?

      def initialize(@port : Int32 = MDNS_PORT, @hostname : String = "matter-device.local", @ip_addresses : Array(Socket::IPAddress) = [] of Socket::IPAddress)
        # Create IPv4 socket
        @socket_ipv4 = begin
          sock = UDPSocket.new(:inet)
          sock.reuse_address = true
          sock.reuse_port = true
          sock.bind("0.0.0.0", MDNS_PORT)

          # Set multicast options
          sock.multicast_loopback = true # Allow receiving our own packets (needed for testing)
          sock.multicast_hops = 255      # TTL for multicast packets

          sock
        rescue ex
          Log.warn(exception: ex) { "Failed to create IPv4 socket: #{ex.message}" }
          nil
        end

        # Create IPv6 socket
        @socket_ipv6 = begin
          sock = UDPSocket.new(:inet6)
          sock.reuse_address = true
          sock.reuse_port = true
          sock.bind("::", MDNS_PORT)

          # Set multicast options
          sock.multicast_loopback = true # Allow receiving our own packets (needed for testing)
          sock.multicast_hops = 255      # TTL for multicast packets

          sock
        rescue ex
          Log.warn(exception: ex) { "Failed to create IPv6 socket: #{ex.message}" }
          nil
        end

        @running = false

        # Ensure at least one socket was created successfully
        raise "Failed to create any mDNS socket" if @socket_ipv4.nil? && @socket_ipv6.nil?
        @advertised_services = Hash(String, {ServiceType, Int32, Hash(String, String), CommissioningInfo?}).new
      end

      # Start listening for mDNS queries
      def start : Nil
        return if @running

        @running = true

        # Join IPv4 multicast group and start receive loop
        if sock4 = @socket_ipv4
          begin
            sock4.join_group(MDNS_IPV4)
            Log.info { "Joined IPv4 mDNS multicast group 224.0.0.251" }

            spawn do
              receive_loop_ipv4(sock4)
            end
          rescue ex
            Log.warn(exception: ex) { "Could not join IPv4 multicast group: #{ex.message}" }
          end
        end

        # Join IPv6 multicast group and start receive loop
        if sock6 = @socket_ipv6
          begin
            sock6.join_group(MDNS_IPV6)
            Log.info { "Joined IPv6 mDNS multicast group ff02::fb" }

            spawn do
              receive_loop_ipv6(sock6)
            end
          rescue ex
            Log.warn(exception: ex) { "Could not join IPv6 multicast group: #{ex.message}" }
          end
        end

        # Start periodic announcement loop
        spawn do
          periodic_announcement_loop
        end
      end

      # Stop listening
      def stop : Nil
        @running = false

        # Leave IPv4 multicast group
        if sock4 = @socket_ipv4
          begin
            sock4.leave_group(MDNS_IPV4)
            sock4.close unless sock4.closed?
          rescue ex
            Log.warn(exception: ex) { "Error stopping IPv4: #{ex.message}" }
          end
        end

        # Leave IPv6 multicast group
        if sock6 = @socket_ipv6
          begin
            sock6.leave_group(MDNS_IPV6)
            sock6.close unless sock6.closed?
          rescue ex
            Log.warn(exception: ex) { "Error stopping IPv6: #{ex.message}" }
          end
        end
      end

      # Close responder
      def close : Nil
        stop
      end

      # Periodic announcement loop - re-announces all services every ANNOUNCEMENT_INTERVAL
      private def periodic_announcement_loop : Nil
        while @running
          sleep ANNOUNCEMENT_INTERVAL
          reannounce_all_services if @running
        end
      rescue ex
        Log.error(exception: ex) { "Error in periodic announcement loop: #{ex.message}" }
      end

      # Re-announce all currently advertised services
      private def reannounce_all_services : Nil
        return if @advertised_services.empty?

        Log.debug { "Re-announcing #{@advertised_services.size} service(s)" }

        @advertised_services.each do |instance, (service_type, port, txt_records, commissioning_info)|
          begin
            if commissioning_info
              # Commissioning service - need to build full records with subtypes
              service = ServiceNames::COMMISSIONING
              records = build_commissioning_records(
                info: commissioning_info,
                service: service,
                instance: instance,
                port: port,
                txt_records: txt_records,
                ttl: DEFAULT_TTL
              )
            else
              # Operational service - simpler records
              service = ServiceNames.service_name(service_type)
              records = build_service_records(
                service: service,
                instance: instance,
                port: port,
                txt_records: txt_records,
                ttl: DEFAULT_TTL
              )
            end

            send_announcement(records)
          rescue ex
            Log.warn(exception: ex) { "Failed to re-announce service #{instance}: #{ex.message}" }
          end
        end
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
        @advertised_services[instance] = {ServiceType::Commissioning, port, info.to_txt_records, info}

        records = build_commissioning_records(
          info: info,
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
        instance = ServiceNames.operational_instance(info.compressed_fabric_id, info.node_id)

        # Track this service for query responses
        @advertised_services[instance] = {ServiceType::Operational, port, info.to_txt_records, nil}

        records = build_service_records(
          service: service,
          instance: instance,
          port: port,
          txt_records: info.to_txt_records,
          ttl: ttl
        )

        send_announcement(records)
      end

      # Stop all commissioning advertisements
      def stop_commissioning : Nil
        # Find and remove all commissioning services
        commissioning_instances = @advertised_services.select { |_, v| v[0] == ServiceType::Commissioning }.keys
        commissioning_instances.each do |instance|
          Log.info { "Stopping commissioning advertisement for: #{instance}" }
          send_goodbye(ServiceType::Commissioning, instance)
        end
      end

      # Stop all operational advertisements
      def stop_operational_advertisement : Nil
        # Find and remove all operational services
        operational_instances = @advertised_services.select { |_, v| v[0] == ServiceType::Operational }.keys
        operational_instances.each do |instance|
          Log.info { "Stopping operational advertisement for: #{instance}" }
          send_goodbye(ServiceType::Operational, instance)
        end
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

      private def build_commissioning_records(
        info : CommissioningInfo,
        service : String,
        instance : String,
        port : Int32,
        txt_records : Hash(String, String),
        ttl : Time::Span,
      ) : Array(DNS::Packet::ResourceRecord)
        records = [] of DNS::Packet::ResourceRecord

        # Build subtype names
        vendor_sub = ServiceNames.vendor_subtype(info.vendor_id)
        device_type_sub = ServiceNames.device_type_subtype(info.device_type)
        short_disc_sub = ServiceNames.short_discriminator_subtype(info.discriminator)
        long_disc_sub = ServiceNames.long_discriminator_subtype(info.discriminator)
        commissioning_mode_sub = ServiceNames.commissioning_mode_subtype

        # PTR records from _services._dns-sd._udp.local to all subtypes (for browse lists)
        records << RecordBuilder.build_ptr(ServiceNames::SERVICE_DISCOVERY, service, ttl)
        records << RecordBuilder.build_ptr(ServiceNames::SERVICE_DISCOVERY, vendor_sub, ttl)
        records << RecordBuilder.build_ptr(ServiceNames::SERVICE_DISCOVERY, device_type_sub, ttl)
        records << RecordBuilder.build_ptr(ServiceNames::SERVICE_DISCOVERY, short_disc_sub, ttl)
        records << RecordBuilder.build_ptr(ServiceNames::SERVICE_DISCOVERY, long_disc_sub, ttl)
        records << RecordBuilder.build_ptr(ServiceNames::SERVICE_DISCOVERY, commissioning_mode_sub, ttl)

        # PTR records from service -> instance
        records << RecordBuilder.build_ptr(service, instance, ttl)

        # PTR records from subtypes -> instance (for subtype browsing)
        records << RecordBuilder.build_ptr(vendor_sub, instance, ttl)
        records << RecordBuilder.build_ptr(device_type_sub, instance, ttl)
        records << RecordBuilder.build_ptr(short_disc_sub, instance, ttl)
        records << RecordBuilder.build_ptr(long_disc_sub, instance, ttl)
        records << RecordBuilder.build_ptr(commissioning_mode_sub, instance, ttl)

        # SRV record: instance -> hostname:port
        records << RecordBuilder.build_srv(instance, port, @hostname, ttl)

        # TXT record: instance metadata
        records << RecordBuilder.build_txt(instance, txt_records, ttl)

        # A/AAAA records: hostname -> IP addresses
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
        additional_records = records.select { |r| r.type != RecordBuilder::TYPE_PTR }

        # Build mDNS announcement packet per RFC 6763
        # PTR records in Answer Section
        # SRV, TXT, A, AAAA records in Additional Records Section
        # Authority Section should be empty for mDNS
        packet = DNS::Packet.new(
          id: 0_u16,
          response: true,
          authoritative_answer: true, # Critical: We are authoritative
          answers: ptr_records,
          authorities: [] of DNS::Packet::ResourceRecord, # Empty per RFC 6763
          additionals: additional_records                 # SRV, TXT, A, AAAA all go here
        )

        send_multicast(packet)
      end

      private def send_multicast(packet : DNS::Packet) : Nil
        data = packet.to_slice
        Log.debug { "Sending mDNS packet: #{data.size} bytes, #{packet.answers.size} answers, #{packet.authorities.size} authorities, #{packet.additionals.size} additionals" }

        # Send to IPv4 multicast
        if sock4 = @socket_ipv4
          begin
            bytes_sent = sock4.send(data, MDNS_IPV4)
            Log.debug { "Sent #{bytes_sent} bytes to IPv4 multicast 224.0.0.251:5353" }
          rescue ex
            Log.error(exception: ex) { "Error sending IPv4 multicast: #{ex.message}" }
          end
        end

        # Send to IPv6 multicast
        if sock6 = @socket_ipv6
          begin
            bytes_sent = sock6.send(data, MDNS_IPV6)
            Log.debug { "Sent #{bytes_sent} bytes to IPv6 multicast ff02::fb:5353" }
          rescue ex
            Log.error(exception: ex) { "Error sending IPv6 multicast: #{ex.message}" }
          end
        end
      end

      # IPv4 receive loop
      private def receive_loop_ipv4(sock : UDPSocket) : Nil
        buffer = Bytes.new(9000) # Max DNS packet size
        data = nil

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
            Log.error(exception: ex) { "Error receiving IPv4 mDNS packet: #{ex.message}\npacket data: 0x#{data.try(&.hexstring)}" } if @running
          end
        end
      end

      # IPv6 receive loop
      private def receive_loop_ipv6(sock : UDPSocket) : Nil
        buffer = Bytes.new(9000) # Max DNS packet size
        data = nil

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
            Log.error(exception: ex) { "Error receiving IPv6 mDNS packet: #{ex.message}\npacket data: 0x#{data.try(&.hexstring)}" } if @running
          end
        end
      end

      private def process_query(query : DNS::Packet) : Nil
        # Check if any questions match our advertised services
        query.questions.each do |question|
          Log.debug { "Processing question: name=#{question.name}, type=#{question.type}" }
          # Check for service type queries (PTR or ANY)
          if question.type == RecordBuilder::TYPE_PTR || question.type == 255 # 255 = ANY
            check_service_query(question.name)
            # For ANY queries, also check if it's an instance-specific query
            check_instance_query(question.name) if question.type == 255
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
        @advertised_services.each do |instance, (service_type, port, txt_records, comm_info)|
          expected_service = ServiceNames.service_name(service_type)

          if service_name == expected_service
            Log.debug { "Query matches our service: #{service_name}, sending response for instance: #{instance}" }
            # Respond with our service (with all PTR records for commissioning)
            records = if info = comm_info
                        build_commissioning_records(
                          info: info,
                          service: expected_service,
                          instance: instance,
                          port: port,
                          txt_records: txt_records,
                          ttl: DEFAULT_TTL
                        )
                      else
                        build_service_records(
                          service: expected_service,
                          instance: instance,
                          port: port,
                          txt_records: txt_records,
                          ttl: DEFAULT_TTL
                        )
                      end
            send_announcement(records)
          end
        end
      end

      private def check_instance_query(instance_name : String) : Nil
        # Check if query matches one of our advertised instances
        if service_info = @advertised_services[instance_name]?
          service_type, port, txt_records, comm_info = service_info
          service = ServiceNames.service_name(service_type)

          # Respond with our instance (with all PTR records for commissioning)
          records = if info = comm_info
                      build_commissioning_records(
                        info: info,
                        service: service,
                        instance: instance_name,
                        port: port,
                        txt_records: txt_records,
                        ttl: DEFAULT_TTL
                      )
                    else
                      build_service_records(
                        service: service,
                        instance: instance_name,
                        port: port,
                        txt_records: txt_records,
                        ttl: DEFAULT_TTL
                      )
                    end
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
