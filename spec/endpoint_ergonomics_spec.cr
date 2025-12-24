require "./spec_helper"
require "../src/matter/endpoint"
require "../src/matter/device_type"
require "../src/matter/cluster/on_off_cluster"
require "../src/matter/cluster/level_control_cluster"
require "../src/matter/cluster/identify_cluster"

describe "Endpoint Ergonomics" do
  describe "simplified cluster access" do
    it "gets cluster by type instead of numeric ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)
      endpoint.add_cluster(on_off)

      # Old way: endpoint.get_cluster(0x0006_u32)
      # New way: endpoint.get_cluster(Matter::Cluster::OnOffCluster)
      cluster = endpoint.get_cluster(Matter::Cluster::OnOffCluster)
      cluster.should_not be_nil
      cluster.not_nil!.cluster_id.id.should eq(0x0006_u32)
      cluster.not_nil!.on_off?.should be_false
    end

    it "gets cluster with bang method that raises on missing" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      expect_raises(KeyError, /not found/) do
        endpoint.get_cluster!(Matter::Cluster::OnOffCluster)
      end
    end

    it "works with node-level cluster access" do
      node = Matter::MatterNode.new
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.dimmable_light)

      level_control = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 50_u8)
      endpoint.add_cluster(level_control)
      node.add_endpoint(endpoint)

      # Old way: node.get_endpoint(1_u16).not_nil!.get_cluster(0x0008_u32)
      # New way: node.get_cluster(1_u16, Matter::Cluster::LevelControlCluster)
      cluster = node.get_cluster(1_u16, Matter::Cluster::LevelControlCluster)
      cluster.should_not be_nil
      cluster.not_nil!.current_level.should eq(50_u8)
    end
  end

  describe "optional command fields parameter" do
    it "invokes commands without needing to pass empty Bytes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)
      endpoint.add_cluster(on_off)

      # Old way: endpoint.invoke_command(0x0006_u32, CMD_ON, Bytes.new(0))
      # New way: endpoint.invoke_command(0x0006_u32, CMD_ON)
      result = endpoint.invoke_command(
        Matter::Cluster::OnOffCluster::CLUSTER_ID,
        Matter::Cluster::OnOffCluster::CMD_ON
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      on_off.on_off?.should be_true
    end

    it "works with node-level command invocation" do
      node = Matter::MatterNode.new
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)
      endpoint.add_cluster(on_off)
      node.add_endpoint(endpoint)

      # Old way: node.invoke_command(1_u16, 0x0006_u32, CMD_TOGGLE, Bytes.new(0))
      # New way: node.invoke_command(1_u16, 0x0006_u32, CMD_TOGGLE)
      result = node.invoke_command(
        1_u16,
        Matter::Cluster::OnOffCluster::CLUSTER_ID,
        Matter::Cluster::OnOffCluster::CMD_TOGGLE
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      on_off.on_off?.should be_false
    end
  end

  describe "high-level device control patterns" do
    it "demonstrates idiomatic control flow" do
      # Build a complete dimmable light
      node = Matter::MatterNode.new
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.dimmable_light)

      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)
      level_control = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 0_u8)

      endpoint.add_cluster(on_off)
      endpoint.add_cluster(level_control)
      node.add_endpoint(endpoint)

      # Pattern 1: Direct cluster access for reading state (most ergonomic)
      light = node.get_cluster!(1_u16, Matter::Cluster::OnOffCluster)
      light.on_off?.should be_false

      dimmer = node.get_cluster!(1_u16, Matter::Cluster::LevelControlCluster)
      dimmer.current_level.should eq(0_u8)

      # Use commands to control (directly on cluster reference)
      light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON)
      light.on_off?.should be_true

      # Pattern 2: Command invocation (protocol-level)
      result = node.invoke_command(
        1_u16,
        Matter::Cluster::OnOffCluster::CLUSTER_ID,
        Matter::Cluster::OnOffCluster::CMD_OFF
      )
      result.as(Matter::InteractionModel::Status).success?.should be_true
      on_off.on_off?.should be_false

      # Pattern 3: Attribute read (protocol-level)
      result = node.read_attribute(
        1_u16,
        Matter::Cluster::LevelControlCluster::CLUSTER_ID,
        Matter::Cluster::LevelControlCluster::ATTR_CURRENT_LEVEL
      )
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(0_u8) # Still at initial value
    end

    it "demonstrates multi-endpoint device control" do
      # Build a 2-gang light switch
      node = Matter::MatterNode.new

      # Endpoint 1: First light
      endpoint1_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint1 = Matter::Endpoint.new(endpoint1_id, Matter::DeviceType.on_off_light)
      light1 = Matter::Cluster::OnOffCluster.new(endpoint1_id, on_off: false)
      endpoint1.add_cluster(light1)

      # Endpoint 2: Second light
      endpoint2_id = Matter::DataType::EndpointNumber.new(2_u16)
      endpoint2 = Matter::Endpoint.new(endpoint2_id, Matter::DeviceType.on_off_light)
      light2 = Matter::Cluster::OnOffCluster.new(endpoint2_id, on_off: false)
      endpoint2.add_cluster(light2)

      node.add_endpoint(endpoint1)
      node.add_endpoint(endpoint2)

      # Control each light independently using typed cluster access
      light1_ref = node.get_cluster!(1_u16, Matter::Cluster::OnOffCluster)
      light2_ref = node.get_cluster!(2_u16, Matter::Cluster::OnOffCluster)

      light1_ref.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON)
      light2_ref.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF)

      light1.on_off?.should be_true
      light2.on_off?.should be_false

      # Or control both at once
      [1_u16, 2_u16].each do |ep_id|
        node.invoke_command(
          ep_id,
          Matter::Cluster::OnOffCluster::CLUSTER_ID,
          Matter::Cluster::OnOffCluster::CMD_ON
        )
      end

      light1.on_off?.should be_true
      light2.on_off?.should be_true
    end
  end
end
