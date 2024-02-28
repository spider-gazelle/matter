module Matter
  module Network
    class MulticastServer
      PORT = 5353
      IPv4 = Socket::IPAddress.new("224.0.0.251", PORT)
      IPv6 = Socket::IPAddress.new("FF02::FB", PORT)

      getter socket : UDPSocket

      def initialize(@address : Socket::IPAddress = IPv4, buffer_size = 16, loopback = false, hops = 255)
        interface = @address.family.inet? ? Constants::DEFAULT_INTERFACE_IPV4 : Constants::DEFAULT_INTERFACE_IPV6

        @socket = UDPSocket.new @address.family
        @socket.reuse_address = true
        @socket.reuse_port = true
        @socket.bind(@address.family.inet? ? Socket::IPAddress::UNSPECIFIED : Socket::IPAddress::UNSPECIFIED6, @address.port)
        @socket.multicast_interface(interface)
        @socket.join_group(@address)
        @socket.multicast_loopback = loopback
        @socket.multicast_hops = hops
      end

      def close
        @socket.close
      end
    end
  end
end