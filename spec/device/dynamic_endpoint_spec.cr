require "../spec_helper"
require "../../src/matter/device/base"
require "../../src/matter/cluster/on_off"
require "../../src/matter/cluster/bridged_device_basic_information"

# Test device for dynamic endpoint tests
class TestBridgeDevice < Matter::Device::Base
  def initialize
    super(Matter::Storage::Memory.new)
  end

  def device_name : String
    "Test Bridge"
  end

  def vendor_id : UInt16
    0xFFF1_u16
  end

  def product_id : UInt16
    0x8000_u16
  end

  def discriminator : UInt16
    3840_u16
  end

  def setup_pin : UInt32
    20202021_u32
  end

  def primary_device_type_id : UInt32
    Matter::DeviceType::ROOT_NODE
  end

  # Bridge has no static device endpoints
  protected def device_clusters : Array(Matter::Cluster::Base)
    [] of Matter::Cluster::Base
  end

  protected def endpoint_device_types : Hash(UInt16, UInt32)
    {} of UInt16 => UInt32
  end
end

describe "Dynamic Endpoint Management" do
  describe "#add_endpoint" do
    it "adds a new endpoint with clusters" do
      device = TestBridgeDevice.new

      endpoint_id = 1_u16
      endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)

      on_off = Matter::Cluster::OnOff.new(endpoint)
      bridged_info = Matter::Cluster::BridgedDeviceBasicInformation.new(
        endpoint,
        reachable: true,
        product_name: "Test Light"
      )

      result = device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off, bridged_info]
      )

      result.should be_true

      # Verify clusters are registered
      device.message_handler.clusters.has_key?({endpoint_id, Matter::Cluster::OnOff::CLUSTER_ID}).should be_true
      device.message_handler.clusters.has_key?({endpoint_id, Matter::Cluster::BridgedDeviceBasicInformation::CLUSTER_ID}).should be_true

      # Verify descriptor was auto-injected
      device.message_handler.clusters.has_key?({endpoint_id, Matter::Cluster::Descriptor::CLUSTER_ID}).should be_true

      # Verify descriptor has correct device type
      descriptor = device.message_handler.clusters[{endpoint_id, Matter::Cluster::Descriptor::CLUSTER_ID}]
        .as(Matter::Cluster::Descriptor)
      descriptor.device_type_list.size.should eq(1)
      descriptor.device_type_list[0].device_type.should eq(Matter::DeviceType::ON_OFF_LIGHT)

      # Verify descriptor has server list populated
      descriptor.server_list.should contain(Matter::Cluster::OnOff::CLUSTER_ID)
      descriptor.server_list.should contain(Matter::Cluster::BridgedDeviceBasicInformation::CLUSTER_ID)
      descriptor.server_list.should contain(Matter::Cluster::Descriptor::CLUSTER_ID)
    end

    it "adds endpoint to root node parts list" do
      device = TestBridgeDevice.new

      endpoint_id = 1_u16
      endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
      on_off = Matter::Cluster::OnOff.new(endpoint)

      device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off]
      )

      # Verify root node's parts list contains the new endpoint
      root_descriptor = device.message_handler.clusters[{0_u16, Matter::Cluster::Descriptor::CLUSTER_ID}]
        .as(Matter::Cluster::Descriptor)
      root_descriptor.parts_list.should contain(endpoint_id)
    end

    it "returns false for duplicate endpoint" do
      device = TestBridgeDevice.new

      endpoint_id = 1_u16
      endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
      on_off1 = Matter::Cluster::OnOff.new(endpoint)

      # First add should succeed
      result1 = device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off1]
      )
      result1.should be_true

      # Second add should fail
      on_off2 = Matter::Cluster::OnOff.new(endpoint)
      result2 = device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off2]
      )
      result2.should be_false
    end

    it "returns false for endpoint 0" do
      device = TestBridgeDevice.new

      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      on_off = Matter::Cluster::OnOff.new(endpoint)

      result = device.add_endpoint(
        endpoint_id: 0_u16,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off]
      )

      result.should be_false
    end

    it "raises for mismatched endpoint ID" do
      device = TestBridgeDevice.new

      endpoint = Matter::DataType::EndpointNumber.new(2_u16)
      on_off = Matter::Cluster::OnOff.new(endpoint)

      expect_raises(ArgumentError, /endpoint_id/) do
        device.add_endpoint(
          endpoint_id: 1_u16, # Mismatched!
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end
    end
  end

  describe "#remove_endpoint" do
    it "removes an endpoint and its clusters" do
      device = TestBridgeDevice.new

      endpoint_id = 1_u16
      endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
      on_off = Matter::Cluster::OnOff.new(endpoint)
      bridged_info = Matter::Cluster::BridgedDeviceBasicInformation.new(endpoint)

      device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off, bridged_info]
      )

      # Verify clusters exist
      device.message_handler.clusters.has_key?({endpoint_id, Matter::Cluster::OnOff::CLUSTER_ID}).should be_true

      # Remove endpoint
      result = device.remove_endpoint(endpoint_id)
      result.should be_true

      # Verify clusters are gone
      device.message_handler.clusters.has_key?({endpoint_id, Matter::Cluster::OnOff::CLUSTER_ID}).should be_false
      device.message_handler.clusters.has_key?({endpoint_id, Matter::Cluster::BridgedDeviceBasicInformation::CLUSTER_ID}).should be_false
      device.message_handler.clusters.has_key?({endpoint_id, Matter::Cluster::Descriptor::CLUSTER_ID}).should be_false
    end

    it "removes endpoint from root node parts list" do
      device = TestBridgeDevice.new

      endpoint_id = 1_u16
      endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
      on_off = Matter::Cluster::OnOff.new(endpoint)

      device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off]
      )

      # Verify in parts list
      root_descriptor = device.message_handler.clusters[{0_u16, Matter::Cluster::Descriptor::CLUSTER_ID}]
        .as(Matter::Cluster::Descriptor)
      root_descriptor.parts_list.should contain(endpoint_id)

      # Remove endpoint
      device.remove_endpoint(endpoint_id)

      # Verify removed from parts list
      root_descriptor.parts_list.should_not contain(endpoint_id)
    end

    it "returns false for non-existent endpoint" do
      device = TestBridgeDevice.new
      result = device.remove_endpoint(99_u16)
      result.should be_false
    end

    it "returns false for endpoint 0" do
      device = TestBridgeDevice.new
      result = device.remove_endpoint(0_u16)
      result.should be_false
    end
  end

  describe "#endpoint_ids" do
    it "returns all non-root endpoint IDs" do
      device = TestBridgeDevice.new

      # Initially empty (only root node)
      device.endpoint_ids.should be_empty

      # Add some endpoints
      (1..3).each do |i|
        endpoint_id = i.to_u16
        endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
        on_off = Matter::Cluster::OnOff.new(endpoint)
        device.add_endpoint(
          endpoint_id: endpoint_id,
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end

      ids = device.endpoint_ids
      ids.size.should eq(3)
      ids.should contain(1_u16)
      ids.should contain(2_u16)
      ids.should contain(3_u16)
      ids.should_not contain(0_u16)
    end

    it "returns sorted IDs" do
      device = TestBridgeDevice.new

      [5_u16, 2_u16, 8_u16, 1_u16].each do |endpoint_id|
        endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
        on_off = Matter::Cluster::OnOff.new(endpoint)
        device.add_endpoint(
          endpoint_id: endpoint_id,
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end

      device.endpoint_ids.should eq([1_u16, 2_u16, 5_u16, 8_u16])
    end
  end

  describe "#next_endpoint_id" do
    it "returns 1 when no endpoints exist" do
      device = TestBridgeDevice.new
      device.next_endpoint_id.should eq(1_u16)
    end

    it "returns next available ID" do
      device = TestBridgeDevice.new

      # Add endpoints 1, 2, 3
      (1..3).each do |i|
        endpoint_id = i.to_u16
        endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
        on_off = Matter::Cluster::OnOff.new(endpoint)
        device.add_endpoint(
          endpoint_id: endpoint_id,
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end

      device.next_endpoint_id.should eq(4_u16)
    end

    it "fills gaps in endpoint IDs" do
      device = TestBridgeDevice.new

      # Add endpoints 1, 3 (skip 2)
      [1_u16, 3_u16].each do |endpoint_id|
        endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
        on_off = Matter::Cluster::OnOff.new(endpoint)
        device.add_endpoint(
          endpoint_id: endpoint_id,
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end

      device.next_endpoint_id.should eq(2_u16)
    end
  end

  describe "multiple endpoint operations" do
    it "supports adding and removing multiple endpoints" do
      device = TestBridgeDevice.new

      # Add 5 endpoints
      5.times do |i|
        endpoint_id = (i + 1).to_u16
        endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
        on_off = Matter::Cluster::OnOff.new(endpoint)
        device.add_endpoint(
          endpoint_id: endpoint_id,
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end

      device.endpoint_ids.size.should eq(5)

      # Remove some
      device.remove_endpoint(2_u16)
      device.remove_endpoint(4_u16)

      ids = device.endpoint_ids
      ids.size.should eq(3)
      ids.should eq([1_u16, 3_u16, 5_u16])

      # Add more (should fill gaps)
      device.next_endpoint_id.should eq(2_u16)

      endpoint = Matter::DataType::EndpointNumber.new(2_u16)
      on_off = Matter::Cluster::OnOff.new(endpoint)
      device.add_endpoint(
        endpoint_id: 2_u16,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off]
      )

      device.endpoint_ids.should eq([1_u16, 2_u16, 3_u16, 5_u16])
    end
  end

  describe "subscription notifications" do
    # These tests verify the integration between dynamic endpoints and
    # subscription notifications. The actual notification delivery is tested
    # elsewhere; here we verify the flow doesn't error and state is consistent.

    it "triggers notification flow when endpoint is added" do
      device = TestBridgeDevice.new

      endpoint_id = 1_u16
      endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
      on_off = Matter::Cluster::OnOff.new(endpoint)

      # This should trigger notify_subscriptions for PartsList
      # (verified by debug log: "notify_subscriptions: endpoint=0, cluster=0x1d, attr=0x3")
      result = device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off]
      )

      result.should be_true

      # Verify PartsList was updated (prerequisite for notification)
      root_descriptor = device.message_handler.clusters[{0_u16, Matter::Cluster::Descriptor::CLUSTER_ID}]
        .as(Matter::Cluster::Descriptor)
      root_descriptor.parts_list.should contain(endpoint_id)
    end

    it "triggers notification flow when endpoint is removed" do
      device = TestBridgeDevice.new

      endpoint_id = 1_u16
      endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
      on_off = Matter::Cluster::OnOff.new(endpoint)

      device.add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: [on_off]
      )

      # This should trigger notify_subscriptions for PartsList
      result = device.remove_endpoint(endpoint_id)
      result.should be_true

      # Verify PartsList was updated (prerequisite for notification)
      root_descriptor = device.message_handler.clusters[{0_u16, Matter::Cluster::Descriptor::CLUSTER_ID}]
        .as(Matter::Cluster::Descriptor)
      root_descriptor.parts_list.should_not contain(endpoint_id)
    end

    it "can read PartsList attribute after endpoint changes" do
      device = TestBridgeDevice.new

      # Add multiple endpoints
      [1_u16, 2_u16, 3_u16].each do |endpoint_id|
        endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
        on_off = Matter::Cluster::OnOff.new(endpoint)
        device.add_endpoint(
          endpoint_id: endpoint_id,
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end

      # Read the PartsList attribute via the cluster interface
      # (this is what a subscriber would receive in a ReportData)
      root_descriptor = device.message_handler.clusters[{0_u16, Matter::Cluster::Descriptor::CLUSTER_ID}]
        .as(Matter::Cluster::Descriptor)

      # Parse the TLV response - endpoint IDs may be encoded as UInt8 or UInt16
      parts = read_tlv(root_descriptor, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list.map do |part|
        case v = part.value
        when UInt8  then v.to_u16
        when UInt16 then v
        else             raise "Unexpected type: #{v.class}"
        end
      end

      parts.should contain(1_u16)
      parts.should contain(2_u16)
      parts.should contain(3_u16)
    end

    it "correctly updates PartsList TLV when endpoints change" do
      device = TestBridgeDevice.new

      # Add endpoints
      [1_u16, 2_u16].each do |endpoint_id|
        endpoint = Matter::DataType::EndpointNumber.new(endpoint_id)
        on_off = Matter::Cluster::OnOff.new(endpoint)
        device.add_endpoint(
          endpoint_id: endpoint_id,
          device_type: Matter::DeviceType::ON_OFF_LIGHT,
          clusters: [on_off]
        )
      end

      # Remove one endpoint
      device.remove_endpoint(1_u16)

      # Read PartsList - should only have endpoint 2
      root_descriptor = device.message_handler.clusters[{0_u16, Matter::Cluster::Descriptor::CLUSTER_ID}]
        .as(Matter::Cluster::Descriptor)

      parts = read_tlv(root_descriptor, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list.map do |part|
        case v = part.value
        when UInt8  then v.to_u16
        when UInt16 then v
        else             raise "Unexpected type: #{v.class}"
        end
      end

      parts.should_not contain(1_u16)
      parts.should contain(2_u16)
    end
  end
end
