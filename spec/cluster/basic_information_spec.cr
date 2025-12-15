require "../spec_helper"
require "../../src/matter/cluster/basic_information_cluster"

describe Matter::Cluster::BasicInformationCluster do
  describe "initialization" do
    it "creates basic information cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0028_u32)
      cluster.name.should eq("BasicInformation")
      cluster.data_version.should eq(0_u32)
    end

    it "initializes with default values" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      cluster.data_model_revision.should eq(1_u16)
      cluster.vendor_name.should eq("")
      cluster.vendor_id.should eq(0_u16)
      cluster.product_name.should eq("")
      cluster.product_id.should eq(0_u16)
      cluster.node_label.should eq("")
      cluster.location.should eq("XX")
      cluster.hardware_version.should eq(0_u16)
      cluster.hardware_version_string.should eq("1.0")
      cluster.software_version.should eq(0_u32)
      cluster.software_version_string.should eq("1.0.0")
    end
  end

  describe "required attributes" do
    it "has all required attributes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 15

      # Check for required attributes
      data_model_revision = attributes.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::ATTR_DATA_MODEL_REVISION }
      data_model_revision.should_not be_nil
      data_model_revision.not_nil!.name.should eq("DataModelRevision")
      data_model_revision.not_nil!.writable.should be_false

      vendor_name = attributes.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_NAME }
      vendor_name.should_not be_nil
      vendor_name.not_nil!.writable.should be_false

      vendor_id = attributes.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_ID }
      vendor_id.should_not be_nil
      vendor_id.not_nil!.writable.should be_false

      product_name = attributes.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::ATTR_PRODUCT_NAME }
      product_name.should_not be_nil
      product_name.not_nil!.writable.should be_false

      node_label = attributes.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::ATTR_NODE_LABEL }
      node_label.should_not be_nil
      node_label.not_nil!.writable.should be_true # User can set node label
    end
  end

  describe "TLV attribute encoding - read_attribute" do
    it "reads DATA_MODEL_REVISION with TLV encoding" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        data_model_revision: 17_u16
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_DATA_MODEL_REVISION)
      result.should be_a(Bytes)

      # Parse TLV
      parsed = TLV::Any.from_slice(result.as(Bytes))
      parsed.value.should eq(17)
    end

    it "reads VENDOR_NAME with TLV encoding" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        vendor_name: "Test Vendor"
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_NAME)
      result.should be_a(Bytes)

      parsed = TLV::Any.from_slice(result.as(Bytes))
      parsed.value.should eq("Test Vendor")
    end

    it "reads VENDOR_ID with TLV encoding" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        vendor_id: 0xFFF1_u16
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_ID)
      result.should be_a(Bytes)

      parsed = TLV::Any.from_slice(result.as(Bytes))
      parsed.value.should eq(0xFFF1)
    end

    it "reads SOFTWARE_VERSION with TLV encoding" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        software_version: 0x01020304_u32
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_SOFTWARE_VERSION)
      result.should be_a(Bytes)

      parsed = TLV::Any.from_slice(result.as(Bytes))
      parsed.value.should eq(0x01020304)
    end

    it "reads LOCAL_CONFIG_DISABLED with TLV encoding" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        local_config_disabled: true
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_LOCAL_CONFIG_DISABLED)
      result.should be_a(Bytes)

      parsed = TLV::Any.from_slice(result.as(Bytes))
      parsed.value.should eq(true)
    end

    it "reads CAPABILITY_MINIMA with TLV struct encoding" do
      capability = Matter::Cluster::BasicInformationCluster::CapabilityMinimaStruct.new(
        case_sessions_per_fabric: 5_u16,
        subscriptions_per_fabric: 10_u16
      )

      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        capability_minima: capability
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_CAPABILITY_MINIMA)
      result.should be_a(Bytes)

      # Parse TLV structure using TLV::Serializable
      parsed = Matter::Cluster::BasicInformationCluster::CapabilityMinimaStruct.from_slice(result.as(Bytes))
      parsed.case_sessions_per_fabric.should eq(5)
      parsed.subscriptions_per_fabric.should eq(10)
    end

    it "reads PRODUCT_APPEARANCE with TLV struct encoding" do
      appearance = Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Matte,
        primary_color: Matter::Cluster::BasicInformationCluster::Color::Blue
      )

      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        product_appearance: appearance
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_PRODUCT_APPEARANCE)
      result.should be_a(Bytes)

      # Parse TLV structure using TLV::Serializable
      parsed = Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.from_slice(result.as(Bytes))
      parsed.finish.should eq(Matter::Cluster::BasicInformationCluster::ProductFinish::Matte)
      parsed.primary_color.should eq(Matter::Cluster::BasicInformationCluster::Color::Blue)
    end

    it "reads PRODUCT_APPEARANCE with nullable primary_color omitted" do
      appearance = Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Polished,
        primary_color: nil
      )

      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        product_appearance: appearance
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_PRODUCT_APPEARANCE)
      result.should be_a(Bytes)

      # Parse TLV structure using TLV::Serializable
      parsed = Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.from_slice(result.as(Bytes))
      parsed.finish.should eq(Matter::Cluster::BasicInformationCluster::ProductFinish::Polished)
      parsed.primary_color.should be_nil
    end

    it "returns UnsupportedAttribute for missing PRODUCT_APPEARANCE" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        product_appearance: nil
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_PRODUCT_APPEARANCE)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "TLV attribute decoding - write_attribute" do
    it "writes NODE_LABEL with TLV decoding" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      # Encode new label as TLV
      tlv_value = TLV::Any.new("My Device", nil).to_slice

      initial_version = cluster.data_version
      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_NODE_LABEL, tlv_value)

      status.should be_a(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.node_label.should eq("My Device")
      cluster.data_version.should eq(initial_version + 1)
    end

    it "rejects NODE_LABEL exceeding max length (32 bytes)" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      long_label = "a" * 33
      tlv_value = TLV::Any.new(long_label, nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_NODE_LABEL, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
    end

    it "writes LOCATION with TLV decoding and validates format" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      tlv_value = TLV::Any.new("US", nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_LOCATION, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.location.should eq("US")
    end

    it "normalizes LOCATION to uppercase" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      tlv_value = TLV::Any.new("gb", nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_LOCATION, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.location.should eq("GB")
    end

    it "accepts region-agnostic location XX" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      tlv_value = TLV::Any.new("XX", nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_LOCATION, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.location.should eq("XX")
    end

    it "rejects LOCATION with invalid length" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      tlv_value = TLV::Any.new("USA", nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_LOCATION, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
    end

    it "rejects LOCATION with non-alpha characters" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      tlv_value = TLV::Any.new("U1", nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_LOCATION, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
    end

    it "writes LOCAL_CONFIG_DISABLED with TLV decoding" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        local_config_disabled: false
      )

      tlv_value = TLV::Any.new(true, nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_LOCAL_CONFIG_DISABLED, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.local_config_disabled.should eq(true)
    end

    it "rejects write to read-only VENDOR_NAME" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      tlv_value = TLV::Any.new("New Vendor", nil).to_slice

      status = cluster.write_attribute(Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_NAME, tlv_value)

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "event emission" do
    it "emits StartUp event with TLV-encoded software version" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        software_version: 0x01000000_u32
      )

      event_data = cluster.emit_start_up_event(0x01000000_u32)
      event_data.should be_a(Bytes)

      # Parse using TLV::Serializable
      parsed = Matter::Cluster::BasicInformationCluster::StartUpEvent.from_slice(event_data)
      parsed.software_version.should eq(0x01000000)
    end

    it "emits ShutDown event with empty TLV structure" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      event_data = cluster.emit_shut_down_event
      event_data.should be_a(Bytes)

      # ShutDown event is an empty structure - just verify it deserializes
      parsed = Matter::Cluster::BasicInformationCluster::ShutDownEvent.from_slice(event_data)
      parsed.should_not be_nil
    end

    it "emits Leave event with fabric index" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16)
      )

      event_data = cluster.emit_leave_event(1_u8)
      event_data.should be_a(Bytes)

      # Parse using TLV::Serializable
      parsed = Matter::Cluster::BasicInformationCluster::LeaveEvent.from_slice(event_data)
      parsed.fabric_index.should eq(1)
    end

    it "emits ReachableChanged event and updates reachable attribute" do
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        reachable: true
      )

      initial_version = cluster.data_version
      event_data = cluster.emit_reachable_changed_event(false)
      event_data.should be_a(Bytes)

      cluster.reachable.should eq(false)
      cluster.data_version.should eq(initial_version + 1)

      # Parse using TLV::Serializable
      parsed = Matter::Cluster::BasicInformationCluster::ReachableChangedEvent.from_slice(event_data)
      parsed.reachable_new_value.should eq(false)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute read" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "complete device configuration" do
    it "configures a complete device with all attributes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        vendor_name: "SmartHome Inc",
        vendor_id: 0xFFF1_u16,
        product_name: "WiFi Smart Bulb",
        product_id: 0x8001_u16,
        node_label: "Kitchen Light",
        hardware_version: 2_u16,
        hardware_version_string: "2.1",
        software_version: 0x01020304_u32,
        software_version_string: "1.2.3.4",
        manufacturing_date: "20231215",
        part_number: "BULB-001",
        product_url: "https://smarthome.example/bulb",
        serial_number: "SN987654321"
      )

      cluster.vendor_name.should eq("SmartHome Inc")
      cluster.vendor_id.should eq(0xFFF1_u16)
      cluster.product_name.should eq("WiFi Smart Bulb")
      cluster.product_id.should eq(0x8001_u16)
      cluster.node_label.should eq("Kitchen Light")
      cluster.hardware_version.should eq(2_u16)
      cluster.hardware_version_string.should eq("2.1")
      cluster.software_version.should eq(0x01020304_u32)
      cluster.software_version_string.should eq("1.2.3.4")
      cluster.manufacturing_date.should eq("20231215")
      cluster.part_number.should eq("BULB-001")
      cluster.product_url.should eq("https://smarthome.example/bulb")
      cluster.serial_number.should eq("SN987654321")
    end
  end
end
