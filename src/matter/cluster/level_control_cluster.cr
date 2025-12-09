require "./cluster"

module Matter
  module Cluster
    # Level Control Cluster Implementation (0x0008)
    #
    # Provides level control (dimming) functionality for lights, volume controls,
    # blinds, and other devices with adjustable levels.
    #
    # Features:
    # - OnOff (OO): Dependency with the On/Off cluster
    # - Lighting (LT): Lighting control interface (affects level semantics)
    # - Frequency (FQ): Frequency control support (provisional)
    #
    # Matter Spec: Application 1.6
    class LevelControlCluster < Base
      CLUSTER_ID = 0x0008_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        OnOff     = 0x01 # OO - Dependency with On/Off cluster
        Lighting  = 0x02 # LT - Lighting control interface
        Frequency = 0x04 # FQ - Frequency control (provisional)
      end

      # Attributes
      ATTR_CURRENT_LEVEL          = 0x0000_u32
      ATTR_REMAINING_TIME         = 0x0001_u32 # Lighting feature
      ATTR_MIN_LEVEL              = 0x0002_u32
      ATTR_MAX_LEVEL              = 0x0003_u32
      ATTR_CURRENT_FREQUENCY      = 0x0004_u32 # Frequency feature
      ATTR_MIN_FREQUENCY          = 0x0005_u32 # Frequency feature
      ATTR_MAX_FREQUENCY          = 0x0006_u32 # Frequency feature
      ATTR_OPTIONS                = 0x000F_u32
      ATTR_ON_OFF_TRANSITION_TIME = 0x0010_u32 # Lighting feature
      ATTR_ON_LEVEL               = 0x0011_u32
      ATTR_ON_TRANSITION_TIME     = 0x0012_u32 # Lighting feature
      ATTR_OFF_TRANSITION_TIME    = 0x0013_u32 # Lighting feature
      ATTR_DEFAULT_MOVE_RATE      = 0x0014_u32 # Lighting feature
      ATTR_START_UP_CURRENT_LEVEL = 0x4000_u32 # Lighting feature

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      # Commands
      CMD_MOVE_TO_LEVEL             = 0x00_u32
      CMD_MOVE                      = 0x01_u32
      CMD_STEP                      = 0x02_u32
      CMD_STOP                      = 0x03_u32
      CMD_MOVE_TO_LEVEL_WITH_ON_OFF = 0x04_u32 # OnOff feature
      CMD_MOVE_WITH_ON_OFF          = 0x05_u32 # OnOff feature
      CMD_STEP_WITH_ON_OFF          = 0x06_u32 # OnOff feature
      CMD_STOP_WITH_ON_OFF          = 0x07_u32 # OnOff feature
      CMD_MOVE_TO_CLOSEST_FREQUENCY = 0x08_u32 # Frequency feature

      # Move Mode enum
      enum MoveMode : UInt8
        Up   = 0
        Down = 1
      end

      # Step Mode enum
      enum StepMode : UInt8
        Up   = 0
        Down = 1
      end

      # Feature map
      property feature_map : Feature

      # Base attributes
      property current_level : UInt8
      property min_level : UInt8
      property max_level : UInt8
      property on_level : UInt8?
      property options : UInt8

      # Lighting feature attributes
      property remaining_time : UInt16
      property on_off_transition_time : UInt16
      property on_transition_time : UInt16?
      property off_transition_time : UInt16?
      property default_move_rate : UInt8?
      property start_up_current_level : UInt8?

      # Frequency feature attributes
      property current_frequency : UInt16
      property min_frequency : UInt16
      property max_frequency : UInt16

      # Callbacks
      @on_level_changed : Proc(UInt8, UInt8, Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @current_level : UInt8 = 0_u8,
        @min_level : UInt8 = 0_u8,
        @max_level : UInt8 = 254_u8,
        @on_level : UInt8? = nil,
        @options : UInt8 = 0_u8,
        @feature_map : Feature = Feature::OnOff | Feature::Lighting,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Initialize Lighting feature attributes
        @remaining_time = 0_u16
        @on_off_transition_time = 0_u16
        @on_transition_time = nil
        @off_transition_time = nil
        @default_move_rate = nil
        @start_up_current_level = nil

        # Initialize Frequency feature attributes
        @current_frequency = 0_u16
        @min_frequency = 0_u16
        @max_frequency = 0_u16
      end

      def name : String
        "LevelControl"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [] of AttributeMetadata

        # CurrentLevel (mandatory)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_CURRENT_LEVEL),
          name: "currentLevel",
          type: :uint8,
          writable: false,
          min: 0_i64,
          max: 254_i64
        )

        # MinLevel (optional, default depends on Lighting feature)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_MIN_LEVEL),
          name: "minLevel",
          type: :uint8,
          writable: false,
          optional: true
        )

        # MaxLevel (optional)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_MAX_LEVEL),
          name: "maxLevel",
          type: :uint8,
          writable: false,
          optional: true
        )

        # Options (mandatory)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_OPTIONS),
          name: "options",
          type: :uint8,
          writable: true
        )

        # OnLevel (optional)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_ON_LEVEL),
          name: "onLevel",
          type: :uint8,
          writable: true,
          optional: true
        )

        # Lighting feature attributes
        if @feature_map.lighting?
          # RemainingTime (mandatory with LT)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_REMAINING_TIME),
            name: "remainingTime",
            type: :uint16,
            writable: false
          )

          # OnOffTransitionTime (optional)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ON_OFF_TRANSITION_TIME),
            name: "onOffTransitionTime",
            type: :uint16,
            writable: true,
            optional: true
          )

          # OnTransitionTime (optional)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ON_TRANSITION_TIME),
            name: "onTransitionTime",
            type: :uint16,
            writable: true,
            optional: true
          )

          # OffTransitionTime (optional)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_OFF_TRANSITION_TIME),
            name: "offTransitionTime",
            type: :uint16,
            writable: true,
            optional: true
          )

          # DefaultMoveRate (optional)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_DEFAULT_MOVE_RATE),
            name: "defaultMoveRate",
            type: :uint8,
            writable: true,
            optional: true
          )

          # StartUpCurrentLevel (mandatory with LT)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_START_UP_CURRENT_LEVEL),
            name: "startUpCurrentLevel",
            type: :uint8,
            writable: true
          )
        end

        # Frequency feature attributes
        if @feature_map.frequency?
          # CurrentFrequency (mandatory with FQ)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_CURRENT_FREQUENCY),
            name: "currentFrequency",
            type: :uint16,
            writable: false
          )

          # MinFrequency (mandatory with FQ)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_MIN_FREQUENCY),
            name: "minFrequency",
            type: :uint16,
            writable: false
          )

          # MaxFrequency (mandatory with FQ)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_MAX_FREQUENCY),
            name: "maxFrequency",
            type: :uint16,
            writable: false
          )
        end

        # Global attributes
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(CLUSTER_REVISION),
          name: "clusterRevision",
          type: :uint16,
          writable: false,
          default: encode_uint16(5_u16)
        )

        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(FEATURE_MAP),
          name: "featureMap",
          type: :uint32,
          writable: false,
          default: encode_uint32(@feature_map.value)
        )

        attrs
      end

      def commands : Array(CommandMetadata)
        cmds = [] of CommandMetadata

        # Base commands (always present)
        cmds << CommandMetadata.new(
          id: DataType::CommandId.new(CMD_MOVE_TO_LEVEL),
          name: "moveToLevel"
        )

        cmds << CommandMetadata.new(
          id: DataType::CommandId.new(CMD_MOVE),
          name: "move"
        )

        cmds << CommandMetadata.new(
          id: DataType::CommandId.new(CMD_STEP),
          name: "step"
        )

        cmds << CommandMetadata.new(
          id: DataType::CommandId.new(CMD_STOP),
          name: "stop"
        )

        # OnOff feature commands
        if @feature_map.on_off?
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_MOVE_TO_LEVEL_WITH_ON_OFF),
            name: "moveToLevelWithOnOff"
          )

          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_MOVE_WITH_ON_OFF),
            name: "moveWithOnOff"
          )

          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STEP_WITH_ON_OFF),
            name: "stepWithOnOff"
          )

          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STOP_WITH_ON_OFF),
            name: "stopWithOnOff"
          )
        end

        # Frequency feature commands
        if @feature_map.frequency?
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_MOVE_TO_CLOSEST_FREQUENCY),
            name: "moveToClosestFrequency"
          )
        end

        cmds
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_CURRENT_LEVEL
          encode_uint8(@current_level)
        when ATTR_MIN_LEVEL
          encode_uint8(@min_level)
        when ATTR_MAX_LEVEL
          encode_uint8(@max_level)
        when ATTR_OPTIONS
          encode_uint8(@options)
        when ATTR_ON_LEVEL
          if level = @on_level
            encode_uint8(level)
          else
            encode_null
          end
        when ATTR_REMAINING_TIME
          return unsupported_attribute unless @feature_map.lighting?
          encode_uint16(@remaining_time)
        when ATTR_ON_OFF_TRANSITION_TIME
          return unsupported_attribute unless @feature_map.lighting?
          encode_uint16(@on_off_transition_time)
        when ATTR_ON_TRANSITION_TIME
          return unsupported_attribute unless @feature_map.lighting?
          if time = @on_transition_time
            encode_uint16(time)
          else
            encode_null
          end
        when ATTR_OFF_TRANSITION_TIME
          return unsupported_attribute unless @feature_map.lighting?
          if time = @off_transition_time
            encode_uint16(time)
          else
            encode_null
          end
        when ATTR_DEFAULT_MOVE_RATE
          return unsupported_attribute unless @feature_map.lighting?
          if rate = @default_move_rate
            encode_uint8(rate)
          else
            encode_null
          end
        when ATTR_START_UP_CURRENT_LEVEL
          return unsupported_attribute unless @feature_map.lighting?
          if level = @start_up_current_level
            encode_uint8(level)
          else
            encode_null
          end
        when ATTR_CURRENT_FREQUENCY
          return unsupported_attribute unless @feature_map.frequency?
          encode_uint16(@current_frequency)
        when ATTR_MIN_FREQUENCY
          return unsupported_attribute unless @feature_map.frequency?
          encode_uint16(@min_frequency)
        when ATTR_MAX_FREQUENCY
          return unsupported_attribute unless @feature_map.frequency?
          encode_uint16(@max_frequency)
        when FEATURE_MAP
          encode_uint32(@feature_map.value)
        when CLUSTER_REVISION
          encode_uint16(5_u16)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_OPTIONS
          if value.size >= 1
            @options = value[0]
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ATTR_ON_LEVEL
          if value.size >= 1
            new_level = value[0]
            if new_level >= @min_level && new_level <= @max_level
              @on_level = new_level
              increment_version
              InteractionModel::Status.new(InteractionModel::StatusCode::Success)
            else
              InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
            end
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ATTR_ON_OFF_TRANSITION_TIME
          return unsupported_attribute unless @feature_map.lighting?
          if value.size >= 2
            @on_off_transition_time = IO::ByteFormat::LittleEndian.decode(UInt16, value)
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ATTR_ON_TRANSITION_TIME
          return unsupported_attribute unless @feature_map.lighting?
          if value.size >= 2
            @on_transition_time = IO::ByteFormat::LittleEndian.decode(UInt16, value)
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ATTR_OFF_TRANSITION_TIME
          return unsupported_attribute unless @feature_map.lighting?
          if value.size >= 2
            @off_transition_time = IO::ByteFormat::LittleEndian.decode(UInt16, value)
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ATTR_DEFAULT_MOVE_RATE
          return unsupported_attribute unless @feature_map.lighting?
          if value.size >= 1
            @default_move_rate = value[0]
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ATTR_START_UP_CURRENT_LEVEL
          return unsupported_attribute unless @feature_map.lighting?
          if value.size >= 1
            @start_up_current_level = value[0]
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_MOVE_TO_LEVEL
          handle_move_to_level_command(fields)
        when CMD_MOVE
          handle_move_command(fields)
        when CMD_STEP
          handle_step_command(fields)
        when CMD_STOP
          handle_stop_command(fields)
        when CMD_MOVE_TO_LEVEL_WITH_ON_OFF
          return unsupported_command unless @feature_map.on_off?
          handle_move_to_level_command(fields)
        when CMD_MOVE_WITH_ON_OFF
          return unsupported_command unless @feature_map.on_off?
          handle_move_command(fields)
        when CMD_STEP_WITH_ON_OFF
          return unsupported_command unless @feature_map.on_off?
          handle_step_command(fields)
        when CMD_STOP_WITH_ON_OFF
          return unsupported_command unless @feature_map.on_off?
          handle_stop_command(fields)
        when CMD_MOVE_TO_CLOSEST_FREQUENCY
          return unsupported_command unless @feature_map.frequency?
          handle_move_to_closest_frequency(fields)
        else
          super
        end
      end

      # Handle MoveToLevel command
      private def handle_move_to_level_command(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 1

        target_level = fields[0]
        move_to_level(target_level)
      end

      # Handle Move command
      private def handle_move_command(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 1

        # For simplified implementation, just indicate success
        # Real implementation would start continuous movement
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Handle Step command
      private def handle_step_command(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 2

        mode = StepMode.from_value(fields[0])
        step_size = fields[1]

        case mode
        when StepMode::Up
          new_level = @current_level.to_u16 + step_size
          move_to_level([new_level, @max_level.to_u16].min.to_u8)
        when StepMode::Down
          new_level = @current_level.to_i16 - step_size
          move_to_level([new_level, @min_level.to_i16].max.to_u8)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
        end
      end

      # Handle Stop command
      private def handle_stop_command(fields : Bytes) : InteractionModel::Status
        @remaining_time = 0_u16
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Handle MoveToClosestFrequency command
      private def handle_move_to_closest_frequency(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 2

        target_frequency = IO::ByteFormat::LittleEndian.decode(UInt16, fields)

        # Clamp to valid range
        clamped = [@min_frequency, [target_frequency, @max_frequency].min].max
        @current_frequency = clamped
        increment_version

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Move to a specific level with clamping
      private def move_to_level(new_level : UInt8) : InteractionModel::Status
        old_level = @current_level

        # Clamp to valid range
        clamped_level = [@min_level, [new_level, @max_level].min].max

        @current_level = clamped_level
        @remaining_time = 0_u16 # Instant transition for simplified implementation
        increment_version

        # Trigger callback if level actually changed
        if old_level != @current_level
          @on_level_changed.try &.call(old_level, @current_level)
        end

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Set callback for level changes
      def on_level_changed(&block : UInt8, UInt8 -> Nil)
        @on_level_changed = block
      end

      # Helper methods
      private def unsupported_attribute : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
      end

      private def unsupported_command : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
      end

      private def encode_null : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put_null(nil)
        io.rewind.to_slice
      end
    end
  end
end
