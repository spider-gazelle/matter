require "../spec_helper"
require "../../src/matter/cluster/descriptor"
require "tlv"

describe Matter::Cluster::Descriptor do
  describe "initialization" do
    it "creates descriptor cluster" do
      cluster = build(Matter::Cluster::Descriptor)

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
      cluster = build(Matter::Cluster::Descriptor)

      value = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST)
      # Empty list should be encoded as empty TLV array (not just Bytes.new(0))
      value.to_slice.size.should be > 0
    end

    it "reads ServerList attribute" do
      cluster = build(Matter::Cluster::Descriptor)

      value = cluster.read_attribute(Matter::Cluster::Descriptor::ATTR_SERVER_LIST)
      value.should be_a(TLV::Any)
    end

    it "reads ClientList attribute" do
      cluster = build(Matter::Cluster::Descriptor)

      value = cluster.read_attribute(Matter::Cluster::Descriptor::ATTR_CLIENT_LIST)
      value.should be_a(TLV::Any)
    end

    it "reads PartsList attribute" do
      cluster = build(Matter::Cluster::Descriptor)

      value = cluster.read_attribute(Matter::Cluster::Descriptor::ATTR_PARTS_LIST)
      value.should be_a(TLV::Any)
    end

    it "returns status for unsupported attribute write" do
      cluster = build(Matter::Cluster::Descriptor)

      status = write(cluster,
        Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST,
        Bytes[0, 1, 2, 3]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      cluster = build(Matter::Cluster::Descriptor)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 4

      device_type = attributes.find { |attr| attr.id.id == Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST }
      device_type.should_not be_nil
      device_type_attr = device_type.as(Matter::Cluster::AttributeMetadata)
      device_type_attr.name.should eq("deviceTypeList")
      device_type_attr.writable?.should be_false
    end
  end

  describe "DeviceTypeStruct" do
    it "creates device type struct" do
      device_type = Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 1_u16
      )

      device_type.device_type.should eq(0x0100_u32)
      device_type.revision.should eq(1_u16)
    end

    it "creates on/off light device type" do
      on_off_light = Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )

      on_off_light.device_type.should eq(0x0100_u32)
      on_off_light.revision.should eq(2_u16)
    end

    it "creates dimmable light device type" do
      dimmable_light = Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0101_u32, # Dimmable Light
        revision: 2_u16
      )

      dimmable_light.device_type.should eq(0x0101_u32)
    end
  end

  describe "device type management" do
    it "adds device type to list" do
      cluster = build(Matter::Cluster::Descriptor)

      device_type = Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 2_u16
      )

      cluster.device_type_list << device_type
      cluster.device_type_list.size.should eq(1)
      cluster.device_type_list[0].device_type.should eq(0x0100_u32)
    end

    it "supports multiple device types" do
      cluster = build(Matter::Cluster::Descriptor)

      # Add root node device type
      cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0016_u32,
        revision: 1_u16
      )

      # Add aggregator device type
      cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x000E_u32,
        revision: 1_u16
      )

      cluster.device_type_list.size.should eq(2)
    end
  end

  describe "server list management" do
    it "adds server clusters" do
      cluster = build(Matter::Cluster::Descriptor)

      cluster.server_list << 0x0006_u32 # On/Off
      cluster.server_list << 0x0008_u32 # Level Control

      cluster.server_list.size.should eq(3) # Descriptor + added clusters
      cluster.server_list.should contain(0x0006_u32)
      cluster.server_list.should contain(0x0008_u32)
    end

    it "tracks mandatory clusters" do
      cluster = build(Matter::Cluster::Descriptor)

      # Add mandatory clusters (Descriptor already added automatically)
      cluster.server_list << 0x0003_u32 # Identify

      cluster.server_list.size.should eq(2)
    end
  end

  describe "client list management" do
    it "adds client clusters" do
      cluster = build(Matter::Cluster::Descriptor)

      cluster.client_list << 0x0006_u32 # On/Off client
      cluster.client_list << 0x0008_u32 # Level Control client

      cluster.client_list.size.should eq(2)
    end

    it "can have empty client list" do
      cluster = build(Matter::Cluster::Descriptor)

      cluster.client_list.should be_empty
    end
  end

  describe "parts list management" do
    it "adds child endpoints" do
      cluster = build(Matter::Cluster::Descriptor, 0)

      cluster.parts_list << 1_u16
      cluster.parts_list << 2_u16
      cluster.parts_list << 3_u16

      cluster.parts_list.size.should eq(3)
      cluster.parts_list.should contain(1_u16)
      cluster.parts_list.should contain(2_u16)
      cluster.parts_list.should contain(3_u16)
    end

    it "can have empty parts list for leaf endpoints" do
      cluster = build(Matter::Cluster::Descriptor)

      cluster.parts_list.should be_empty
    end
  end

  describe "device composition" do
    it "describes simple light endpoint" do
      cluster = build(Matter::Cluster::Descriptor)

      # Device type: On/Off Light
      cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
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
      cluster = build(Matter::Cluster::Descriptor, 0)

      # Device type: Root Node
      cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
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
      cluster = build(Matter::Cluster::Descriptor)

      cluster.server_list << 0x0006_u32
      cluster.server_list << 0x0008_u32

      cluster.has_server_cluster?(0x0006_u32).should be_true
      cluster.has_server_cluster?(0x0009_u32).should be_false
    end

    it "checks if cluster is client" do
      cluster = build(Matter::Cluster::Descriptor)

      cluster.client_list << 0x0006_u32

      cluster.has_client_cluster?(0x0006_u32).should be_true
      cluster.has_client_cluster?(0x0008_u32).should be_false
    end

    it "checks if endpoint has part" do
      cluster = build(Matter::Cluster::Descriptor, 0)

      cluster.parts_list << 1_u16
      cluster.parts_list << 2_u16

      cluster.has_part?(1_u16).should be_true
      cluster.has_part?(3_u16).should be_false
    end

    it "gets primary device type" do
      cluster = build(Matter::Cluster::Descriptor)

      cluster.primary_device_type.should be_nil

      device_type1 = Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 2_u16
      )
      device_type2 = Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0016_u32,
        revision: 1_u16
      )

      cluster.device_type_list << device_type1
      cluster.device_type_list << device_type2

      primary = cluster.primary_device_type
      primary.should_not be_nil
      primary.as(Matter::Cluster::Descriptor::DeviceTypeStruct).device_type.should eq(0x0100_u32)
    end
  end

  describe "TLV encoding" do
    describe "DeviceTypeList" do
      it "encodes empty device type list" do
        cluster = build(Matter::Cluster::Descriptor)

        encoded = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST)
        encoded.to_slice.size.should be > 0

        # Decode and verify empty array
        device_types = encoded.as_list
        device_types.should be_empty
      end

      it "encodes single device type" do
        cluster = build(Matter::Cluster::Descriptor)

        cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
          device_type: 0x0100_u32,
          revision: 2_u16
        )

        # Decode and verify
        device_types = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST).as_list
        device_types.size.should eq(1)

        # Parse the DeviceTypeStruct from the first element
        dt = Matter::Cluster::Descriptor::DeviceTypeStruct.from_slice(device_types[0].to_slice)
        dt.device_type.should eq(0x0100_u32)
        dt.revision.should eq(2_u16)
      end

      it "encodes multiple device types" do
        cluster = build(Matter::Cluster::Descriptor, 0)

        cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
          device_type: 0x0016_u32,
          revision: 1_u16
        )
        cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
          device_type: 0x000E_u32,
          revision: 1_u16
        )

        # Decode and verify
        device_types = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST).as_list
        device_types.size.should eq(2)

        # First device type
        dt1 = Matter::Cluster::Descriptor::DeviceTypeStruct.from_slice(device_types[0].to_slice)
        dt1.device_type.should eq(0x0016_u32)
        dt1.revision.should eq(1_u16)

        # Second device type
        dt2 = Matter::Cluster::Descriptor::DeviceTypeStruct.from_slice(device_types[1].to_slice)
        dt2.device_type.should eq(0x000E_u32)
        dt2.revision.should eq(1_u16)
      end
    end

    describe "ServerList" do
      it "encodes server list" do
        cluster = build(Matter::Cluster::Descriptor)

        # Descriptor is automatically added
        cluster.server_list << 0x0006_u32 # On/Off
        cluster.server_list << 0x0008_u32 # Level Control

        # Decode and verify
        clusters = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_SERVER_LIST).as_list
        clusters.size.should eq(3)

        # Check cluster IDs
        cluster_ids = clusters.map { |entry| entry.value.as(Int).to_u32 }

        cluster_ids.should contain(0x001D_u32) # Descriptor
        cluster_ids.should contain(0x0006_u32) # On/Off
        cluster_ids.should contain(0x0008_u32) # Level Control
      end

      it "encodes empty server list with only descriptor" do
        cluster = build(Matter::Cluster::Descriptor)

        clusters = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_SERVER_LIST).as_list
        clusters.size.should eq(1) # Just Descriptor itself

        cluster_id = clusters[0].value.as(Int).to_u32
        cluster_id.should eq(0x001D_u32)
      end
    end

    describe "ClientList" do
      it "encodes empty client list" do
        cluster = build(Matter::Cluster::Descriptor)

        clusters = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_CLIENT_LIST).as_list
        clusters.should be_empty
      end

      it "encodes client list with clusters" do
        cluster = build(Matter::Cluster::Descriptor)

        cluster.client_list << 0x0006_u32 # On/Off client
        cluster.client_list << 0x0008_u32 # Level Control client

        clusters = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_CLIENT_LIST).as_list
        clusters.size.should eq(2)

        cluster_ids = clusters.map { |entry| entry.value.as(Int).to_u32 }

        cluster_ids.should contain(0x0006_u32)
        cluster_ids.should contain(0x0008_u32)
      end
    end

    describe "PartsList" do
      it "encodes empty parts list" do
        cluster = build(Matter::Cluster::Descriptor)

        parts = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list
        parts.should be_empty
      end

      it "encodes parts list with child endpoints" do
        cluster = build(Matter::Cluster::Descriptor, 0)

        cluster.parts_list << 1_u16
        cluster.parts_list << 2_u16
        cluster.parts_list << 3_u16

        parts = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list
        parts.size.should eq(3)

        endpoint_ids = parts.map { |part| part.value.as(Int).to_u16 }

        endpoint_ids.should contain(1_u16)
        endpoint_ids.should contain(2_u16)
        endpoint_ids.should contain(3_u16)
      end
    end

    describe "complete endpoint encoding" do
      it "encodes root endpoint descriptor" do
        cluster = build(Matter::Cluster::Descriptor, 0)

        # Root node device type
        cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
          device_type: 0x0016_u32,
          revision: 1_u16
        )

        # Mandatory clusters
        cluster.server_list << 0x001F_u32 # Access Control
        cluster.server_list << 0x0028_u32 # Basic Information
        cluster.server_list << 0x0030_u32 # General Commissioning

        # Child endpoints
        cluster.parts_list << 1_u16
        cluster.parts_list << 2_u16

        # Verify all attributes encode successfully
        device_types = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST)
        device_types.to_slice.size.should be > 0

        servers = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_SERVER_LIST)
        servers.to_slice.size.should be > 0

        clients = cluster.read_attribute(Matter::Cluster::Descriptor::ATTR_CLIENT_LIST)
        clients.should be_a(TLV::Any)

        parts = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_PARTS_LIST)
        parts.to_slice.size.should be > 0
      end

      it "encodes light endpoint descriptor" do
        cluster = build(Matter::Cluster::Descriptor)

        # On/Off Light device type
        cluster.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
          device_type: 0x0100_u32,
          revision: 2_u16
        )

        # Server clusters
        cluster.server_list << 0x0003_u32 # Identify
        cluster.server_list << 0x0006_u32 # On/Off

        # No client clusters or parts for leaf endpoint

        # Decode device types
        dt_array = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST).as_list
        dt_array.size.should eq(1)

        # Decode servers
        server_array = read_tlv(cluster, Matter::Cluster::Descriptor::ATTR_SERVER_LIST).as_list
        server_array.size.should eq(3) # Descriptor + Identify + On/Off
      end
    end
  end
end
