require "./spec_helper"
require "../src/matter/cluster/basic_information_cluster"

describe Matter::Cluster::BasicInformationCluster do
  describe "initialization" do
    it "creates cluster with default values" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      cluster.name.should eq("BasicInformation")
      cluster.cluster_id.id.should eq(0x0028_u32)
      cluster.data_model_revision.should eq(1_u16)
      cluster.vendor_name.should eq("Test Vendor")
      cluster.product_name.should eq("Test Product")
      cluster.location.should eq("XX")
      cluster.reachable.should be_true
    end

    it "creates cluster with custom values" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        vendor_name: "Acme Corp",
        product_name: "Smart Light",
        vendor_id: 0x1234_u16,
        product_id: 0x5678_u16,
        hardware_version: 2_u16,
        software_version: 100_u32
      )

      cluster.vendor_name.should eq("Acme Corp")
      cluster.product_name.should eq("Smart Light")
      cluster.vendor_id.id.should eq(0x1234_u16)
      cluster.product_id.should eq(0x5678_u16)
      cluster.hardware_version.should eq(2_u16)
      cluster.software_version.should eq(100_u32)
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      attrs = cluster.attributes
      attrs.size.should eq(15)

      # Check for key attributes
      data_model = attrs.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::DATA_MODEL_REVISION }
      data_model.should_not be_nil
      data_model.not_nil!.name.should eq("DataModelRevision")
      data_model.not_nil!.writable.should be_false

      vendor_name = attrs.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::VENDOR_NAME }
      vendor_name.should_not be_nil
      vendor_name.not_nil!.type.should eq(:string)

      node_label = attrs.find { |a| a.id.id == Matter::Cluster::BasicInformationCluster::NODE_LABEL }
      node_label.should_not be_nil
      node_label.not_nil!.writable.should be_true
    end

    it "reads VendorName attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        vendor_name: "Test Corp"
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::VENDOR_NAME)
      result.should be_a(Bytes)
      String.new(result.as(Bytes)).should eq("Test Corp")
    end

    it "reads VendorID attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        vendor_id: 0xABCD_u16
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::VENDOR_ID)
      result.should be_a(Bytes)
      # Vendor ID is encoded as little-endian UInt16
      result.as(Bytes).should eq(Bytes[0xCD, 0xAB])
    end

    it "reads ProductName attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        product_name: "Smart Device"
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::PRODUCT_NAME)
      result.should be_a(Bytes)
      String.new(result.as(Bytes)).should eq("Smart Device")
    end

    it "reads SoftwareVersion attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        software_version: 12345_u32
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::SOFTWARE_VERSION)
      result.should be_a(Bytes)
      result.as(Bytes).size.should eq(4) # UInt32
    end

    it "reads HardwareVersion attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        hardware_version: 5_u16
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::HARDWARE_VERSION)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[5, 0])
    end

    it "reads Reachable attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        reachable: true
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::REACHABLE)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[1])
    end

    it "returns NotFound for SerialNumber when not set" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::SERIAL_NUMBER)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::NotFound
      )
    end

    it "reads SerialNumber when set" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(
        endpoint,
        serial_number: "SN123456"
      )

      result = cluster.read_attribute(Matter::Cluster::BasicInformationCluster::SERIAL_NUMBER)
      result.should be_a(Bytes)
      String.new(result.as(Bytes)).should eq("SN123456")
    end

    it "writes NodeLabel attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      initial_version = cluster.data_version

      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::NODE_LABEL,
        "My Device".to_slice
      )

      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.node_label.should eq("My Device")
      cluster.data_version.should eq(initial_version + 1)
    end

    it "writes Location attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::LOCATION,
        "US".to_slice
      )

      status.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.location.should eq("US")
    end

    it "normalizes Location to uppercase" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::LOCATION,
        "gb".to_slice
      )

      cluster.location.should eq("GB")
    end

    it "rejects invalid Location length" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      # Too long
      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::LOCATION,
        "USA".to_slice
      )
      status.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::ConstraintError
      )

      # Too short
      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::LOCATION,
        "U".to_slice
      )
      status.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::ConstraintError
      )
    end

    it "rejects writing read-only attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      status = cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::VENDOR_NAME,
        "Hacker".to_slice
      )

      status.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedWrite
      )
    end
  end

  describe "data versioning" do
    it "increments version on attribute changes" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::BasicInformationCluster.new(endpoint)

      initial_version = cluster.data_version

      cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::NODE_LABEL,
        "Device 1".to_slice
      )

      cluster.data_version.should eq(initial_version + 1)

      cluster.write_attribute(
        Matter::Cluster::BasicInformationCluster::LOCATION,
        "FR".to_slice
      )

      cluster.data_version.should eq(initial_version + 2)
    end
  end
end
