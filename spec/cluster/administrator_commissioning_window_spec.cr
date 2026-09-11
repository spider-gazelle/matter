require "../support/administrator_commissioning_helpers"

module Matter::Cluster
  describe AdministratorCommissioning do
    describe "command parsing with TLV" do
      describe "OpenCommissioningWindow" do
        it "parses valid TLV-encoded command and opens window" do
          cluster = build(AdministratorCommissioning, 0)

          # Create TLV-encoded OpenCommissioningWindowRequest
          tlv_data = create_open_commissioning_window_tlv(
            timeout: 900_u16,
            verifier: Bytes.new(97, 0xAB_u8),
            discriminator: 3840_u16,
            iterations: 10000_u32,
            salt: Bytes.new(32, 0xCD_u8)
          )

          result = invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_COMMISSIONING_WINDOW,
            tlv_data
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::EnhancedWindowOpen)
        end

        it "handles malformed TLV data" do
          cluster = build(AdministratorCommissioning, 0)

          # Invalid TLV data
          bad_tlv = TLV::Any.new(Bytes[0xFF, 0xFF, 0xFF])

          result = invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_COMMISSIONING_WINDOW,
            bad_tlv
          )

          # A request that fails to decode is an InvalidCommand
          expect_status(result, Matter::InteractionModel::StatusCode::InvalidCommand)
        end

        it "returns busy status when window already open" do
          cluster = build(AdministratorCommissioning, 0)

          # Create TLV-encoded OpenCommissioningWindowRequest
          tlv_data = create_open_commissioning_window_tlv(
            timeout: 900_u16,
            verifier: Bytes.new(97, 0xAB_u8),
            discriminator: 3840_u16,
            iterations: 10000_u32,
            salt: Bytes.new(32, 0xCD_u8)
          )

          # First open succeeds
          invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_COMMISSIONING_WINDOW,
            tlv_data
          )
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::EnhancedWindowOpen)

          # Second open should fail with Busy
          result2 = invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_COMMISSIONING_WINDOW,
            tlv_data
          )

          result2.should be_a(Matter::InteractionModel::Status | CommandResponse)
          result2.as(Matter::InteractionModel::Status).status.value.should eq(156_u8) # InteractionModel::StatusCode::Busy
        end
      end

      describe "OpenBasicCommissioningWindow" do
        it "parses valid TLV-encoded command and opens window" do
          cluster = build(AdministratorCommissioning, 0)

          # Create TLV-encoded OpenBasicCommissioningWindowRequest
          tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

          result = invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen)
        end

        it "handles malformed TLV data" do
          cluster = build(AdministratorCommissioning, 0)

          # Invalid TLV data
          bad_tlv = TLV::Any.new(Bytes[0xFF, 0xFF, 0xFF])

          result = invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            bad_tlv
          )

          # A request that fails to decode is an InvalidCommand
          expect_status(result, Matter::InteractionModel::StatusCode::InvalidCommand)
        end

        it "returns busy status when window already open" do
          cluster = build(AdministratorCommissioning, 0)

          # Create TLV-encoded OpenBasicCommissioningWindowRequest
          tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

          # First open succeeds
          invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen)

          # Second open should fail with Busy
          result = invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          result.as(Matter::InteractionModel::Status).status.value.should eq(156_u8) # InteractionModel::StatusCode::Busy
        end
      end

      describe "RevokeCommissioning" do
        it "successfully revokes an open window" do
          cluster = build(AdministratorCommissioning, 0)

          # First open a basic window
          tlv_data = create_open_basic_commissioning_window_tlv(600_u16)
          invoke(cluster,
            AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen)

          # Then revoke it
          result = invoke(cluster,
            AdministratorCommissioning::CMD_REVOKE_COMMISSIONING,
            Bytes.new(0)
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
        end

        it "returns WindowNotOpen when no window is open" do
          cluster = build(AdministratorCommissioning, 0)

          # No callback set, window closed by default
          result = invoke(cluster,
            AdministratorCommissioning::CMD_REVOKE_COMMISSIONING,
            Bytes.new(0)
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          result.as(Matter::InteractionModel::Status).status.value.should eq(1_u8) # StatusCode::WindowNotOpen (implementation returns Failure)
        end

        it "closes window when no callback set and window is open" do
          cluster = build(AdministratorCommissioning, 0)

          # Open a window first
          cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen)

          # Revoke with no callback - should close directly
          result = invoke(cluster,
            AdministratorCommissioning::CMD_REVOKE_COMMISSIONING,
            Bytes.new(0)
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          result.as(Matter::InteractionModel::Status).status.value.should eq(0_u8) # Success
          cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
        end
      end
    end

    describe "window management" do
      it "tracks window status" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
        cluster.window_timeout.should be_nil
      end

      it "opens enhanced commissioning window" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.open_enhanced_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::EnhancedWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0xFFF1_u16)
        cluster.window_timeout.should_not be_nil
      end

      it "opens basic commissioning window" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.open_basic_window(180_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0xFFF1_u16)
      end

      it "closes commissioning window" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.open_basic_window(180_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen)

        cluster.close_window
        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_timeout.should be_nil
      end

      it "checks if window is expired" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.open_basic_window(0_u16, 1_u8, 0xFFF1_u16) # Expires immediately
        cluster.window_expired?.should be_true
      end

      it "checks if window is not expired" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_expired?.should be_false
      end
    end

    describe "window state checks" do
      it "checks if window is open" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.window_open?.should be_false

        cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_open?.should be_true
      end

      it "checks window type" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.open_enhanced_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.enhanced_window_open?.should be_true
        cluster.window_status.basic_window_open?.should be_false

        cluster.close_window
        cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.enhanced_window_open?.should be_false
        cluster.window_status.basic_window_open?.should be_true
      end
    end

    describe "admin tracking" do
      it "tracks admin fabric index" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.admin_fabric_index.should be_nil

        cluster.open_basic_window(300_u16, 2_u8, 0xFFF1_u16)
        cluster.admin_fabric_index.should eq(2_u8)
      end

      it "tracks admin vendor ID" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.admin_vendor_id.should be_nil

        cluster.open_basic_window(300_u16, 1_u8, 0xFFF2_u16)
        cluster.admin_vendor_id.should eq(0xFFF2_u16)
      end
    end

    describe "OpenBasicCommissioningWindow command" do
      it "opens basic commissioning window with valid timeout" do
        cluster = AdministratorCommissioning.new

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen)
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
        cluster.revoke_commissioning!

        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
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
        cluster.revoke_commissioning!

        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
        cluster.window_open?.should be_false
      end

      it "raises error when no window open" do
        cluster = AdministratorCommissioning.new

        expect_raises(AdministratorCommissioning::WindowNotOpenError, /No commissioning window/) do
          cluster.revoke_commissioning!
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

        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
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
        cluster.revoke_commissioning!
        cluster.window_open?.should be_false

        # Wait to ensure timeout doesn't fire
        sleep 5.5.seconds

        # Window should stay closed (not re-opened by stale timeout)
        cluster.window_open?.should be_false
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

    describe "time tracking" do
      it "returns nil time_remaining when window not open" do
        cluster = AdministratorCommissioning.new

        cluster.time_remaining.should be_nil
      end

      it "tracks time remaining during open window" do
        cluster = AdministratorCommissioning.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
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
  end
end
