require "log"
require "./failsafe_timer"
require "./fabric_manager"
require "./session_manager"
require "./commissioning_window"
require "./clusters/network_commissioning"

module Matter
  # FailsafeContext manages commissioning state and coordinates rollback on failure
  #
  # The failsafe context is created when ArmFailSafe is invoked and tracks all
  # commissioning state changes (fabric operations, network config, etc.) so that
  # they can be rolled back if the failsafe timer expires.
  #
  # Matter Core Spec §11.10.7 - General Commissioning Cluster
  # Matter Core Spec §5.5 - Commissioning Flows
  class FailsafeContext
    Log = ::Log.for("matter.failsafe_context")

    # Fabric index associated with this context (nil for PASE/initial commissioning)
    property associated_fabric_index : UInt8?

    # Breadcrumb value for progress tracking
    property breadcrumb : UInt64

    # Maximum cumulative failsafe timeout (hard limit)
    property max_cumulative_seconds : UInt16

    # CSR nonce for pairing (tracks session ID)
    property csr_nonce : Bytes?

    # Whether this is for updating an existing NOC (vs adding new)
    property for_update_noc : Bool

    # Network commissioning state snapshot (for rollback)
    property network_state_snapshot : Hash(String, String)?

    # Root certificate bytes (for validation)
    property root_cert : Bytes?

    # Whether a new fabric was added during this context
    property added_fabric_index : UInt8?

    # Regulatory config snapshot (for rollback)
    property regulatory_config_snapshot : Tuple(UInt8, String)? # (location_type, country_code)

    # NOC update snapshot (for UpdateNOC rollback)
    # Stores: (fabric_index, operational_cert, operational_key)
    property noc_update_snapshot : Tuple(UInt8, Bytes, Bytes)?

    @timer : FailsafeTimer?
    @expiry_callback : Proc(Nil)

    # Create a new failsafe context
    #
    # @param fabric_index Fabric index for CASE sessions (nil for PASE)
    # @param breadcrumb Progress tracking value
    # @param expiry_callback Callback invoked when failsafe expires (performs rollback)
    def initialize(
      @associated_fabric_index : UInt8?,
      @breadcrumb : UInt64,
      @expiry_callback : Proc(Nil),
    )
      @max_cumulative_seconds = 900_u16 # Default 15 minutes (Matter spec max)
      @csr_nonce = nil
      @for_update_noc = false
      @network_state_snapshot = nil
      @root_cert = nil
      @added_fabric_index = nil
      @regulatory_config_snapshot = nil
      @noc_update_snapshot = nil
      @timer = nil

      Log.info { "Created failsafe context: fabric=#{@associated_fabric_index || "PASE"}, breadcrumb=#{breadcrumb}" }
    end

    # Arm the failsafe timer with specified durations
    #
    # @param expiry_length Primary timer duration in seconds (0 = disarm)
    # @param max_cumulative Maximum cumulative duration in seconds
    def arm(expiry_length : UInt16, max_cumulative : UInt16) : Nil
      if expiry_length == 0
        # Disarm the failsafe
        disarm
        return
      end

      # If timer already exists, re-arm it
      if timer = @timer
        timer.re_arm(@associated_fabric_index, expiry_length)
        Log.info { "Re-armed failsafe: primary=#{expiry_length}s" }
        return
      end

      # Create new timer
      @max_cumulative_seconds = max_cumulative
      @timer = FailsafeTimer.new(
        fabric_index: @associated_fabric_index,
        expiry_length: expiry_length,
        max_cumulative: max_cumulative,
        expiry_callback: @expiry_callback
      )

      Log.info { "Armed failsafe: primary=#{expiry_length}s, cumulative=#{max_cumulative}s" }
    end

    # Disarm the failsafe timer (mark as completed without triggering rollback)
    def disarm : Nil
      if timer = @timer
        timer.complete
        @timer = nil
        Log.info { "Disarmed failsafe" }
      end
    end

    # Check if the failsafe timer is currently armed
    def armed? : Bool
      if timer = @timer
        timer.running?
      else
        false
      end
    end

    # Get time remaining on primary timer
    def primary_time_remaining : Time::Span?
      @timer.try(&.primary_time_remaining)
    end

    # Get time remaining on cumulative timer
    def cumulative_time_remaining : Time::Span?
      @timer.try(&.cumulative_time_remaining)
    end

    # Validate that fabric index matches this context
    #
    # @param fabric_index Fabric index to validate
    # @return true if matches, false otherwise
    def matches_fabric?(fabric_index : UInt8?) : Bool
      @associated_fabric_index == fabric_index
    end

    # Record that a new fabric was added during commissioning
    #
    # This will be rolled back if failsafe expires.
    def record_added_fabric(fabric_index : UInt8) : Nil
      @added_fabric_index = fabric_index
      # Update associated fabric index to the new fabric
      @associated_fabric_index = fabric_index
      Log.info { "Recorded added fabric: #{fabric_index}" }
    end

    # Record network commissioning state for rollback
    #
    # @param state Snapshot of network configuration
    def record_network_state(state : Hash(String, String)) : Nil
      @network_state_snapshot = state
      Log.debug { "Recorded network state snapshot" }
    end

    # Record CSR nonce for session tracking
    #
    # @param nonce CSR nonce bytes
    def record_csr_nonce(nonce : Bytes) : Nil
      @csr_nonce = nonce
      Log.debug { "Recorded CSR nonce" }
    end

    # Record root certificate for validation
    #
    # @param cert Root certificate bytes
    def record_root_cert(cert : Bytes) : Nil
      @root_cert = cert
      Log.debug { "Recorded root certificate" }
    end

    # Mark this context as being for UpdateNOC (vs AddNOC)
    def mark_for_update_noc : Nil
      @for_update_noc = true
      Log.debug { "Marked context for UpdateNOC" }
    end

    # Record NOC state before UpdateNOC for rollback
    #
    # @param fabric_index Fabric index being updated
    # @param operational_cert Current operational certificate
    # @param operational_key Current operational private key
    def record_noc_update(fabric_index : UInt8, operational_cert : Bytes, operational_key : Bytes) : Nil
      # Only record the first snapshot (don't overwrite on subsequent changes)
      if @noc_update_snapshot.nil?
        @noc_update_snapshot = {fabric_index, operational_cert, operational_key}
        Log.debug { "Recorded NOC update snapshot for fabric #{fabric_index}" }
      end
    end

    # Record regulatory config state for rollback
    #
    # @param location_type Current regulatory location type (as UInt8)
    # @param country_code Current country code (2-character string)
    def record_regulatory_config(location_type : UInt8, country_code : String) : Nil
      # Only record the first snapshot (don't overwrite on subsequent changes)
      if @regulatory_config_snapshot.nil?
        @regulatory_config_snapshot = {location_type, country_code}
        Log.debug { "Recorded regulatory config snapshot: location=#{location_type}, country=#{country_code}" }
      end
    end

    # Perform complete rollback of all commissioning state
    #
    # This implements the 9-step rollback sequence from Matter spec:
    # 1. Revoke added fabric (if AddNOC was used)
    # 2. Revert UpdateNOC changes
    # 3. Restore network commissioning state
    # 4. Clear PASE sessions
    # 5. Reset breadcrumb to 0
    # 6. Close commissioning windows
    # 7. Clear CSR session
    # 8. Reset regulatory config
    # 9. Clean up temporary state
    #
    # @param fabric_manager FabricManager for fabric operations
    # @param session_manager SessionManager for PASE cleanup
    # @param network_commissioning NetworkCommissioning cluster for network state restoration
    # @param commissioning_window For closing windows
    # @param general_commissioning GeneralCommissioning cluster for regulatory config reset
    def rollback(
      fabric_manager : FabricManager? = nil,
      session_manager : SessionManager? = nil,
      network_commissioning : Clusters::NetworkCommissioning? = nil,
      commissioning_window : CommissioningWindow? = nil,
      general_commissioning : Clusters::GeneralCommissioning? = nil,
    ) : Nil
      Log.warn { "Performing failsafe rollback" }

      # Step 1: Revoke added fabric (if AddNOC was used)
      if added_index = @added_fabric_index
        if fm = fabric_manager
          begin
            fm.remove_fabric(added_index)
            Log.info { "Rolled back added fabric: #{added_index}" }
          rescue ex
            Log.error(exception: ex) { "Failed to rollback added fabric" }
          end
        end
      end

      # Step 2: Revert UpdateNOC changes
      if @for_update_noc
        if snapshot = @noc_update_snapshot
          if fm = fabric_manager
            begin
              fabric_index, operational_cert, operational_key = snapshot
              fm.restore_noc(fabric_index, operational_cert, operational_key)
              Log.info { "Reverted UpdateNOC changes for fabric #{fabric_index}" }
            rescue ex
              Log.error(exception: ex) { "Failed to revert UpdateNOC changes" }
            end
          end
        else
          Log.warn { "UpdateNOC marked but no snapshot recorded" }
        end
      end

      # Step 3: Restore network commissioning state
      if snapshot = @network_state_snapshot
        if nc = network_commissioning
          begin
            nc.restore_network_state(snapshot)
            Log.info { "Restored network commissioning state" }
          rescue ex
            Log.error(exception: ex) { "Failed to restore network state" }
          end
        end
      end

      # Step 4: Clear PASE sessions
      if sm = session_manager
        begin
          sm.clear_pase_sessions
          Log.info { "Cleared PASE sessions" }
        rescue ex
          Log.error(exception: ex) { "Failed to clear PASE sessions" }
        end
      end

      # Step 5: Reset breadcrumb to 0
      @breadcrumb = 0_u64
      Log.debug { "Reset breadcrumb to 0" }

      # Step 6: Close commissioning windows
      if cw = commissioning_window
        begin
          cw.close
          Log.info { "Closed commissioning window" }
        rescue ex
          Log.error(exception: ex) { "Failed to close commissioning window" }
        end
      end

      # Step 7: Clear CSR session
      @csr_nonce = nil
      Log.debug { "Cleared CSR nonce" }

      # Step 8: Reset regulatory config
      if snapshot = @regulatory_config_snapshot
        if gc = general_commissioning
          begin
            location_type, country_code = snapshot
            gc.restore_regulatory_config(location_type, country_code)
            Log.info { "Restored regulatory config: location=#{location_type}, country=#{country_code}" }
          rescue ex
            Log.error(exception: ex) { "Failed to restore regulatory config" }
          end
        end
      end

      # Step 9: Clean up temporary state
      @network_state_snapshot = nil
      @root_cert = nil
      @added_fabric_index = nil
      @regulatory_config_snapshot = nil
      @noc_update_snapshot = nil
      @for_update_noc = false
      Log.debug { "Cleaned up temporary state" }

      Log.warn { "Rollback completed" }
    end

    # Close and cleanup the failsafe context
    #
    # Should be called when context is destroyed.
    def close : Nil
      if timer = @timer
        timer.close
        @timer = nil
      end
      Log.debug { "Closed failsafe context" }
    end
  end

  # Note: The following classes are now implemented in separate files:
  # - FabricManager (./fabric_manager.cr)
  # - SessionManager (./session_manager.cr)
  # - CommissioningWindow (./commissioning_window.cr)
  # - Clusters::NetworkCommissioning (./clusters/network_commissioning.cr)
  # - Clusters::GeneralCommissioning (./clusters/general_commissioning.cr)
end
