require "./spec_helper"
require "../src/matter/endpoint"
require "../src/matter/device_type"
require "../src/matter/cluster/on_off"
require "../src/matter/cluster/level_control"
require "../src/matter/cluster/identify"

describe "Endpoint Ergonomics" do
  describe "simplified cluster access" do
    it "gets cluster by type instead of numeric ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      on_off = Matter::Cluster::OnOff.new(endpoint_id, on_off: false)
      endpoint.add_cluster(on_off)

      cluster = endpoint.get_cluster(Matter::Cluster::OnOff)
      cluster.should_not be_nil
      cluster.as(Matter::Cluster::OnOff).cluster_id.id.should eq(0x0006_u32)
      cluster.as(Matter::Cluster::OnOff).on_off?.should be_false
    end

    it "gets cluster with bang method that raises on missing" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      expect_raises(KeyError, /not found/) do
        endpoint.get_cluster!(Matter::Cluster::OnOff)
      end
    end

    it "works with node-level cluster access" do
      node = Matter::MatterNode.new
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.dimmable_light)

      level_control = Matter::Cluster::LevelControl.new(endpoint_id, current_level: 50_u8)
      endpoint.add_cluster(level_control)
      node.add_endpoint(endpoint)

      cluster = node.get_cluster(1_u16, Matter::Cluster::LevelControl)
      cluster.should_not be_nil
      cluster.as(Matter::Cluster::LevelControl).current_level.should eq(50_u8)
    end
  end

  describe "optional command fields parameter" do
    it "invokes commands without fields" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      on_off = Matter::Cluster::OnOff.new(endpoint_id, on_off: false)
      endpoint.add_cluster(on_off)

      result = endpoint.invoke_command(
        Matter::Cluster::OnOff::CLUSTER_ID,
        Matter::Cluster::OnOff::CMD_ON
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      on_off.on_off?.should be_true
    end

    it "works with node-level command invocation" do
      node = Matter::MatterNode.new
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)

      on_off = Matter::Cluster::OnOff.new(endpoint_id, on_off: true)
      endpoint.add_cluster(on_off)
      node.add_endpoint(endpoint)

      result = node.invoke_command(
        1_u16,
        Matter::Cluster::OnOff::CLUSTER_ID,
        Matter::Cluster::OnOff::CMD_TOGGLE
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

      on_off = Matter::Cluster::OnOff.new(endpoint_id, on_off: false)
      level_control = Matter::Cluster::LevelControl.new(endpoint_id, current_level: 0_u8)

      endpoint.add_cluster(on_off)
      endpoint.add_cluster(level_control)
      node.add_endpoint(endpoint)

      # Pattern 1: Direct cluster access for reading state (most ergonomic)
      light = node.get_cluster!(1_u16, Matter::Cluster::OnOff)
      light.on_off?.should be_false

      dimmer = node.get_cluster!(1_u16, Matter::Cluster::LevelControl)
      dimmer.current_level.should eq(0_u8)

      # Use commands to control (directly on cluster reference)
      invoke(light, Matter::Cluster::OnOff::CMD_ON)
      light.on_off?.should be_true

      # Pattern 2: Command invocation (protocol-level)
      result = node.invoke_command(
        1_u16,
        Matter::Cluster::OnOff::CLUSTER_ID,
        Matter::Cluster::OnOff::CMD_OFF
      )
      result.as(Matter::InteractionModel::Status).success?.should be_true
      on_off.on_off?.should be_false

      # Pattern 3: Attribute read (protocol-level)
      result = node.read_attribute(
        1_u16,
        Matter::Cluster::LevelControl::CLUSTER_ID,
        Matter::Cluster::LevelControl::ATTR_CURRENT_LEVEL
      )
      result.should be_a(TLV::Any)
      result.as(TLV::Any).value.should eq(0_u8) # Still at initial value
    end

    it "demonstrates multi-endpoint device control" do
      # Build a 2-gang light switch
      node = Matter::MatterNode.new

      # Endpoint 1: First light
      endpoint1_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint1 = Matter::Endpoint.new(endpoint1_id, Matter::DeviceType.on_off_light)
      light1 = Matter::Cluster::OnOff.new(endpoint1_id, on_off: false)
      endpoint1.add_cluster(light1)

      # Endpoint 2: Second light
      endpoint2_id = Matter::DataType::EndpointNumber.new(2_u16)
      endpoint2 = Matter::Endpoint.new(endpoint2_id, Matter::DeviceType.on_off_light)
      light2 = Matter::Cluster::OnOff.new(endpoint2_id, on_off: false)
      endpoint2.add_cluster(light2)

      node.add_endpoint(endpoint1)
      node.add_endpoint(endpoint2)

      # Control each light independently using typed cluster access
      light1_ref = node.get_cluster!(1_u16, Matter::Cluster::OnOff)
      light2_ref = node.get_cluster!(2_u16, Matter::Cluster::OnOff)

      invoke(light1_ref, Matter::Cluster::OnOff::CMD_ON)
      invoke(light2_ref, Matter::Cluster::OnOff::CMD_OFF)

      light1.on_off?.should be_true
      light2.on_off?.should be_false

      # Or control both at once
      [1_u16, 2_u16].each do |ep_id|
        node.invoke_command(
          ep_id,
          Matter::Cluster::OnOff::CLUSTER_ID,
          Matter::Cluster::OnOff::CMD_ON
        )
      end

      light1.on_off?.should be_true
      light2.on_off?.should be_true
    end
  end
end
