module Matter
  module Cluster
    module Definitions
      module Binding
        struct Target
          # This field is the remote target node ID. If the Endpoint field is present, this field shall be present.
          @[TLV::Field(tag: 1)]
          property node : DataType::NodeId?

          # This field is the target group ID that represents remote endpoints. If the Endpoint field is present, this
          # field shall NOT be present.
          @[TLV::Field(tag: 2)]
          property group : DataType::GroupId?

          # This field is the remote endpoint that the local endpoint is bound to. If the Group field is present, this
          # field shall NOT be present.
          @[TLV::Field(tag: 3)]
          property endpoint : DataType::EndpointNumber?

          # This field is the cluster ID (client & server) on the local and target endpoint(s). If this field is
          # present, the client cluster shall also exist on this endpoint (with this Binding cluster). If this field is
          # present, the target shall be this cluster on the target endpoint(s).
          @[TLV::Field(tag: 4)]
          property cluster : DataType::ClusterId?

          @[TLV::Field(tag: 254)]
          property fabric_index : DataType::FabricIndex
        end
      end
    end
  end
end
