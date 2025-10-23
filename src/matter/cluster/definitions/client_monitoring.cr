module Matter
  module Cluster
    module Definitions
      module ClientMonitoring
        struct MonitoringRegistration
          include TLV::Serializable

          @[TLV::Field(tag: 1)]
          property client_node_id : DataType::NodeId

          @[TLV::Field(tag: 2)]
          property icid : UInt64
        end

        # Input to the ClientMonitoring registerClientMonitoring command
        struct RegisterClientMonitoringRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property client_node_id : DataType::NodeId

          @[TLV::Field(tag: 1)]
          property icid : UInt64
        end

        # Input to the ClientMonitoring unregisterClientMonitoring command
        struct UnregisterClientMonitoringRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property client_node_id : DataType::NodeId

          @[TLV::Field(tag: 1)]
          property icid : UInt64
        end
      end
    end
  end
end
