require "./cluster"

module Matter
  module Cluster
    # Level Control Cluster Implementation (0x0008)
    #
    # Provides level control (dimming) functionality for lights, volume controls,
    # blinds, and other devices with adjustable levels.
    #
    # Matter Spec: Application 1.6
    class LevelControlCluster < Base
      CLUSTER_ID = 0x0008_u32

      # Attributes (using ATTR_ prefix for consistency)
      ATTR_CURRENT_LEVEL          = 0x0000_u32
      ATTR_REMAINING_TIME         = 0x0001_u32
      ATTR_MIN_LEVEL              = 0x0002_u32
      ATTR_MAX_LEVEL              = 0x0003_u32
      ATTR_CURRENT_FREQUENCY      = 0x0004_u32
      ATTR_MIN_FREQUENCY          = 0x0005_u32
      ATTR_MAX_FREQUENCY          = 0x0006_u32
      ATTR_OPTIONS                = 0x000F_u32
      ATTR_ON_OFF_TRANSITION_TIME = 0x0010_u32
      ATTR_ON_LEVEL               = 0x0011_u32
      ATTR_ON_TRANSITION_TIME     = 0x0012_u32
      ATTR_OFF_TRANSITION_TIME    = 0x0013_u32
      ATTR_DEFAULT_MOVE_RATE      = 0x0014_u32
      ATTR_START_UP_CURRENT_LEVEL = 0x4000_u32

      # Commands
      CMD_MOVE_TO_LEVEL             = 0x00_u32
      CMD_MOVE                      = 0x01_u32
      CMD_STEP                      = 0x02_u32
      CMD_STOP                      = 0x03_u32
      CMD_MOVE_TO_LEVEL_WITH_ON_OFF = 0x04_u32
      CMD_MOVE_WITH_ON_OFF          = 0x05_u32
      CMD_STEP_WITH_ON_OFF          = 0x06_u32
      CMD_STOP_WITH_ON_OFF          = 0x07_u32
      CMD_MOVE_TO_CLOSEST_FREQUENCY = 0x08_u32

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

      # Attribute storage
      property current_level : UInt8
      property min_level : UInt8
      property max_level : UInt8
      property remaining_time : UInt16
      property on_level : UInt8?
      property options : UInt8

      # Callbacks
      @on_level_changed : Proc(UInt8, UInt8, Nil)?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @current_level : UInt8 = 0_u8,
                     @min_level : UInt8 = 0_u8,
                     @max_level : UInt8 = 254_u8,
                     @on_level : UInt8? = nil,
                     @options : UInt8 = 0_u8)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @remaining_time = 0_u16
      end

      def name : String
        "LevelControl"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CURRENT_LEVEL),
            "CurrentLevel",
            :uint8,
            writable: false,
            min: 0_i64,
            max: 254_i64
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_REMAINING_TIME),
            "RemainingTime",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MIN_LEVEL),
            "MinLevel",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MAX_LEVEL),
            "MaxLevel",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OPTIONS),
            "Options",
            :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ON_LEVEL),
            "OnLevel",
            :uint8,
            writable: true
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_MOVE_TO_LEVEL),
            "MoveToLevel"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_MOVE),
            "Move"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_STEP),
            "Step"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_STOP),
            "Stop"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_MOVE_TO_LEVEL_WITH_ON_OFF),
            "MoveToLevelWithOnOff"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_MOVE_WITH_ON_OFF),
            "MoveWithOnOff"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_STEP_WITH_ON_OFF),
            "StepWithOnOff"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_STOP_WITH_ON_OFF),
            "StopWithOnOff"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_MOVE_TO_CLOSEST_FREQUENCY),
            "MoveToClosestFrequency"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_CURRENT_LEVEL
          encode_uint8(@current_level)
        when ATTR_REMAINING_TIME
          encode_uint16(@remaining_time)
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
            InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
          end
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
            # Validate range
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
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_MOVE_TO_LEVEL, CMD_MOVE_TO_LEVEL_WITH_ON_OFF
          handle_move_to_level_command(fields)
        when CMD_MOVE, CMD_MOVE_WITH_ON_OFF
          handle_move_command(fields)
        when CMD_STEP, CMD_STEP_WITH_ON_OFF
          handle_step_command(fields)
        when CMD_STOP, CMD_STOP_WITH_ON_OFF
          handle_stop_command(fields)
        when CMD_MOVE_TO_CLOSEST_FREQUENCY
          # Frequency control not implemented
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
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
    end
  end
end
