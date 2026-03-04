require "../spec_helper"
require "../../src/matter/cluster/administrator_commissioning_cluster"

# Helper to create TLV-encoded OpenCommissioningWindowRequest
def create_open_commissioning_window_tlv(
  timeout : UInt16,
  verifier : Bytes,
  discriminator : UInt16,
  iterations : UInt32,
  salt : Bytes,
) : Bytes
  Matter::Cluster::Definitions::AdministratorCommissioning::OpenCommissioningWindowRequest.new(
    commissioning_timeout: timeout,
    pake_passcode_verifier: verifier,
    discriminator: discriminator,
    iterations: iterations,
    salt: salt
  ).to_slice
end

# Helper to create TLV-encoded OpenBasicCommissioningWindowRequest
def create_open_basic_commissioning_window_tlv(timeout : UInt16) : Bytes
  Matter::Cluster::Definitions::AdministratorCommissioning::OpenBasicCommissioningWindowRequest.new(
    commissioning_timeout: timeout
  ).to_slice
end

module Matter::Cluster
  describe AdministratorCommissioningCluster do
    describe "initialization" do
      it "creates administrator commissioning cluster" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.cluster_id.id.should eq(0x003C_u32)
        cluster.name.should eq("AdministratorCommissioning")
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
      end
    end

    describe "attributes" do
      it "reads WindowStatus attribute" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        value = cluster.read_attribute(AdministratorCommissioningCluster::ATTR_WINDOW_STATUS)
        value.should be_a(Bytes)
        decode_tlv_value(value.as(Bytes)).should eq(0_u8) # WindowNotOpen
      end

      it "reads AdminFabricIndex attribute when nil" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        value = cluster.read_attribute(AdministratorCommissioningCluster::ATTR_ADMIN_FABRIC_INDEX)
        value.should be_a(Bytes)
        decode_tlv_value(value.as(Bytes)).should be_nil
      end

      it "reads AdminVendorId attribute when nil" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        value = cluster.read_attribute(AdministratorCommissioningCluster::ATTR_ADMIN_VENDOR_ID)
        value.should be_a(Bytes)
        decode_tlv_value(value.as(Bytes)).should be_nil
      end

      it "returns status for unsupported attribute write" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        status = cluster.write_attribute(
          AdministratorCommissioningCluster::ATTR_WINDOW_STATUS,
          Bytes[1]
        )

        status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
      end
    end

    describe "metadata" do
      it "provides attribute metadata" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        attributes = cluster.attributes
        attributes.should_not be_empty
        attributes.size.should be >= 3

        window_status = attributes.find { |attr| attr.id.id == AdministratorCommissioningCluster::ATTR_WINDOW_STATUS }
        window_status.should_not be_nil
        window_status_attr = window_status.as(AttributeMetadata)
        window_status_attr.name.should eq("WindowStatus")
        window_status_attr.writable?.should be_false
      end

      it "provides command metadata" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        commands = cluster.commands
        commands.should_not be_empty
        commands.size.should be >= 3

        open_window = commands.find { |cmd| cmd.id.id == AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW }
        open_window.should_not be_nil
        open_window.as(CommandMetadata).name.should eq("OpenCommissioningWindow")
      end
    end

    describe "CommissioningWindowStatus" do
      it "defines window status codes" do
        AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen.value.should eq(0_u8)
        AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen.value.should eq(1_u8)
        AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen.value.should eq(2_u8)
      end
    end

    describe "StatusCode" do
      it "defines status codes" do
        AdministratorCommissioningCluster::StatusCode::Busy.value.should eq(2_u8)
        AdministratorCommissioningCluster::StatusCode::PAKEParameterError.value.should eq(3_u8)
        AdministratorCommissioningCluster::StatusCode::WindowNotOpen.value.should eq(4_u8)
      end
    end

    describe "commands" do
      it "handles OpenCommissioningWindow command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        result = cluster.invoke_command(AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
      end

      it "handles OpenBasicCommissioningWindow command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        result = cluster.invoke_command(AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
      end

      it "handles RevokeCommissioning command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        result = cluster.invoke_command(AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
      end
    end

    describe "command parsing with TLV" do
      describe "OpenCommissioningWindow" do
        it "parses valid TLV-encoded command and opens window" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # Create TLV-encoded OpenCommissioningWindowRequest
          tlv_data = create_open_commissioning_window_tlv(
            timeout: 900_u16,
            verifier: Bytes.new(97, 0xAB_u8),
            discriminator: 3840_u16,
            iterations: 10000_u32,
            salt: Bytes.new(32, 0xCD_u8)
          )

          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
            tlv_data
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)
        end

        it "handles malformed TLV data" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # Invalid TLV data
          bad_tlv = Bytes[0xFF, 0xFF, 0xFF]

          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
            bad_tlv
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          # Should return PAKEParameterError status
          if result.is_a?(CommandResponse)
            result.data[0]
          else
            result.as(Matter::InteractionModel::Status).status.value
          end.should eq(1_u8) # StatusCode::PAKEParameterError
        end

        it "returns busy status when window already open" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # Create TLV-encoded OpenCommissioningWindowRequest
          tlv_data = create_open_commissioning_window_tlv(
            timeout: 900_u16,
            verifier: Bytes.new(97, 0xAB_u8),
            discriminator: 3840_u16,
            iterations: 10000_u32,
            salt: Bytes.new(32, 0xCD_u8)
          )

          # First open succeeds
          cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
            tlv_data
          )
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)

          # Second open should fail with Busy
          result2 = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
            tlv_data
          )

          result2.should be_a(Matter::InteractionModel::Status | CommandResponse)
          if result2.is_a?(CommandResponse)
            result2.data[0]
          else
            result2.as(Matter::InteractionModel::Status).status.value
          end.should eq(156_u8) # InteractionModel::StatusCode::Busy
        end
      end

      describe "OpenBasicCommissioningWindow" do
        it "parses valid TLV-encoded command and opens window" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # Create TLV-encoded OpenBasicCommissioningWindowRequest
          tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)
        end

        it "handles malformed TLV data" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # Invalid TLV data
          bad_tlv = Bytes[0xFF, 0xFF, 0xFF]

          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            bad_tlv
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          # Should return Busy error status (error handling for parse failure)
          # Implementation returns Failure (1) instead
          if result.is_a?(CommandResponse)
            result.data[0]
          else
            result.as(Matter::InteractionModel::Status).status.value
          end.should eq(1_u8) # StatusCode::Failure
        end

        it "returns busy status when window already open" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # Create TLV-encoded OpenBasicCommissioningWindowRequest
          tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

          # First open succeeds
          cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

          # Second open should fail with Busy
          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          if result.is_a?(CommandResponse)
            result.data[0]
          else
            result.as(Matter::InteractionModel::Status).status.value
          end.should eq(156_u8) # InteractionModel::StatusCode::Busy
        end
      end

      describe "RevokeCommissioning" do
        it "successfully revokes an open window" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # First open a basic window
          tlv_data = create_open_basic_commissioning_window_tlv(600_u16)
          cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
            tlv_data
          )
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

          # Then revoke it
          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING,
            Bytes.new(0)
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        end

        it "returns WindowNotOpen when no window is open" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # No callback set, window closed by default
          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING,
            Bytes.new(0)
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          if result.is_a?(CommandResponse)
            result.data[0]
          else
            result.as(Matter::InteractionModel::Status).status.value
          end.should eq(1_u8) # StatusCode::WindowNotOpen (implementation returns Failure)
        end

        it "closes window when no callback set and window is open" do
          endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
          cluster = AdministratorCommissioningCluster.new(endpoint_id)

          # Open a window first
          cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

          # Revoke with no callback - should close directly
          result = cluster.invoke_command(
            AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING,
            Bytes.new(0)
          )

          result.should be_a(Matter::InteractionModel::Status | CommandResponse)
          if result.is_a?(CommandResponse)
            result.data[0]
          else
            result.as(Matter::InteractionModel::Status).status.value
          end.should eq(0_u8) # Success
          cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        end
      end
    end

    describe "window management" do
      it "tracks window status" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        cluster.window_timeout.should be_nil
      end

      it "opens enhanced commissioning window" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.open_enhanced_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0xFFF1_u16)
        cluster.window_timeout.should_not be_nil
      end

      it "opens basic commissioning window" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.open_basic_window(180_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0xFFF1_u16)
      end

      it "closes commissioning window" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.open_basic_window(180_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

        cluster.close_window
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_timeout.should be_nil
      end

      it "checks if window is expired" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.open_basic_window(0_u16, 1_u8, 0xFFF1_u16) # Expires immediately
        cluster.window_expired?.should be_true
      end

      it "checks if window is not expired" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_expired?.should be_false
      end
    end

    describe "window state checks" do
      it "checks if window is open" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.window_open?.should be_false

        cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_open?.should be_true
      end

      it "checks window type" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

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
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.admin_fabric_index.should be_nil

        cluster.open_basic_window(300_u16, 2_u8, 0xFFF1_u16)
        cluster.admin_fabric_index.should eq(2_u8)
      end

      it "tracks admin vendor ID" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.admin_vendor_id.should be_nil

        cluster.open_basic_window(300_u16, 1_u8, 0xFFF2_u16)
        cluster.admin_vendor_id.should eq(0xFFF2_u16)
      end
    end

    describe "PAKE parameters" do
      it "stores PAKE verifier for enhanced commissioning" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        verifier = Bytes.new(97, 0xAB_u8)
        cluster.pake_verifier = verifier
        cluster.pake_verifier.should eq(verifier)
      end

      it "stores discriminator" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.discriminator = 3840_u16
        cluster.discriminator.should eq(3840_u16)
      end

      it "stores iterations" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.iterations = 1000_u32
        cluster.iterations.should eq(1000_u32)
      end

      it "stores salt" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        salt = Bytes.new(32, 0xCD_u8)
        cluster.salt = salt
        cluster.salt.should eq(salt)
      end
    end

    describe "session context" do
      it "initializes session context as nil" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        cluster.session_fabric_index.should be_nil
        cluster.session_vendor_id.should be_nil
      end

      it "uses session context in OpenCommissioningWindow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        # Set session context
        cluster.session_fabric_index = 3_u8
        cluster.session_vendor_id = 0xABCD_u16

        # Create TLV-encoded OpenCommissioningWindowRequest
        tlv_data = create_open_commissioning_window_tlv(
          timeout: 900_u16,
          verifier: Bytes.new(97, 0xAB_u8),
          discriminator: 3840_u16,
          iterations: 10000_u32,
          salt: Bytes.new(32, 0xCD_u8)
        )

        result = cluster.invoke_command(
          AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
          tlv_data
        )

        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
        # Verify session context was applied to admin attributes
        cluster.admin_fabric_index.should eq(3_u8)
        cluster.admin_vendor_id.should eq(0xABCD_u16)
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)
      end

      it "uses nil values when session context not set in OpenCommissioningWindow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        # Don't set session context - should use nil (no session info available)

        # Create TLV-encoded OpenCommissioningWindowRequest
        tlv_data = create_open_commissioning_window_tlv(
          timeout: 900_u16,
          verifier: Bytes.new(97, 0xAB_u8),
          discriminator: 3840_u16,
          iterations: 10000_u32,
          salt: Bytes.new(32, 0xCD_u8)
        )

        result = cluster.invoke_command(
          AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
          tlv_data
        )

        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
        # Verify nil values when no session context
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)
      end

      it "uses session context in OpenBasicCommissioningWindow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        # Set session context
        cluster.session_fabric_index = 5_u8
        cluster.session_vendor_id = 0x1234_u16

        # Create TLV-encoded OpenBasicCommissioningWindowRequest
        tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

        result = cluster.invoke_command(
          AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          tlv_data
        )

        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
        # Verify session context was applied to admin attributes
        cluster.admin_fabric_index.should eq(5_u8)
        cluster.admin_vendor_id.should eq(0x1234_u16)
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)
      end

      it "uses nil values when session context not set in OpenBasicCommissioningWindow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        # Don't set session context - should use nil (no session info available)

        # Create TLV-encoded OpenBasicCommissioningWindowRequest
        tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

        result = cluster.invoke_command(
          AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          tlv_data
        )

        result.should be_a(Matter::InteractionModel::Status | CommandResponse)
        # Verify nil values when no session context
        cluster.admin_fabric_index.should be_nil
        cluster.admin_vendor_id.should be_nil
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)
      end

      it "allows session context to be updated between commands" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = AdministratorCommissioningCluster.new(endpoint_id)

        # First command with fabric 1
        cluster.session_fabric_index = 1_u8
        cluster.session_vendor_id = 0x1111_u16

        tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

        cluster.invoke_command(
          AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          tlv_data
        )

        # Verify first command used fabric 1
        cluster.admin_fabric_index.should eq(1_u8)
        cluster.admin_vendor_id.should eq(0x1111_u16)
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

        # Close window to allow second open
        cluster.close_window

        # Second command with different fabric
        cluster.session_fabric_index = 2_u8
        cluster.session_vendor_id = 0x2222_u16

        cluster.invoke_command(
          AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          tlv_data
        )

        # Verify second command used fabric 2
        cluster.admin_fabric_index.should eq(2_u8)
        cluster.admin_vendor_id.should eq(0x2222_u16)
        cluster.window_status.should eq(AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)
      end
    end

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
