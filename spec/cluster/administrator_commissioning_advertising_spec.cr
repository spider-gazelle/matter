require "../support/administrator_commissioning_helpers"

module Matter::Cluster
  describe AdministratorCommissioning do
    describe "initialization" do
      it "creates administrator commissioning cluster" do
        cluster = build(AdministratorCommissioning, 0)

        cluster.cluster_id.id.should eq(0x003C_u32)
        cluster.name.should eq("AdministratorCommissioning")
        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
      end
    end

    describe "attributes" do
      it "reads WindowStatus attribute" do
        cluster = build(AdministratorCommissioning, 0)

        read(cluster, AdministratorCommissioning::ATTR_WINDOW_STATUS).should eq(0_u8) # WindowNotOpen
      end

      it "reads AdminFabricIndex attribute when nil" do
        cluster = build(AdministratorCommissioning, 0)

        read(cluster, AdministratorCommissioning::ATTR_ADMIN_FABRIC_INDEX).should be_nil
      end

      it "reads AdminVendorId attribute when nil" do
        cluster = build(AdministratorCommissioning, 0)

        read(cluster, AdministratorCommissioning::ATTR_ADMIN_VENDOR_ID).should be_nil
      end

      it "returns status for unsupported attribute write" do
        cluster = build(AdministratorCommissioning, 0)

        status = write(cluster,
          AdministratorCommissioning::ATTR_WINDOW_STATUS,
          1_u8
        )

        status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
      end
    end

    describe "metadata" do
      it "provides attribute metadata" do
        cluster = build(AdministratorCommissioning, 0)

        attributes = cluster.attributes
        attributes.should_not be_empty
        attributes.size.should be >= 3

        window_status = attributes.find { |attr| attr.id.id == AdministratorCommissioning::ATTR_WINDOW_STATUS }
        window_status.should_not be_nil
        window_status_attr = window_status.as(AttributeMetadata)
        window_status_attr.name.should eq("windowStatus")
        window_status_attr.writable?.should be_false
      end

      it "provides command metadata" do
        cluster = build(AdministratorCommissioning, 0)

        commands = cluster.commands
        commands.should_not be_empty
        commands.size.should be >= 3

        open_window = commands.find { |cmd| cmd.id.id == AdministratorCommissioning::CMD_OPEN_COMMISSIONING_WINDOW }
        open_window.should_not be_nil
        open_window.as(CommandMetadata).name.should eq("openCommissioningWindow")
      end
    end

    describe "CommissioningWindowStatus" do
      it "defines window status codes" do
        AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen.value.should eq(0_u8)
        AdministratorCommissioning::CommissioningWindowStatus::EnhancedWindowOpen.value.should eq(1_u8)
        AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen.value.should eq(2_u8)
      end
    end

    describe "StatusCode" do
      it "defines status codes" do
        AdministratorCommissioning::StatusCode::Busy.value.should eq(2_u8)
        AdministratorCommissioning::StatusCode::PAKEParameterError.value.should eq(3_u8)
        AdministratorCommissioning::StatusCode::WindowNotOpen.value.should eq(4_u8)
      end
    end

    describe "commands" do
      it "handles OpenCommissioningWindow command" do
        cluster = build(AdministratorCommissioning, 0)

        result = invoke(cluster, AdministratorCommissioning::CMD_OPEN_COMMISSIONING_WINDOW, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
      end

      it "handles OpenBasicCommissioningWindow command" do
        cluster = build(AdministratorCommissioning, 0)

        result = invoke(cluster, AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
      end

      it "handles RevokeCommissioning command" do
        cluster = build(AdministratorCommissioning, 0)

        result = invoke(cluster, AdministratorCommissioning::CMD_REVOKE_COMMISSIONING, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
      end
    end

    describe "initialization and attributes" do
      it "initializes with default values" do
        cluster = AdministratorCommissioning.new

        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_open?.should be_false
      end

      it "exposes cluster ID" do
        AdministratorCommissioning::CLUSTER_ID.should eq(0x003C_u32)
      end

      it "defines window status enum values" do
        AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen.value.should eq(0_u8)
        AdministratorCommissioning::CommissioningWindowStatus::EnhancedWindowOpen.value.should eq(1_u8)
        AdministratorCommissioning::CommissioningWindowStatus::BasicWindowOpen.value.should eq(2_u8)
      end
    end

    describe "commissioning advertising callback" do
      it "asks for the device discriminator when a basic window opens" do
        cluster = build(AdministratorCommissioning, 0)
        requests = [] of {UInt16?, Matter::MDNS::CommissioningMode}
        cluster.on_start_commissioning_advertising = ->(discriminator : UInt16?, mode : Matter::MDNS::CommissioningMode) do
          requests << {discriminator, mode}
        end

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(commissioning_timeout: 900_u16)
        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        requests.should eq([{nil, Matter::MDNS::CommissioningMode::Basic}])
        cluster.close
      end

      it "asks for the requested discriminator when an enhanced window opens" do
        cluster = build(AdministratorCommissioning, 0)
        requests = [] of {UInt16?, Matter::MDNS::CommissioningMode}
        cluster.on_start_commissioning_advertising = ->(discriminator : UInt16?, mode : Matter::MDNS::CommissioningMode) do
          requests << {discriminator, mode}
        end

        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: Bytes.new(97, 0xAB_u8),
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: Bytes.new(32, 0xCD_u8)
        )
        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)

        requests.should eq([{1234_u16, Matter::MDNS::CommissioningMode::Enhanced}])
        cluster.close
      end

      it "stops advertising when the window is revoked" do
        cluster = build(AdministratorCommissioning, 0)
        stops = 0
        cluster.on_stop_commissioning_advertising = -> { stops += 1 }

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(commissioning_timeout: 900_u16)
        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.revoke_commissioning!

        stops.should eq(1)
      end
    end

    describe "integration callbacks" do
      it "invokes on_configure_pase_server callback for enhanced commissioning" do
        cluster = AdministratorCommissioning.new
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
        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
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
        cluster = AdministratorCommissioning.new
        callback_invoked = false
        received_pin = 0_u32
        received_iterations = 0_u32

        cluster.on_configure_pase_pin = ->(pin : UInt32, iterations : UInt32, _salt : Bytes) {
          callback_invoked = true
          received_pin = pin
          received_iterations = iterations
          nil
        }

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        callback_invoked.should be_true
        received_pin.should eq(20202021_u32) # Standard test PIN
        received_iterations.should eq(1000_u32)

        cluster.close
      end

      it "invokes on_stop_pase_server callback when window closes" do
        cluster = AdministratorCommissioning.new
        callback_invoked = false

        cluster.on_stop_pase_server = -> {
          callback_invoked = true
          nil
        }

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 600_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)
        callback_invoked.should be_false # Not invoked yet

        cluster.revoke_commissioning!

        callback_invoked.should be_true
      end

      it "works without callbacks configured" do
        cluster = AdministratorCommissioning.new

        # Don't configure any callbacks

        verifier = Bytes.new(97, 0_u8)
        salt = Bytes.new(32, 1_u8)
        request = AdministratorCommissioning::OpenCommissioningWindowRequest.new(
          commissioning_timeout: 900_u16,
          pake_passcode_verifier: verifier,
          discriminator: 1234_u16,
          iterations: 10000_u32,
          salt: salt
        )

        # Should not raise - callbacks are optional
        cluster.open_commissioning_window(request, 1_u8, 0x1234_u16)
        cluster.window_open?.should be_true

        cluster.revoke_commissioning!
        cluster.window_open?.should be_false
      end

      it "stops the PASE server when the window times out" do
        cluster = AdministratorCommissioning.new
        cluster.configure_timeout_bounds(minimum: 1_u16, maximum: 10_u16)

        pase_stopped = false

        cluster.on_stop_pase_server = -> {
          pase_stopped = true
          nil
        }

        request = AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
          commissioning_timeout: 1_u16
        )

        cluster.open_basic_commissioning_window(request, 1_u8, 0x1234_u16)

        pase_stopped.should be_false

        # Wait for timeout
        sleep 1.5.seconds
        Fiber.yield

        pase_stopped.should be_true
        cluster.window_open?.should be_false
      end
    end

    describe "wire status mapping" do
      it "answers ConstraintError when the commissioning timeout is out of bounds" do
        cluster = build(AdministratorCommissioning, 0)
        too_short = AdministratorCommissioning::MINIMUM_COMMISSIONING_TIMEOUT - 1

        result = invoke(cluster,
          AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          create_open_basic_commissioning_window_tlv(too_short)
        )

        result.should eq(Matter::InteractionModel::Status.constraint_error)
        cluster.window_status.should eq(AdministratorCommissioning::CommissioningWindowStatus::WindowNotOpen)
      end

      it "answers Failure with the PAKEParameterError cluster status for a bad verifier" do
        cluster = build(AdministratorCommissioning, 0)
        tlv_data = create_open_commissioning_window_tlv(
          timeout: 900_u16,
          verifier: Bytes.new(AdministratorCommissioning::PAKE_PASSCODE_VERIFIER_LENGTH - 1, 0xAB_u8),
          discriminator: 3840_u16,
          iterations: 10000_u32,
          salt: Bytes.new(32, 0xCD_u8)
        )

        result = invoke(cluster, AdministratorCommissioning::CMD_OPEN_COMMISSIONING_WINDOW, tlv_data)

        result.should eq(Matter::InteractionModel::Status.cluster_failure(AdministratorCommissioning::StatusCode::PAKEParameterError))
      end

      it "answers Busy when a window is already open" do
        cluster = build(AdministratorCommissioning, 0)
        tlv_data = create_open_basic_commissioning_window_tlv(600_u16)
        invoke(cluster, AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW, tlv_data)

        result = invoke(cluster, AdministratorCommissioning::CMD_OPEN_BASIC_COMMISSIONING_WINDOW, tlv_data)

        result.should eq(Matter::InteractionModel::Status.busy)
      end

      it "answers Failure with the WindowNotOpen cluster status when revoking a closed window" do
        cluster = build(AdministratorCommissioning, 0)

        result = invoke(cluster, AdministratorCommissioning::CMD_REVOKE_COMMISSIONING, Bytes.new(0))

        result.should eq(Matter::InteractionModel::Status.cluster_failure(AdministratorCommissioning::StatusCode::WindowNotOpen))
      end
    end
  end
end
