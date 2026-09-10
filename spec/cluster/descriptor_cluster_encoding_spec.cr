require "../spec_helper"
require "../../src/matter/cluster/descriptor_cluster"

describe Matter::Cluster::DescriptorCluster do
  describe "TLV encoding" do
    it "encodes DeviceTypeList as TLV Array (not List)" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      # Add a device type
      cluster.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 1_u16
      )

      # Read the attribute
      result = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      result.should be_a(Bytes)
      bytes = result.as(Bytes)

      # Parse the TLV
      tlv = TLV.parse(bytes)

      # The element type should be Array (0x16), not List (0x17)
      # Array = ElementType::Array
      # List = ElementType::List
      tlv.header.element_type.should eq(TLV::ElementType::Array)
    end

    it "encodes ServerList as TLV Array" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      # ServerList should already have CLUSTER_ID from initialize
      result = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
      result.should be_a(Bytes)
      bytes = result.as(Bytes)

      tlv = TLV.parse(bytes)
      tlv.header.element_type.should eq(TLV::ElementType::Array)
    end

    it "encodes PartsList as TLV Array" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)
      cluster.add_part(1_u16)

      result = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_PARTS_LIST)
      result.should be_a(Bytes)
      bytes = result.as(Bytes)

      tlv = TLV.parse(bytes)
      tlv.header.element_type.should eq(TLV::ElementType::Array)
    end

    it "encodes AttributeList as TLV Array" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::Base::GLOBAL_ATTRIBUTE_LIST)
      result.should be_a(Bytes)
      bytes = result.as(Bytes)

      tlv = TLV.parse(bytes)
      tlv.header.element_type.should eq(TLV::ElementType::Array)
    end

    it "encodes DeviceTypeList elements with anonymous tags" do
      endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      cluster.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32,
        revision: 1_u16
      )

      result = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      bytes = result.as(Bytes)

      tlv = TLV.parse(bytes)
      tlv.header.element_type.should eq(TLV::ElementType::Array)

      # Array should have one element
      tlv.size.should eq(1)

      # The element should be a structure (DeviceTypeStruct)
      first_element = tlv[0]
      first_element.header.element_type.should eq(TLV::ElementType::Structure)

      # The element should have an anonymous tag (nil)
      first_element.header.ids.should be_nil
    end

    it "encodes DeviceTypeStruct with correct field tags" do
      dt = Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 2_u16
      )

      bytes = dt.to_slice
      tlv = TLV.parse(bytes)

      # Should be a structure
      tlv.header.element_type.should eq(TLV::ElementType::Structure)

      # Tag 0: device_type (UInt32)
      tlv[0_u8].as_u32.should eq(0x0016_u32)

      # Tag 1: revision (UInt16)
      tlv[1_u8].as_u16.should eq(2_u16)
    end
  end
end
