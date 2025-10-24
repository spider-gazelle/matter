require "./cluster"

module Matter
  module Cluster
    # Administrator Commissioning Cluster (0x003C)
    #
    # Provides functionality for opening commissioning windows to allow
    # new administrators to commission the device.
    #
    # Matter Spec: Core 11.18
    class AdministratorCommissioningCluster < Base
      CLUSTER_ID = 0x003C_u32

      # Commissioning Window Status
      enum CommissioningWindowStatus : UInt8
        WindowNotOpen      = 0 # No commissioning window open
        EnhancedWindowOpen = 1 # Enhanced commissioning window open (PAKE)
        BasicWindowOpen    = 2 # Basic commissioning window open
      end

      # Status Codes
      enum StatusCode : UInt8
        Busy               = 2 # Commissioning window already open
        PAKEParameterError = 3 # Invalid PAKE parameters
        WindowNotOpen      = 4 # No window open for revocation
      end

      # Attributes
      ATTR_WINDOW_STATUS      = 0x0000_u32
      ATTR_ADMIN_FABRIC_INDEX = 0x0001_u32
      ATTR_ADMIN_VENDOR_ID    = 0x0002_u32

      # Commands
      CMD_OPEN_COMMISSIONING_WINDOW       = 0x00_u32
      CMD_OPEN_BASIC_COMMISSIONING_WINDOW = 0x01_u32
      CMD_REVOKE_COMMISSIONING            = 0x02_u32

      # Attribute storage
      property window_status : CommissioningWindowStatus
      property admin_fabric_index : UInt8?
      property admin_vendor_id : UInt16?

      # Window state
      property window_timeout : Time?

      # PAKE parameters (for enhanced commissioning)
      property pake_verifier : Bytes?
      property discriminator : UInt16?
      property iterations : UInt32?
      property salt : Bytes?

      # Callbacks
      property on_open_commissioning_window : Proc(UInt16, Bytes, UInt16, Bytes, UInt32, UInt8, UInt16, StatusCode)?
      property on_open_basic_commissioning_window : Proc(UInt16, UInt8, UInt16, StatusCode)?
      property on_revoke_commissioning : Proc(StatusCode)?

      def initialize(endpoint_id : DataType::EndpointNumber)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @window_status = CommissioningWindowStatus::WindowNotOpen
        @admin_fabric_index = nil
        @admin_vendor_id = nil

        @window_timeout = nil

        @pake_verifier = nil
        @discriminator = nil
        @iterations = nil
        @salt = nil

        @on_open_commissioning_window = nil
        @on_open_basic_commissioning_window = nil
        @on_revoke_commissioning = nil
      end

      def name : String
        "AdministratorCommissioning"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_WINDOW_STATUS),
            "WindowStatus",
            :enum8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ADMIN_FABRIC_INDEX),
            "AdminFabricIndex",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ADMIN_VENDOR_ID),
            "AdminVendorId",
            :uint16,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_OPEN_COMMISSIONING_WINDOW),
            "OpenCommissioningWindow"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_OPEN_BASIC_COMMISSIONING_WINDOW),
            "OpenBasicCommissioningWindow"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_REVOKE_COMMISSIONING),
            "RevokeCommissioning"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_WINDOW_STATUS
          encode_uint8(@window_status.value)
        when ATTR_ADMIN_FABRIC_INDEX
          if index = @admin_fabric_index
            encode_uint8(index)
          else
            Bytes.new(0) # Null
          end
        when ATTR_ADMIN_VENDOR_ID
          if vendor = @admin_vendor_id
            encode_uint16(vendor)
          else
            Bytes.new(0) # Null
          end
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only
        super
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        case command_id
        when CMD_OPEN_COMMISSIONING_WINDOW
          handle_open_commissioning_window(fields)
        when CMD_OPEN_BASIC_COMMISSIONING_WINDOW
          handle_open_basic_commissioning_window(fields)
        when CMD_REVOKE_COMMISSIONING
          handle_revoke_commissioning(fields)
        else
          super
        end
      end

      private def handle_open_commissioning_window(fields : Bytes) : Bytes
        # Simplified implementation
        # TODO: Parse commissioningTimeout, PAKEVerifier, discriminator, iterations, salt from fields
        Bytes.new(0)
      end

      private def handle_open_basic_commissioning_window(fields : Bytes) : Bytes
        # Simplified implementation
        # TODO: Parse commissioningTimeout from fields
        Bytes.new(0)
      end

      private def handle_revoke_commissioning(fields : Bytes) : Bytes
        # Simplified implementation
        Bytes.new(0)
      end

      # Window management methods

      # Open enhanced commissioning window (with PAKE)
      def open_enhanced_window(timeout_seconds : UInt16, fabric_index : UInt8, vendor_id : UInt16) : Nil
        @window_status = CommissioningWindowStatus::EnhancedWindowOpen
        @admin_fabric_index = fabric_index
        @admin_vendor_id = vendor_id
        @window_timeout = Time.utc + timeout_seconds.seconds
        increment_version
      end

      # Open basic commissioning window
      def open_basic_window(timeout_seconds : UInt16, fabric_index : UInt8, vendor_id : UInt16) : Nil
        @window_status = CommissioningWindowStatus::BasicWindowOpen
        @admin_fabric_index = fabric_index
        @admin_vendor_id = vendor_id
        @window_timeout = Time.utc + timeout_seconds.seconds
        increment_version
      end

      # Close commissioning window
      def close_window : Nil
        @window_status = CommissioningWindowStatus::WindowNotOpen
        @admin_fabric_index = nil
        @admin_vendor_id = nil
        @window_timeout = nil
        @pake_verifier = nil
        @discriminator = nil
        @iterations = nil
        @salt = nil
        increment_version
      end

      # Check if window is expired
      def is_window_expired? : Bool
        return false unless timeout = @window_timeout
        Time.utc >= timeout
      end

      # Check if any commissioning window is open
      def is_window_open? : Bool
        !@window_status.window_not_open?
      end

      # Helper: Encode UInt16 as bytes
      private def encode_uint16(value : UInt16) : Bytes
        io = IO::Memory.new
        io.write_bytes(value, IO::ByteFormat::LittleEndian)
        io.to_slice
      end
    end
  end
end
