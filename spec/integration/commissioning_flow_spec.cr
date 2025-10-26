require "../spec_helper"
require "../../src/matter/clusters/administrator_commissioning"
require "../../src/matter/clusters/general_commissioning"
require "../../src/matter/failsafe_context"

module Matter
  describe "Commissioning Flow Integration" do
    describe "successful commissioning flow" do
      it "completes full commissioning with window → failsafe → complete" do
        # Setup: Create cluster instances
        admin_comm = Clusters::AdministratorCommissioning.new
        general_comm = Clusters::GeneralCommissioning.new

        # Configure lower timeouts for fast testing
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Step 1: Administrator opens commissioning window (enhanced)
        verifier = Bytes.new(97, 0xAB_u8)
        salt = Bytes.new(32, 0x01_u8)

        open_request = Clusters::AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        admin_comm.open_commissioning_window(open_request, 1_u8, 0x1234_u16)
        admin_comm.window_status.should eq(Clusters::AdministratorCommissioning::WindowStatus::EnhancedWindowOpen)
        admin_comm.admin_fabric_index.should eq(1_u8)

        # Step 2: New commissioner establishes PASE session (simulated)
        # In real implementation, PASE would use the verifier to establish session
        sleep 0.1.seconds

        # Step 3: New commissioner arms failsafe
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 100_u64
        )

        response = general_comm.arm_failsafe(
          request: arm_request,
          session_fabric_index: nil, # PASE session (no fabric yet)
          is_pase_session: true
        )

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::OK)
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
        rearm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 150_u64
        )
        general_comm.arm_failsafe(rearm_request, 2_u8, false)

        # Step 6: Complete commissioning (CASE session required)
        complete_response = general_comm.commissioning_complete(
          session_fabric_index: 2_u8, # New fabric from AddNOC
          is_case_session: true       # Now using CASE session
        )

        complete_response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::OK)
        general_comm.failsafe_armed?.should be_false
        general_comm.breadcrumb.should eq(0_u64) # Reset on success

        # Cleanup
        admin_comm.close
      end

      it "completes basic commissioning flow with default passcode" do
        admin_comm = Clusters::AdministratorCommissioning.new
        general_comm = Clusters::GeneralCommissioning.new

        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Step 1: Open basic commissioning window
        open_request = Clusters::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )

        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        admin_comm.window_status.should eq(Clusters::AdministratorCommissioning::WindowStatus::BasicWindowOpen)

        # Step 2-6: Same flow as enhanced (PASE → ArmFailSafe → NOC → Complete)
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 200_u64
        )

        general_comm.arm_failsafe(arm_request, nil, true)
        general_comm.failsafe_armed?.should be_true

        sleep 0.2.seconds

        # Simulate AddNOC updating fabric
        rearm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 3_u16,
          breadcrumb: 250_u64
        )
        general_comm.arm_failsafe(rearm_request, 2_u8, false)

        complete_response = general_comm.commissioning_complete(2_u8, true)
        complete_response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::OK)

        admin_comm.close
      end
    end

    describe "failsafe expiry and rollback" do
      it "triggers rollback when failsafe expires during commissioning" do
        general_comm = Clusters::GeneralCommissioning.new
        rollback_invoked = Channel(Bool).new(1)

        # Arm failsafe with short timeout
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
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
        admin_comm = Clusters::AdministratorCommissioning.new
        general_comm = Clusters::GeneralCommissioning.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open window
        open_request = Clusters::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Arm failsafe with short timeout
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
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
        admin_comm = Clusters::AdministratorCommissioning.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Admin 1 opens window
        open_request = Clusters::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Admin 2 tries to open window (should fail)
        expect_raises(Clusters::AdministratorCommissioning::BusyError, /already opened/) do
          admin_comm.open_basic_commissioning_window(open_request, 2_u8, 0x5678_u16)
        end

        # Original admin should still own window
        admin_comm.admin_fabric_index.should eq(1_u8)

        admin_comm.close
      end

      it "prevents CASE session from arming failsafe when different fabric active" do
        general_comm = Clusters::GeneralCommissioning.new

        # Fabric 1 arms failsafe
        arm_request1 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, 1_u8, false)

        # Fabric 2 tries to arm failsafe (should fail)
        arm_request2 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, 2_u8, false)

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::BusyWithOtherAdmin)
        general_comm.breadcrumb.should eq(100_u64) # Not changed
      end

      it "allows PASE to take over from CASE when window open" do
        admin_comm = Clusters::AdministratorCommissioning.new
        general_comm = Clusters::GeneralCommissioning.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open commissioning window
        open_request = Clusters::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        general_comm.open_commissioning_window

        # Fabric 1 (CASE) arms failsafe
        arm_request1 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, 1_u8, false)

        # PASE session takes over (priority)
        arm_request2 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, nil, true)

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::OK)
        general_comm.breadcrumb.should eq(200_u64) # PASE took over

        admin_comm.close
      end
    end

    describe "window and failsafe coordination" do
      it "window expires independently of failsafe" do
        admin_comm = Clusters::AdministratorCommissioning.new
        general_comm = Clusters::GeneralCommissioning.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open short window (1 second)
        open_request = Clusters::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Arm longer failsafe (5 seconds)
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
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
        admin_comm = Clusters::AdministratorCommissioning.new
        general_comm = Clusters::GeneralCommissioning.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open window
        open_request = Clusters::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Arm failsafe
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
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
        general_comm = Clusters::GeneralCommissioning.new

        response = general_comm.commissioning_complete(1_u8, true)

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::NoFailSafe)
      end

      it "rejects commissioning complete with PASE session" do
        general_comm = Clusters::GeneralCommissioning.new

        # Arm failsafe with PASE
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)

        # Try to complete with PASE (should fail)
        response = general_comm.commissioning_complete(nil, false)

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::InvalidAuthentication)
      end

      it "rejects commissioning complete with wrong fabric" do
        general_comm = Clusters::GeneralCommissioning.new

        # Arm failsafe with fabric 1
        arm_request = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, 1_u8, false)

        # Try to complete with fabric 2 (should fail)
        response = general_comm.commissioning_complete(2_u8, true)

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::InvalidAuthentication)
      end
    end

    describe "re-arming failsafe during commissioning" do
      it "extends failsafe timeout with re-arm" do
        general_comm = Clusters::GeneralCommissioning.new

        # Initial arm
        arm_request1 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 2_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, nil, true)

        # Wait 1 second
        sleep 1.0.seconds

        # Re-arm with 2 more seconds
        arm_request2 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 2_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, nil, true)

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::OK)
        general_comm.breadcrumb.should eq(200_u64)

        # Failsafe should still be armed after original timeout
        sleep 1.5.seconds
        general_comm.failsafe_armed?.should be_true

        # But should expire after re-armed timeout
        sleep 1.0.seconds
        general_comm.failsafe_armed?.should be_false
      end

      it "disarms failsafe with expiry_length=0" do
        general_comm = Clusters::GeneralCommissioning.new

        # Arm failsafe
        arm_request1 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request1, nil, true)

        # Disarm with 0
        arm_request2 = Clusters::GeneralCommissioning::ArmFailSafeRequest.new(
          expiry_length_seconds: 0_u16,
          breadcrumb: 200_u64
        )
        response = general_comm.arm_failsafe(arm_request2, nil, true)

        response.error_code.should eq(Clusters::GeneralCommissioning::CommissioningError::OK)
        general_comm.failsafe_armed?.should be_false
        general_comm.breadcrumb.should eq(100_u64) # Not updated on disarm
      end
    end
  end
end
