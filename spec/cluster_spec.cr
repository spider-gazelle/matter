require "./spec_helper"
require "../src/matter/cluster/cluster"
require "../src/matter/cluster/descriptor_cluster"
require "../src/matter/cluster/on_off_cluster"

describe Matter::Cluster do
  describe "DescriptorCluster" do
    it "creates descriptor cluster" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      cluster.name.should eq("Descriptor")
      cluster.cluster_id.id.should eq(0x001D_u32)
      cluster.endpoint_id.should eq(endpoint)
      cluster.data_version.should eq(0_u32)
    end

    it "has required attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      attrs = cluster.attributes
      attrs.size.should be >= 4

      # Check for required attributes
      device_type_list = attrs.find { |a| a.id.id == Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST }
      device_type_list.should_not be_nil
      device_type_list.not_nil!.name.should eq("DeviceTypeList")
      device_type_list.not_nil!.writable.should be_false

      server_list = attrs.find { |a| a.id.id == Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST }
      server_list.should_not be_nil
    end

    it "reads device type list" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      result.should be_a(Bytes)
      # Empty list encodes as TLV array
      result.as(Bytes).size.should be > 0
    end

    it "reads server list" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      servers = [0x0006_u32, 0x0008_u32]

      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)
      cluster.server_list << servers[0]
      cluster.server_list << servers[1]

      result = cluster.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
      result.should be_a(Bytes)
      # Now properly TLV encoded
      result.as(Bytes).size.should be > 0
    end

    it "returns error for unsupported attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::DescriptorCluster.new(endpoint)

      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "OnOffCluster" do
    it "creates on/off cluster" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint)

      cluster.name.should eq("OnOff")
      cluster.cluster_id.id.should eq(0x0006_u32)
      cluster.on_off.should be_false
    end

    it "has required attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint)

      # Only cluster-specific attributes are in attributes array
      # Global attributes (featureMap, clusterRevision) are handled by base class
      attrs = cluster.attributes
      attrs.size.should eq(1) # Just onOff (global attrs handled separately)

      on_off_attr = attrs.find { |a| a.id.id == Matter::Cluster::OnOffCluster::ATTR_ON_OFF }
      on_off_attr.should_not be_nil
      on_off_attr.not_nil!.name.should eq("onOff")
      on_off_attr.not_nil!.type.should eq(:bool)
      on_off_attr.not_nil!.writable.should be_false

      # Global attributes can be read via read_attribute
      result = cluster.read_attribute(0xFFFC_u32) # FeatureMap
      result.should be_a(Bytes)
    end

    it "has required commands" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint)

      cmds = cluster.commands
      cmds.size.should eq(3) # Base cluster: off, on, toggle (Lighting commands require Lighting feature)

      off_cmd = cmds.find { |c| c.id.id == Matter::Cluster::OnOffCluster::CMD_OFF }
      off_cmd.should_not be_nil
      off_cmd.not_nil!.name.should eq("off")

      on_cmd = cmds.find { |c| c.id.id == Matter::Cluster::OnOffCluster::CMD_ON }
      on_cmd.should_not be_nil

      toggle_cmd = cmds.find { |c| c.id.id == Matter::Cluster::OnOffCluster::CMD_TOGGLE }
      toggle_cmd.should_not be_nil
    end

    it "reads OnOff attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint, on_off: true)

      result = cluster.read_attribute(Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(true)
    end

    it "executes Off command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint, on_off: true)

      cluster.on_off.should be_true

      result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      cluster.on_off.should be_false

      # Check attribute value updated
      attr_value = cluster.read_attribute(Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      decode_tlv_value(attr_value.as(Bytes)).should eq(false)
    end

    it "executes On command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

      cluster.on_off.should be_false

      result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      cluster.on_off.should be_true
    end

    it "executes Toggle command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

      # Toggle off -> on
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      cluster.on_off.should be_true

      # Toggle on -> off
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      cluster.on_off.should be_false
    end

    it "increments data version on command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint)

      initial_version = cluster.data_version
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      cluster.data_version.should eq(initial_version + 1)
    end

    it "returns error for unsupported command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint)

      result = cluster.invoke_command(0x9999_u32, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedCommand)
    end
  end
end
