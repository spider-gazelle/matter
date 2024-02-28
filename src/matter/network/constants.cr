module Matter
  module Network
    module Constants
      DEFAULT_INTERFACE_IPV4 = Socket::IPAddress.new("0.0.0.0", 10222)
      DEFAULT_INTERFACE_IPV6 = 0_u32
    end
  end
end
