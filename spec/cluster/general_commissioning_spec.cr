require "../spec_helper"
require "../../src/matter/cluster/general_commissioning_cluster"

# Helper functions for TLV encoding command data
def create_arm_failsafe_request_tlv(expiry_length : UInt16, breadcrumb : UInt64) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  data = {
    0_u8 => expiry_length,
    1_u8 => breadcrumb,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_set_regulatory_config_request_tlv(regulatory_config : UInt8, country_code : String, breadcrumb : UInt64) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  data = {
    0_u8 => regulatory_config,
    1_u8 => country_code,
    2_u8 => breadcrumb,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

describe Matter::Cluster::GeneralCommissioningCluster do
  describe "initialization" do
    it "creates general commissioning cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0030_u32)
      cluster.name.should eq("GeneralCommissioning")
      cluster.breadcrumb.should eq(0_u64)
      cluster.fail_safe_active.should be_false
    end
  end

  describe "attributes" do
    it "reads Breadcrumb attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::GeneralCommissioningCluster::ATTR_BREADCRUMB)
      value.should be_a(Bytes)
      # UInt64 encoded as 8 bytes
      value.as(Bytes).size.should eq(8)
    end

    it "writes Breadcrumb attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      # Encode UInt64 value
      io = IO::Memory.new
      io.write_bytes(0x1234567890ABCDEF_u64, IO::ByteFormat::LittleEndian)
      new_value = io.to_slice

      status = cluster.write_attribute(
        Matter::Cluster::GeneralCommissioningCluster::ATTR_BREADCRUMB,
        new_value
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.breadcrumb.should eq(0x1234567890ABCDEF_u64)
    end

    it "reads BasicCommissioningInfo attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::GeneralCommissioningCluster::ATTR_BASIC_COMMISSIONING_INFO)
      value.should be_a(Bytes)
    end

    it "reads RegulatoryConfig attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::GeneralCommissioningCluster::ATTR_REGULATORY_CONFIG)
      value.should be_a(Bytes)
    end

    it "reads LocationCapability attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::GeneralCommissioningCluster::ATTR_LOCATION_CAPABILITY)
      value.should be_a(Bytes)
    end

    it "reads SupportsConcurrentConnection attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::GeneralCommissioningCluster::ATTR_SUPPORTS_CONCURRENT_CONNECTION)
      value.should be_a(Bytes)
      decode_tlv_value(value.as(Bytes)).should eq(true)
    end

    it "returns status for unsupported attribute write" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::GeneralCommissioningCluster::ATTR_REGULATORY_CONFIG,
        Bytes[0]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 5

      breadcrumb = attributes.find { |a| a.id.id == Matter::Cluster::GeneralCommissioningCluster::ATTR_BREADCRUMB }
      breadcrumb.should_not be_nil
      breadcrumb.not_nil!.name.should eq("Breadcrumb")
      breadcrumb.not_nil!.writable.should be_true
    end

    it "provides command metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      commands = cluster.commands
      commands.should_not be_empty
      commands.size.should be >= 3

      arm_failsafe = commands.find { |c| c.id.id == Matter::Cluster::GeneralCommissioningCluster::CMD_ARM_FAIL_SAFE }
      arm_failsafe.should_not be_nil
      arm_failsafe.not_nil!.name.should eq("ArmFailSafe")
    end
  end

  describe "BasicCommissioningInfo" do
    it "creates basic commissioning info" do
      info = Matter::Cluster::GeneralCommissioningCluster::BasicCommissioningInfo.new(
        fail_safe_expiry_length: 60_u16,
        max_cumulative_failsafe_seconds: 900_u16
      )

      info.fail_safe_expiry_length.should eq(60_u16)
      info.max_cumulative_failsafe_seconds.should eq(900_u16)
    end
  end

  describe "RegulatoryLocationType" do
    it "defines regulatory location types" do
      Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor.value.should eq(0_u8)
      Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Outdoor.value.should eq(1_u8)
      Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor.value.should eq(2_u8)
    end
  end

  describe "CommissioningError" do
    it "defines commissioning error codes" do
      Matter::Cluster::GeneralCommissioningCluster::CommissioningError::OK.value.should eq(0_u8)
      Matter::Cluster::GeneralCommissioningCluster::CommissioningError::ValueOutsideRange.value.should eq(1_u8)
      Matter::Cluster::GeneralCommissioningCluster::CommissioningError::InvalidAuthentication.value.should eq(2_u8)
      Matter::Cluster::GeneralCommissioningCluster::CommissioningError::NoFailSafe.value.should eq(3_u8)
      Matter::Cluster::GeneralCommissioningCluster::CommissioningError::BusyWithOtherAdmin.value.should eq(4_u8)
    end
  end

  describe "commands" do
    it "handles ArmFailSafe command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      command_data = create_arm_failsafe_request_tlv(60_u16, 0x1234_u64)
      result = cluster.invoke_command(Matter::Cluster::GeneralCommissioningCluster::CMD_ARM_FAIL_SAFE, command_data)
      result.should be_a(Bytes)
    end

    it "handles SetRegulatoryConfig command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      command_data = create_set_regulatory_config_request_tlv(2_u8, "US", 0x5678_u64) # IndoorOutdoor
      result = cluster.invoke_command(Matter::Cluster::GeneralCommissioningCluster::CMD_SET_REGULATORY_CONFIG, command_data)
      result.should be_a(Bytes)
    end

    it "handles CommissioningComplete command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      # CommissioningComplete has no request parameters, but still needs empty TLV structure
      result = cluster.invoke_command(Matter::Cluster::GeneralCommissioningCluster::CMD_COMMISSIONING_COMPLETE, Bytes.new(0))
      result.should be_a(Bytes)
    end
  end

  describe "fail-safe management" do
    it "tracks fail-safe state" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.fail_safe_active.should be_false
      cluster.fail_safe_expiry_time.should be_nil
    end

    it "arms fail-safe" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.arm_fail_safe(60_u16)
      cluster.fail_safe_active.should be_true
      cluster.fail_safe_expiry_time.should_not be_nil
    end

    it "disarms fail-safe" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.arm_fail_safe(60_u16)
      cluster.fail_safe_active.should be_true

      cluster.disarm_fail_safe
      cluster.fail_safe_active.should be_false
      cluster.fail_safe_expiry_time.should be_nil
    end

    it "checks if fail-safe is expired" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.arm_fail_safe(0_u16) # Expired immediately
      cluster.is_fail_safe_expired?.should be_true
    end
  end

  describe "regulatory configuration" do
    it "tracks regulatory config" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.regulatory_config.should eq(Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor)
    end

    it "updates regulatory config" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.regulatory_config = Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor
      cluster.regulatory_config.should eq(Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor)
    end

    it "tracks country code" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.country_code.should eq("XX")
    end

    it "updates country code" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.country_code = "US"
      cluster.country_code.should eq("US")
    end
  end

  describe "breadcrumb tracking" do
    it "tracks breadcrumb value" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.breadcrumb.should eq(0_u64)
    end

    it "updates breadcrumb" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.breadcrumb = 0x123456789ABCDEF0_u64
      cluster.breadcrumb.should eq(0x123456789ABCDEF0_u64)
    end
  end

  describe "commissioning info" do
    it "provides basic commissioning info" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      info = cluster.basic_commissioning_info
      info.fail_safe_expiry_length.should eq(60_u16)
      info.max_cumulative_failsafe_seconds.should eq(900_u16)
    end

    it "supports concurrent connection" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.supports_concurrent_connection.should be_true
    end
  end

  describe "location capability" do
    it "tracks location capability" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

      cluster.location_capability.should eq(Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor)
    end
  end
end
