require "./cluster"
require "./definitions/level_control"

module Matter
  module Cluster
    # Level Control Cluster Implementation (0x0008)
    # Provides level control (dimming) functionality
    class LevelControlCluster < Base
      CLUSTER_ID = 0x0008_u32

      # Attribute IDs
      CURRENT_LEVEL          = 0x0000_u32
      REMAINING_TIME         = 0x0001_u32
      MIN_LEVEL              = 0x0002_u32
      MAX_LEVEL              = 0x0003_u32
      CURRENT_FREQUENCY      = 0x0004_u32
      MIN_FREQUENCY          = 0x0005_u32
      MAX_FREQUENCY          = 0x0006_u32
      OPTIONS                = 0x000F_u32
      ON_OFF_TRANSITION_TIME = 0x0010_u32
      ON_LEVEL               = 0x0011_u32
      ON_TRANSITION_TIME     = 0x0012_u32
      OFF_TRANSITION_TIME    = 0x0013_u32
      DEFAULT_MOVE_RATE      = 0x0014_u32
      START_UP_CURRENT_LEVEL = 0x4000_u32

      # Command IDs
      CMD_MOVE_TO_LEVEL             = 0x00_u32
      CMD_MOVE                      = 0x01_u32
      CMD_STEP                      = 0x02_u32
      CMD_STOP                      = 0x03_u32
      CMD_MOVE_TO_LEVEL_WITH_ON_OFF = 0x04_u32
      CMD_MOVE_WITH_ON_OFF          = 0x05_u32
      CMD_STEP_WITH_ON_OFF          = 0x06_u32
      CMD_STOP_WITH_ON_OFF          = 0x07_u32
      CMD_MOVE_TO_CLOSEST_FREQUENCY = 0x08_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      property current_level : UInt8
      property min_level : UInt8
      property max_level : UInt8
      property remaining_time : UInt16
      property on_level : UInt8?
      property options : UInt8

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @current_level : UInt8 = 0_u8,
        @min_level : UInt8 = 0_u8,
        @max_level : UInt8 = 254_u8,
        @on_level : UInt8? = nil,
        @options : UInt8 = 0_u8,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @remaining_time = 0_u16
        @attribute_values[CURRENT_LEVEL] = encode_uint8(@current_level)
        @attribute_values[MIN_LEVEL] = encode_uint8(@min_level)
        @attribute_values[MAX_LEVEL] = encode_uint8(@max_level)
        @attribute_values[OPTIONS] = encode_uint8(@options)
      end

      def name : String
        "LevelControl"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CURRENT_LEVEL),
            name: "CurrentLevel",
            type: :uint8,
            writable: false,
            min: 0,
            max: 254
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(REMAINING_TIME),
            name: "RemainingTime",
            type: :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(MIN_LEVEL),
            name: "MinLevel",
            type: :uint8,
            writable: false,
            default: encode_uint8(0_u8)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(MAX_LEVEL),
            name: "MaxLevel",
            type: :uint8,
            writable: false,
            default: encode_uint8(254_u8)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(OPTIONS),
            name: "Options",
            type: :uint8,
            writable: true,
            default: encode_uint8(0_u8)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ON_LEVEL),
            name: "OnLevel",
            type: :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLUSTER_REVISION),
            name: "ClusterRevision",
            type: :uint16,
            writable: false,
            default: encode_uint16(5_u16)
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
            id: DataType::CommandId.new(CMD_MOVE_TO_LEVEL),
            name: "MoveToLevel"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_MOVE),
            name: "Move"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STEP),
            name: "Step"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STOP),
            name: "Stop"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_MOVE_TO_LEVEL_WITH_ON_OFF),
            name: "MoveToLevelWithOnOff"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_MOVE_WITH_ON_OFF),
            name: "MoveWithOnOff"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STEP_WITH_ON_OFF),
            name: "StepWithOnOff"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STOP_WITH_ON_OFF),
            name: "StopWithOnOff"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_MOVE_TO_CLOSEST_FREQUENCY),
            name: "MoveToClosestFrequency"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when CURRENT_LEVEL
          encode_uint8(@current_level)
        when REMAINING_TIME
          encode_uint16(@remaining_time)
        when MIN_LEVEL
          encode_uint8(@min_level)
        when MAX_LEVEL
          encode_uint8(@max_level)
        when OPTIONS
          encode_uint8(@options)
        when ON_LEVEL
          if level = @on_level
            encode_uint8(level)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
          end
        else
          super(attribute_id)
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when OPTIONS
          if value.size >= 1
            @options = value[0]
            @attribute_values[OPTIONS] = encode_uint8(@options)
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ON_LEVEL
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
          super(attribute_id, value)
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        case command_id
        when CMD_MOVE_TO_LEVEL, CMD_MOVE_TO_LEVEL_WITH_ON_OFF
          # Would decode MoveToLevelRequest from fields
          # For simplified implementation, just set to mid-level
          move_to_level(127_u8)
        when CMD_MOVE, CMD_MOVE_WITH_ON_OFF
          # Would decode MoveRequest from fields
          # For simplified implementation, increment level
          new_level = @current_level.to_u16 + 10
          move_to_level([new_level, @max_level.to_u16].min.to_u8)
        when CMD_STEP, CMD_STEP_WITH_ON_OFF
          # Would decode StepRequest from fields
          # For simplified implementation, step by 10
          new_level = @current_level.to_u16 + 10
          move_to_level([new_level, @max_level.to_u16].min.to_u8)
        when CMD_STOP, CMD_STOP_WITH_ON_OFF
          # Stop any transitions
          @remaining_time = 0_u16
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when CMD_MOVE_TO_CLOSEST_FREQUENCY
          # Frequency control not implemented
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      private def move_to_level(new_level : UInt8) : InteractionModel::Status
        # Clamp to valid range
        new_level = [@min_level, [new_level, @max_level].min].max

        @current_level = new_level
        @attribute_values[CURRENT_LEVEL] = encode_uint8(@current_level)
        @remaining_time = 0_u16 # Instant transition for simplified implementation
        increment_version
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end
    end
  end
end
