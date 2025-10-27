require "../failsafe_context"
require "log"

module Matter
  module Clusters
    # General Commissioning Cluster (0x0030)
    #
    # Provides commands and attributes to support the device commissioning process.
    # This includes commissioning window management, failsafe timer management,
    # regulatory configuration, and commissioning completion.
    #
    # Matter Core Spec §11.9 - General Commissioning Cluster
    class GeneralCommissioning
      Log = ::Log.for("matter.cluster.general_commissioning")

      CLUSTER_ID = 0x0030_u16

      # Regulatory Location Type
      enum RegulatoryLocationType : UInt8
        Indoor        = 0
        Outdoor       = 1
        IndoorOutdoor = 2
      end

      # Commissioning Error Codes
      enum CommissioningError : UInt8
        OK                    = 0
        ValueOutsideRange     = 1
        InvalidAuthentication = 2
        NoFailSafe            = 3
        BusyWithOtherAdmin    = 4
        RequiredTCNotAccepted = 5
        TCMinVersionNotMet    = 6
        TCRequired            = 7
      end

      # ========================================================================
      # Attributes
      # ========================================================================

      # Breadcrumb attribute (0x0000) - progress tracking during commissioning
      property breadcrumb : UInt64 = 0_u64

      # BasicCommissioningInfo attribute (0x0001)
      # Contains MaxCumulativeFailsafeSeconds and MaxNetworkCommissioningSeconds
      property max_cumulative_failsafe_seconds : UInt16 = 900_u16   # 15 minutes default
      property max_network_commissioning_seconds : UInt16 = 900_u16 # 15 minutes default

      # RegulatoryConfig attribute (0x0002) - current regulatory location
      property regulatory_config : RegulatoryLocationType = RegulatoryLocationType::Indoor

      # Country code (stored for rollback purposes)
      property country_code : String = "XX" # Default: unknown/unspecified

      # LocationCapability attribute (0x0003) - supported regulatory locations
      property location_capability : RegulatoryLocationType = RegulatoryLocationType::IndoorOutdoor

      # SupportsConcurrentConnection attribute (0x0004)
      property supports_concurrent_connection : Bool = true

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

      def initialize
        @failsafe_context = nil
        @admin_fabric_index = nil
        @commissioning_window_open = false
        @terms_conditions_accepted = false
      end

      # ========================================================================
      # ArmFailSafe Command (0x00)
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

      # CommissioningComplete command response
      struct CommissioningCompleteResponse
        property error_code : CommissioningError
        property debug_text : String = ""

        def initialize(@error_code, @debug_text = "")
        end
      end

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
    end
  end
end
