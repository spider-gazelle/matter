require "../spec_helper"
require "../../src/matter/commissioning/window_service"

# The window on its own: no cluster, no wire, just the state machine and the
# PASE / mDNS callbacks the device installs.
SHORT_TIMEOUT =  1_u16
LONG_TIMEOUT  = 10_u16

private def window_service(target : RecordingWindowTarget) : Matter::Commissioning::WindowService
  Matter::Commissioning::WindowService.new(target, minimum_timeout: SHORT_TIMEOUT, maximum_timeout: LONG_TIMEOUT)
end

private def valid_pake_verifier : Bytes
  Bytes.new(Matter::Commissioning::WindowService::PAKE_PASSCODE_VERIFIER_LENGTH, 0xAB_u8)
end

private def valid_pake_salt : Bytes
  Bytes.new(Matter::Commissioning::WindowService::PAKE_SALT_MAX_LENGTH, 0xCD_u8)
end

module Matter::Commissioning
  describe WindowService do
    describe "#open_enhanced" do
      it "opens a window, advertises it and configures the PASE server" do
        target = RecordingWindowTarget.new
        service = window_service(target)
        configured = [] of Tuple(Bytes, UInt32, Bytes)
        advertised = [] of Tuple(UInt16?, MDNS::CommissioningMode)
        service.on_configure_pase_server = ->(verifier : Bytes, iterations : UInt32, salt : Bytes) do
          configured << {verifier, iterations, salt}
          nil
        end
        service.on_start_commissioning_advertising = ->(discriminator : UInt16?, mode : MDNS::CommissioningMode) do
          advertised << {discriminator, mode}
          nil
        end

        service.open_enhanced(
          timeout_seconds: LONG_TIMEOUT,
          verifier: valid_pake_verifier,
          discriminator: 3840_u16,
          iterations: WindowService::BASIC_WINDOW_ITERATIONS,
          salt: valid_pake_salt,
          admin_fabric_index: 1_u8,
          admin_vendor_id: 0xFFF1_u16
        )

        service.enhanced_open?.should be_true
        service.expired?.should be_false
        service.pake_verifier.should eq(valid_pake_verifier)
        configured.size.should eq(1)
        advertised.should eq([{3840_u16, MDNS::CommissioningMode::Enhanced}])
        target.status.should eq(WindowStatus::EnhancedWindowOpen)
        target.admin_fabric_index.should eq(1_u8)
        target.admin_vendor_id.should eq(0xFFF1_u16)

        service.close
      end

      it "rejects a verifier of the wrong length" do
        service = window_service(RecordingWindowTarget.new)

        expect_raises(PAKEParameterError, /verifier length is invalid/) do
          service.open_enhanced(
            timeout_seconds: LONG_TIMEOUT,
            verifier: Bytes.new(WindowService::PAKE_PASSCODE_VERIFIER_LENGTH - 1, 0_u8),
            discriminator: 3840_u16,
            iterations: WindowService::BASIC_WINDOW_ITERATIONS,
            salt: valid_pake_salt,
            admin_fabric_index: 1_u8,
            admin_vendor_id: 0xFFF1_u16
          )
        end

        service.open?.should be_false
      end

      it "rejects a timeout outside the configured bounds" do
        service = window_service(RecordingWindowTarget.new)

        expect_raises(ArgumentError, /must not exceed/) do
          service.open_enhanced(
            timeout_seconds: LONG_TIMEOUT + 1,
            verifier: valid_pake_verifier,
            discriminator: 3840_u16,
            iterations: WindowService::BASIC_WINDOW_ITERATIONS,
            salt: valid_pake_salt,
            admin_fabric_index: 1_u8,
            admin_vendor_id: 0xFFF1_u16
          )
        end

        service.open?.should be_false
      end
    end

    describe "#open_basic" do
      it "advertises the device's own discriminator and passcode" do
        target = RecordingWindowTarget.new
        service = window_service(target)
        pins = [] of UInt32
        advertised = [] of Tuple(UInt16?, MDNS::CommissioningMode)
        service.on_configure_pase_pin = ->(pin : UInt32, _iterations : UInt32, _salt : Bytes) do
          pins << pin
          nil
        end
        service.on_start_commissioning_advertising = ->(discriminator : UInt16?, mode : MDNS::CommissioningMode) do
          advertised << {discriminator, mode}
          nil
        end

        service.open_basic(LONG_TIMEOUT, 1_u8, 0xFFF1_u16)

        service.basic_open?.should be_true
        pins.should eq([SetupPayload.default_pin])
        advertised.should eq([{nil, MDNS::CommissioningMode::Basic}])

        service.close
      end

      it "refuses a second window" do
        service = window_service(RecordingWindowTarget.new)
        service.open_basic(LONG_TIMEOUT, 1_u8, 0xFFF1_u16)

        expect_raises(BusyError, /already opened/) do
          service.open_basic(LONG_TIMEOUT, 2_u8, 0xFFF2_u16)
        end

        service.close
      end
    end

    describe "#revoke" do
      it "closes an open window and stops the PASE server" do
        target = RecordingWindowTarget.new
        service = window_service(target)
        stopped = 0
        service.on_stop_pase_server = -> { stopped += 1; nil }
        service.open_basic(LONG_TIMEOUT, 1_u8, 0xFFF1_u16)

        service.revoke

        service.open?.should be_false
        stopped.should eq(1)
        target.status.should eq(WindowStatus::WindowNotOpen)
        target.admin_fabric_index.should be_nil
        target.notifications.should eq(1)
      end

      it "fails when no window is open" do
        service = window_service(RecordingWindowTarget.new)

        expect_raises(WindowNotOpenError, /No commissioning window/) do
          service.revoke
        end
      end
    end

    describe "timeout" do
      it "closes the window when the timeout passes" do
        service = window_service(RecordingWindowTarget.new)
        service.open_basic(SHORT_TIMEOUT, 1_u8, 0xFFF1_u16)

        service.open?.should be_true
        sleep(SHORT_TIMEOUT.seconds + 500.milliseconds)
        Fiber.yield

        service.open?.should be_false
      end
    end

    describe "#mark_open" do
      it "records a window without any side effects" do
        target = RecordingWindowTarget.new
        service = window_service(target)
        advertised = 0
        service.on_start_commissioning_advertising = ->(_discriminator : UInt16?, _mode : MDNS::CommissioningMode) do
          advertised += 1
          nil
        end

        # Below the minimum timeout: a real open would be rejected
        service.mark_open(WindowStatus::BasicWindowOpen, 0_u16, 1_u8, 0xFFF1_u16)

        service.basic_open?.should be_true
        service.expired?.should be_true
        advertised.should eq(0)
        target.notifications.should eq(1)
      end
    end
  end
end
