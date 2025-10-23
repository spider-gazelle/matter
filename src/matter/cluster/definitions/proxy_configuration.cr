module Matter
  module Cluster
    module Definitions
      module ProxyConfiguration
        # ProxyAllNodes
        #
        # This field shall be set to to 'true' to indicate to the proxy that it shall proxy all nodes. When 'true', the
        # SourceList attribute is ignored.
        #
        # SourceList
        #
        # When ProxyAllNodes is 'false', this list contains the set of NodeIds of sources that this proxy shall
        # specifically proxy.
        struct Configuration
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property proxy_all_nodes : Bool

          @[TLV::Field(tag: 1)]
          property source_list : Array(DataType::NodeId)
        end
      end
    end
  end
end
