require "../spec_helper"
require "../../src/matter/cluster/descriptor_cluster"

describe Matter::Cluster::DescriptorCluster do
  describe "initialization" do
    it "creates descriptor cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x001D_u32)
      cluster.name.should eq("Descriptor")
      cluster.device_type_list.should be_empty
      cluster.server_list.size.should eq(1) # Contains Descriptor itself
      cluster.server_list.should contain(0x001D_u32)
      cluster.client_list.should be_empty
      cluster.parts_list.should be_empty
    end
  end

  describe "attributes" do
    it "reads DeviceTypeList attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes.new(0)) # Empty list
    end

    it "reads ServerList attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
      value.should be_a(Bytes)
    end

    it "reads ClientList attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_CLIENT_LIST)
      value.should be_a(Bytes)
    end

    it "reads PartsList attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_PARTS_LIST)
      value.should be_a(Bytes)
    end

    it "returns status for unsupported attribute write" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST,
        Bytes[0, 1, 2, 3]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 4

      device_type = attributes.find { |a| a.id.id == Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST }
      device_type.should_not be_nil
      device_type.not_nil!.name.should eq("DeviceTypeList")
      device_type.not_nil!.writable.should be_false
    end
  end

  describe "DeviceTypeStruct" do
    it "creates device type struct" do
      device_type = Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 1_u16
      )

      device_type.device_type.should eq(0x0100_u32)
      device_type.revision.should eq(1_u16)
    end

    it "creates on/off light device type" do
      on_off_light = Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )

      on_off_light.device_type.should eq(0x0100_u32)
      on_off_light.revision.should eq(2_u16)
    end

    it "creates dimmable light device type" do
      dimmable_light = Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0101_u32, # Dimmable Light
        revision: 2_u16
      )

      dimmable_light.device_type.should eq(0x0101_u32)
    end
  end

  describe "device type management" do
    it "adds device type to list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      device_type = Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 2_u16
      )

      cluster.device_type_list << device_type
      cluster.device_type_list.size.should eq(1)
      cluster.device_type_list[0].device_type.should eq(0x0100_u32)
    end

    it "supports multiple device types" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Add root node device type
      cluster.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32,
        revision: 1_u16
      )

      # Add aggregator device type
      cluster.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x000E_u32,
        revision: 1_u16
      )

      cluster.device_type_list.size.should eq(2)
    end
  end

  describe "server list management" do
    it "adds server clusters" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.server_list << 0x0006_u32 # On/Off
      cluster.server_list << 0x0008_u32 # Level Control

      cluster.server_list.size.should eq(3) # Descriptor + added clusters
      cluster.server_list.should contain(0x0006_u32)
      cluster.server_list.should contain(0x0008_u32)
    end

    it "tracks mandatory clusters" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Add mandatory clusters (Descriptor already added automatically)
      cluster.server_list << 0x0003_u32 # Identify

      cluster.server_list.size.should eq(2)
    end
  end

  describe "client list management" do
    it "adds client clusters" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.client_list << 0x0006_u32 # On/Off client
      cluster.client_list << 0x0008_u32 # Level Control client

      cluster.client_list.size.should eq(2)
    end

    it "can have empty client list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.client_list.should be_empty
    end
  end

  describe "parts list management" do
    it "adds child endpoints" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.parts_list << 1_u16
      cluster.parts_list << 2_u16
      cluster.parts_list << 3_u16

      cluster.parts_list.size.should eq(3)
      cluster.parts_list.should contain(1_u16)
      cluster.parts_list.should contain(2_u16)
      cluster.parts_list.should contain(3_u16)
    end

    it "can have empty parts list for leaf endpoints" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.parts_list.should be_empty
    end
  end

  describe "device composition" do
    it "describes simple light endpoint" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Device type: On/Off Light
      cluster.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 2_u16
      )

      # Server clusters (Descriptor already added automatically)
      cluster.server_list << 0x0003_u32 # Identify
      cluster.server_list << 0x0006_u32 # On/Off

      # No client clusters
      # No parts

      cluster.device_type_list.size.should eq(1)
      cluster.server_list.size.should eq(3)
      cluster.client_list.should be_empty
      cluster.parts_list.should be_empty
    end

    it "describes root endpoint with parts" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Device type: Root Node
      cluster.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32,
        revision: 1_u16
      )

      # Server clusters (mandatory for root, Descriptor already added automatically)
      cluster.server_list << 0x001F_u32 # Access Control
      cluster.server_list << 0x0028_u32 # Basic Information
      cluster.server_list << 0x0030_u32 # General Commissioning
      cluster.server_list << 0x0031_u32 # Network Commissioning
      cluster.server_list << 0x003C_u32 # Administrator Commissioning
      cluster.server_list << 0x003E_u32 # Operational Credentials

      # Child endpoints
      cluster.parts_list << 1_u16
      cluster.parts_list << 2_u16

      cluster.device_type_list.size.should eq(1)
      cluster.server_list.size.should eq(7)
      cluster.parts_list.size.should eq(2)
    end
  end

  describe "helpers" do
    it "checks if cluster is server" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.server_list << 0x0006_u32
      cluster.server_list << 0x0008_u32

      cluster.has_server_cluster?(0x0006_u32).should be_true
      cluster.has_server_cluster?(0x0009_u32).should be_false
    end

    it "checks if cluster is client" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.client_list << 0x0006_u32

      cluster.has_client_cluster?(0x0006_u32).should be_true
      cluster.has_client_cluster?(0x0008_u32).should be_false
    end

    it "checks if endpoint has part" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      cluster.parts_list << 1_u16
      cluster.parts_list << 2_u16

      cluster.has_part?(1_u16).should be_true
      cluster.has_part?(3_u16).should be_false
    end
  end
end
