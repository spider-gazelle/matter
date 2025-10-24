require "./cluster"
require "./definitions/identify"

module Matter
  module Cluster
    # Identify Cluster Implementation (0x0003)
    # Provides a way to identify devices (e.g., by flashing a light or making a sound)
    class IdentifyCluster < Base
      CLUSTER_ID = 0x0003_u32

      # Attribute IDs
      IDENTIFY_TIME = 0x0000_u32
      IDENTIFY_TYPE = 0x0001_u32

      # Command IDs
      CMD_IDENTIFY       = 0x00_u32
      CMD_TRIGGER_EFFECT = 0x01_u32
      CMD_IDENTIFY_QUERY = 0x40_u32

      # Response IDs
      CMD_IDENTIFY_QUERY_RESPONSE = 0x00_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      property identify_time : UInt16
      property identify_type : Definitions::Identify::Type

      # Callback for when identify is triggered
      property on_identify : Proc(UInt16, Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @identify_time : UInt16 = 0_u16,
        @identify_type : Definitions::Identify::Type = Definitions::Identify::Type::None,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @attribute_values[IDENTIFY_TIME] = encode_uint16(@identify_time)
        @attribute_values[IDENTIFY_TYPE] = encode_uint8(@identify_type.value)
      end

      def name : String
        "Identify"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(IDENTIFY_TIME),
            name: "IdentifyTime",
            type: :uint16,
            writable: true,
            default: encode_uint16(0_u16)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(IDENTIFY_TYPE),
            name: "IdentifyType",
            type: :uint8,
            writable: false,
            default: encode_uint8(Definitions::Identify::Type::None.value)
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
            id: DataType::CommandId.new(CMD_IDENTIFY),
            name: "Identify"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_TRIGGER_EFFECT),
            name: "TriggerEffect"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_IDENTIFY_QUERY),
            name: "IdentifyQuery"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when IDENTIFY_TIME
          encode_uint16(@identify_time)
        when IDENTIFY_TYPE
          encode_uint8(@identify_type.value)
        else
          super(attribute_id)
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when IDENTIFY_TIME
          if value.size >= 2
            # Decode little-endian UInt16
            @identify_time = IO::ByteFormat::LittleEndian.decode(UInt16, value)
            @attribute_values[IDENTIFY_TIME] = encode_uint16(@identify_time)
            increment_version

            # Trigger identify callback if time is non-zero
            if @identify_time > 0
              @on_identify.try(&.call(@identify_time))
            end

            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        else
          super(attribute_id, value)
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        case command_id
        when CMD_IDENTIFY
          # Would decode Definitions::Identify::Request from fields
          # For simplified implementation, set identify time to 5 seconds
          @identify_time = 5_u16
          @attribute_values[IDENTIFY_TIME] = encode_uint16(@identify_time)
          increment_version

          # Trigger identify callback
          @on_identify.try(&.call(@identify_time))

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when CMD_TRIGGER_EFFECT
          # Would decode Definitions::Identify::TriggerEffectRequest from fields
          # For simplified implementation, trigger a default effect
          @on_identify.try(&.call(3_u16)) # 3 second effect

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when CMD_IDENTIFY_QUERY
          # Return current identify time if device is identifying
          if @identify_time > 0
            # Encode IdentifyQueryResponse
            io = IO::Memory.new
            IO::ByteFormat::LittleEndian.encode(@identify_time, io)
            io.to_slice
          else
            # No response if not identifying
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          end
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      # Helper method to start identifying
      def start_identify(duration : UInt16)
        @identify_time = duration
        @attribute_values[IDENTIFY_TIME] = encode_uint16(@identify_time)
        increment_version
        @on_identify.try(&.call(@identify_time))
      end

      # Helper method to stop identifying
      def stop_identify
        @identify_time = 0_u16
        @attribute_values[IDENTIFY_TIME] = encode_uint16(@identify_time)
        increment_version
      end
    end
  end
end
