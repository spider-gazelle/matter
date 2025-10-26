require "socket"
require "log"

module Matter
  module MDNS
    # MulticastSocket for mDNS communication
    #
    # Provides UDP multicast I/O on port 5353 for mDNS (Multicast DNS).
    # Supports both IPv4 (224.0.0.251) and IPv6 (ff02::fb) multicast groups.
    #
    # RFC 6762 §5.1: Multicast DNS uses port 5353 on both IPv4 and IPv6
    class MulticastSocket
      Log = ::Log.for("matter.mdns.socket")

      # mDNS multicast addresses
      MDNS_IPV4_MULTICAST_ADDRESS = "224.0.0.251"
      MDNS_IPV6_MULTICAST_ADDRESS = "ff02::fb"
      MDNS_PORT                   = 5353_u16

      # TTL for multicast packets (RFC 6762 §11: SHOULD be 255)
      MULTICAST_TTL = 255

      property socket : UDPSocket
      property family : Socket::Family

      # Multicast group addresses this socket is joined to
      @joined_groups : Set(String) = Set(String).new

      def initialize(@family : Socket::Family = Socket::Family::INET)
        @socket = UDPSocket.new(@family)
        configure_socket
        Log.info { "MulticastSocket initialized for #{@family}" }
      end

      # Configure socket for multicast operation
      private def configure_socket : Nil
        # Allow address reuse (multiple processes can bind to 5353)
        @socket.reuse_address = true
        @socket.reuse_port = true

        # Bind to INADDR_ANY (0.0.0.0 or ::) on port 5353
        bind_address = @family.inet? ? Socket::IPAddress.new("0.0.0.0", MDNS_PORT) : Socket::IPAddress.new("::", MDNS_PORT)

        @socket.bind(bind_address)
        Log.debug { "Socket bound to #{bind_address}" }

        # Set multicast TTL/hops
        @socket.multicast_hops = MULTICAST_TTL

        # Enable multicast loopback (receive our own packets for testing)
        @socket.multicast_loopback = true

        Log.debug { "Socket configured: TTL=#{MULTICAST_TTL}, loopback=true" }
      end

      # Join the mDNS multicast group
      #
      # RFC 6762 §5.1: All mDNS responders and queriers MUST join the multicast group
      def join_multicast_group : Nil
        multicast_address = @family.inet? ? MDNS_IPV4_MULTICAST_ADDRESS : MDNS_IPV6_MULTICAST_ADDRESS

        return if @joined_groups.includes?(multicast_address)

        begin
          if @family.inet?
            # IPv4: Use INADDR_ANY for the interface
            @socket.join_group(Socket::IPAddress.new(multicast_address, 0))
          else
            # IPv6: Use interface index 0 (all interfaces)
            @socket.join_group(Socket::IPAddress.new(multicast_address, 0))
          end

          @joined_groups << multicast_address
          Log.info { "Joined multicast group #{multicast_address}" }
        rescue ex
          Log.error(exception: ex) { "Failed to join multicast group #{multicast_address}" }
          raise ex
        end
      end

      # Leave the mDNS multicast group
      def leave_multicast_group : Nil
        multicast_address = @family.inet? ? MDNS_IPV4_MULTICAST_ADDRESS : MDNS_IPV6_MULTICAST_ADDRESS

        return unless @joined_groups.includes?(multicast_address)

        begin
          if @family.inet?
            @socket.leave_group(Socket::IPAddress.new(multicast_address, 0))
          else
            @socket.leave_group(Socket::IPAddress.new(multicast_address, 0))
          end

          @joined_groups.delete(multicast_address)
          Log.info { "Left multicast group #{multicast_address}" }
        rescue ex
          Log.error(exception: ex) { "Failed to leave multicast group #{multicast_address}" }
        end
      end

      # Send data to the mDNS multicast group
      #
      # @param data The DNS packet bytes to send
      # @return Number of bytes sent
      def send_multicast(data : Bytes) : Int32
        multicast_address = @family.inet? ? MDNS_IPV4_MULTICAST_ADDRESS : MDNS_IPV6_MULTICAST_ADDRESS

        destination = Socket::IPAddress.new(multicast_address, MDNS_PORT)
        bytes_sent = @socket.send(data, to: destination)

        Log.trace { "Sent #{bytes_sent} bytes to #{destination}" }
        bytes_sent
      end

      # Receive data from the multicast group
      #
      # @param buffer Buffer to receive data into
      # @return Tuple of (bytes_received, sender_address)
      def receive(buffer : Bytes) : Tuple(Int32, Socket::IPAddress)
        bytes_received, sender = @socket.receive(buffer)
        Log.trace { "Received #{bytes_received} bytes from #{sender}" }
        {bytes_received, sender}
      end

      # Receive data with a timeout
      #
      # @param buffer Buffer to receive data into
      # @param timeout Timeout duration
      # @return Tuple of (bytes_received, sender_address) or nil if timeout
      def receive(buffer : Bytes, timeout : Time::Span) : Tuple(Int32, Socket::IPAddress)?
        old_timeout = @socket.read_timeout
        @socket.read_timeout = timeout

        begin
          bytes_received, sender = @socket.receive(buffer)
          {bytes_received, sender}
        rescue IO::TimeoutError
          nil
        ensure
          @socket.read_timeout = old_timeout
        end
      end

      # Get the multicast address for this socket's family
      def multicast_address : String
        @family.inet? ? MDNS_IPV4_MULTICAST_ADDRESS : MDNS_IPV6_MULTICAST_ADDRESS
      end

      # Check if socket is closed
      def closed? : Bool
        @socket.closed?
      end

      # Close the socket and leave all multicast groups
      def close : Nil
        return if closed?

        Log.info { "Closing multicast socket" }

        # Leave all joined groups
        @joined_groups.each do |group|
          begin
            @socket.leave_group(Socket::IPAddress.new(group, 0))
          rescue ex
            Log.warn(exception: ex) { "Error leaving group #{group} during close" }
          end
        end
        @joined_groups.clear

        @socket.close
        Log.debug { "Multicast socket closed" }
      end
    end
  end
end
