module Matter
  module Network
    module Constants
      MDNS_PORT = 5353
      MDNS_ADDRESS_IPv4 = Socket::IPAddress.new("224.0.0.251", MDNS_PORT)
      MDNS_ADDRESS_IPv6 = Socket::IPAddress.new("FF02::FB", MDNS_PORT)

      DEFAULT_INTERFACE_IPV4 = Socket::IPAddress.new("0.0.0.0", 10222)
      DEFAULT_INTERFACE_IPV6 = 0_u32
    end
  end
end
