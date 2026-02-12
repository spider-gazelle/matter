require "./cluster"

module Matter
  module Cluster
    # Boolean State Cluster (0x0045)
    #
    # Exposes a single read-only boolean state value.
    # Commonly used by contact sensors.
    class BooleanStateCluster < Base
      CLUSTER_ID = 0x0045_u32

      ATTR_STATE_VALUE = 0x0000_u32

      getter? state_value : Bool

      def initialize(endpoint_id : DataType::EndpointNumber, @state_value : Bool = false)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      def name : String
        "BooleanState"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_STATE_VALUE),
            "StateValue",
            :bool,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_STATE_VALUE
          @state_value.to_tlv
        else
          super
        end
      end

      def update_state(value : Bool)
        old_value = @state_value
        return if old_value == value

        @state_value = value
        increment_version_and_notify(ATTR_STATE_VALUE)
        @on_state_changed.try &.call(old_value, value)
      end

      @on_state_changed : Proc(Bool, Bool, Nil)?

      def on_state_changed(&block : Bool, Bool -> Nil)
        @on_state_changed = block
      end
    end
  end
end
