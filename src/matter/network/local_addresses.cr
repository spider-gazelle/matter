require "socket"

module Matter
  module Network
    # Public resolvers used only as UDP `connect` targets. Connecting a UDP socket
    # sends nothing; it makes the kernel pick the outbound interface for that
    # destination, whose address is then read back from `local_address`.
    IPV6_ROUTE_PROBE = Socket::IPAddress.new("2606:4700:4700::1111", 53)
    IPV4_ROUTE_PROBE = Socket::IPAddress.new("8.8.8.8", 80)

    # Returned when no routable interface can be determined.
    LOOPBACK_ADDRESS = Socket::IPAddress.new("127.0.0.1", 0)

    # Port is not meaningful for an interface address.
    UNSPECIFIED_PORT = 0

    # The addresses a device should advertise: the IPv6 then IPv4 address of the
    # interface that routes to the internet, or loopback if neither exists.
    def self.local_ip_addresses : Array(Socket::IPAddress)
      addresses = [] of Socket::IPAddress
      {IPV6_ROUTE_PROBE, IPV4_ROUTE_PROBE}.each do |probe|
        if address = outbound_address(probe)
          addresses << address
        end
      end

      if addresses.empty?
        Log.warn { "no routable interface found, falling back to #{LOOPBACK_ADDRESS.address}" }
        addresses << LOOPBACK_ADDRESS
      end
      addresses
    end

    private def self.outbound_address(probe : Socket::IPAddress) : Socket::IPAddress?
      socket = UDPSocket.new(probe.family)
      socket.connect(probe)
      Socket::IPAddress.new(socket.local_address.address, UNSPECIFIED_PORT)
    rescue error : IO::Error
      Log.warn(exception: error) { "unable to determine the local #{probe.family} address" }
      nil
    ensure
      socket.try &.close
    end
  end
end
