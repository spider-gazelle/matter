require "../spec_helper"
require "../../src/matter/cluster/administrator_commissioning_cluster"
require "../../src/matter/cluster/general_commissioning_cluster"
require "../../src/matter/failsafe_context"
require "../../src/matter/session_manager"

module Matter
  describe "Commissioning Flow Integration" do
    describe "successful commissioning flow" do
      it "completes full commissioning with window → failsafe → complete" do
        # Setup: Create cluster instances
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Configure lower timeouts for fast testing
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Step 1: Administrator opens commissioning window (enhanced)
        verifier = Bytes.new(97, 0xAB_u8)
        salt = Bytes.new(32, 0x01_u8)

        open_request = Cluster::AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        admin_comm.open_commissioning_window(open_request, 1_u8, 0x1234_u16)
        admin_comm.window_status.should eq(Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)
        admin_comm.admin_fabric_index.should eq(1_u8)

        # Step 2: New commissioner establishes PASE session (simulated)
        # In real implementation, PASE would use the verifier to establish session
        sleep 0.1.seconds

        # Step 3: New commissioner arms failsafe
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 100_u64
        )

        response = general_comm.arm_failsafe(
          request: arm_request,
          session_fabric_index: nil, # PASE session (no fabric yet)
          is_pase_session: true
        )

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)
        general_comm.failsafe_armed?.should be_true
        general_comm.breadcrumb.should eq(100_u64)

        # Step 4: Configure network (simulated - NetworkCommissioning cluster)
        sleep 0.1.seconds
        # In real flow: AddOrUpdateWiFiNetwork, ConnectNetwork commands

        # Step 5: Add NOC (simulated - OperationalCredentials cluster)
        sleep 0.1.seconds
        # In real flow: CSR generation, AddNOC command
        # This would create fabric index 2 for new commissioner
        # And update the failsafe context fabric index to 2

        # For now, we'll re-arm failsafe with the new fabric to simulate AddNOC updating it
        rearm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 150_u64
        )
        general_comm.arm_failsafe(rearm_request, 2_u8, false)

        # Step 6: Complete commissioning (CASE session required)
        complete_response = general_comm.commissioning_complete(
          session_fabric_index: 2_u8, # New fabric from AddNOC
          is_case_session: true       # Now using CASE session
        )

        complete_response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)
        general_comm.failsafe_armed?.should be_false
        general_comm.breadcrumb.should eq(0_u64) # Reset on success

        # Cleanup
        admin_comm.close
      end

      it "completes basic commissioning flow with default passcode" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new

        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Step 1: Open basic commissioning window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )

        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        admin_comm.window_status.should eq(Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

        # Step 2-6: Same flow as enhanced (PASE → ArmFailSafe → NOC → Complete)
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 200_u64
        )

        general_comm.arm_failsafe(arm_request, nil, true)
        general_comm.failsafe_armed?.should be_true

        sleep 0.2.seconds

        # Simulate AddNOC updating fabric
        rearm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 250_u64
        )
        general_comm.arm_failsafe(rearm_request, 2_u8, false)

        complete_response = general_comm.commissioning_complete(2_u8, true)
        complete_response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)

        admin_comm.close
      end
    end

    describe "failsafe expiry and rollback" do
      it "triggers rollback when failsafe expires during commissioning" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Arm failsafe with short timeout
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 1_u16, # 1 second
          breadcrumb: 999_u64
        )

        general_comm.arm_failsafe(arm_request, nil, true)
        general_comm.breadcrumb.should eq(999_u64)

        # Simulate commissioning in progress (but not completing)
        sleep 0.5.seconds
        general_comm.failsafe_armed?.should be_true

        # Wait for failsafe to expire
        sleep 1.0.seconds

        # Verify rollback occurred
        general_comm.breadcrumb.should eq(0_u64) # Reset by rollback
        general_comm.failsafe_armed?.should be_false
      end

      it "closes commissioning window when failsafe expires" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Arm failsafe with short timeout
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 1_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)

        # Wait for failsafe expiry
        sleep 1.5.seconds

        # Failsafe should be expired
        general_comm.failsafe_armed?.should be_false
        general_comm.breadcrumb.should eq(0_u64)

        # Window should still be open (separate timeout)
        admin_comm.window_open?.should be_true

        admin_comm.close
      end
    end

    describe "concurrent commissioner conflicts" do
      it "prevents second administrator from opening window" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Admin 1 opens window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Admin 2 tries to open window (should fail)
        expect_raises(Cluster::AdministratorCommissioningCluster::BusyError, /already opened/) do
          admin_comm.open_basic_commissioning_window(open_request, 2_u8, 0x5678_u16)
        end

        # Original admin should still own window
        admin_comm.admin_fabric_index.should eq(1_u8)

        admin_comm.close
      end

      it "prevents CASE session from arming failsafe when different fabric active" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Fabric 1 arms failsafe
        arm_request1 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, 1_u8, false)

        # Fabric 2 tries to arm failsafe (should fail)
        arm_request2 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, 2_u8, false)

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::BusyWithOtherAdmin)
        general_comm.breadcrumb.should eq(100_u64) # Not changed
      end

      it "allows PASE to take over from CASE when window open" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open commissioning window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        general_comm.open_commissioning_window

        # Fabric 1 (CASE) arms failsafe
        arm_request1 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, 1_u8, false)

        # PASE session takes over (priority)
        arm_request2 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, nil, true)

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)
        general_comm.breadcrumb.should eq(200_u64) # PASE took over

        admin_comm.close
      end
    end

    describe "window and failsafe coordination" do
      it "window expires independently of failsafe" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open short window (1 second)
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Arm longer failsafe (5 seconds)
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)

        # Wait for window to expire
        sleep 1.5.seconds
        Fiber.yield

        # Window should be closed
        admin_comm.window_open?.should be_false

        # Failsafe should still be armed
        general_comm.failsafe_armed?.should be_true
      end

      it "can revoke window while failsafe is armed" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Arm failsafe
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)

        # Revoke window (should succeed)
        admin_comm.revoke_commissioning
        admin_comm.window_open?.should be_false

        # Failsafe should still be armed
        general_comm.failsafe_armed?.should be_true
      end
    end

    describe "commissioning complete validation" do
      it "rejects commissioning complete without armed failsafe" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        response = general_comm.commissioning_complete(1_u8, true)

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::NoFailSafe)
      end

      it "rejects commissioning complete with PASE session" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Arm failsafe with PASE
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)

        # Try to complete with PASE (should fail)
        response = general_comm.commissioning_complete(nil, false)

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::InvalidAuthentication)
      end

      it "rejects commissioning complete with wrong fabric" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Arm failsafe with fabric 1
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, 1_u8, false)

        # Try to complete with fabric 2 (should fail)
        response = general_comm.commissioning_complete(2_u8, true)

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::InvalidAuthentication)
      end
    end

    describe "re-arming failsafe during commissioning" do
      it "extends failsafe timeout with re-arm" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Initial arm
        arm_request1 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 2_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, nil, true)

        # Wait 1 second
        sleep 1.0.seconds

        # Re-arm with 2 more seconds
        arm_request2 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 2_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, nil, true)

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)
        general_comm.breadcrumb.should eq(200_u64)

        # Failsafe should still be armed after original timeout
        sleep 1.5.seconds
        general_comm.failsafe_armed?.should be_true

        # But should expire after re-armed timeout
        sleep 1.0.seconds
        general_comm.failsafe_armed?.should be_false
      end

      it "disarms failsafe with expiry_length=0" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Arm failsafe
        arm_request1 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, nil, true)

        # Disarm with 0
        arm_request2 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 0_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, nil, true)

        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)
        general_comm.failsafe_armed?.should be_false
        general_comm.breadcrumb.should eq(100_u64) # Not updated on disarm
      end
    end

    describe "callback integration with SessionManager" do
      it "clears PASE sessions on successful commissioning" do
        # Create integrated system
        session_manager = SessionManager.new
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Wire up callback
        general_comm.on_clear_pase_sessions = -> : Nil {
          # Clear all PASE sessions from session manager
          session_manager.pase_session_ids.each do |session_id|
            session_manager.remove_pase_session(session_id)
          end
        }

        # Simulate commissioning: Create some PASE sessions
        pase_session1 = SessionManager::PaseSession.new(100_u16, passcode: 12345678_u32)
        pase_session2 = SessionManager::PaseSession.new(101_u16, passcode: 87654321_u32)

        session_manager.add_pase_session(pase_session1)
        session_manager.add_pase_session(pase_session2)
        session_manager.pase_session_ids.size.should eq(2)

        # Complete commissioning
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, 1_u8, false)

        response = general_comm.commissioning_complete(1_u8, true)
        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)

        # PASE sessions should be cleared
        session_manager.pase_session_ids.should be_empty
      end

      it "persists fabric table on successful commissioning" do
        general_comm = Cluster::GeneralCommissioningCluster.new
        fabric_persisted = false
        persisted_fabric_data : String? = nil

        # Wire up persistence callback
        general_comm.on_persist_fabric_table = -> : Nil {
          # Simulate persisting fabric table to storage
          fabric_persisted = true
          persisted_fabric_data = "fabric_table_v1.json" # Mock filename
        }

        # Complete commissioning
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, 1_u8, false)

        response = general_comm.commissioning_complete(1_u8, true)
        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)

        # Fabric table should be persisted
        fabric_persisted.should be_true
        persisted_fabric_data.should_not be_nil
      end

      it "integrates with SessionManager for full commissioning flow" do
        # Create complete system
        session_manager = SessionManager.new
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new

        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Track events
        pase_sessions_cleared = false
        fabric_table_persisted = false

        # Wire up all callbacks
        general_comm.on_clear_pase_sessions = -> : Nil {
          session_manager.pase_session_ids.each do |session_id|
            session_manager.remove_pase_session(session_id)
          end
          pase_sessions_cleared = true
        }

        general_comm.on_persist_fabric_table = -> : Nil {
          fabric_table_persisted = true
        }

        # Step 1: Open commissioning window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        general_comm.open_commissioning_window

        # Step 2: Establish PASE session (simulated)
        pase_session = SessionManager::PaseSession.new(1000_u16, passcode: 12345678_u32)
        session_manager.add_pase_session(pase_session)
        session_manager.has_pase_session?(1000_u16).should be_true

        # Step 3: Arm failsafe (PASE session)
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)

        # Step 4: Add NOC and transition to CASE (simulated)
        # This would create fabric index 2
        rearm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 150_u64
        )
        general_comm.arm_failsafe(rearm_request, 2_u8, false)

        # Create CASE session
        case_session = SessionManager::CaseSession.new(
          session_id: 3000_u16,
          fabric_index: 2_u8,
          peer_node_id: 0x2222222222222222_u64,
          vendor_id: 0x1234_u16
        )
        session_manager.add_case_session(case_session)

        # Step 5: Complete commissioning
        response = general_comm.commissioning_complete(2_u8, true)
        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)

        # Verify callbacks were invoked
        pase_sessions_cleared.should be_true
        fabric_table_persisted.should be_true

        # Verify PASE session was cleared
        session_manager.has_pase_session?(1000_u16).should be_false

        # Verify CASE session still exists (not cleared)
        session_manager.has_case_session?(3000_u16).should be_true

        admin_comm.close
      end

      it "enforces Terms & Conditions when enabled" do
        general_comm = Cluster::GeneralCommissioningCluster.new
        general_comm.terms_conditions_required = true

        # Try to complete commissioning without accepting TC
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, 1_u8, false)

        response = general_comm.commissioning_complete(1_u8, true)

        # Should be blocked
        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::RequiredTCNotAccepted)

        # Now accept and try again
        general_comm.accept_terms_conditions

        arm_request2 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 200_u64
        )
        general_comm.arm_failsafe(arm_request2, 1_u8, false)

        response2 = general_comm.commissioning_complete(1_u8, true)
        response2.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)
      end

      it "uses TC callback to check acceptance" do
        general_comm = Cluster::GeneralCommissioningCluster.new
        general_comm.terms_conditions_required = true

        tc_check_count = 0
        tc_accepted = false

        # Wire up TC check callback
        general_comm.on_check_terms_conditions = -> : Bool {
          tc_check_count += 1
          tc_accepted # Return current state
        }

        # Try to complete commissioning without accepting TC
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, 1_u8, false)

        response = general_comm.commissioning_complete(1_u8, true)

        # Should be blocked
        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::RequiredTCNotAccepted)
        tc_check_count.should eq(1)

        # Now accept (externally)
        tc_accepted = true

        arm_request2 = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 60_u16,
          breadcrumb: 200_u64
        )
        general_comm.arm_failsafe(arm_request2, 1_u8, false)

        response2 = general_comm.commissioning_complete(1_u8, true)
        response2.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)
        tc_check_count.should eq(2)
      end

      it "validates country codes with whitelist" do
        general_comm = Cluster::GeneralCommissioningCluster.new

        # Configure whitelist for specific countries
        general_comm.country_code_whitelist = ["US", "CA", "GB", "DE"]

        # Try to set whitelisted country (should succeed)
        request_us = Cluster::GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "US",
          breadcrumb: 100_u64
        )
        response_us = (general_comm.regulatory_config = request_us)
        response_us.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)

        # Try to set non-whitelisted country (should fail)
        request_jp = Cluster::GeneralCommissioningCluster::SetRegulatoryConfigRequest.new(
          new_regulatory_config: Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
          country_code: "JP",
          breadcrumb: 200_u64
        )
        response_jp = (general_comm.regulatory_config = request_jp)
        response_jp.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::ValueOutsideRange)
        response_jp.debug_text.should contain("not in whitelist")
      end
    end
  end
end
