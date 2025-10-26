require "../spec_helper"
require "../../src/matter/clusters/administrator_commissioning"

module Matter::Clusters
  describe AdministratorCommissioning do
    describe "initialization and attributes" do
      it "initializes with default values" do
        cluster = AdministratorCommissioning.new

        cluster.window_status.should eq(AdministratorCommissioning::WindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_open?.should be_false
      end

      it "exposes cluster ID" do
        AdministratorCommissioning::CLUSTER_ID.should eq(0x003C_u16)
      end

      it "defines window status enum values" do
        AdministratorCommissioning::WindowStatus::WindowNotOpen.value.should eq(0_u8)
        AdministratorCommissioning::WindowStatus::EnhancedWindowOpen.value.should eq(1_u8)
        AdministratorCommissioning::WindowStatus::BasicWindowOpen.value.should eq(2_u8)
      end
    end

    describe "OpenCommissioningWindow command (Enhanced)" do
      it "opens enhanced commissioning window with valid parameters" do
        cluster = AdministratorCommissioning.new

        # Valid 97-byte verifier (32 bytes w0 + 65 bytes L)
        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)

        cluster.window_status.should eq(AdministratorCommissioning::WindowStatus::EnhancedWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "rejects invalid verifier length" do
        cluster = AdministratorCommissioning.new

        # Invalid: 96 bytes (should be 97)
        verifier = Bytes.new(96, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(AdministratorCommissioning::PAKEParameterError, /verifier length is invalid/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end

        cluster.window_open?.should be_false
      end

      it "rejects iterations below minimum" do
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 999_u32, # Below 1000
          salt: salt
        )

        expect_raises(AdministratorCommissioning::PAKEParameterError, /iterations invalid/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects iterations above maximum" do
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 100001_u32, # Above 100,000
          salt: salt
        )

        expect_raises(AdministratorCommissioning::PAKEParameterError, /iterations invalid/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects salt below minimum length" do
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(15, 1_u8) # Below 16 bytes

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(AdministratorCommissioning::PAKEParameterError, /salt has invalid length/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects salt above maximum length" do
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(33, 1_u8) # Above 32 bytes

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        expect_raises(AdministratorCommissioning::PAKEParameterError, /salt has invalid length/) do
          cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects timeout below minimum" do
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        # Open first window
        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)

        # Try to open second window
        expect_raises(AdministratorCommissioning::BusyError, /already opened/) do
          cluster.open_commissioning_window(request, 2_u8, 0x5678_u16)
        end

        # First window should still be open
        cluster.admin_fabric_index.should eq(1_u8)
      end
    end

    describe "OpenBasicCommissioningWindow command" do
      it "opens basic commissioning window with valid timeout" do
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        cluster.window_status.should eq(AdministratorCommissioning::WindowStatus::BasicWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "rejects timeout below minimum" do
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 100_u16
        )

        expect_raises(ArgumentError, /must not be lower/) do
          cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects timeout above maximum" do
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1000_u16
        )

        expect_raises(ArgumentError, /must not exceed/) do
          cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        end
      end

      it "rejects opening window when one already open" do
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        # Open first window
        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        # Try to open second window
        expect_raises(AdministratorCommissioning::BusyError, /already opened/) do
          cluster.open_basic_commissioning_window(request, 2_u8, 0x5678_u16)
        end
      end
    end

    describe "RevokeCommissioning command" do
      it "revokes open enhanced commissioning window" do
        cluster = AdministratorCommissioning.new

        # Open enhanced window
        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)
        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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

        cluster.window_status.should eq(AdministratorCommissioning::WindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_open?.should be_false
      end

      it "revokes open basic commissioning window" do
        cluster = AdministratorCommissioning.new

        # Open basic window
        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )
        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        # Revoke window
        cluster.revoke_commissioning

        cluster.window_status.should eq(AdministratorCommissioning::WindowStatus::WindowNotOpen)
        cluster.window_open?.should be_false
      end

      it "raises error when no window open" do
        cluster = AdministratorCommissioning.new

        expect_raises(AdministratorCommissioning::WindowNotOpenError, /No commissioning window/) do
          cluster.revoke_commissioning
        end
      end
    end

    describe "window timeout behavior" do
      it "automatically closes window after timeout" do
        cluster = AdministratorCommissioning.new
        # Configure lower bounds for fast testing
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16 # 1 second for fast test
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        # Wait for timeout
        sleep 1.5.seconds
        Fiber.yield # Ensure all fibers have run

        cluster.window_status.should eq(AdministratorCommissioning::WindowStatus::WindowNotOpen)
        cluster.window_open?.should be_false
        cluster.admin_fabric_index.should be_nil
      end

      it "cancels timeout timer when window manually revoked" do
        cluster = AdministratorCommissioning.new
        # Configure lower bounds for fast testing
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0xAB_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(16, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 180_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end

      it "accepts timeout at maximum boundary (900 seconds)" do
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true
      end
    end

    describe "cleanup" do
      it "closes window on explicit close call" do
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        cluster.close
        cluster.window_open?.should be_false
      end
    end
  end
end
