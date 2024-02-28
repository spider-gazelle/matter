module Matter
  class Server
    PORT = 5540

    getter nodes : Array(Node) = [] of Node

    getter storage_manager : Storage::Manager
    getter options : NamedTuple(disable_ipv4: Bool?, mdns_interface: String?) = {disable_ipv4: false, mdns_interface: "*"}

    def initialize(@storage_manager : Storage::Manager, options : NamedTuple(disable_ipv4: Bool?, mdns_interface: String?)? = nil)
      @options = options unless options.nil?
    end

    def disable_ipv4? : Bool
      options.disableIpv4 && options.disableIpv4
    end

    def add_commissioning_server(commissioning_server : CommissioningServer, node_options : NamedTuple(uniqueNodeId: String?)?)
    end

    def add_commissioning_controller(commissioning_controller : CommissioningController, node_options : NamedTuple(uniqueNodeId: String?)?)
    end

    private def prepare_node(node : Node)
      node.disable_ipv4 = options.disable_ipv4
    end

    def start
    end

    def stop
    end
  end
end
