require "../spec_helper"
require "../../src/matter/cluster/bridged_device_basic_information"

describe Matter::Cluster::BridgedDeviceBasicInformation do
  describe "#initialize" do
    it "creates cluster with default values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)

      cluster.reachable?.should be_true
      cluster.vendor_name.should be_nil
      cluster.product_name.should be_nil
      cluster.unique_id.should be_nil
    end

    it "creates cluster with custom values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(
        endpoint,
        reachable: true,
        vendor_name: "Test Vendor",
        product_name: "Test Product",
        node_label: "Test Label",
        unique_id: "unique-123",
        hardware_version: 2_u16,
        software_version: 100_u32
      )

      cluster.reachable?.should be_true
      cluster.vendor_name.should eq("Test Vendor")
      cluster.product_name.should eq("Test Product")
      cluster.node_label.should eq("Test Label")
      cluster.unique_id.should eq("unique-123")
      cluster.hardware_version.should eq(2_u16)
      cluster.software_version.should eq(100_u32)
    end
  end

  describe "#read_attribute" do
    it "reads Reachable attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, reachable: true)

      read(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_REACHABLE).should be_true
    end

    it "reads NodeLabel attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, node_label: "My Device")

      read(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_NODE_LABEL).should eq("My Device")
    end

    it "reads VendorName when present" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, vendor_name: "Acme Corp")

      read(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_VENDOR_NAME).should eq("Acme Corp")
    end

    it "returns UnsupportedAttribute for VendorName when not present" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)

      read_status(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_VENDOR_NAME).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end

    it "reads UniqueID when present" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, unique_id: "abc-123")

      read(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_UNIQUE_ID).should eq("abc-123")
    end
  end

  describe "#write_attribute" do
    it "allows writing NodeLabel" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, node_label: "Original")

      new_label = "New Label"
      status = write(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_NODE_LABEL, new_label)

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.node_label.should eq("New Label")
    end

    it "rejects NodeLabel over 32 bytes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)

      long_label = ("A" * 33)
      status = write(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_NODE_LABEL, long_label)

      status.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
    end

    it "rejects writing to read-only attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, reachable: true)

      value = Bytes[0]
      status = write(cluster, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_REACHABLE, value)

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "#reachable=" do
    it "updates reachable state" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, reachable: true)

      cluster.reachable?.should be_true

      cluster.reachable = (false)
      cluster.reachable?.should be_false

      cluster.reachable = (true)
      cluster.reachable?.should be_true
    end

    it "calls reachability callback" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, reachable: true)

      callback_called = false
      callback_value = true

      cluster.on_reachable_changed do |new_state|
        callback_called = true
        callback_value = new_state
      end

      cluster.reachable = (false)

      callback_called.should be_true
      callback_value.should be_false
    end

    it "does not call callback when state unchanged" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, reachable: true)

      callback_called = false
      cluster.on_reachable_changed do |_new_state|
        callback_called = true
      end

      cluster.reachable = (true) # Same state
      callback_called.should be_false
    end
  end

  describe "#emit_reachable_changed_event" do
    it "generates valid TLV event data" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)

      event_data = cluster.emit_reachable_changed_event(false)
      event_data.should be_a(Bytes)
      event_data.size.should be > 0

      # Verify it's valid TLV
      decoded = Matter::Cluster::BridgedDeviceBasicInformation::ReachableChangedEvent.from_slice(event_data)
      decoded.reachable_new_value?.should be_false
    end
  end

  describe "persistence" do
    it "saves and restores state" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster1 = Matter::Cluster::BridgedDeviceBasicInformation.new(
        endpoint,
        reachable: true,
        node_label: "Saved Label"
      )

      # Modify state
      new_label = "Modified Label"
      write(cluster1, Matter::Cluster::BridgedDeviceBasicInformation::ATTR_NODE_LABEL, new_label)
      cluster1.reachable = false

      # Save state
      document = cluster1.save_state.as(Matter::Storage::Document)
      document["node_label"].should eq("Modified Label")
      document["reachable"].should be_false

      # Create new cluster and restore
      cluster2 = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)
      cluster2.restore_state(document)

      cluster2.node_label.should eq("Modified Label")
      cluster2.reachable?.should be_false
    end
  end

  describe "#attributes" do
    it "includes required Reachable attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)

      attrs = cluster.attributes
      reachable_attr = attrs.find { |attr| attr.id.id == Matter::Cluster::BridgedDeviceBasicInformation::ATTR_REACHABLE }
      reachable_attr.should_not be_nil
    end

    it "includes optional attributes only when set" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      # Without optional attributes
      cluster1 = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)
      attrs1 = cluster1.attributes
      vendor_attr1 = attrs1.find { |attr| attr.id.id == Matter::Cluster::BridgedDeviceBasicInformation::ATTR_VENDOR_NAME }
      vendor_attr1.should be_nil

      # With optional attributes
      cluster2 = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint, vendor_name: "Test")
      attrs2 = cluster2.attributes
      vendor_attr2 = attrs2.find { |attr| attr.id.id == Matter::Cluster::BridgedDeviceBasicInformation::ATTR_VENDOR_NAME }
      vendor_attr2.should_not be_nil
    end
  end

  describe "#name" do
    it "returns cluster name" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)
      cluster.name.should eq("BridgedDeviceBasicInformation")
    end
  end

  describe "cluster ID" do
    it "has correct cluster ID" do
      Matter::Cluster::BridgedDeviceBasicInformation::CLUSTER_ID.should eq(0x0039_u32)
    end
  end
end
