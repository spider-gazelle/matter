require "./cluster"
require "./definitions/on_off"

module Matter
  module Cluster
    # On/Off Cluster Implementation (0x0006)
    # Provides binary on/off control
    class OnOffCluster < Base
      CLUSTER_ID = 0x0006_u32

      # Attribute IDs (using ATTR_ prefix for consistency)
      ATTR_ON_OFF = 0x0000_u32

      # Command IDs
      CMD_OFF        = 0x00_u32
      CMD_ON         = 0x01_u32
      CMD_TOGGLE     = 0x02_u32
      CMD_OFF_EFFECT = 0x40_u32
      CMD_ON_RECALL  = 0x41_u32
      CMD_ON_TIMED   = 0x42_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      property on_off : Bool

      # Callbacks
      @on_state_changed : Proc(Bool, Nil)?

      def initialize(endpoint_id : DataType::EndpointNumber, @on_off : Bool = false)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @attribute_values[ATTR_ON_OFF] = encode_bool(@on_off)
      end

      def name : String
        "OnOff"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ON_OFF),
            name: "OnOff",
            type: :bool,
            writable: false,
            default: encode_bool(false)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLUSTER_REVISION),
            name: "ClusterRevision",
            type: :uint16,
            writable: false,
            default: encode_uint16(4_u16)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(FEATURE_MAP),
            name: "FeatureMap",
            type: :uint32,
            writable: false,
            default: encode_uint32(0_u32)
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_OFF),
            name: "Off"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ON),
            name: "On"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_TOGGLE),
            name: "Toggle"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_OFF_EFFECT),
            name: "OffWithEffect"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ON_RECALL),
            name: "OnWithRecallGlobalScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ON_TIMED),
            name: "OnWithTimedOff"
          ),
        ]
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_OFF
          set_on_off(false)
        when CMD_ON
          set_on_off(true)
        when CMD_TOGGLE
          set_on_off(!@on_off)
        when CMD_OFF_EFFECT
          # Would decode OffWithEffectRequest from fields
          set_on_off(false)
        when CMD_ON_RECALL
          set_on_off(true)
        when CMD_ON_TIMED
          # Would decode OnWithTimedOffRequest from fields
          set_on_off(true)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      private def set_on_off(value : Bool) : InteractionModel::Status
        # Only update if state actually changes (optimization)
        if @on_off != value
          @on_off = value
          @attribute_values[ATTR_ON_OFF] = encode_bool(value)
          increment_version

          # Trigger callback only on actual change
          @on_state_changed.try &.call(value)
        end

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Set callback for state changes
      def on_state_changed(&block : Bool -> Nil)
        @on_state_changed = block
      end
    end
  end
end
