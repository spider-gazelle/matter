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

      cluster 0x0030, revision: 2

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
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property expiry_length_seconds : UInt16

        @[TLV::Field(tag: 1)]
        property breadcrumb : UInt64

        @[TLV::Field(tag: 2)]
        property timeout_ms : UInt32 = 0_u32 # Deprecated, kept for compatibility

        def initialize(@expiry_length_seconds, @breadcrumb, @timeout_ms = 0_u32)
        end
      end

      # ArmFailSafe command response
      struct ArmFailSafeResponse
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property error_code : CommissioningError

        @[TLV::Field(tag: 1)]
        property debug_text : String = ""

        def initialize(@error_code : CommissioningError, @debug_text = "")
        end
      end

      # SetRegulatoryConfig command request
      struct SetRegulatoryConfigRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property new_regulatory_config : RegulatoryLocationType

        @[TLV::Field(tag: 1)]
        property country_code : String

        @[TLV::Field(tag: 2)]
        property breadcrumb : UInt64

        def initialize(@new_regulatory_config : RegulatoryLocationType, @country_code : String, @breadcrumb : UInt64)
        end
      end

      # SetRegulatoryConfig command response
      struct SetRegulatoryConfigResponse
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property error_code : CommissioningError

        @[TLV::Field(tag: 1)]
        property debug_text : String = ""

        def initialize(@error_code : CommissioningError, @debug_text = "")
        end
      end

      # CommissioningComplete command response
      struct CommissioningCompleteResponse
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property error_code : CommissioningError

        @[TLV::Field(tag: 1)]
        property debug_text : String = ""

        def initialize(@error_code : CommissioningError, @debug_text = "")
        end
      end

      # BasicCommissioningInfo - returned by BasicCommissioningInfo attribute
      struct BasicCommissioningInfo
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property fail_safe_expiry_length : UInt16

        @[TLV::Field(tag: 1)]
        property max_cumulative_failsafe_seconds : UInt16

        def initialize(@fail_safe_expiry_length, @max_cumulative_failsafe_seconds)
        end
      end

      # ========================================================================
      # Attributes
      # ========================================================================

      # Failsafe and network commissioning windows default to 15 minutes
      DEFAULT_COMMISSIONING_SECONDS = 900_u16

      # Progress tracking during commissioning; not persisted (Matter Core §11.10.6.1)
      attribute 0x0000, :breadcrumb, UInt64, default: 0_u64, writable: true, persist: false, write_access: :administer
      # Built from `max_cumulative_failsafe_seconds` / `max_network_commissioning_seconds` in `read_attribute`
      attribute 0x0001, :basic_commissioning_info, BasicCommissioningInfo, default: BasicCommissioningInfo.new(DEFAULT_COMMISSIONING_SECONDS, DEFAULT_COMMISSIONING_SECONDS), fixed: true
      attribute 0x0002, :regulatory_config, RegulatoryLocationType, default: RegulatoryLocationType::IndoorOutdoor
      attribute 0x0003, :location_capability, RegulatoryLocationType, default: RegulatoryLocationType::IndoorOutdoor, fixed: true
      attribute 0x0004, :supports_concurrent_connection, Bool, default: true, fixed: true
      # Commissioning on backup power is not supported
      attribute 0x000C, :is_commissioning_without_power, Bool, default: false

      # BasicCommissioningInfo attribute (0x0001)
      # Contains MaxCumulativeFailsafeSeconds and MaxNetworkCommissioningSeconds
      property max_cumulative_failsafe_seconds : UInt16 = DEFAULT_COMMISSIONING_SECONDS
      property max_network_commissioning_seconds : UInt16 = DEFAULT_COMMISSIONING_SECONDS

      # Country code (stored for rollback purposes)
      property country_code : String = "XX" # Default: unknown/unspecified

      # ========================================================================
      # Commands
      # ========================================================================

      command 0x00, :arm_fail_safe, request: Definitions::GeneralCommissioning::ArmFailSafeRequest, response: ArmFailSafeResponse, response_id: 0x01, access: :administer
      command 0x02, :set_regulatory_config, request: Definitions::GeneralCommissioning::SetRegularConfigurationRequest, response: SetRegulatoryConfigResponse, response_id: 0x03, access: :administer
      command 0x04, :commissioning_complete, response: CommissioningCompleteResponse, response_id: 0x05, access: :administer

      # ========================================================================
      # Feature Support
      # ========================================================================

      # Terms & Conditions feature support
      property? terms_conditions_required : Bool = false

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

      # Callback to reset OperationalCredentials failsafe context when a new failsafe is armed
      # This is necessary because the OperationalCredentials cluster has its own failsafe state
      # tracking (noc_added_or_updated, etc.) that must be reset for each new commissioning session
      property on_failsafe_armed : (Proc(Nil))? = nil

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

      # BasicCommissioningInfo is built from the configured windows.
      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | TLV::Any
        case attribute_id
        when ATTR_BASIC_COMMISSIONING_INFO
          tlv(BasicCommissioningInfo.new(@max_cumulative_failsafe_seconds, @max_network_commissioning_seconds))
        else
          super
        end
      end

      # ========================================================================
      # Command entry points (DSL dispatch)
      # ========================================================================

      def arm_fail_safe(request_def : Definitions::GeneralCommissioning::ArmFailSafeRequest) : ArmFailSafeResponse
        # Convert to cluster request struct
        request = ArmFailSafeRequest.new(
          expiry_length_seconds: request_def.expiry_length_seconds,
          breadcrumb: request_def.breadcrumb
        )

        # Call public command handler with the session context from `Base#invoke_command`
        arm_failsafe(
          request: request,
          session_fabric_index: request_fabric_index,
          is_pase_session: !request_is_case_session?
        )
      end

      # ameba:disable Naming/AccessorMethodName
      def set_regulatory_config(request_def : Definitions::GeneralCommissioning::SetRegularConfigurationRequest) : SetRegulatoryConfigResponse
        # Convert to cluster request struct
        request = SetRegulatoryConfigRequest.new(
          new_regulatory_config: RegulatoryLocationType.from_value(request_def.new_regulatory_configuration.value),
          country_code: request_def.country_code,
          breadcrumb: request_def.breadcrumb
        )

        # Call public command handler
        self.regulatory_config = request
      end

      def commissioning_complete : CommissioningCompleteResponse
        # Call public command handler with the session context from `Base#invoke_command`
        commissioning_complete(
          session_fabric_index: request_fabric_index,
          is_case_session: request_is_case_session?
        )
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
            Log.error(exception: ex) do
              "Failed to re-arm failsafe (expiry_length_seconds=#{request.expiry_length_seconds} " \
              "max_cumulative_seconds=#{@max_cumulative_failsafe_seconds} breadcrumb=#{request.breadcrumb} " \
              "session_fabric_index=#{session_fabric_index.inspect} commissioning_window_open=#{@commissioning_window_open} pase_session=#{is_pase_session})"
            end
            return ArmFailSafeResponse.new(
              CommissioningError::BusyWithOtherAdmin,
              "Cannot re-arm: #{ex.message}"
            )
          end
        else
          # Create new context
          failsafe_ctx = FailsafeContext.new(
            associated_fabric_index: session_fabric_index,
            breadcrumb: request.breadcrumb,
            expiry_callback: -> { handle_failsafe_expiry }
          )
          @failsafe_context = failsafe_ctx
          failsafe_ctx.arm(
            request.expiry_length_seconds,
            @max_cumulative_failsafe_seconds
          )
          @admin_fabric_index = session_fabric_index
          @breadcrumb = request.breadcrumb

          # Notify OperationalCredentials cluster to reset its failsafe state
          # This is critical for proper handling of subsequent CSR/NOC operations
          if callback = @on_failsafe_armed
            callback.call
          end

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
      def regulatory_config=(
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
        @failsafe_context.as(FailsafeContext).arm(expiry_seconds, @max_cumulative_failsafe_seconds)
      end

      # Disarm the failsafe
      def disarm_fail_safe : Nil
        if context = @failsafe_context
          context.disarm
          @failsafe_context = nil
        end
      end

      # Check if failsafe is expired
      def fail_safe_expired? : Bool
        if context = @failsafe_context
          !context.armed?
        else
          false
        end
      end

      # Record that a fabric was added during this failsafe context
      #
      # This should be called by OperationalCredentialsCluster when AddNOC succeeds.
      # It updates the failsafe context so that CommissioningComplete can be called
      # from a CASE session on the new fabric (PASE→CASE transition).
      #
      # @param fabric_index The index of the newly added fabric
      def record_added_fabric(fabric_index : UInt8) : Nil
        if context = @failsafe_context
          context.record_added_fabric(fabric_index)
          Log.info { "Recorded added fabric #{fabric_index} in failsafe context" }
        else
          Log.warn { "No failsafe context to record added fabric #{fabric_index}" }
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
    end
  end
end
