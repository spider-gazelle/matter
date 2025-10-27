require "./cluster"
require "./definitions/general_commissioning"
require "../failsafe_context"
require "log"

module Matter
  module Cluster
    # General Commissioning Cluster (0x0030)
    #
    # Provides commands and attributes to support the device commissioning process.
    # This includes commissioning window management, failsafe timer management,
    # regulatory configuration, and commissioning completion.
    #
    # Matter Core Spec §11.9 - General Commissioning Cluster
    class GeneralCommissioningCluster < Base
      Log = ::Log.for("matter.cluster.general_commissioning")

      CLUSTER_ID = 0x0030_u32

      # ========================================================================
      # Enumerations
      # ========================================================================

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
        RequiredTCNotAccepted = 5 # Terms & Conditions not accepted
        TCMinVersionNotMet    = 6 # Terms & Conditions minimum version not met
        TCRequired            = 7 # Terms & Conditions required
      end

      # ========================================================================
      # Command Structures
      # ========================================================================

      # ArmFailSafe command request
      struct ArmFailSafeRequest
        property expiry_length_seconds : UInt16
        property breadcrumb : UInt64
        property timeout_ms : UInt32 = 0_u32 # Deprecated, kept for compatibility

        def initialize(@expiry_length_seconds, @breadcrumb, @timeout_ms = 0_u32)
        end
      end

      # ArmFailSafe command response
      struct ArmFailSafeResponse
        property error_code : CommissioningError
        property debug_text : String = ""

        def initialize(@error_code, @debug_text = "")
        end
      end

      # SetRegulatoryConfig command request
      struct SetRegulatoryConfigRequest
        property new_regulatory_config : RegulatoryLocationType
        property country_code : String
        property breadcrumb : UInt64

        def initialize(@new_regulatory_config, @country_code, @breadcrumb)
        end
      end

      # SetRegulatoryConfig command response
      struct SetRegulatoryConfigResponse
        property error_code : CommissioningError
        property debug_text : String = ""

        def initialize(@error_code, @debug_text = "")
        end
      end

      # CommissioningComplete command response
      struct CommissioningCompleteResponse
        property error_code : CommissioningError
        property debug_text : String = ""

        def initialize(@error_code, @debug_text = "")
        end
      end

      # BasicCommissioningInfo - returned by BasicCommissioningInfo attribute
      struct BasicCommissioningInfo
        property fail_safe_expiry_length : UInt16
        property max_cumulative_failsafe_seconds : UInt16

        def initialize(@fail_safe_expiry_length, @max_cumulative_failsafe_seconds)
        end
      end

      # ========================================================================
      # Attributes
      # ========================================================================

      ATTR_BREADCRUMB                     = 0x0000_u32
      ATTR_BASIC_COMMISSIONING_INFO       = 0x0001_u32
      ATTR_REGULATORY_CONFIG              = 0x0002_u32
      ATTR_LOCATION_CAPABILITY            = 0x0003_u32
      ATTR_SUPPORTS_CONCURRENT_CONNECTION = 0x0004_u32

      # Breadcrumb attribute (0x0000) - progress tracking during commissioning
      property breadcrumb : UInt64 = 0_u64

      # BasicCommissioningInfo attribute (0x0001)
      # Contains MaxCumulativeFailsafeSeconds and MaxNetworkCommissioningSeconds
      property max_cumulative_failsafe_seconds : UInt16 = 900_u16   # 15 minutes default
      property max_network_commissioning_seconds : UInt16 = 900_u16 # 15 minutes default

      # RegulatoryConfig attribute (0x0002) - current regulatory location
      property regulatory_config : RegulatoryLocationType = RegulatoryLocationType::IndoorOutdoor

      # Country code (stored for rollback purposes)
      property country_code : String = "XX" # Default: unknown/unspecified

      # LocationCapability attribute (0x0003) - supported regulatory locations
      property location_capability : RegulatoryLocationType = RegulatoryLocationType::IndoorOutdoor

      # SupportsConcurrentConnection attribute (0x0004)
      property supports_concurrent_connection : Bool = true

      # ========================================================================
      # Commands
      # ========================================================================

      CMD_ARM_FAIL_SAFE                   = 0x00_u32
      CMD_ARM_FAIL_SAFE_RESPONSE          = 0x01_u32
      CMD_SET_REGULATORY_CONFIG           = 0x02_u32
      CMD_SET_REGULATORY_CONFIG_RESPONSE  = 0x03_u32
      CMD_COMMISSIONING_COMPLETE          = 0x04_u32
      CMD_COMMISSIONING_COMPLETE_RESPONSE = 0x05_u32

      # ========================================================================
      # Feature Support
      # ========================================================================

      # Terms & Conditions feature support
      property terms_conditions_required : Bool = false

      # Country code whitelist (nil = all countries allowed)
      property country_code_whitelist : Array(String)? = nil

      # ========================================================================
      # State Management
      # ========================================================================

      @failsafe_context : FailsafeContext?
      @admin_fabric_index : UInt8?
      @commissioning_window_open : Bool = false
      @terms_conditions_accepted : Bool = false

      # ========================================================================
      # Callbacks
      # ========================================================================

      # Callback to check if Terms & Conditions have been accepted
      property on_check_terms_conditions : (Proc(Bool))? = nil

      # Callback to persist the fabric table after successful commissioning
      property on_persist_fabric_table : (Proc(Nil))? = nil

      # Callback to clear all PASE sessions after successful commissioning
      property on_clear_pase_sessions : (Proc(Nil))? = nil

      # ========================================================================
      # Initialization
      # ========================================================================

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @failsafe_context = nil
        @admin_fabric_index = nil
        @commissioning_window_open = false
        @terms_conditions_accepted = false
      end

      # ========================================================================
      # Base Class Implementation
      # ========================================================================

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
          handle_arm_fail_safe_tlv(fields)
        when CMD_SET_REGULATORY_CONFIG
          handle_set_regulatory_config_tlv(fields)
        when CMD_COMMISSIONING_COMPLETE
          handle_commissioning_complete_tlv(fields)
        else
          super
        end
      end

      # ========================================================================
      # TLV Command Handlers (for Base class routing)
      # ========================================================================

      private def handle_arm_fail_safe_tlv(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request_def = Definitions::GeneralCommissioning::ArmFailSafeRequest.new(fields)

        # Convert to cluster request struct
        request = ArmFailSafeRequest.new(
          expiry_length_seconds: request_def.expiryLengthSeconds,
          breadcrumb: request_def.breadcrumb
        )

        # Call public command handler (session info would come from context in real implementation)
        response = arm_failsafe(
          request: request,
          session_fabric_index: nil,
          is_pase_session: true
        )

        # Encode response as TLV
        encode_arm_fail_safe_response(response)
      end

      private def handle_set_regulatory_config_tlv(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request_def = Definitions::GeneralCommissioning::SetRegularConfigurationRequest.new(fields)

        # Convert to cluster request struct
        request = SetRegulatoryConfigRequest.new(
          new_regulatory_config: RegulatoryLocationType.from_value(request_def.new_regulatory_configuration.value),
          country_code: request_def.country_code,
          breadcrumb: request_def.breadcrumb
        )

        # Call public command handler
        response = set_regulatory_config(request)

        # Encode response as TLV
        encode_set_regulatory_config_response(response)
      end

      private def handle_commissioning_complete_tlv(fields : Bytes) : Bytes
        # CommissioningComplete has no request fields

        # Call public command handler (session info would come from context in real implementation)
        response = commissioning_complete(
          session_fabric_index: nil,
          is_case_session: false
        )

        # Encode response as TLV
        encode_commissioning_complete_response(response)
      end

      # ========================================================================
      # ArmFailSafe Command (0x00)
      # ========================================================================

      # Handle ArmFailSafe command
      #
      # Arms or re-arms the failsafe timer. The failsafe timer ensures that commissioning
      # changes are rolled back if commissioning doesn't complete successfully.
      #
      # @param request ArmFailSafe request with expiry length and breadcrumb
      # @param session_fabric_index Fabric index of requesting session (nil for PASE)
      # @param is_pase_session Whether this is a PASE session
      # @return ArmFailSafe response with status
      def arm_failsafe(
        request : ArmFailSafeRequest,
        session_fabric_index : UInt8?,
        is_pase_session : Bool,
      ) : ArmFailSafeResponse
        Log.info { "ArmFailSafe: expiry=#{request.expiry_length_seconds}s, breadcrumb=#{request.breadcrumb}, fabric=#{session_fabric_index || "PASE"}" }

        # Validate expiry length is within spec limits
        if request.expiry_length_seconds > 0 && request.expiry_length_seconds > @max_cumulative_failsafe_seconds
          return ArmFailSafeResponse.new(
            CommissioningError::ValueOutsideRange,
            "ExpiryLengthSeconds exceeds max (#{@max_cumulative_failsafe_seconds}s)"
          )
        end

        # Check for conflicts with other admins
        # PASE sessions get priority when commissioning window is open
        # Also allow PASE (nil) to transition to CASE (fabric) for AddNOC
        if context = @failsafe_context
          # If there's an existing context, check for conflicts
          unless context.matches_fabric?(session_fabric_index)
            # Different fabric is trying to commission

            # Allow PASE→CASE transition (nil → fabric) for AddNOC
            if context.associated_fabric_index.nil? && session_fabric_index
              Log.info { "PASE transitioning to CASE with fabric #{session_fabric_index}" }
              # Allow re-arm to proceed (will update fabric below)
            elsif is_pase_session && @commissioning_window_open
              # PASE gets priority - expire existing failsafe
              Log.warn { "PASE session taking over from fabric #{context.associated_fabric_index}" }
              expire_failsafe
            else
              # CASE session blocked by another admin
              return ArmFailSafeResponse.new(
                CommissioningError::BusyWithOtherAdmin,
                "Another admin is currently commissioning"
              )
            end
          end
        end

        # Handle disarm (expiry_length = 0)
        if request.expiry_length_seconds == 0
          if context = @failsafe_context
            Log.info { "Disarming failsafe" }
            context.disarm
            @failsafe_context = nil
            @admin_fabric_index = nil
          end
          # Don't update breadcrumb on disarm
          return ArmFailSafeResponse.new(CommissioningError::OK)
        end

        # Create or re-arm failsafe context
        if context = @failsafe_context
          # Re-arm existing context
          begin
            context.arm(request.expiry_length_seconds, @max_cumulative_failsafe_seconds)
            @breadcrumb = request.breadcrumb

            # Update fabric if PASE→CASE transition
            if context.associated_fabric_index.nil? && session_fabric_index
              context.associated_fabric_index = session_fabric_index
              @admin_fabric_index = session_fabric_index
              Log.info { "Updated failsafe fabric to #{session_fabric_index} (PASE→CASE transition)" }
            end

            Log.info { "Re-armed failsafe" }
          rescue ex
            Log.error(exception: ex) { "Failed to re-arm failsafe" }
            return ArmFailSafeResponse.new(
              CommissioningError::BusyWithOtherAdmin,
              "Cannot re-arm: #{ex.message}"
            )
          end
        else
          # Create new context
          @failsafe_context = FailsafeContext.new(
            associated_fabric_index: session_fabric_index,
            breadcrumb: request.breadcrumb,
            expiry_callback: -> { handle_failsafe_expiry }
          )
          @failsafe_context.not_nil!.arm(
            request.expiry_length_seconds,
            @max_cumulative_failsafe_seconds
          )
          @admin_fabric_index = session_fabric_index
          @breadcrumb = request.breadcrumb
          Log.info { "Armed new failsafe" }
        end

        ArmFailSafeResponse.new(CommissioningError::OK)
      end

      # ========================================================================
      # CommissioningComplete Command (0x04)
      # ========================================================================

      # Handle CommissioningComplete command
      #
      # Signals that commissioning is complete. This validates that all required
      # commissioning steps have been performed, then disarms the failsafe and
      # persists the commissioned state.
      #
      # @param session_fabric_index Fabric index of requesting session
      # @param is_case_session Whether this is a CASE session (required)
      # @return CommissioningComplete response with status
      def commissioning_complete(
        session_fabric_index : UInt8?,
        is_case_session : Bool,
      ) : CommissioningCompleteResponse
        Log.info { "CommissioningComplete: fabric=#{session_fabric_index}" }

        # Validate session type - MUST be CASE
        unless is_case_session
          return CommissioningCompleteResponse.new(
            CommissioningError::InvalidAuthentication,
            "CommissioningComplete requires CASE session"
          )
        end

        # Validate failsafe is armed
        context = @failsafe_context
        unless context && context.armed?
          return CommissioningCompleteResponse.new(
            CommissioningError::NoFailSafe,
            "No active failsafe context"
          )
        end

        # Validate fabric matches failsafe context
        unless context.matches_fabric?(session_fabric_index)
          return CommissioningCompleteResponse.new(
            CommissioningError::InvalidAuthentication,
            "Fabric mismatch: expected #{context.associated_fabric_index}, got #{session_fabric_index}"
          )
        end

        # Validate Terms & Conditions acceptance if TC feature is enabled
        if @terms_conditions_required
          tc_accepted = if callback = @on_check_terms_conditions
                          callback.call
                        else
                          @terms_conditions_accepted
                        end

          unless tc_accepted
            return CommissioningCompleteResponse.new(
              CommissioningError::RequiredTCNotAccepted,
              "Terms and Conditions not accepted"
            )
          end
        end

        # Success - disarm failsafe and persist state
        Log.info { "Commissioning completed successfully" }
        context.disarm
        @failsafe_context = nil
        @admin_fabric_index = nil

        # Reset breadcrumb on successful completion
        @breadcrumb = 0_u64

        # Persist fabric table to non-volatile storage
        if callback = @on_persist_fabric_table
          callback.call
          Log.debug { "Fabric table persisted" }
        end

        # Close commissioning window
        close_commissioning_window

        # Clear PASE sessions (no longer needed after successful commissioning)
        if callback = @on_clear_pase_sessions
          callback.call
          Log.debug { "PASE sessions cleared" }
        end

        CommissioningCompleteResponse.new(CommissioningError::OK)
      end

      # ========================================================================
      # SetRegulatoryConfig Command (0x02)
      # ========================================================================

      # Handle SetRegulatoryConfig command
      #
      # Sets the regulatory configuration (indoor/outdoor) and country code.
      #
      # @param request SetRegulatoryConfig request
      # @return SetRegulatoryConfig response with status
      def set_regulatory_config(
        request : SetRegulatoryConfigRequest,
      ) : SetRegulatoryConfigResponse
        Log.info { "SetRegulatoryConfig: location=#{request.new_regulatory_config}, country=#{request.country_code}" }

        # Validate regulatory location against capability
        unless validate_regulatory_location(request.new_regulatory_config)
          return SetRegulatoryConfigResponse.new(
            CommissioningError::ValueOutsideRange,
            "Requested location #{request.new_regulatory_config} not supported (capability: #{@location_capability})"
          )
        end

        # Validate country code format (2-character ISO 3166-1 alpha-2)
        unless request.country_code.size == 2 && request.country_code.chars.all?(&.ascii_uppercase?)
          return SetRegulatoryConfigResponse.new(
            CommissioningError::ValueOutsideRange,
            "Invalid country code format (expected 2 uppercase letters)"
          )
        end

        # Validate country code against whitelist if configured
        if whitelist = @country_code_whitelist
          unless whitelist.includes?(request.country_code)
            return SetRegulatoryConfigResponse.new(
              CommissioningError::ValueOutsideRange,
              "Country code #{request.country_code} not in whitelist"
            )
          end
        end

        # Record current state for rollback if failsafe is armed
        if context = @failsafe_context
          if context.armed?
            context.record_regulatory_config(@regulatory_config.value, @country_code)
          end
        end

        # Apply configuration atomically (only update breadcrumb on success)
        @regulatory_config = request.new_regulatory_config
        @country_code = request.country_code
        @breadcrumb = request.breadcrumb

        Log.info { "Regulatory config updated" }
        SetRegulatoryConfigResponse.new(CommissioningError::OK)
      end

      # ========================================================================
      # Helper Methods
      # ========================================================================

      # Validate that requested regulatory location is within capability
      private def validate_regulatory_location(requested : RegulatoryLocationType) : Bool
        case @location_capability
        when RegulatoryLocationType::Indoor
          requested == RegulatoryLocationType::Indoor
        when RegulatoryLocationType::Outdoor
          requested == RegulatoryLocationType::Outdoor
        when RegulatoryLocationType::IndoorOutdoor
          true # All locations supported
        else
          false
        end
      end

      # Handle failsafe timer expiry - perform rollback
      private def handle_failsafe_expiry : Nil
        Log.warn { "Failsafe expired - performing rollback" }

        if context = @failsafe_context
          context.rollback(general_commissioning: self)
          @failsafe_context = nil
          @admin_fabric_index = nil
        end

        # Close commissioning window
        @commissioning_window_open = false

        # Reset breadcrumb
        @breadcrumb = 0_u64
      end

      # Manually expire the failsafe (for PASE takeover)
      private def expire_failsafe : Nil
        if context = @failsafe_context
          context.disarm
          handle_failsafe_expiry
        end
      end

      # Check if failsafe is currently armed
      def failsafe_armed? : Bool
        if context = @failsafe_context
          context.armed?
        else
          false
        end
      end

      # Alias for backward compatibility
      def fail_safe_active : Bool
        failsafe_armed?
      end

      # Get failsafe expiry time (when it will expire)
      def fail_safe_expiry_time : Time?
        if context = @failsafe_context
          if remaining = context.primary_time_remaining
            Time.utc + remaining
          end
        end
      end

      # Simple arm failsafe method for tests (arms with default max cumulative)
      def arm_fail_safe(expiry_seconds : UInt16) : Nil
        # Create failsafe context if needed
        unless @failsafe_context
          @failsafe_context = FailsafeContext.new(
            associated_fabric_index: nil,
            breadcrumb: @breadcrumb,
            expiry_callback: -> { handle_failsafe_expiry }
          )
        end

        # Arm the failsafe with the specified duration
        @failsafe_context.not_nil!.arm(expiry_seconds, @max_cumulative_failsafe_seconds)
      end

      # Disarm the failsafe
      def disarm_fail_safe : Nil
        if context = @failsafe_context
          context.disarm
          @failsafe_context = nil
        end
      end

      # Check if failsafe is expired
      def is_fail_safe_expired? : Bool
        if context = @failsafe_context
          !context.armed?
        else
          false
        end
      end

      # Get basic commissioning info (for BasicCommissioningInfo attribute)
      def basic_commissioning_info : BasicCommissioningInfo
        # Default fail-safe expiry length (60 seconds as per Matter spec default)
        fail_safe_expiry = 60_u16

        BasicCommissioningInfo.new(
          fail_safe_expiry_length: fail_safe_expiry,
          max_cumulative_failsafe_seconds: @max_cumulative_failsafe_seconds
        )
      end

      # Get current failsafe context (for testing/inspection)
      def failsafe_context : FailsafeContext?
        @failsafe_context
      end

      # Restore regulatory config from snapshot (called during rollback)
      #
      # This is called by FailsafeContext#rollback to restore the previous
      # regulatory configuration when a failsafe expires.
      #
      # @param location_type Previous regulatory location type value
      # @param country_code Previous country code
      def restore_regulatory_config(location_type : UInt8, country_code : String) : Nil
        @regulatory_config = RegulatoryLocationType.from_value(location_type)
        @country_code = country_code
        Log.info { "Restored regulatory config: location=#{@regulatory_config}, country=#{country_code}" }
      end

      # Open commissioning window (allows PASE sessions)
      def open_commissioning_window : Nil
        @commissioning_window_open = true
        Log.info { "Commissioning window opened" }
      end

      # Close commissioning window
      def close_commissioning_window : Nil
        @commissioning_window_open = false
        Log.info { "Commissioning window closed" }
      end

      # Accept Terms & Conditions (for TC feature)
      #
      # This method is used when the Terms & Conditions feature is enabled
      # to mark that the user has accepted the terms.
      def accept_terms_conditions : Nil
        @terms_conditions_accepted = true
        Log.info { "Terms & Conditions accepted" }
      end

      # Check if Terms & Conditions are accepted
      def terms_conditions_accepted? : Bool
        @terms_conditions_accepted
      end

      # ========================================================================
      # TLV Encoding Helpers
      # ========================================================================

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
          0_u8 => @max_cumulative_failsafe_seconds,
          1_u8 => @max_network_commissioning_seconds,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      # Encode ArmFailSafeResponse as TLV
      private def encode_arm_fail_safe_response(response : ArmFailSafeResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => response.error_code.value,
          1_u8 => response.debug_text,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      # Encode SetRegulatoryConfigResponse as TLV
      private def encode_set_regulatory_config_response(response : SetRegulatoryConfigResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => response.error_code.value,
          1_u8 => response.debug_text,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      # Encode CommissioningCompleteResponse as TLV
      private def encode_commissioning_complete_response(response : CommissioningCompleteResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => response.error_code.value,
          1_u8 => response.debug_text,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end
    end

    # Alias for backward compatibility with tests expecting "GeneralCommissioning"
    alias GeneralCommissioning = GeneralCommissioningCluster
  end

  # Top-level alias for tests
  module Clusters
    alias GeneralCommissioning = Cluster::GeneralCommissioningCluster
  end
end
