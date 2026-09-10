require "./cluster"

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

      CLUSTER_REVISION = 6_u16

      # StartUpOnOff enum values
      enum StartUpOnOff : UInt8
        Off    = 0
        On     = 1
        Toggle = 2
      end

      # State
      property? on_off : Bool
      property feature_map : Feature

      # Lighting feature attributes
      property? global_scene_control : Bool
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

        @attribute_values[ATTR_ON_OFF] = @on_off.to_tlv
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
        # Only cluster-specific attributes - global attributes (FeatureMap, ClusterRevision, etc.)
        # are handled by the base class
        attrs = [
          # Base attribute - always present
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ON_OFF),
            name: "onOff",
            type: :bool,
            writable: false,
            default: false.to_tlv
          ),
        ]

        # Lighting feature adds these attributes
        if feature_map.lighting?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_GLOBAL_SCENE_CONTROL),
            name: "globalSceneControl",
            type: :bool,
            writable: false,
            default: true.to_tlv
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ON_TIME),
            name: "onTime",
            type: :uint16,
            writable: true,
            default: 0_u16.to_tlv
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_OFF_WAIT_TIME),
            name: "offWaitTime",
            type: :uint16,
            writable: true,
            default: 0_u16.to_tlv
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
          @on_off.to_tlv
        when ATTR_GLOBAL_SCENE_CONTROL
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          @global_scene_control.to_tlv
        when ATTR_ON_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          @on_time.to_tlv
        when ATTR_OFF_WAIT_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          @off_wait_time.to_tlv
        when ATTR_START_UP_ON_OFF
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          if suo = @start_up_on_off
            suo.value.to_tlv
          else
            nil.to_tlv
          end
        when GLOBAL_FEATURE_MAP
          feature_map.value.to_tlv
        when GLOBAL_ATTRIBUTE_LIST
          encode_attribute_list
        when GLOBAL_ACCEPTED_COMMAND_LIST
          encode_accepted_command_list
        when GLOBAL_GENERATED_COMMAND_LIST
          encode_generated_command_list
        else
          super
        end
      end

      # Encode list of supported attribute IDs as TLV array
      private def encode_attribute_list : Bytes
        # Build list of supported attributes
        attr_ids = [ATTR_ON_OFF]

        # Lighting feature adds additional attributes
        if feature_map.lighting?
          attr_ids << ATTR_GLOBAL_SCENE_CONTROL
          attr_ids << ATTR_ON_TIME
          attr_ids << ATTR_OFF_WAIT_TIME
          attr_ids << ATTR_START_UP_ON_OFF
        end

        # Global attributes (always present)
        attr_ids << GLOBAL_GENERATED_COMMAND_LIST
        attr_ids << GLOBAL_ACCEPTED_COMMAND_LIST
        attr_ids << GLOBAL_ATTRIBUTE_LIST
        attr_ids << GLOBAL_FEATURE_MAP
        attr_ids << GLOBAL_CLUSTER_REVISION

        attr_ids.to_tlv
      end

      # Encode list of accepted command IDs as TLV array
      private def encode_accepted_command_list : Bytes
        cmd_ids = [CMD_OFF]

        # On and Toggle only available without OffOnly feature
        unless feature_map.off_only?
          cmd_ids << CMD_ON
          cmd_ids << CMD_TOGGLE
        end

        # Lighting feature adds additional commands
        if feature_map.lighting?
          cmd_ids << CMD_OFF_WITH_EFFECT
          cmd_ids << CMD_ON_WITH_RECALL_GLOBAL_SCENE
          cmd_ids << CMD_ON_WITH_TIMED_OFF
        end

        cmd_ids.to_tlv
      end

      # Encode list of generated command IDs as TLV array (empty for OnOff)
      private def encode_generated_command_list : Bytes
        # OnOff cluster doesn't generate any response commands
        ([] of UInt32).to_tlv
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_ON_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          on_time = decode_u16(value)
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) unless on_time
          @on_time = on_time
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_OFF_WAIT_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          off_wait_time = decode_u16(value)
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) unless off_wait_time
          @off_wait_time = off_wait_time
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_START_UP_ON_OFF
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless feature_map.lighting?
          # Nullable enum
          if tlv_null?(value)
            @start_up_on_off = nil
          else
            start_up = decode_u8(value)
            return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) unless start_up
            @start_up_on_off = StartUpOnOff.from_value(start_up)
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
          @attribute_values[ATTR_ON_OFF] = value.to_tlv
          increment_version_and_notify(ATTR_ON_OFF)
          @on_state_changed.try &.call(value)
        end
      end

      # ------------------------------------------------------------------------
      # Public Interface
      # ------------------------------------------------------------------------

      def on? : Bool
        @on_off
      end

      def off? : Bool
        !@on_off
      end

      def on=(state : Bool) : Bool
        state ? handle_on : handle_off
        state
      end

      def toggle : Bool
        handle_toggle
        @on_off
      end

      # ------------------------------------------------------------------------
      # Persistence support
      # ------------------------------------------------------------------------

      private struct PersistedState
        include JSON::Serializable

        getter? on_off : Bool
        getter? global_scene_control : Bool
        getter on_time : UInt16
        getter off_wait_time : UInt16
        getter start_up_on_off : UInt8?
        getter data_version : UInt32

        def initialize(
          @on_off : Bool,
          @global_scene_control : Bool,
          @on_time : UInt16,
          @off_wait_time : UInt16,
          @start_up_on_off : UInt8?,
          @data_version : UInt32,
        )
        end
      end

      def save_state : String?
        PersistedState.new(
          on_off: @on_off,
          global_scene_control: @global_scene_control,
          on_time: @on_time,
          off_wait_time: @off_wait_time,
          start_up_on_off: @start_up_on_off.try(&.value),
          data_version: @data_version
        ).to_json
      end

      def restore_state(json : String) : Nil
        state = PersistedState.from_json(json)

        @on_off = state.on_off?
        @attribute_values[ATTR_ON_OFF] = @on_off.to_tlv

        if feature_map.lighting?
          @global_scene_control = state.global_scene_control?
          @on_time = state.on_time
          @off_wait_time = state.off_wait_time
          @start_up_on_off = state.start_up_on_off.try { |v| StartUpOnOff.from_value(v) }
        end

        @data_version = state.data_version
      rescue
        # Start fresh if restore fails
      end

      # ------------------------------------------------------------------------
      # ScenesManagement extension field sets
      # ------------------------------------------------------------------------
      def store_scene_extension_field_set : ScenesManagementCluster::ExtensionFieldSet?
        ScenesManagementCluster::ExtensionFieldSet.new(
          cluster_id: CLUSTER_ID,
          attribute_list: [
            {ATTR_ON_OFF, @on_off.to_tlv},
          ]
        )
      end

      def apply_scene_extension_field_set(field_set : ScenesManagementCluster::ExtensionFieldSet) : Bool
        return false unless field_set.cluster_id == CLUSTER_ID

        field_set.attribute_value_list.each do |attribute_id, value|
          next unless attribute_id == ATTR_ON_OFF

          begin
            parsed = TLV::Any.from_slice(value).value
            case parsed
            when Bool
              set_on_off(parsed)
              return true
            end
          rescue
            # Ignore malformed TLV
          end
        end

        false
      end

      # Set callback for state changes
      def on_state_changed(&block : Bool -> Nil)
        @on_state_changed = block
      end
    end
  end
end
