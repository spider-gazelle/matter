module Matter
  abstract class Node
    property disable_ipv4 : Bool = false

    abstract def port
    abstract def start
    abstract def close

    abstract def mdns_broadcaster=(mdnsBroadcaster : MdnsBroadcaster)
    abstract def mdns_scanner=(mdnsScanner : MdnsScanner)
  end
end
