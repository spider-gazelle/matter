require "./cluster"
require "./definitions/on_off"

module Matter
  module Cluster
    # On/Off Cluster Implementation (0x0006)
    # Provides binary on/off control with optional lighting and timing features
    #
    # Features:
    # - Lighting (LT): Enables level control interaction and global scene management
    # - DeadFrontBehavior (DF): Device exhibits "dead front" when off
    # - OffOnly: Device can only be turned off (On/Toggle not supported)
    #
    # Matter Spec: Application Clusters 1.5
    class OnOffCluster < Base
      CLUSTER_ID = 0x0006_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        None              =    0
        Lighting          = 0x01 # LT - Lighting applications
        DeadFrontBehavior = 0x02 # DF - Dead front behavior when off
        OffOnly           = 0x04 # OFFONLY - Only off command supported
      end

      # Attribute IDs
      ATTR_ON_OFF               = 0x0000_u32
      ATTR_GLOBAL_SCENE_CONTROL = 0x4000_u32 # Lighting feature
      ATTR_ON_TIME              = 0x4001_u32 # Lighting feature
      ATTR_OFF_WAIT_TIME        = 0x4002_u32 # Lighting feature
      ATTR_START_UP_ON_OFF      = 0x4003_u32 # Lighting feature

      # Command IDs
      CMD_OFF                         = 0x00_u32
      CMD_ON                          = 0x01_u32 # Not with OffOnly
      CMD_TOGGLE                      = 0x02_u32 # Not with OffOnly
      CMD_OFF_WITH_EFFECT             = 0x40_u32 # Lighting feature
      CMD_ON_WITH_RECALL_GLOBAL_SCENE = 0x41_u32 # Lighting feature
      CMD_ON_WITH_TIMED_OFF           = 0x42_u32 # Lighting feature

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      # StartUpOnOff enum values
      enum StartUpOnOff : UInt8
        Off    = 0
        On     = 1
        Toggle = 2
      end

      # State
      property on_off : Bool
      property feature_map : Feature

      # Lighting feature attributes
      property global_scene_control : Bool
      property on_time : UInt16
      property off_wait_time : UInt16
      property start_up_on_off : StartUpOnOff?

      # Callbacks
      @on_state_changed : Proc(Bool, Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @on_off : Bool = false,
        @feature_map : Feature = Feature::None,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate feature combinations
        validate_features!

        # Initialize Lighting feature attributes
        @global_scene_control = true
        @on_time = 0_u16
        @off_wait_time = 0_u16
        @start_up_on_off = nil

        @attribute_values[ATTR_ON_OFF] = encode_bool(@on_off)
      end

      # Validate feature flag combinations per Matter spec
      private def validate_features!
        # Illegal: Lighting + OffOnly
        if feature_map.lighting? && feature_map.off_only?
          raise ArgumentError.new("OnOff cluster: Lighting and OffOnly features cannot be combined")
        end

        # Illegal: DeadFrontBehavior + OffOnly
        if feature_map.dead_front_behavior? && feature_map.off_only?
          raise ArgumentError.new("OnOff cluster: DeadFrontBehavior and OffOnly features cannot be combined")
        end
      end

      def name : String
        "OnOff"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          # Base attribute - always present
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ON_OFF),
            name: "onOff",
            type: :bool,
            writable: false,
            default: encode_bool(false)
          ),
          # Global attributes
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLUSTER_REVISION),
            name: "clusterRevision",
            type: :uint16,
            writable: false,
            default: encode_uint16(6_u16) # Cluster revision 6
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(FEATURE_MAP),
            name: "featureMap",
            type: :uint32,
            writable: false,
            default: encode_uint32(feature_map.value)
          ),
        ]

        # Lighting feature adds these attributes
        if feature_map.lighting?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_GLOBAL_SCENE_CONTROL),
            name: "globalSceneControl",
            type: :bool,
            writable: false,
            default: encode_bool(true)
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ON_TIME),
            name: "onTime",
            type: :uint16,
            writable: true,
            default: encode_uint16(0_u16)
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_OFF_WAIT_TIME),
            name: "offWaitTime",
            type: :uint16,
            writable: true,
            default: encode_uint16(0_u16)
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_START_UP_ON_OFF),
            name: "startUpOnOff",
            type: :enum8,
            writable: true,
            optional: true # Can be null
          )
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        cmds = [
          # Off command - always present
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_OFF),
            name: "off"
          ),
        ]

        # On and Toggle only available without OffOnly feature
        unless feature_map.off_only?
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ON),
            name: "on"
          )
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_TOGGLE),
            name: "toggle"
          )
        end

        # Lighting feature adds these commands
        if feature_map.lighting?
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_OFF_WITH_EFFECT),
            name: "offWithEffect"
          )
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ON_WITH_RECALL_GLOBAL_SCENE),
            name: "onWithRecallGlobalScene"
          )
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ON_WITH_TIMED_OFF),
            name: "onWithTimedOff"
          )
        end

        cmds
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_ON_OFF
          encode_bool(@on_off)
        when ATTR_GLOBAL_SCENE_CONTROL
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          encode_bool(@global_scene_control)
        when ATTR_ON_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          encode_uint16(@on_time)
        when ATTR_OFF_WAIT_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          encode_uint16(@off_wait_time)
        when ATTR_START_UP_ON_OFF
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          if suo = @start_up_on_off
            encode_uint8(suo.value)
          else
            # Return null
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            writer.put_null(nil)
            io.rewind.to_slice
          end
        when FEATURE_MAP
          encode_uint32(feature_map.value)
        when CLUSTER_REVISION
          encode_uint16(6_u16)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_ON_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          @on_time = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_OFF_WAIT_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          @off_wait_time = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_START_UP_ON_OFF
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          # Could be null or enum value
          if value.size > 0 && value[0] != 0x14 # Not TLV null
            @start_up_on_off = StartUpOnOff.from_value(value[0])
          else
            @start_up_on_off = nil
          end
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_OFF
          handle_off
        when CMD_ON
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) if feature_map.off_only?
          handle_on
        when CMD_TOGGLE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) if feature_map.off_only?
          handle_toggle
        when CMD_OFF_WITH_EFFECT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) unless feature_map.lighting?
          handle_off_with_effect(fields)
        when CMD_ON_WITH_RECALL_GLOBAL_SCENE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) unless feature_map.lighting?
          handle_on_with_recall_global_scene
        when CMD_ON_WITH_TIMED_OFF
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) unless feature_map.lighting?
          handle_on_with_timed_off(fields)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      private def handle_off : InteractionModel::Status
        set_on_off(false)
        if feature_map.lighting?
          @global_scene_control = false
        end
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def handle_on : InteractionModel::Status
        set_on_off(true)
        if feature_map.lighting?
          @global_scene_control = true
        end
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def handle_toggle : InteractionModel::Status
        if @on_off
          handle_off
        else
          handle_on
        end
      end

      private def handle_off_with_effect(fields : Bytes) : InteractionModel::Status
        # Would decode EffectIdentifier and EffectVariant from fields
        # For now, just turn off
        set_on_off(false)
        @global_scene_control = false
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def handle_on_with_recall_global_scene : InteractionModel::Status
        set_on_off(true)
        @global_scene_control = true
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def handle_on_with_timed_off(fields : Bytes) : InteractionModel::Status
        # Would decode OnOffControl, OnTime, OffWaitTime from fields
        # For now, just turn on
        set_on_off(true)
        @global_scene_control = true
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def set_on_off(value : Bool)
        if @on_off != value
          @on_off = value
          @attribute_values[ATTR_ON_OFF] = encode_bool(value)
          increment_version
          @on_state_changed.try &.call(value)
        end
      end

      # Set callback for state changes
      def on_state_changed(&block : Bool -> Nil)
        @on_state_changed = block
      end
    end
  end
end
