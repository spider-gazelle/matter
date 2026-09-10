require "../spec_helper"
require "../../src/matter/cluster/descriptor_cluster"
require "../../src/matter/cluster/access_control_cluster"
require "../../src/matter/cluster/basic_information_cluster"
require "../../src/matter/cluster/general_commissioning_cluster"
require "../../src/matter/cluster/administrator_commissioning_cluster"
require "../../src/matter/cluster/operational_credentials_cluster"
require "../../src/matter/cluster/network_commissioning_cluster"
require "../../src/matter/cluster/identify_cluster"
require "../../src/matter/cluster/on_off_cluster"
require "../../src/matter/cluster/level_control_cluster"
require "../../src/matter/cluster/color_control_cluster"
require "../../src/matter/cluster/groups_cluster"
require "../../src/matter/cluster/scenes_management_cluster"
require "tlv"

# Helper to extract integer value from TLV::Any
def extract_int_value(any : TLV::Any) : UInt32
  case v = any.value
  when Int then v.to_u32
  else          0_u32
  end
end

def extract_u16_value(any : TLV::Any) : UInt16
  case v = any.value
  when Int then v.to_u16
  else          0_u16
  end
end

# Integration tests demonstrating real-world Descriptor cluster usage patterns
#
# The Descriptor cluster is REQUIRED on every endpoint and provides the device
# composition information that controllers use to understand device capabilities.
#
# These tests show:
# - Device discovery patterns
# - Endpoint hierarchy (root + child endpoints)
# - Device type identification
# - Cluster capability discovery
# - Bridge/aggregator patterns

describe "Descriptor Integration" do
  describe "simple on/off light device" do
    it "describes a basic light endpoint" do
      # Endpoint 1: On/Off Light
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Device Type: On/Off Light (0x0100)
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 2_u16
      )

      # Server Clusters (capabilities this endpoint provides)
      # Descriptor is already added automatically
      descriptor.add_server(Matter::Cluster::IdentifyCluster)
        .add_server(Matter::Cluster::GroupsCluster)
        .add_server(Matter::Cluster::ScenesManagementCluster)
        .add_server(Matter::Cluster::OnOffCluster)

      # No client clusters (this device doesn't control other devices)
      # No parts list (this is a leaf endpoint)

      # Verify device type can be discovered
      primary_type = descriptor.primary_device_type
      primary_type.should_not be_nil
      primary_type.as(Matter::Cluster::DescriptorCluster::DeviceTypeStruct).device_type.should eq(0x0100_u32)

      # Controller would read this over the network
      device_types_tlv = descriptor.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      device_types_tlv.should be_a(Bytes)

      # Decode to see what controller sees
      parsed = TLV::Any.from_slice(device_types_tlv.as(Bytes))
      types = parsed.value.as(Array(TLV::Any))
      types.size.should eq(1)

      # Controller knows this is an On/Off Light
      type_hash = types[0].value.as(TLV::Structure)
      device_type = extract_int_value(type_hash[0_u8])
      device_type.should eq(0x0100_u32)

      # Controller discovers available clusters
      servers_tlv = descriptor.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
      parsed = TLV::Any.from_slice(servers_tlv.as(Bytes))
      clusters = parsed.value.as(Array(TLV::Any))
      clusters.size.should eq(5) # Descriptor + Identify + Groups + Scenes Management + On/Off

      # Controller knows it can control this light via On/Off cluster
      descriptor.has_server_cluster?(Matter::Cluster::OnOffCluster).should be_true
    end
  end

  describe "dimmable light device" do
    it "describes a dimmable light with multiple device types" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_id)

      # Device Types: Dimmable Light (0x0101) which also includes On/Off Light
      # In Matter, device types can be composed
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0101_u32, # Dimmable Light
        revision: 2_u16
      )

      # Server Clusters
      descriptor.add_server(Matter::Cluster::IdentifyCluster)
        .add_server(Matter::Cluster::OnOffCluster)
        .add_server(Matter::Cluster::LevelControlCluster) # dimming

      # Verify controller sees dimming capability
      descriptor.has_server_cluster?(Matter::Cluster::LevelControlCluster).should be_true

      # Read server list
      servers_tlv = descriptor.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
      parsed = TLV::Any.from_slice(servers_tlv.as(Bytes))
      clusters = parsed.value.as(Array(TLV::Any))

      # Convert to cluster IDs
      cluster_ids = clusters.map { |cluster| extract_int_value(cluster) }

      # Controller knows it can dim this light
      cluster_ids.should contain(Matter::Cluster::LevelControlCluster::CLUSTER_ID)
    end
  end

  describe "root endpoint with child endpoints" do
    it "describes device hierarchy with parts list" do
      # Endpoint 0: Root Node (aggregator for child endpoints)
      root_endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      root_descriptor = Matter::Cluster::DescriptorCluster.new(root_endpoint)

      # Device Type: Root Node (0x0016)
      root_descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32,
        revision: 1_u16
      )

      # Root endpoint has all the mandatory commissioning clusters
      root_descriptor.add_server(Matter::Cluster::AccessControlCluster)
        .add_server(Matter::Cluster::BasicInformationCluster)
        .add_server(Matter::Cluster::GeneralCommissioningCluster)
        .add_server(Matter::Cluster::NetworkCommissioningCluster)
        .add_server(Matter::Cluster::AdministratorCommissioningCluster)
        .add_server(Matter::Cluster::OperationalCredentialsCluster)
      # Note: Group Key Management cluster not yet implemented

      # Parts list tells controller about child endpoints
      root_descriptor.add_part(1_u16) # First light
        .add_part(2_u16)              # Second light

      # Controller reads parts list to discover endpoints
      parts_tlv = root_descriptor.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_PARTS_LIST)
      parsed = TLV::Any.from_slice(parts_tlv.as(Bytes))
      parts = parsed.value.as(Array(TLV::Any))
      parts.size.should eq(2)

      # Controller now knows to query endpoints 1 and 2
      endpoint_ids = parts.map { |part| extract_u16_value(part) }
      endpoint_ids.should contain(1_u16)
      endpoint_ids.should contain(2_u16)

      # Helper verifies endpoint is a child
      root_descriptor.has_part?(1_u16).should be_true
      root_descriptor.has_part?(2_u16).should be_true
      root_descriptor.has_part?(3_u16).should be_false
    end
  end

  describe "multi-endpoint device (e.g., dual light fixture)" do
    it "describes complete device composition" do
      # This simulates a dual light fixture with one Matter node controlling two lights

      # Endpoint 0: Root
      root = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 1_u16
      )
      root.add_server(Matter::Cluster::AccessControlCluster)
        .add_server(Matter::Cluster::BasicInformationCluster)
        .add_server(Matter::Cluster::GeneralCommissioningCluster)
        .add_part(1_u16)
        .add_part(2_u16)

      # Endpoint 1: First Light
      light1 = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(1_u16))
      light1.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )
      light1.add_server(Matter::Cluster::IdentifyCluster)
        .add_server(Matter::Cluster::OnOffCluster)

      # Endpoint 2: Second Light
      light2 = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(2_u16))
      light2.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )
      light2.add_server(Matter::Cluster::IdentifyCluster)
        .add_server(Matter::Cluster::OnOffCluster)

      # Controller discovery flow:
      # 1. Read endpoint 0 descriptor
      root_parts = root.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_PARTS_LIST)
      parsed = TLV::Any.from_slice(root_parts.as(Bytes))
      child_endpoints = parsed.value.as(Array(TLV::Any))
      child_endpoints.size.should eq(2)

      # 2. Read each child endpoint descriptor
      light1_types = light1.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      parsed = TLV::Any.from_slice(light1_types.as(Bytes))
      types1 = parsed.value.as(Array(TLV::Any))
      types1.size.should eq(1)

      light2_types = light2.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      parsed = TLV::Any.from_slice(light2_types.as(Bytes))
      types2 = parsed.value.as(Array(TLV::Any))
      types2.size.should eq(1)

      # 3. Controller now knows:
      # - This is a multi-endpoint device (root has parts)
      # - It has two On/Off Light endpoints
      # - It can control each light independently via endpoints 1 and 2
    end
  end

  describe "bridge device pattern" do
    it "describes a bridge with bridged devices" do
      # A bridge is a Matter device that exposes non-Matter devices to the Matter network
      # For example, a Zigbee bridge that exposes Zigbee lights via Matter

      # Endpoint 0: Root (Aggregator)
      root = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x000E_u32, # Aggregator (bridge)
        revision: 1_u16
      )
      root.add_server(Matter::Cluster::AccessControlCluster)
        .add_server(Matter::Cluster::BasicInformationCluster)
      root.server_list << 0x0039_u32 # Bridged Device Basic Information (not yet implemented)

      # Bridge can have many bridged devices
      # Let's add 5 bridged light endpoints
      5.times do |i|
        root.parts_list << (i + 1).to_u16
      end

      # Verify bridge structure
      root.primary_device_type.as(Matter::Cluster::DescriptorCluster::DeviceTypeStruct).device_type.should eq(0x000E_u32)
      root.parts_list.size.should eq(5)

      # Each bridged device would have its own endpoint with descriptor
      bridged_light = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(1_u16))
      bridged_light.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )
      bridged_light.add_server(Matter::Cluster::IdentifyCluster)
        .add_server(Matter::Cluster::OnOffCluster)
      bridged_light.server_list << 0x0039_u32 # Bridged Device Basic Information (not yet implemented)

      # Controller can discover all bridged devices
      parts_tlv = root.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_PARTS_LIST)
      parsed = TLV::Any.from_slice(parts_tlv.as(Bytes))
      bridged_endpoints = parsed.value.as(Array(TLV::Any))
      bridged_endpoints.size.should eq(5)

      # Controller would then read descriptor on each bridged endpoint
      # to determine device type and capabilities
    end
  end

  describe "controller binding pattern" do
    it "describes a device with client clusters (bindings)" do
      # A switch or sensor that controls other devices uses client clusters
      # Client clusters indicate outbound bindings

      # Endpoint 1: On/Off Light Switch
      switch = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(1_u16))

      # Device Type: On/Off Light Switch (0x0103)
      switch.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0103_u32,
        revision: 2_u16
      )

      # Server clusters (capabilities this device provides)
      switch.add_server(Matter::Cluster::IdentifyCluster)
      switch.server_list << 0x003B_u32 # Switch (not yet implemented)

      # Client clusters (this device can control other devices)
      switch.add_client(Matter::Cluster::OnOffCluster)
        .add_client(Matter::Cluster::LevelControlCluster)

      # Verify binding capabilities
      switch.has_client_cluster?(Matter::Cluster::OnOffCluster).should be_true
      switch.has_client_cluster?(Matter::Cluster::LevelControlCluster).should be_true

      # Controller reads client list to know what this device can control
      clients_tlv = switch.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_CLIENT_LIST)
      parsed = TLV::Any.from_slice(clients_tlv.as(Bytes))
      clients = parsed.value.as(Array(TLV::Any))
      clients.size.should eq(2)

      client_ids = clients.map { |client| extract_int_value(client) }

      # Controller knows this switch can be bound to On/Off and Level Control devices
      client_ids.should contain(Matter::Cluster::OnOffCluster::CLUSTER_ID)
      client_ids.should contain(Matter::Cluster::LevelControlCluster::CLUSTER_ID)
    end
  end

  describe "commissioning discovery flow" do
    it "simulates controller discovering device during commissioning" do
      # This simulates what a controller does during commissioning

      # Step 1: Controller reads endpoint 0 descriptor
      root = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 1_u16
      )
      root.add_server(Matter::Cluster::AccessControlCluster)
        .add_server(Matter::Cluster::BasicInformationCluster)
        .add_part(1_u16)
        .add_part(2_u16)

      # Step 2: Discover device type
      device_types_tlv = root.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
      parsed = TLV::Any.from_slice(device_types_tlv.as(Bytes))
      types = parsed.value.as(Array(TLV::Any))

      root_type_hash = types[0].value.as(TLV::Structure)
      root_type = extract_int_value(root_type_hash[0_u8])
      root_type.should eq(0x0016_u32) # It's a root node

      # Step 3: Discover mandatory clusters
      servers_tlv = root.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
      parsed = TLV::Any.from_slice(servers_tlv.as(Bytes))
      clusters = parsed.value.as(Array(TLV::Any))

      cluster_ids = clusters.map { |cluster| extract_int_value(cluster) }

      # Verify mandatory root clusters present
      cluster_ids.should contain(Matter::Cluster::DescriptorCluster::CLUSTER_ID)
      cluster_ids.should contain(Matter::Cluster::AccessControlCluster::CLUSTER_ID)
      cluster_ids.should contain(Matter::Cluster::BasicInformationCluster::CLUSTER_ID)

      # Step 4: Discover child endpoints
      parts_tlv = root.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_PARTS_LIST)
      parsed = TLV::Any.from_slice(parts_tlv.as(Bytes))
      parts = parsed.value.as(Array(TLV::Any))

      child_endpoints = parts.map { |part| extract_u16_value(part) }

      child_endpoints.size.should eq(2)
      child_endpoints.should contain(1_u16)
      child_endpoints.should contain(2_u16)

      # Step 5: Controller would now query descriptors on endpoints 1 and 2
      # to build complete device model

      # This information is used to:
      # - Show correct UI in controller app
      # - Know what commands/attributes are available
      # - Enable automation rules
      # - Set up bindings between devices
    end
  end

  describe "device capability matching" do
    it "identifies device capabilities from descriptor" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      descriptor = Matter::Cluster::DescriptorCluster.new(endpoint)

      # Extended Color Light
      descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x010D_u32, # Extended Color Light
        revision: 2_u16
      )

      # Full featured color light clusters
      descriptor.add_server(Matter::Cluster::IdentifyCluster)
        .add_server(Matter::Cluster::GroupsCluster)
        .add_server(Matter::Cluster::ScenesManagementCluster)
        .add_server(Matter::Cluster::OnOffCluster)
        .add_server(Matter::Cluster::LevelControlCluster)
      descriptor.server_list << 0x0300_u32 # Color Control (not yet implemented)

      # Controller determines capabilities:
      capabilities = {
        on_off:      descriptor.has_server_cluster?(Matter::Cluster::OnOffCluster),
        dimming:     descriptor.has_server_cluster?(Matter::Cluster::LevelControlCluster),
        color:       descriptor.has_server_cluster?(0x0300_u32), # Color Control (not yet implemented)
        groups:      descriptor.has_server_cluster?(Matter::Cluster::GroupsCluster),
        scenes:      descriptor.has_server_cluster?(Matter::Cluster::ScenesManagementCluster),
        occupancy:   descriptor.has_server_cluster?(0x0406_u32), # Occupancy Sensing (not present)
        temperature: descriptor.has_server_cluster?(0x0402_u32), # Temperature Measurement (not present)
      }

      capabilities[:on_off].should be_true
      capabilities[:dimming].should be_true
      capabilities[:color].should be_true
      capabilities[:groups].should be_true
      capabilities[:scenes].should be_true
      capabilities[:occupancy].should be_false
      capabilities[:temperature].should be_false

      # Controller UI would show:
      # - On/Off button
      # - Brightness slider
      # - Color picker
      # - Group/Scene options
      # But NOT:
      # - Temperature readings
      # - Occupancy status
    end
  end

  describe "endpoint zero special requirements" do
    it "verifies endpoint 0 has all mandatory clusters" do
      # Endpoint 0 (root) MUST have specific mandatory clusters per Matter spec

      root = Matter::Cluster::DescriptorCluster.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 1_u16
      )

      # Add all mandatory clusters for root endpoint
      root.add_server(Matter::Cluster::AccessControlCluster)
        .add_server(Matter::Cluster::BasicInformationCluster)
        .add_server(Matter::Cluster::GeneralCommissioningCluster)

      # Add remaining mandatory clusters (not yet implemented)
      root.server_list << 0x0031_u32 # Network Commissioning
      root.server_list << 0x003C_u32 # Administrator Commissioning
      root.server_list << 0x003E_u32 # Operational Credentials
      root.server_list << 0x0033_u32 # Group Key Management

      # Verify all mandatory clusters present
      root.has_server_cluster?(Matter::Cluster::DescriptorCluster).should be_true
      root.has_server_cluster?(Matter::Cluster::AccessControlCluster).should be_true
      root.has_server_cluster?(Matter::Cluster::BasicInformationCluster).should be_true
      root.has_server_cluster?(Matter::Cluster::GeneralCommissioningCluster).should be_true
      root.has_server_cluster?(0x0031_u32).should be_true # Network Commissioning (not yet implemented)
      root.has_server_cluster?(0x003C_u32).should be_true # Administrator Commissioning (not yet implemented)
      root.has_server_cluster?(0x003E_u32).should be_true # Operational Credentials (not yet implemented)
      root.has_server_cluster?(0x0033_u32).should be_true # Group Key Management (not yet implemented)

      # Read and verify via TLV
      servers_tlv = root.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
      parsed = TLV::Any.from_slice(servers_tlv.as(Bytes))
      clusters = parsed.value.as(Array(TLV::Any))

      # Should have all 8 mandatory clusters
      clusters.size.should be >= 8
    end
  end
end
