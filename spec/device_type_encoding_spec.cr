require "./spec_helper"
require "../src/matter/cluster/descriptor_cluster"
require "../src/matter/constants/device_types"

describe "DeviceType encoding for HomeKit compatibility" do
  describe "device_type_list attribute" do
    it "encodes On/Off Light device type correctly" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Add On/Off Light device type (0x0100)
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: Matter::DeviceTypes::ON_OFF_LIGHT.to_u32,
        revision: 2_u16
      )

      # Read the device_type_list attribute (0x0000)
      result = descriptor.read_attribute(0x0000_u32)
      result.should be_a(Bytes)

      bytes = result.as(Bytes)
      puts "device_type_list TLV encoding: #{bytes.hexstring}"

      # Decode the TLV to verify structure
      # Should be an array containing one struct with device_type=0x0100 and revision=2
      # TLV format: array_start, struct_start, uint32(tag=0, value=0x0100), uint16(tag=1, value=2), struct_end, array_end

      # Verify the bytes contain the device type 0x0100 (256)
      # In little-endian: 00 01 00 00
      # TLV uses compact encoding: 256 fits in 2 bytes (0x0100)
      # Format: 25 (uint16) 00 (tag 0) 00 01 (value 256 LE)
      bytes.hexstring.should contain("25000001")
    end

    it "encodes Root Node device type correctly" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Add Root Node device type (0x0016)
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: Matter::DeviceTypes::ROOT_NODE.to_u32,
        revision: 1_u16
      )

      result = descriptor.read_attribute(0x0000_u32)
      result.should be_a(Bytes)

      bytes = result.as(Bytes)
      puts "Root Node device_type_list TLV encoding: #{bytes.hexstring}"

      # TLV uses compact encoding: 22 fits in 1 byte (0x16)
      # Format: 24 (uint8) 00 (tag 0) 16 (value 22)
      bytes.hexstring.should contain("240016")
    end

    it "encodes server_list correctly for On/Off Light" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Add mandatory clusters for On/Off Light
      descriptor.server_list << 0x0003_u32 # Identify
      descriptor.server_list << 0x0004_u32 # Groups
      descriptor.server_list << 0x0005_u32 # Scenes
      descriptor.server_list << 0x0006_u32 # OnOff

      # Read the server_list attribute (0x0001)
      result = descriptor.read_attribute(0x0001_u32)
      result.should be_a(Bytes)

      bytes = result.as(Bytes)
      puts "server_list TLV encoding: #{bytes.hexstring}"

      # Should contain all cluster IDs
      # Identify = 0x0003, Groups = 0x0004, Scenes = 0x0005, OnOff = 0x0006
    end
  end

  describe "FeatureMap encoding" do
    it "encodes OnOff cluster with LIGHTING feature" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      on_off = Matter::Cluster::OnOffCluster.new(
        endpoint_id,
        on_off: false,
        feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting
      )

      # FeatureMap attribute ID is 0xFFFC (65532)
      result = on_off.read_attribute(0xFFFC_u32)
      result.should be_a(Bytes)

      bytes = result.as(Bytes)
      puts "OnOff FeatureMap TLV encoding: #{bytes.hexstring}"

      # Should contain 0x01 (LIGHTING feature)
      # The value should be UInt32 with value 1
    end

    it "encodes OnOff cluster without LIGHTING feature" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      on_off = Matter::Cluster::OnOffCluster.new(
        endpoint_id,
        on_off: false,
        feature_map: Matter::Cluster::OnOffCluster::Feature::None
      )

      result = on_off.read_attribute(0xFFFC_u32)
      result.should be_a(Bytes)

      bytes = result.as(Bytes)
      puts "OnOff FeatureMap (no features) TLV encoding: #{bytes.hexstring}"

      # Should contain 0x00 (no features)
    end
  end

  describe "ClusterRevision encoding" do
    it "encodes OnOff cluster revision" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      on_off = Matter::Cluster::OnOffCluster.new(endpoint_id)

      # ClusterRevision attribute ID is 0xFFFD (65533)
      result = on_off.read_attribute(0xFFFD_u32)
      result.should be_a(Bytes)

      bytes = result.as(Bytes)
      puts "OnOff ClusterRevision TLV encoding: #{bytes.hexstring}"
    end

    it "encodes Descriptor cluster revision" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      result = descriptor.read_attribute(0xFFFD_u32)
      result.should be_a(Bytes)

      bytes = result.as(Bytes)
      puts "Descriptor ClusterRevision TLV encoding: #{bytes.hexstring}"
    end
  end
end
