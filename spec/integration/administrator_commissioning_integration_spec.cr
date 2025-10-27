require "../spec_helper"
require "../../src/matter/cluster/administrator_commissioning_cluster"
require "../../src/matter/cluster/general_commissioning_cluster"
require "../../src/matter/session_manager"
require "../../src/matter/session/pase/pase"

module Matter
  describe "Administrator Commissioning Integration" do
    describe "PASE server configuration callbacks" do
      it "configures PASE server for enhanced commissioning window" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Track PASE server configuration
        pase_configured = false
        verifier_received : Bytes? = nil
        iterations_received : UInt32? = nil
        salt_received : Bytes? = nil

        # Wire up callback
        admin_comm.on_configure_pase_server = ->(verifier : Bytes, iterations : UInt32, salt : Bytes) : Nil {
          pase_configured = true
          verifier_received = verifier
          iterations_received = iterations
          salt_received = salt
        }

        # Open enhanced commissioning window
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

        # Verify callback was invoked
        pase_configured.should be_true
        verifier_received.should eq(verifier)
        iterations_received.should eq(10000_u32)
        salt_received.should eq(salt)

        admin_comm.window_status.should eq(Cluster::AdministratorCommissioningCluster::WindowStatus::EnhancedWindowOpen)

        admin_comm.close
      end

      it "configures PASE server for basic commissioning window" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Track PASE server configuration
        pase_pin_configured = false
        pin_received : UInt32? = nil
        iterations_received : UInt32? = nil
        salt_received : Bytes? = nil

        # Wire up callback
        admin_comm.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, salt : Bytes) : Nil {
          pase_pin_configured = true
          pin_received = pin
          iterations_received = iterations
          salt_received = salt
        }

        # Open basic commissioning window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )

        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Verify callback was invoked
        pase_pin_configured.should be_true
        pin_received.should_not be_nil
        iterations_received.should_not be_nil
        salt_received.should_not be_nil
        pin_received.not_nil!.should be > 0

        admin_comm.window_status.should eq(Cluster::AdministratorCommissioningCluster::WindowStatus::BasicWindowOpen)

        admin_comm.close
      end

      it "stops PASE server when window closes" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        pase_stopped = false

        # Wire up callbacks
        admin_comm.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, salt : Bytes) : Nil {
          # PASE server started
        }

        admin_comm.on_stop_pase_server = -> : Nil {
          pase_stopped = true
        }

        # Open window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Revoke window
        admin_comm.revoke_commissioning
        pase_stopped.should be_true

        admin_comm.window_status.should eq(Cluster::AdministratorCommissioningCluster::WindowStatus::WindowNotOpen)
      end

      it "stops PASE server when window expires" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        pase_stopped = false

        # Wire up callbacks
        admin_comm.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, salt : Bytes) : Nil {
          # PASE server started
        }

        admin_comm.on_stop_pase_server = -> : Nil {
          pase_stopped = true
        }

        # Open window with 1 second timeout
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Wait for expiry
        sleep 1.5.seconds

        pase_stopped.should be_true
        admin_comm.window_status.should eq(Cluster::AdministratorCommissioningCluster::WindowStatus::WindowNotOpen)
      end
    end

    describe "PASE session integration" do
      it "integrates with PASE session establishment" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        session_manager = SessionManager.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Track PASE configuration
        configured_pin : UInt32? = nil
        configured_iterations : UInt32? = nil
        configured_salt : Bytes? = nil

        # Wire up callback to capture PASE parameters
        admin_comm.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, salt : Bytes) : Nil {
          configured_pin = pin
          configured_iterations = iterations
          configured_salt = salt
        }

        # Open basic commissioning window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Simulate PASE session establishment using configured parameters
        configured_pin.should_not be_nil
        configured_iterations.should_not be_nil
        configured_salt.should_not be_nil

        # Create PASE session with the configured PIN
        pase_session = SessionManager::PaseSession.new(
          session_id: 1000_u16,
          passcode: configured_pin
        )
        session_manager.add_pase_session(pase_session)

        # Verify session was created
        session_manager.has_pase_session?(1000_u16).should be_true

        # Clean up
        session_manager.remove_pase_session(1000_u16)
        admin_comm.close
      end

      it "integrates PASE parameters with SPAKE2+ protocol" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Track PASE configuration
        configured_pin : UInt32? = nil
        configured_iterations : UInt32? = nil
        configured_salt : Bytes? = nil

        admin_comm.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, salt : Bytes) : Nil {
          configured_pin = pin
          configured_iterations = iterations
          configured_salt = salt
        }

        # Open window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Use the configured parameters to create PASE protocol objects
        pbkdf_params = Session::Pase::PbkdfParameters.new(
          iterations: configured_iterations.not_nil!.to_i32,
          salt: configured_salt.not_nil!
        )

        # Create PASE responder (device side)
        responder = Session::Pase::PaseResponder.new(
          pin_code: configured_pin.not_nil!,
          pbkdf_params: pbkdf_params
        )

        # Verify responder is ready
        responder.pin_code.should eq(configured_pin)
        responder.pbkdf_params.iterations.should eq(configured_iterations.not_nil!.to_i32)

        admin_comm.close
      end
    end

    describe "full commissioning flow with callbacks" do
      it "coordinates PASE, failsafe, and commissioning window lifecycle" do
        # Create integrated system
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new
        session_manager = SessionManager.new

        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Track events
        pase_started = false
        pase_stopped = false
        failsafe_closed = false
        pase_pin : UInt32? = nil

        # Wire up all callbacks
        admin_comm.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, salt : Bytes) : Nil {
          pase_started = true
          pase_pin = pin
        }

        admin_comm.on_stop_pase_server = -> : Nil {
          pase_stopped = true
        }

        admin_comm.on_close_failsafe = -> : Nil {
          failsafe_closed = true
        }

        general_comm.on_clear_pase_sessions = -> : Nil {
          session_manager.pase_session_ids.each do |session_id|
            session_manager.remove_pase_session(session_id)
          end
        }

        # Step 1: Open commissioning window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        general_comm.open_commissioning_window

        pase_started.should be_true
        admin_comm.window_open?.should be_true

        # Step 2: Establish PASE session
        pase_session = SessionManager::PaseSession.new(1000_u16, passcode: pase_pin)
        session_manager.add_pase_session(pase_session)
        session_manager.has_pase_session?(1000_u16).should be_true

        # Step 3: Arm failsafe
        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)
        general_comm.failsafe_armed?.should be_true

        # Step 4: Add NOC (simulated) - transition to CASE
        rearm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 5_u16,
          breadcrumb: 150_u64
        )
        general_comm.arm_failsafe(rearm_request, 2_u8, false)

        # Create CASE session
        case_session = SessionManager::CaseSession.new(
          session_id: 3000_u16,
          fabric_index: 2_u8,
          peer_node_id: 0x2222222222222222_u64
        )
        session_manager.add_case_session(case_session)

        # Step 5: Complete commissioning
        response = general_comm.commissioning_complete(2_u8, true)
        response.error_code.should eq(Cluster::GeneralCommissioningCluster::CommissioningError::OK)

        # Verify session cleanup happened
        session_manager.has_pase_session?(1000_u16).should be_false # PASE cleared
        session_manager.has_case_session?(3000_u16).should be_true  # CASE preserved
        general_comm.failsafe_armed?.should be_false

        # Commissioning complete doesn't automatically close the window
        # Administrator must manually close it or it will timeout
        admin_comm.window_open?.should be_true

        # Manually close the window
        admin_comm.revoke_commissioning
        pase_stopped.should be_true
        admin_comm.window_open?.should be_false

        admin_comm.close
      end

      it "handles commissioning failure and cleanup" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        general_comm = Cluster::GeneralCommissioningCluster.new
        session_manager = SessionManager.new

        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        pase_stopped = false
        failsafe_closed = false

        admin_comm.on_stop_pase_server = -> : Nil {
          pase_stopped = true
        }

        admin_comm.on_close_failsafe = -> : Nil {
          failsafe_closed = true
        }

        # Open window and arm failsafe
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        arm_request = Cluster::GeneralCommissioningCluster::ArmFailSafeRequest.new(
          expiry_length_seconds: 1_u16, # Short timeout
          breadcrumb: 100_u64
        )
        general_comm.arm_failsafe(arm_request, nil, true)

        # Wait for failsafe expiry
        sleep 1.5.seconds

        # Verify cleanup happened
        general_comm.failsafe_armed?.should be_false
        general_comm.breadcrumb.should eq(0_u64) # Reset by rollback

        # Window should still be open (separate timeout)
        admin_comm.window_open?.should be_true

        # Close window manually
        admin_comm.revoke_commissioning
        pase_stopped.should be_true

        admin_comm.close
      end
    end

    describe "concurrent access control" do
      it "prevents multiple administrators from opening window simultaneously" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Admin 1 (fabric 1) opens window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        admin_comm.admin_fabric_index.should eq(1_u8)
        admin_comm.admin_vendor_id.should eq(0x1234_u16)

        # Admin 2 (fabric 2) tries to open window (should fail)
        expect_raises(Cluster::AdministratorCommissioningCluster::BusyError, /already opened/) do
          admin_comm.open_basic_commissioning_window(open_request, 2_u8, 0x5678_u16)
        end

        # Original admin should still own window
        admin_comm.admin_fabric_index.should eq(1_u8)
        admin_comm.admin_vendor_id.should eq(0x1234_u16)

        admin_comm.close
      end

      it "clears window state when closed and reopened by same admin" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Open window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        admin_comm.window_open?.should be_true

        # Close window
        admin_comm.revoke_commissioning
        admin_comm.window_open?.should be_false

        # Same admin can re-open
        open_request2 = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request2, 1_u8, 0x1234_u16)

        # Should be open again
        admin_comm.window_open?.should be_true
        admin_comm.admin_fabric_index.should eq(1_u8)

        admin_comm.close
      end

      it "tracks administrator fabric and vendor ID" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        admin_comm.admin_fabric_index.should be_nil
        admin_comm.admin_vendor_id.should be_nil

        # Open window
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 5_u8, 0xABCD_u16)

        # Should track fabric and vendor
        admin_comm.admin_fabric_index.should eq(5_u8)
        admin_comm.admin_vendor_id.should eq(0xABCD_u16)

        # Close window
        admin_comm.revoke_commissioning

        # Should clear tracking
        admin_comm.admin_fabric_index.should be_nil
        admin_comm.admin_vendor_id.should be_nil

        admin_comm.close
      end
    end

    describe "timeout management" do
      it "enforces minimum commissioning timeout" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new

        # Try to open window with too short timeout
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 60_u16 # Less than 180 second minimum
        )

        expect_raises(ArgumentError, /minimum|must/) do
          admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        end
      end

      it "enforces maximum commissioning timeout" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new

        # Try to open window with too long timeout (default max is 900s)
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1000_u16 # More than 900 second default max
        )

        expect_raises(ArgumentError, /maximum|must|exceed/) do
          admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)
        end
      end

      it "allows configurable timeout bounds for testing" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new

        # Configure lower bounds for fast testing
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Now can use short timeouts
        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        admin_comm.window_open?.should be_true

        admin_comm.close
      end

      it "tracks window expiry time" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        open_request = Cluster::AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )
        admin_comm.open_basic_commissioning_window(open_request, 1_u8, 0x1234_u16)

        # Window should have approximately 5 seconds remaining
        time_remaining = admin_comm.time_remaining
        time_remaining.should_not be_nil
        time_remaining.not_nil!.total_seconds.should be_close(5.0, 1.0)

        admin_comm.close
      end
    end

    describe "PAKE parameter validation" do
      it "validates passcode verifier length" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        # Invalid verifier length (should be 97 bytes)
        verifier = Bytes.new(50, 0xAB_u8) # Wrong size
        salt = Bytes.new(32, 0x01_u8)

        open_request = Cluster::AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(Cluster::AdministratorCommissioningCluster::PAKEParameterError, /verifier|97/) do
          admin_comm.open_commissioning_window(open_request, 1_u8, 0x1234_u16)
        end
      end

      it "validates salt length range" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        verifier = Bytes.new(97, 0xAB_u8)

        # Salt too short
        salt_short = Bytes.new(10, 0x01_u8)
        open_request_short = Cluster::AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt_short
        )

        expect_raises(Cluster::AdministratorCommissioningCluster::PAKEParameterError, /salt|16|32/) do
          admin_comm.open_commissioning_window(open_request_short, 1_u8, 0x1234_u16)
        end

        # Salt too long
        salt_long = Bytes.new(40, 0x01_u8)
        open_request_long = Cluster::AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt_long
        )

        expect_raises(Cluster::AdministratorCommissioningCluster::PAKEParameterError, /salt|16|32/) do
          admin_comm.open_commissioning_window(open_request_long, 1_u8, 0x1234_u16)
        end
      end

      it "validates PBKDF2 iteration count range" do
        admin_comm = Cluster::AdministratorCommissioningCluster.new
        admin_comm.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        verifier = Bytes.new(97, 0xAB_u8)
        salt = Bytes.new(32, 0x01_u8)

        # Iterations too low
        open_request_low = Cluster::AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 500_u32, # Less than 1000 minimum
          salt: salt
        )

        expect_raises(Cluster::AdministratorCommissioningCluster::PAKEParameterError, /iterations|1000|100000/) do
          admin_comm.open_commissioning_window(open_request_low, 1_u8, 0x1234_u16)
        end

        # Iterations too high
        open_request_high = Cluster::AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 200000_u32, # More than 100000 maximum
          salt: salt
        )

        expect_raises(Cluster::AdministratorCommissioningCluster::PAKEParameterError, /iterations|1000|100000/) do
          admin_comm.open_commissioning_window(open_request_high, 1_u8, 0x1234_u16)
        end
      end
    end
  end
end
