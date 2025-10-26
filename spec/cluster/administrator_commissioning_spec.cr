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
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # Structure with anonymous tag
  data = {
    0_u8 => timeout,
    1_u8 => verifier,
    2_u8 => discriminator,
    3_u8 => iterations,
    4_u8 => salt,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

# Helper to create TLV-encoded OpenBasicCommissioningWindowRequest
def create_open_basic_commissioning_window_tlv(timeout : UInt16) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # Structure with anonymous tag
  data = {
    0_u8 => timeout,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

describe Matter::Cluster::AdministratorCommissioningCluster do
  describe "initialization" do
    it "creates administrator commissioning cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x003C_u32)
      cluster.name.should eq("AdministratorCommissioning")
      cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
      cluster.admin_fabric_index.should be_nil
      cluster.admin_vendor_id.should be_nil
    end
  end

  describe "attributes" do
    it "reads WindowStatus attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AdministratorCommissioningCluster::ATTR_WINDOW_STATUS)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes[0]) # WindowNotOpen
    end

    it "reads AdminFabricIndex attribute when nil" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AdministratorCommissioningCluster::ATTR_ADMIN_FABRIC_INDEX)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes.new(0)) # Null
    end

    it "reads AdminVendorId attribute when nil" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AdministratorCommissioningCluster::ATTR_ADMIN_VENDOR_ID)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes.new(0)) # Null
    end

    it "returns status for unsupported attribute write" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::AdministratorCommissioningCluster::ATTR_WINDOW_STATUS,
        Bytes[1]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 3

      window_status = attributes.find { |a| a.id.id == Matter::Cluster::AdministratorCommissioningCluster::ATTR_WINDOW_STATUS }
      window_status.should_not be_nil
      window_status.not_nil!.name.should eq("WindowStatus")
      window_status.not_nil!.writable.should be_false
    end

    it "provides command metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      commands = cluster.commands
      commands.should_not be_empty
      commands.size.should be >= 3

      open_window = commands.find { |c| c.id.id == Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW }
      open_window.should_not be_nil
      open_window.not_nil!.name.should eq("OpenCommissioningWindow")
    end
  end

  describe "CommissioningWindowStatus" do
    it "defines window status codes" do
      Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen.value.should eq(0_u8)
      Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen.value.should eq(1_u8)
      Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen.value.should eq(2_u8)
    end
  end

  describe "StatusCode" do
    it "defines status codes" do
      Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy.value.should eq(2_u8)
      Matter::Cluster::AdministratorCommissioningCluster::StatusCode::PAKEParameterError.value.should eq(3_u8)
      Matter::Cluster::AdministratorCommissioningCluster::StatusCode::WindowNotOpen.value.should eq(4_u8)
    end
  end

  describe "commands" do
    it "handles OpenCommissioningWindow command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      result = cluster.invoke_command(Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW, Bytes.new(0))
      result.should be_a(Bytes)
    end

    it "handles OpenBasicCommissioningWindow command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      result = cluster.invoke_command(Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW, Bytes.new(0))
      result.should be_a(Bytes)
    end

    it "handles RevokeCommissioning command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      result = cluster.invoke_command(Matter::Cluster::AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING, Bytes.new(0))
      result.should be_a(Bytes)
    end
  end

  describe "command parsing with TLV" do
    describe "OpenCommissioningWindow" do
      it "parses valid TLV-encoded command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Create TLV-encoded OpenCommissioningWindowRequest
        tlv_data = create_open_commissioning_window_tlv(
          timeout: 900_u16,
          verifier: Bytes.new(97, 0xAB_u8),
          discriminator: 3840_u16,
          iterations: 10000_u32,
          salt: Bytes.new(32, 0xCD_u8)
        )

        # Set callback to verify parsed parameters
        callback_invoked = false
        cluster.on_open_commissioning_window = ->(timeout : UInt16, verifier : Bytes, disc : UInt16, salt : Bytes, iter : UInt32, fabric : UInt8, vendor : UInt16) {
          callback_invoked = true
          timeout.should eq(900_u16)
          verifier.should eq(Bytes.new(97, 0xAB_u8))
          disc.should eq(3840_u16)
          iter.should eq(10000_u32)
          salt.should eq(Bytes.new(32, 0xCD_u8))
          Matter::Cluster::AdministratorCommissioningCluster::StatusCode.new(0)
        }

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
          tlv_data
        )

        callback_invoked.should be_true
        result.should be_a(Bytes)
      end

      it "handles malformed TLV data" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Invalid TLV data
        bad_tlv = Bytes[0xFF, 0xFF, 0xFF]

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
          bad_tlv
        )

        result.should be_a(Bytes)
        # Should return PAKEParameterError status
        result.as(Bytes)[0].should eq(3_u8) # StatusCode::PAKEParameterError
      end

      it "returns error status from callback" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Create TLV-encoded OpenCommissioningWindowRequest
        tlv_data = create_open_commissioning_window_tlv(
          timeout: 900_u16,
          verifier: Bytes.new(97, 0xAB_u8),
          discriminator: 3840_u16,
          iterations: 10000_u32,
          salt: Bytes.new(32, 0xCD_u8)
        )

        # Callback returns Busy error
        cluster.on_open_commissioning_window = ->(timeout : UInt16, verifier : Bytes, disc : UInt16, salt : Bytes, iter : UInt32, fabric : UInt8, vendor : UInt16) {
          Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy
        }

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_COMMISSIONING_WINDOW,
          tlv_data
        )

        result.should be_a(Bytes)
        result.as(Bytes)[0].should eq(2_u8) # StatusCode::Busy
      end
    end

    describe "OpenBasicCommissioningWindow" do
      it "parses valid TLV-encoded command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Create TLV-encoded OpenBasicCommissioningWindowRequest
        tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

        # Set callback to verify parsed parameters
        callback_invoked = false
        cluster.on_open_basic_commissioning_window = ->(timeout : UInt16, fabric : UInt8, vendor : UInt16) {
          callback_invoked = true
          timeout.should eq(600_u16)
          Matter::Cluster::AdministratorCommissioningCluster::StatusCode.new(0)
        }

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          tlv_data
        )

        callback_invoked.should be_true
        result.should be_a(Bytes)
      end

      it "handles malformed TLV data" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Invalid TLV data
        bad_tlv = Bytes[0xFF, 0xFF, 0xFF]

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          bad_tlv
        )

        result.should be_a(Bytes)
        # Should return Busy error status (error handling for parse failure)
        result.as(Bytes)[0].should eq(2_u8) # StatusCode::Busy
      end

      it "returns error status from callback" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Create TLV-encoded OpenBasicCommissioningWindowRequest
        tlv_data = create_open_basic_commissioning_window_tlv(600_u16)

        # Callback returns Busy error
        cluster.on_open_basic_commissioning_window = ->(timeout : UInt16, fabric : UInt8, vendor : UInt16) {
          Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy
        }

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_OPEN_BASIC_COMMISSIONING_WINDOW,
          tlv_data
        )

        result.should be_a(Bytes)
        result.as(Bytes)[0].should eq(2_u8) # StatusCode::Busy
      end
    end

    describe "RevokeCommissioning" do
      it "invokes callback when set" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        callback_invoked = false
        cluster.on_revoke_commissioning = -> {
          callback_invoked = true
          Matter::Cluster::AdministratorCommissioningCluster::StatusCode.new(0)
        }

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING,
          Bytes.new(0)
        )

        callback_invoked.should be_true
        result.should be_a(Bytes)
      end

      it "returns WindowNotOpen when no window is open" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # No callback set, window closed by default
        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING,
          Bytes.new(0)
        )

        result.should be_a(Bytes)
        result.as(Bytes)[0].should eq(4_u8) # StatusCode::WindowNotOpen
      end

      it "closes window when no callback set and window is open" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Open a window first
        cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
        cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

        # Revoke with no callback - should close directly
        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING,
          Bytes.new(0)
        )

        result.should be_a(Bytes)
        result.as(Bytes)[0].should eq(0_u8) # Success
        cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
      end

      it "returns error status from callback" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

        # Callback returns WindowNotOpen error
        cluster.on_revoke_commissioning = -> {
          Matter::Cluster::AdministratorCommissioningCluster::StatusCode::WindowNotOpen
        }

        result = cluster.invoke_command(
          Matter::Cluster::AdministratorCommissioningCluster::CMD_REVOKE_COMMISSIONING,
          Bytes.new(0)
        )

        result.should be_a(Bytes)
        result.as(Bytes)[0].should eq(4_u8) # StatusCode::WindowNotOpen
      end
    end
  end

  describe "window management" do
    it "tracks window status" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
      cluster.window_timeout.should be_nil
    end

    it "opens enhanced commissioning window" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.open_enhanced_window(300_u16, 1_u8, 0xFFF1_u16)
      cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::EnhancedWindowOpen)
      cluster.admin_fabric_index.should eq(1_u8)
      cluster.admin_vendor_id.should eq(0xFFF1_u16)
      cluster.window_timeout.should_not be_nil
    end

    it "opens basic commissioning window" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.open_basic_window(180_u16, 1_u8, 0xFFF1_u16)
      cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)
      cluster.admin_fabric_index.should eq(1_u8)
      cluster.admin_vendor_id.should eq(0xFFF1_u16)
    end

    it "closes commissioning window" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.open_basic_window(180_u16, 1_u8, 0xFFF1_u16)
      cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::BasicWindowOpen)

      cluster.close_window
      cluster.window_status.should eq(Matter::Cluster::AdministratorCommissioningCluster::CommissioningWindowStatus::WindowNotOpen)
      cluster.admin_fabric_index.should be_nil
      cluster.admin_vendor_id.should be_nil
      cluster.window_timeout.should be_nil
    end

    it "checks if window is expired" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.open_basic_window(0_u16, 1_u8, 0xFFF1_u16) # Expires immediately
      cluster.is_window_expired?.should be_true
    end

    it "checks if window is not expired" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
      cluster.is_window_expired?.should be_false
    end
  end

  describe "window state checks" do
    it "checks if window is open" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.is_window_open?.should be_false

      cluster.open_basic_window(300_u16, 1_u8, 0xFFF1_u16)
      cluster.is_window_open?.should be_true
    end

    it "checks window type" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

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
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.admin_fabric_index.should be_nil

      cluster.open_basic_window(300_u16, 2_u8, 0xFFF1_u16)
      cluster.admin_fabric_index.should eq(2_u8)
    end

    it "tracks admin vendor ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.admin_vendor_id.should be_nil

      cluster.open_basic_window(300_u16, 1_u8, 0xFFF2_u16)
      cluster.admin_vendor_id.should eq(0xFFF2_u16)
    end
  end

  describe "PAKE parameters" do
    it "stores PAKE verifier for enhanced commissioning" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      verifier = Bytes.new(97, 0xAB_u8)
      cluster.pake_verifier = verifier
      cluster.pake_verifier.should eq(verifier)
    end

    it "stores discriminator" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.discriminator = 3840_u16
      cluster.discriminator.should eq(3840_u16)
    end

    it "stores iterations" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      cluster.iterations = 1000_u32
      cluster.iterations.should eq(1000_u32)
    end

    it "stores salt" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

      salt = Bytes.new(32, 0xCD_u8)
      cluster.salt = salt
      cluster.salt.should eq(salt)
    end
  end
end
