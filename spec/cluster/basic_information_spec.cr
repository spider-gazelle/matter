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

  describe "vendor information" do
    it "sets vendor name and ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        vendor_name: "Acme Corp",
        vendor_id: 0xFFF1_u16
      )

      cluster.vendor_name.should eq("Acme Corp")
      cluster.vendor_id.should eq(0xFFF1_u16)
    end

    it "reads VendorName attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        vendor_name: "Test Vendor"
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_NAME)
      result.should be_a(Bytes)
      # TODO: Properly decode TLV string when implemented
    end

    it "reads VendorID attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        vendor_id: 0x1234_u16
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_ID)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0x34, 0x12]) # Little-endian
    end
  end

  describe "product information" do
    it "sets product name and ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        product_name: "Smart Light",
        product_id: 0x8000_u16
      )

      cluster.product_name.should eq("Smart Light")
      cluster.product_id.should eq(0x8000_u16)
    end

    it "reads ProductName attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        product_name: "Test Product"
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_PRODUCT_NAME)
      result.should be_a(Bytes)
    end

    it "reads ProductID attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        product_id: 0xABCD_u16
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_PRODUCT_ID)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0xCD, 0xAB]) # Little-endian
    end
  end

  describe "version information" do
    it "sets hardware version" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        hardware_version: 2_u16,
        hardware_version_string: "2.0"
      )

      cluster.hardware_version.should eq(2_u16)
      cluster.hardware_version_string.should eq("2.0")
    end

    it "sets software version" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        software_version: 0x01020300_u32,
        software_version_string: "1.2.3"
      )

      cluster.software_version.should eq(0x01020300_u32)
      cluster.software_version_string.should eq("1.2.3")
    end

    it "reads HardwareVersion attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        hardware_version: 3_u16
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_HARDWARE_VERSION)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[3, 0]) # Little-endian
    end

    it "reads SoftwareVersion attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        software_version: 0x12345678_u32
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_SOFTWARE_VERSION)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0x78, 0x56, 0x34, 0x12]) # Little-endian
    end
  end

  describe "user-configurable attributes" do
    it "sets node label" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        node_label: "Living Room Light"
      )

      cluster.node_label.should eq("Living Room Light")
    end

    it "writes node label attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      # TODO: Properly encode TLV string when implemented
      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::ATTR_NODE_LABEL,
        Bytes.new(0)
      )

      status.success?.should be_true
      cluster.data_version.should eq(1_u32) # Version incremented
    end

    it "sets location" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        location: "US"
      )

      cluster.location.should eq("US")
    end

    it "writes location attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::ATTR_LOCATION,
        Bytes.new(0)
      )

      status.success?.should be_true
    end
  end

  describe "optional attributes" do
    it "sets manufacturing date" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        manufacturing_date: "20231215"
      )

      cluster.manufacturing_date.should eq("20231215")
    end

    it "sets part number" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        part_number: "ABC-123-XYZ"
      )

      cluster.part_number.should eq("ABC-123-XYZ")
    end

    it "sets product URL" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        product_url: "https://example.com/product"
      )

      cluster.product_url.should eq("https://example.com/product")
    end

    it "sets product label" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        product_label: "Premium Edition"
      )

      cluster.product_label.should eq("Premium Edition")
    end

    it "sets serial number" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        serial_number: "SN123456789"
      )

      cluster.serial_number.should eq("SN123456789")
    end

    it "sets unique ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        unique_id: "UUID-1234-5678"
      )

      cluster.unique_id.should eq("UUID-1234-5678")
    end
  end

  describe "ProductAppearance structure" do
    it "creates product appearance" do
      appearance = Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Matte,
        primary_color: Matter::Cluster::BasicInformationCluster::Color::Black
      )

      appearance.finish.should eq(Matter::Cluster::BasicInformationCluster::ProductFinish::Matte)
      appearance.primary_color.should eq(Matter::Cluster::BasicInformationCluster::Color::Black)
    end

    it "sets product appearance on cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      appearance = Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Satin,
        primary_color: Matter::Cluster::BasicInformationCluster::Color::White
      )

      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id,
        product_appearance: appearance
      )

      cluster.product_appearance.should_not be_nil
      cluster.product_appearance.not_nil!.finish.should eq(Matter::Cluster::BasicInformationCluster::ProductFinish::Satin)
      cluster.product_appearance.not_nil!.primary_color.should eq(Matter::Cluster::BasicInformationCluster::Color::White)
    end
  end

  describe "CapabilityMinima structure" do
    it "creates capability minima" do
      capability = Matter::Cluster::BasicInformationCluster::CapabilityMinimaStruct.new(
        case_sessions_per_fabric: 3_u16,
        subscriptions_per_fabric: 3_u16
      )

      capability.case_sessions_per_fabric.should eq(3_u16)
      capability.subscriptions_per_fabric.should eq(3_u16)
    end

    it "reads CapabilityMinima attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::ATTR_CAPABILITY_MINIMA)
      result.should be_a(Bytes)
      # TODO: Properly decode TLV structure when implemented
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

    it "returns error for writing read-only attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_NAME,
        Bytes[1, 2, 3]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "events" do
    it "has StartUp event" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      events = cluster.events
      events.should_not be_empty

      startup = events.find { |e| e.id.id == Matter::Cluster::BasicInformationCluster::EVENT_START_UP }
      startup.should_not be_nil
      startup.not_nil!.name.should eq("StartUp")
    end

    it "has ShutDown event" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      events = cluster.events
      shutdown = events.find { |e| e.id.id == Matter::Cluster::BasicInformationCluster::EVENT_SHUT_DOWN }
      shutdown.should_not be_nil
      shutdown.not_nil!.name.should eq("ShutDown")
    end

    it "has Leave event" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      events = cluster.events
      leave = events.find { |e| e.id.id == Matter::Cluster::BasicInformationCluster::EVENT_LEAVE }
      leave.should_not be_nil
      leave.not_nil!.name.should eq("Leave")
    end

    it "has ReachableChanged event" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint_id)

      events = cluster.events
      reachable = events.find { |e| e.id.id == Matter::Cluster::BasicInformationCluster::EVENT_REACHABLE_CHANGED }
      reachable.should_not be_nil
      reachable.not_nil!.name.should eq("ReachableChanged")
    end
  end

  describe "complete device configuration" do
    it "configures a complete device" do
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
