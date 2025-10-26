require "./cluster"
require "./definitions/general_commissioning"

module Matter
  module Cluster
    # General Commissioning Cluster (0x0030)
    #
    # Provides commissioning functionality including fail-safe management,
    # regulatory configuration, and commissioning state tracking.
    #
    # Matter Spec: Core 11.9
    class GeneralCommissioningCluster < Base
      CLUSTER_ID = 0x0030_u32

      # Regulatory Location Type
      enum RegulatoryLocationType : UInt8
        Indoor        = 0 # Indoor use only
        Outdoor       = 1 # Outdoor use only
        IndoorOutdoor = 2 # Indoor and outdoor use
      end

      # Commissioning Error Codes
      enum CommissioningError : UInt8
        OK                    = 0 # Success
        ValueOutsideRange     = 1 # Value outside allowed range
        InvalidAuthentication = 2 # Invalid authentication
        NoFailSafe            = 3 # Fail-safe not armed
        BusyWithOtherAdmin    = 4 # Busy with another administrator
      end

      # Attributes
      ATTR_BREADCRUMB                     = 0x0000_u32
      ATTR_BASIC_COMMISSIONING_INFO       = 0x0001_u32
      ATTR_REGULATORY_CONFIG              = 0x0002_u32
      ATTR_LOCATION_CAPABILITY            = 0x0003_u32
      ATTR_SUPPORTS_CONCURRENT_CONNECTION = 0x0004_u32

      # Commands
      CMD_ARM_FAIL_SAFE                   = 0x00_u32
      CMD_ARM_FAIL_SAFE_RESPONSE          = 0x01_u32
      CMD_SET_REGULATORY_CONFIG           = 0x02_u32
      CMD_SET_REGULATORY_CONFIG_RESPONSE  = 0x03_u32
      CMD_COMMISSIONING_COMPLETE          = 0x04_u32
      CMD_COMMISSIONING_COMPLETE_RESPONSE = 0x05_u32

      # Basic Commissioning Info Structure
      struct BasicCommissioningInfo
        property fail_safe_expiry_length : UInt16         # Max fail-safe seconds
        property max_cumulative_failsafe_seconds : UInt16 # Max cumulative fail-safe time

        def initialize(@fail_safe_expiry_length : UInt16, @max_cumulative_failsafe_seconds : UInt16)
        end
      end

      # Attribute storage
      property breadcrumb : UInt64
      property basic_commissioning_info : BasicCommissioningInfo
      property regulatory_config : RegulatoryLocationType
      property location_capability : RegulatoryLocationType
      property supports_concurrent_connection : Bool

      # Regulatory info
      property country_code : String

      # Fail-safe state
      property fail_safe_active : Bool
      property fail_safe_expiry_time : Time?

      # Callbacks
      property on_arm_fail_safe : Proc(UInt16, UInt64, CommissioningError)?
      property on_set_regulatory_config : Proc(RegulatoryLocationType, String, UInt64, CommissioningError)?
      property on_commissioning_complete : Proc(CommissioningError)?

      def initialize(endpoint_id : DataType::EndpointNumber)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @breadcrumb = 0_u64
        @basic_commissioning_info = BasicCommissioningInfo.new(
          fail_safe_expiry_length: 60_u16,
          max_cumulative_failsafe_seconds: 900_u16
        )
        @regulatory_config = RegulatoryLocationType::IndoorOutdoor
        @location_capability = RegulatoryLocationType::IndoorOutdoor
        @supports_concurrent_connection = true

        @country_code = "XX" # Unknown/default

        @fail_safe_active = false
        @fail_safe_expiry_time = nil

        @on_arm_fail_safe = nil
        @on_set_regulatory_config = nil
        @on_commissioning_complete = nil
      end

      def name : String
        "GeneralCommissioning"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BREADCRUMB),
            "Breadcrumb",
            :uint64,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BASIC_COMMISSIONING_INFO),
            "BasicCommissioningInfo",
            :struct,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_REGULATORY_CONFIG),
            "RegulatoryConfig",
            :enum8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_LOCATION_CAPABILITY),
            "LocationCapability",
            :enum8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SUPPORTS_CONCURRENT_CONNECTION),
            "SupportsConcurrentConnection",
            :bool,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_ARM_FAIL_SAFE),
            "ArmFailSafe"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_SET_REGULATORY_CONFIG),
            "SetRegulatoryConfig"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_COMMISSIONING_COMPLETE),
            "CommissioningComplete"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_BREADCRUMB
          encode_uint64(@breadcrumb)
        when ATTR_BASIC_COMMISSIONING_INFO
          encode_basic_commissioning_info
        when ATTR_REGULATORY_CONFIG
          encode_uint8(@regulatory_config.value)
        when ATTR_LOCATION_CAPABILITY
          encode_uint8(@location_capability.value)
        when ATTR_SUPPORTS_CONCURRENT_CONNECTION
          encode_bool(@supports_concurrent_connection)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_BREADCRUMB
          if value.size >= 8
            io = IO::Memory.new(value)
            @breadcrumb = io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        case command_id
        when CMD_ARM_FAIL_SAFE
          handle_arm_fail_safe(fields)
        when CMD_SET_REGULATORY_CONFIG
          handle_set_regulatory_config(fields)
        when CMD_COMMISSIONING_COMPLETE
          handle_commissioning_complete(fields)
        else
          super
        end
      end

      private def handle_arm_fail_safe(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::GeneralCommissioning::ArmFailSafeRequest.new(fields)

        # Use callback if available
        error_code = if callback = @on_arm_fail_safe
                       callback.call(request.expiryLengthSeconds, request.breadcrumb)
                     else
                       # Default implementation
                       if request.expiryLengthSeconds == 0
                         disarm_fail_safe
                       else
                         arm_fail_safe(request.expiryLengthSeconds)
                         @breadcrumb = request.breadcrumb
                       end
                       CommissioningError::OK
                     end

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => error_code.value,
          1_u8 => "", # debug_text
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_set_regulatory_config(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::GeneralCommissioning::SetRegularConfigurationRequest.new(fields)

        # Convert definitions enum to cluster enum
        regulatory_config = RegulatoryLocationType.from_value(request.new_regulatory_configuration.value)

        # Use callback if available
        error_code = if callback = @on_set_regulatory_config
                       callback.call(
                         regulatory_config,
                         request.country_code,
                         request.breadcrumb
                       )
                     else
                       # Default implementation
                       @regulatory_config = regulatory_config
                       @country_code = request.country_code
                       @breadcrumb = request.breadcrumb
                       increment_version
                       CommissioningError::OK
                     end

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => error_code.value,
          1_u8 => "", # debug_text
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_commissioning_complete(fields : Bytes) : Bytes
        # CommissioningComplete has no request fields

        # Use callback if available
        error_code = if callback = @on_commissioning_complete
                       callback.call
                     else
                       # Default implementation
                       if @fail_safe_active
                         disarm_fail_safe
                         @breadcrumb = 0_u64
                         CommissioningError::OK
                       else
                         CommissioningError::NoFailSafe
                       end
                     end

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => error_code.value,
          1_u8 => "", # debug_text
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      # Fail-safe management methods

      # Arm the fail-safe timer
      def arm_fail_safe(expiry_seconds : UInt16) : Nil
        @fail_safe_active = true
        @fail_safe_expiry_time = Time.utc + expiry_seconds.seconds
        increment_version
      end

      # Disarm the fail-safe timer
      def disarm_fail_safe : Nil
        @fail_safe_active = false
        @fail_safe_expiry_time = nil
        increment_version
      end

      # Check if fail-safe has expired
      def is_fail_safe_expired? : Bool
        return false unless @fail_safe_active
        return false unless expiry = @fail_safe_expiry_time

        Time.utc >= expiry
      end

      # Helper: Encode UInt64 as bytes
      private def encode_uint64(value : UInt64) : Bytes
        io = IO::Memory.new
        io.write_bytes(value, IO::ByteFormat::LittleEndian)
        io.to_slice
      end

      # Helper: Encode BasicCommissioningInfo as TLV structure
      private def encode_basic_commissioning_info : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => @basic_commissioning_info.fail_safe_expiry_length,
          1_u8 => @basic_commissioning_info.max_cumulative_failsafe_seconds,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end
    end
  end
end
