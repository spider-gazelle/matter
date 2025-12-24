require "../spec_helper"
require "../../src/matter/cluster/administrator_commissioning_cluster"

module Matter::Cluster
  describe AdministratorCommissioningCluster do
    describe "initialization and attributes" do
      it "initializes with default values" do
        cluster = AdministratorCommissioningCluster.new

        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_open?.should be_false
      end

      it "exposes cluster ID" do
        AdministratorCommissioningCluster::CLUSTER_ID.should eq(0x003C_u32)
      end

      it "defines window status enum values" do
        AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen.value.should eq(0_u8)
        AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen.value.should eq(1_u8)
        AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen.value.should eq(2_u8)
      end
    end

    describe "OpenCommissioningWindow command (Enhanced)" do
      it "opens enhanced commissioning window with valid parameters" do
        cluster = AdministratorCommissioningCluster.new

        # Valid 97-byte verifier (32 bytes w0 + 65 bytes L)
        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)

        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "rejects invalid verifier length" do
        cluster = AdministratorCommissioningCluster.new

        # Invalid: 96 bytes (should be 97)
        verifier = Bytes.new(96, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(AdministratorCommissioningCluster::PAKEParameterError, /verifier length is invalid/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end

        cluster.window_open?.should be_false
      end

      it "rejects iterations below minimum" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 999_u32, # Below 1000
          salt: salt
        )

        expect_raises(AdministratorCommissioningCluster::PAKEParameterError, /iterations invalid/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects iterations above maximum" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 100001_u32, # Above 100,000
          salt: salt
        )

        expect_raises(AdministratorCommissioningCluster::PAKEParameterError, /iterations invalid/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects salt below minimum length" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(15, 1_u8) # Below 16 bytes

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(AdministratorCommissioningCluster::PAKEParameterError, /salt has invalid length/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects salt above maximum length" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(33, 1_u8) # Above 32 bytes

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(AdministratorCommissioningCluster::PAKEParameterError, /salt has invalid length/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects timeout below minimum" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 179_u16, # Below 180 seconds (3 minutes)
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(ArgumentError, /must not be lower/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects timeout above maximum" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 901_u16, # Above 900 seconds (15 minutes)
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(ArgumentError, /must not exceed/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects opening window when one already open" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        # Open first window
        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)

        # Try to open second window
        expect_raises(AdministratorCommissioningCluster::BusyError, /already opened/) do
          cluster.open_commissioning_window(request, 2_u8, 0x5678_u16)
        end

        # First window should still be open
        cluster.admin_fabric_index.should eq(1_u8)
      end
    end

    describe "OpenBasicCommissioningWindow command" do
      it "opens basic commissioning window with valid timeout" do
        cluster = AdministratorCommissioningCluster.new

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "rejects timeout below minimum" do
        cluster = AdministratorCommissioningCluster.new

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 100_u16
        )

        expect_raises(ArgumentError, /must not be lower/) do
          cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects timeout above maximum" do
        cluster = AdministratorCommissioningCluster.new

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1000_u16
        )

        expect_raises(ArgumentError, /must not exceed/) do
          cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects opening window when one already open" do
        cluster = AdministratorCommissioningCluster.new

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        # Open first window
        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        # Try to open second window
        expect_raises(AdministratorCommissioningCluster::BusyError, /already opened/) do
          cluster.open_basic_commissioning_window(request, 2_u8, 0x5678_u16)
        end
      end
    end

    describe "RevokeCommissioning command" do
      it "revokes open enhanced commissioning window" do
        cluster = AdministratorCommissioningCluster.new

        # Open enhanced window
        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)
        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )
        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        # Revoke window
        cluster.revoke_commissioning

        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_open?.should be_false
      end

      it "revokes open basic commissioning window" do
        cluster = AdministratorCommissioningCluster.new

        # Open basic window
        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )
        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        # Revoke window
        cluster.revoke_commissioning

        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        cluster.window_open?.should be_false
      end

      it "raises error when no window open" do
        cluster = AdministratorCommissioningCluster.new

        expect_raises(AdministratorCommissioningCluster::WindowNotOpenError, /No commissioning window/) do
          cluster.revoke_commissioning
        end
      end
    end

    describe "window timeout behavior" do
      it "automatically closes window after timeout" do
        cluster = AdministratorCommissioningCluster.new
        # Configure lower bounds for fast testing
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16 # 1 second for fast test
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        # Wait for timeout
        sleep 1.5.seconds
        Fiber.yield # Ensure all fibers have run

        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        cluster.window_open?.should be_false
        cluster.admin_fabric_index.should be_nil
      end

      it "cancels timeout timer when window manually revoked" do
        cluster = AdministratorCommissioningCluster.new
        # Configure lower bounds for fast testing
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        sleep 0.1.seconds

        # Revoke before timeout
        cluster.revoke_commissioning
        cluster.window_open?.should be_false

        # Wait to ensure timeout doesn't fire
        sleep 5.5.seconds

        # Window should stay closed (not re-opened by stale timeout)
        cluster.window_open?.should be_false
      end
    end

    describe "PAKE parameter validation edge cases" do
      it "accepts valid verifier at exactly 97 bytes" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0xAB_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "accepts iterations at minimum boundary (1000)" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 1000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "accepts iterations at maximum boundary (100,000)" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 100000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "accepts salt at minimum boundary (16 bytes)" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(16, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "accepts salt at maximum boundary (32 bytes)" do
        cluster = AdministratorCommissioningCluster.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end
    end

    describe "timeout boundary validation" do
      it "accepts timeout at minimum boundary (180 seconds)" do
        cluster = AdministratorCommissioningCluster.new

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 180_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "accepts timeout at maximum boundary (900 seconds)" do
        cluster = AdministratorCommissioningCluster.new

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end
    end

    describe "cleanup" do
      it "closes window on explicit close call" do
        cluster = AdministratorCommissioningCluster.new

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        cluster.close
        cluster.window_open?.should be_false
      end
    end

    describe "time tracking" do
      it "returns nil time_remaining when window not open" do
        cluster = AdministratorCommissioningCluster.new

        cluster.time_remaining.should be_nil
      end

      it "tracks time remaining during open window" do
        cluster = AdministratorCommissioningCluster.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        remaining = cluster.time_remaining
        remaining.should_not be_nil

        # Time remaining should be close to 5 seconds (within tolerance)
        if time = remaining
          time.total_seconds.should be_close(5.0, 0.5)
        end

        cluster.close
      end

      it "returns zero when window has expired" do
        cluster = AdministratorCommissioningCluster.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        # Wait for expiry
        sleep 1.5.seconds
        Fiber.yield

        # Should return nil after window closes automatically
        cluster.time_remaining.should be_nil
      end

      it "updates time remaining as time passes" do
        cluster = AdministratorCommissioningCluster.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 5_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        first_check = cluster.time_remaining
        sleep 1.seconds
        second_check = cluster.time_remaining

        first_check.should_not be_nil
        second_check.should_not be_nil

        if first = first_check
          if second = second_check
            # Second check should show less time remaining
            second.total_seconds.should be < first.total_seconds
          end
        end

        cluster.close
      end
    end

    describe "integration callbacks" do
      it "invokes on_configure_pase_server callback for enhanced commissioning" do
        cluster = AdministratorCommissioningCluster.new
        callback_invoked = false
        received_verifier = Bytes.new(0)
        received_iterations = 0_u32
        received_salt = Bytes.new(0)

        cluster.on_configure_pase_server = ->(verifier : Bytes, iterations : UInt32, salt : Bytes) {
          callback_invoked = true
          received_verifier = verifier
          received_iterations = iterations
          received_salt = salt
          nil
        }

        verifier = Bytes.new(97, 0xAA_u8)
        salt = Bytes.new(32, 0xBB_u8)
        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 5000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)

        callback_invoked.should be_true
        received_verifier.should eq(verifier)
        received_iterations.should eq(5000_u32)
        received_salt.should eq(salt)

        cluster.close
      end

      it "invokes on_configure_pase_pin callback for basic commissioning" do
        cluster = AdministratorCommissioningCluster.new
        callback_invoked = false
        received_pin = 0_u32
        received_iterations = 0_u32

        cluster.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, _salt : Bytes) {
          callback_invoked = true
          received_pin = pin
          received_iterations = iterations
          nil
        }

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        callback_invoked.should be_true
        received_pin.should eq(20202021_u32) # Standard test PIN
        received_iterations.should eq(1000_u32)

        cluster.close
      end

      it "invokes on_stop_pase_server callback when window closes" do
        cluster = AdministratorCommissioningCluster.new
        callback_invoked = false

        cluster.on_stop_pase_server = -> {
          callback_invoked = true
          nil
        }

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        callback_invoked.should be_false # Not invoked yet

        cluster.revoke_commissioning

        callback_invoked.should be_true
      end

      it "invokes on_close_failsafe callback when window closes" do
        cluster = AdministratorCommissioningCluster.new
        callback_invoked = false

        cluster.on_close_failsafe = -> {
          callback_invoked = true
          nil
        }

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        callback_invoked.should be_false # Not invoked yet

        cluster.revoke_commissioning

        callback_invoked.should be_true
      end

      it "works without callbacks configured" do
        cluster = AdministratorCommissioningCluster.new

        # Don't configure any callbacks

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)
        request = AdministratorCommissioningCluster::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        # Should not raise - callbacks are optional
        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        cluster.revoke_commissioning
        cluster.window_open?.should be_false
      end

      it "invokes callbacks on timeout expiry" do
        cluster = AdministratorCommissioningCluster.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        pase_stopped = false
        failsafe_closed = false

        cluster.on_stop_pase_server = -> {
          pase_stopped = true
          nil
        }

        cluster.on_close_failsafe = -> {
          failsafe_closed = true
          nil
        }

        request = AdministratorCommissioningCluster::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        pase_stopped.should be_false
        failsafe_closed.should be_false

        # Wait for timeout
        sleep 1.5.seconds
        Fiber.yield

        pase_stopped.should be_true
        failsafe_closed.should be_true
      end
    end
  end
end
