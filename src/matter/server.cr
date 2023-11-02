module Matter
  class Server
    getter nodes : Array(Node) = [] of Node

    getter storage_manager : Storage::Manager
    getter server_options : NamedTuple(disable_ipv4: Bool, mdns_announce_interface: String) = {disable_ipv4: false, mdns_announce_interface: "*"}

    def initialize(@storage_manager : Storage::Manager, server_options : NamedTuple(disable_ipv4: Bool, mdns_announce_interface: String)? = nil)
      @server_options = server_options unless server_options.nil?
    end

    def disable_ipv4? : Bool
      server_options.disableIpv4 && server_options.disableIpv4
    end

    def add_commissioning_server(commissioning_server : CommissioningServer, node_options : NamedTuple(uniqueNodeId: String?)?)
    end

    def add_commissioning_controller(commissioning_controller : CommissioningController, node_options : NamedTuple(uniqueNodeId: String?)?)
    end

    private def prepare_node(node : Node)
      node.disable_ipv4 = server_options.disable_ipv4
    end

    def start
    end

    def stop
    end
  end
end
