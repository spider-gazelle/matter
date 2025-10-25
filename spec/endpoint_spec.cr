require "./spec_helper"
require "../src/matter/device_type"
require "../src/matter/endpoint"
require "../src/matter/cluster/descriptor_cluster"
require "../src/matter/cluster/on_off_cluster"
require "../src/matter/cluster/level_control_cluster"
require "../src/matter/cluster/identify_cluster"
require "../src/matter/cluster/groups_cluster"
require "../src/matter/cluster/scenes_cluster"

describe Matter::DeviceType do
  describe "device type definitions" do
    it "creates root node device type" do
      dt = Matter::DeviceType.root_node

      dt.device_type_id.id.should eq(0x0016_u32)
      dt.name.should eq("Root Node")
      dt.revision.should eq(1_u16)
      dt.required_server_clusters.should_not be_empty
      dt.requires_cluster?(0x001D_u32).should be_true # Descriptor
      dt.requires_cluster?(0x0028_u32).should be_true # Basic Information
    end

    it "creates on/off light device type" do
      dt = Matter::DeviceType.on_off_light

      dt.device_type_id.id.should eq(0x0100_u32)
      dt.name.should eq("On/Off Light")
      dt.revision.should eq(2_u16)
      dt.requires_cluster?(0x001D_u32).should be_true          # Descriptor
      dt.requires_cluster?(0x0003_u32).should be_true          # Identify
      dt.requires_cluster?(0x0004_u32).should be_true          # Groups
      dt.requires_cluster?(0x0005_u32).should be_true          # Scenes
      dt.requires_cluster?(0x0006_u32).should be_true          # On/Off
      dt.supports_optional_cluster?(0x0008_u32).should be_true # Level Control
    end

    it "creates dimmable light device type" do
      dt = Matter::DeviceType.dimmable_light

      dt.device_type_id.id.should eq(0x0101_u32)
      dt.name.should eq("Dimmable Light")
      dt.requires_cluster?(0x0006_u32).should be_true # On/Off
      dt.requires_cluster?(0x0008_u32).should be_true # Level Control
    end

    it "creates on/off plug-in unit device type" do
      dt = Matter::DeviceType.on_off_plug_in_unit

      dt.device_type_id.id.should eq(0x010A_u32)
      dt.name.should eq("On/Off Plug-in Unit")
      dt.requires_cluster?(0x0006_u32).should be_true # On/Off
    end

    it "creates switch device types" do
      dt = Matter::DeviceType.on_off_light_switch
      dt.device_type_id.id.should eq(0x0103_u32)
      dt.name.should eq("On/Off Light Switch")

      dt2 = Matter::DeviceType.dimmer_switch
      dt2.device_type_id.id.should eq(0x0104_u32)
      dt2.name.should eq("Dimmer Switch")
    end

    it "creates sensor device types" do
      dt = Matter::DeviceType.contact_sensor
      dt.device_type_id.id.should eq(0x0015_u32)
      dt.name.should eq("Contact Sensor")

      dt2 = Matter::DeviceType.temperature_sensor
      dt2.device_type_id.id.should eq(0x0302_u32)
      dt2.name.should eq("Temperature Sensor")
    end

    it "checks cluster requirements" do
      dt = Matter::DeviceType.on_off_light

      dt.requires_cluster?(0x0006_u32).should be_true
      dt.requires_cluster?(0x9999_u32).should be_false

      dt.supports_optional_cluster?(0x0008_u32).should be_true
      dt.supports_optional_cluster?(0x9999_u32).should be_false

      dt.allows_cluster?(0x0006_u32).should be_true  # Required
      dt.allows_cluster?(0x0008_u32).should be_true  # Optional
      dt.allows_cluster?(0x9999_u32).should be_false # Neither
    end
  end

  describe "custom device types" do
    it "creates custom device type" do
      dt = Matter::DeviceType.new(
        Matter::DataType::DeviceTypeId.new(0x1234_u32),
        "Custom Device",
        1_u16,
        required_server_clusters: [0x0006_u32],
        optional_server_clusters: [0x0008_u32]
      )

      dt.device_type_id.id.should eq(0x1234_u32)
      dt.name.should eq("Custom Device")
      dt.requires_cluster?(0x0006_u32).should be_true
      dt.supports_optional_cluster?(0x0008_u32).should be_true
    end
  end
end

describe Matter::Endpoint do
  describe "initialization" do
    it "creates endpoint with device type" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light

      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      endpoint.endpoint_id.number.should eq(1_u16)
      endpoint.primary_device_type.should eq(device_type)
      endpoint.cluster_count.should eq(0)
    end

    it "creates endpoint with multiple device types" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_types = [Matter::DeviceType.on_off_light, Matter::DeviceType.temperature_sensor]

      endpoint = Matter::Endpoint.new(endpoint_id, device_types)

      endpoint.device_types.size.should eq(2)
    end
  end

  describe "cluster management" do
    it "adds cluster to endpoint" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(0x0100_u32, 2_u16)
      descriptor.server_list << 0x0006_u32

      endpoint.add_cluster(descriptor)

      endpoint.cluster_count.should eq(1)
      endpoint.has_cluster?(0x001D_u32).should be_true
    end

    it "rejects cluster with mismatched endpoint ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      # Create cluster for different endpoint
      wrong_endpoint_id = Matter::DataType::EndpointNumber.new(2_u16)
      cluster = Matter::Cluster::OnOffCluster.new(wrong_endpoint_id)

      expect_raises(ArgumentError, /does not match/) do
        endpoint.add_cluster(cluster)
      end
    end

    it "retrieves cluster by ID" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id)
      endpoint.add_cluster(on_off)

      retrieved = endpoint.get_cluster(0x0006_u32)
      retrieved.should_not be_nil
      retrieved.not_nil!.cluster_id.id.should eq(0x0006_u32)
    end

    it "returns nil for missing cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      endpoint.get_cluster(0x9999_u32).should be_nil
    end

    it "raises for missing cluster with bang method" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      expect_raises(KeyError, /not found/) do
        endpoint.get_cluster!(0x9999_u32)
      end
    end

    it "lists cluster IDs" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      endpoint.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::IdentifyCluster.new(endpoint_id))

      ids = endpoint.cluster_ids
      ids.size.should eq(2)
      ids.should contain(0x0006_u32)
      ids.should contain(0x0003_u32)
    end
  end

  describe "validation" do
    it "validates complete on/off light endpoint" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      # Add all required clusters
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(0x0100_u32, 2_u16)
      descriptor.server_list << 0x0003_u32
      descriptor.server_list << 0x0004_u32
      descriptor.server_list << 0x0005_u32
      descriptor.server_list << 0x0006_u32
      endpoint.add_cluster(descriptor)
      endpoint.add_cluster(Matter::Cluster::IdentifyCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::GroupsCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::ScenesCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint_id))

      endpoint.valid?.should be_true
      endpoint.validate.should be_empty
    end

    it "validates incomplete endpoint" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      # Only add some clusters
      endpoint.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint_id))

      endpoint.valid?.should be_false
      errors = endpoint.validate
      errors.should_not be_empty
      # Should be missing Descriptor, Identify, Groups, Scenes
      errors.size.should be >= 3
      errors.any? { |e| e.includes?("0x001D") || e.includes?("Descriptor") }.should be_true
      errors.any? { |e| e.includes?("0x0003") || e.includes?("Identify") }.should be_true
    end

    it "validates dimmable light endpoint" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.dimmable_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      # Add all required clusters
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(0x0101_u32, 2_u16)
      descriptor.server_list << 0x0003_u32
      descriptor.server_list << 0x0004_u32
      descriptor.server_list << 0x0005_u32
      descriptor.server_list << 0x0006_u32
      descriptor.server_list << 0x0008_u32
      endpoint.add_cluster(descriptor)
      endpoint.add_cluster(Matter::Cluster::IdentifyCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::GroupsCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::ScenesCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint_id))
      endpoint.add_cluster(Matter::Cluster::LevelControlCluster.new(endpoint_id))

      endpoint.valid?.should be_true
    end
  end

  describe "cluster operations" do
    it "reads attribute from cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)
      endpoint.add_cluster(on_off)

      result = endpoint.read_attribute(0x0006_u32, Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[1])
    end

    it "returns error for missing cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      result = endpoint.read_attribute(0x9999_u32, 0x0000_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::Failure
      )
    end

    it "writes attribute to cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      identify = Matter::Cluster::IdentifyCluster.new(endpoint_id)
      endpoint.add_cluster(identify)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(10_u16, io)

      status = endpoint.write_attribute(0x0003_u32, Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME, io.to_slice)
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).success?.should be_true

      identify.identify_time.should eq(10_u16)
    end

    it "invokes command on cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)
      endpoint.add_cluster(on_off)

      result = endpoint.invoke_command(0x0006_u32, Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      on_off.on_off.should be_true
    end
  end

  describe "description" do
    it "generates human-readable description" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      endpoint.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint_id))

      desc = endpoint.description
      desc.should contain("Endpoint 1")
      desc.should contain("On/Off Light")
      desc.should contain("1 cluster")
    end
  end
end

describe Matter::MatterNode do
  describe "initialization" do
    it "creates empty node" do
      node = Matter::MatterNode.new

      node.endpoint_count.should eq(0)
    end
  end

  describe "endpoint management" do
    it "adds endpoint to node" do
      node = Matter::MatterNode.new

      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)

      node.add_endpoint(endpoint)

      node.endpoint_count.should eq(1)
      node.has_endpoint?(1_u16).should be_true
    end

    it "retrieves endpoint by ID" do
      node = Matter::MatterNode.new

      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device_type = Matter::DeviceType.on_off_light
      endpoint = Matter::Endpoint.new(endpoint_id, device_type)
      node.add_endpoint(endpoint)

      retrieved = node.get_endpoint(1_u16)
      retrieved.should_not be_nil
      retrieved.not_nil!.endpoint_id.number.should eq(1_u16)
    end

    it "returns nil for missing endpoint" do
      node = Matter::MatterNode.new

      node.get_endpoint(99_u16).should be_nil
    end

    it "raises for missing endpoint with bang method" do
      node = Matter::MatterNode.new

      expect_raises(KeyError, /not found/) do
        node.get_endpoint!(99_u16)
      end
    end

    it "lists endpoint IDs" do
      node = Matter::MatterNode.new

      endpoint1 = Matter::Endpoint.new(
        Matter::DataType::EndpointNumber.new(0_u16),
        Matter::DeviceType.root_node
      )
      endpoint2 = Matter::Endpoint.new(
        Matter::DataType::EndpointNumber.new(1_u16),
        Matter::DeviceType.on_off_light
      )

      node.add_endpoint(endpoint1)
      node.add_endpoint(endpoint2)

      ids = node.endpoint_ids
      ids.size.should eq(2)
      ids.should contain(0_u16)
      ids.should contain(1_u16)
    end
  end

  describe "multi-endpoint operations" do
    it "creates multi-endpoint device" do
      node = Matter::MatterNode.new

      # Endpoint 0: Root node
      endpoint0 = Matter::Endpoint.new(
        Matter::DataType::EndpointNumber.new(0_u16),
        Matter::DeviceType.root_node
      )

      # Endpoint 1: On/Off Light
      endpoint1_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint1 = Matter::Endpoint.new(endpoint1_id, Matter::DeviceType.on_off_light)
      endpoint1.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint1_id))

      # Endpoint 2: Dimmable Light
      endpoint2_id = Matter::DataType::EndpointNumber.new(2_u16)
      endpoint2 = Matter::Endpoint.new(endpoint2_id, Matter::DeviceType.dimmable_light)
      endpoint2.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint2_id))
      endpoint2.add_cluster(Matter::Cluster::LevelControlCluster.new(endpoint2_id))

      node.add_endpoint(endpoint0)
      node.add_endpoint(endpoint1)
      node.add_endpoint(endpoint2)

      node.endpoint_count.should eq(3)
    end

    it "operates on different endpoints independently" do
      node = Matter::MatterNode.new

      # Create two on/off lights on different endpoints
      endpoint1_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint1 = Matter::Endpoint.new(endpoint1_id, Matter::DeviceType.on_off_light)
      endpoint1.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint1_id, on_off: false))

      endpoint2_id = Matter::DataType::EndpointNumber.new(2_u16)
      endpoint2 = Matter::Endpoint.new(endpoint2_id, Matter::DeviceType.on_off_light)
      endpoint2.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint2_id, on_off: false))

      node.add_endpoint(endpoint1)
      node.add_endpoint(endpoint2)

      # Turn on light on endpoint 1
      node.invoke_command(1_u16, 0x0006_u32, Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      # Check endpoint 1 is on, endpoint 2 is still off
      result1 = node.read_attribute(1_u16, 0x0006_u32, Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      result1.as(Bytes).should eq(Bytes[1])

      result2 = node.read_attribute(2_u16, 0x0006_u32, Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      result2.as(Bytes).should eq(Bytes[0])
    end
  end

  describe "node operations" do
    it "reads attribute from endpoint" do
      node = Matter::MatterNode.new

      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)
      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)
      endpoint.add_cluster(on_off)
      node.add_endpoint(endpoint)

      result = node.read_attribute(1_u16, 0x0006_u32, Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[1])
    end

    it "returns error for missing endpoint" do
      node = Matter::MatterNode.new

      result = node.read_attribute(99_u16, 0x0006_u32, 0x0000_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedEndpoint
      )
    end

    it "writes attribute to endpoint" do
      node = Matter::MatterNode.new

      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)
      identify = Matter::Cluster::IdentifyCluster.new(endpoint_id)
      endpoint.add_cluster(identify)
      node.add_endpoint(endpoint)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(15_u16, io)

      status = node.write_attribute(1_u16, 0x0003_u32, Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME, io.to_slice)
      status.success?.should be_true

      identify.identify_time.should eq(15_u16)
    end

    it "invokes command on endpoint" do
      node = Matter::MatterNode.new

      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint = Matter::Endpoint.new(endpoint_id, Matter::DeviceType.on_off_light)
      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)
      endpoint.add_cluster(on_off)
      node.add_endpoint(endpoint)

      result = node.invoke_command(1_u16, 0x0006_u32, Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      result.as(Matter::InteractionModel::Status).success?.should be_true

      on_off.on_off.should be_true
    end
  end

  describe "validation" do
    it "validates complete node" do
      node = Matter::MatterNode.new

      # Endpoint 1: Complete on/off light
      endpoint1_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint1 = Matter::Endpoint.new(endpoint1_id, Matter::DeviceType.on_off_light)
      descriptor1 = Matter::Cluster::DescriptorCluster.new(endpoint1_id)
      descriptor1.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(0x0100_u32, 2_u16)
      descriptor1.server_list << 0x0003_u32
      descriptor1.server_list << 0x0004_u32
      descriptor1.server_list << 0x0005_u32
      descriptor1.server_list << 0x0006_u32
      endpoint1.add_cluster(descriptor1)
      endpoint1.add_cluster(Matter::Cluster::IdentifyCluster.new(endpoint1_id))
      endpoint1.add_cluster(Matter::Cluster::GroupsCluster.new(endpoint1_id))
      endpoint1.add_cluster(Matter::Cluster::ScenesCluster.new(endpoint1_id))
      endpoint1.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint1_id))

      node.add_endpoint(endpoint1)

      node.valid?.should be_true
      node.validate.should be_empty
    end

    it "validates incomplete node" do
      node = Matter::MatterNode.new

      # Endpoint 1: Incomplete on/off light (missing clusters)
      endpoint1_id = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint1 = Matter::Endpoint.new(endpoint1_id, Matter::DeviceType.on_off_light)
      endpoint1.add_cluster(Matter::Cluster::OnOffCluster.new(endpoint1_id))

      node.add_endpoint(endpoint1)

      node.valid?.should be_false
      errors = node.validate
      errors.should_not be_empty
      errors[1_u16].should_not be_empty
    end
  end

  describe "description" do
    it "generates human-readable description" do
      node = Matter::MatterNode.new

      endpoint1 = Matter::Endpoint.new(
        Matter::DataType::EndpointNumber.new(1_u16),
        Matter::DeviceType.on_off_light
      )
      endpoint2 = Matter::Endpoint.new(
        Matter::DataType::EndpointNumber.new(2_u16),
        Matter::DeviceType.dimmable_light
      )

      node.add_endpoint(endpoint1)
      node.add_endpoint(endpoint2)

      desc = node.description
      desc.should contain("MatterNode")
      desc.should contain("2 endpoint")
      desc.should contain("Endpoint 1")
      desc.should contain("Endpoint 2")
      desc.should contain("On/Off Light")
      desc.should contain("Dimmable Light")
    end
  end
end
