require "../interaction_model/status_code"
require "../interaction_model/paths"
require "../datatype/*"
require "./definitions/access_control"

module Matter
  module Cluster
    # Attribute metadata
    struct AttributeMetadata
      property id : DataType::AttributeId
      property name : String
      property type : Symbol # :bool, :uint8, :uint16, :uint32, :int8, :string, :array, etc.
      property writable : Bool
      property default : Bytes?
      property min : Int64?
      property max : Int64?
      property access : Definitions::AccessControl::EntryPrivilege

      def initialize(
        @id : DataType::AttributeId,
        @name : String,
        @type : Symbol,
        @writable : Bool = false,
        @default : Bytes? = nil,
        @min : Int64? = nil,
        @max : Int64? = nil,
        @access : Definitions::AccessControl::EntryPrivilege = Definitions::AccessControl::EntryPrivilege::View,
      )
      end
    end

    # Command metadata
    struct CommandMetadata
      property id : DataType::CommandId
      property name : String
      property access : Definitions::AccessControl::EntryPrivilege

      def initialize(
        @id : DataType::CommandId,
        @name : String,
        @access : Definitions::AccessControl::EntryPrivilege = Definitions::AccessControl::EntryPrivilege::Operate,
      )
      end
    end

    # Event metadata
    struct EventMetadata
      property id : DataType::EventId
      property name : String
      property priority : InteractionModel::EventPriority

      def initialize(
        @id : DataType::EventId,
        @name : String,
        @priority : InteractionModel::EventPriority = InteractionModel::EventPriority::Info,
      )
      end
    end

    # Base class for all cluster implementations
    abstract class Base
      property endpoint_id : DataType::EndpointNumber
      property cluster_id : DataType::ClusterId
      property data_version : UInt32

      # Macro to add class method for accessing CLUSTER_ID constant
      macro inherited
        def self.cluster_id
          CLUSTER_ID
        end
      end

      def initialize(@endpoint_id : DataType::EndpointNumber, @cluster_id : DataType::ClusterId)
        @data_version = 0_u32
        @attribute_values = {} of UInt32 => Bytes
      end

      # Get cluster name
      abstract def name : String

      # Get all attribute metadata
      abstract def attributes : Array(AttributeMetadata)

      # Get all command metadata
      def commands : Array(CommandMetadata)
        [] of CommandMetadata
      end

      # Get all event metadata
      def events : Array(EventMetadata)
        [] of EventMetadata
      end

      # Read an attribute value
      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        metadata = attributes.find { |a| a.id.id == attribute_id }
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless metadata

        # Return stored value or default
        @attribute_values.fetch(attribute_id) do
          metadata.default || InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
        end
      end

      # Write an attribute value
      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        metadata = attributes.find { |a| a.id.id == attribute_id }
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless metadata
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedWrite) unless metadata.writable

        # Validate value (simplified - real implementation would decode and validate)
        @attribute_values[attribute_id] = value
        @data_version += 1

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Invoke a command
      def invoke_command(command_id : UInt32, fields : Bytes = Bytes.new(0)) : InteractionModel::Status | Bytes
        metadata = commands.find { |c| c.id.id == command_id }
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) unless metadata

        # Command implementations override this
        handle_command(command_id, fields)
      end

      # Handle command implementation (to be overridden)
      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
      end

      # Increment data version (call when attribute changes)
      protected def increment_version
        @data_version += 1
      end

      # Get attribute metadata by ID
      def get_attribute_metadata(attribute_id : UInt32) : AttributeMetadata?
        attributes.find { |a| a.id.id == attribute_id }
      end

      # Get command metadata by ID
      def get_command_metadata(command_id : UInt32) : CommandMetadata?
        commands.find { |c| c.id.id == command_id }
      end

      # Helper methods for encoding simple values
      protected def encode_uint8(value : UInt8) : Bytes
        Bytes[value]
      end

      protected def encode_uint16(value : UInt16) : Bytes
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(value, io)
        io.to_slice
      end

      protected def encode_uint32(value : UInt32) : Bytes
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(value, io)
        io.to_slice
      end

      protected def encode_bool(value : Bool) : Bytes
        Bytes[value ? 1_u8 : 0_u8]
      end
    end
  end
end
