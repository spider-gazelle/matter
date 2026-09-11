require "../spec_helper"
require "../../src/matter/cluster/descriptor"
require "../../src/matter/cluster/access_control"
require "../../src/matter/cluster/basic_information"
require "../../src/matter/cluster/general_commissioning"
require "../../src/matter/cluster/administrator_commissioning"
require "../../src/matter/cluster/operational_credentials"
require "../../src/matter/cluster/network_commissioning"
require "../../src/matter/cluster/identify"
require "../../src/matter/cluster/on_off"
require "../../src/matter/cluster/level_control"
require "../../src/matter/cluster/color_control"
require "../../src/matter/cluster/groups"
require "../../src/matter/cluster/scenes_management"
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
      descriptor = Matter::Cluster::Descriptor.new(endpoint_id)

      # Device Type: On/Off Light (0x0100)
      descriptor.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32,
        revision: 2_u16
      )

      # Server Clusters (capabilities this endpoint provides)
      # Descriptor is already added automatically
      descriptor.add_server(Matter::Cluster::Identify)
        .add_server(Matter::Cluster::Groups)
        .add_server(Matter::Cluster::ScenesManagement)
        .add_server(Matter::Cluster::OnOff)

      # No client clusters (this device doesn't control other devices)
      # No parts list (this is a leaf endpoint)

      # Verify device type can be discovered
      primary_type = descriptor.primary_device_type
      primary_type.should_not be_nil
      primary_type.as(Matter::Cluster::Descriptor::DeviceTypeStruct).device_type.should eq(0x0100_u32)

      # Controller would read this over the network
      # Decode to see what controller sees
      types = read_tlv(descriptor, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST).as_list
      types.size.should eq(1)

      # Controller knows this is an On/Off Light
      type_hash = types[0].value.as(TLV::Structure)
      device_type = extract_int_value(type_hash[0_u8])
      device_type.should eq(0x0100_u32)

      # Controller discovers available clusters
      clusters = read_tlv(descriptor, Matter::Cluster::Descriptor::ATTR_SERVER_LIST).as_list
      clusters.size.should eq(5) # Descriptor + Identify + Groups + Scenes Management + On/Off

      # Controller knows it can control this light via On/Off cluster
      descriptor.has_server_cluster?(Matter::Cluster::OnOff).should be_true
    end
  end

  describe "dimmable light device" do
    it "describes a dimmable light with multiple device types" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      descriptor = Matter::Cluster::Descriptor.new(endpoint_id)

      # Device Types: Dimmable Light (0x0101) which also includes On/Off Light
      # In Matter, device types can be composed
      descriptor.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0101_u32, # Dimmable Light
        revision: 2_u16
      )

      # Server Clusters
      descriptor.add_server(Matter::Cluster::Identify)
        .add_server(Matter::Cluster::OnOff)
        .add_server(Matter::Cluster::LevelControl) # dimming

      # Verify controller sees dimming capability
      descriptor.has_server_cluster?(Matter::Cluster::LevelControl).should be_true

      # Read server list
      clusters = read_tlv(descriptor, Matter::Cluster::Descriptor::ATTR_SERVER_LIST).as_list

      # Convert to cluster IDs
      cluster_ids = clusters.map { |cluster| extract_int_value(cluster) }

      # Controller knows it can dim this light
      cluster_ids.should contain(Matter::Cluster::LevelControl::CLUSTER_ID)
    end
  end

  describe "root endpoint with child endpoints" do
    it "describes device hierarchy with parts list" do
      # Endpoint 0: Root Node (aggregator for child endpoints)
      root_endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      root_descriptor = Matter::Cluster::Descriptor.new(root_endpoint)

      # Device Type: Root Node (0x0016)
      root_descriptor.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0016_u32,
        revision: 1_u16
      )

      # Root endpoint has all the mandatory commissioning clusters
      root_descriptor.add_server(Matter::Cluster::AccessControl)
        .add_server(Matter::Cluster::BasicInformation)
        .add_server(Matter::Cluster::GeneralCommissioning)
        .add_server(Matter::Cluster::NetworkCommissioning)
        .add_server(Matter::Cluster::AdministratorCommissioning)
        .add_server(Matter::Cluster::OperationalCredentials)
      # Note: Group Key Management cluster not yet implemented

      # Parts list tells controller about child endpoints
      root_descriptor.add_part(1_u16) # First light
        .add_part(2_u16)              # Second light

      # Controller reads parts list to discover endpoints
      parts = read_tlv(root_descriptor, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list
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
      root = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 1_u16
      )
      root.add_server(Matter::Cluster::AccessControl)
        .add_server(Matter::Cluster::BasicInformation)
        .add_server(Matter::Cluster::GeneralCommissioning)
        .add_part(1_u16)
        .add_part(2_u16)

      # Endpoint 1: First Light
      light1 = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(1_u16))
      light1.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )
      light1.add_server(Matter::Cluster::Identify)
        .add_server(Matter::Cluster::OnOff)

      # Endpoint 2: Second Light
      light2 = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(2_u16))
      light2.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )
      light2.add_server(Matter::Cluster::Identify)
        .add_server(Matter::Cluster::OnOff)

      # Controller discovery flow:
      # 1. Read endpoint 0 descriptor
      child_endpoints = read_tlv(root, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list
      child_endpoints.size.should eq(2)

      # 2. Read each child endpoint descriptor
      types1 = read_tlv(light1, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST).as_list
      types1.size.should eq(1)

      types2 = read_tlv(light2, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST).as_list
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
      root = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x000E_u32, # Aggregator (bridge)
        revision: 1_u16
      )
      root.add_server(Matter::Cluster::AccessControl)
        .add_server(Matter::Cluster::BasicInformation)
      root.server_list << 0x0039_u32 # Bridged Device Basic Information (not yet implemented)

      # Bridge can have many bridged devices
      # Let's add 5 bridged light endpoints
      5.times do |i|
        root.parts_list << (i + 1).to_u16
      end

      # Verify bridge structure
      root.primary_device_type.as(Matter::Cluster::Descriptor::DeviceTypeStruct).device_type.should eq(0x000E_u32)
      root.parts_list.size.should eq(5)

      # Each bridged device would have its own endpoint with descriptor
      bridged_light = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(1_u16))
      bridged_light.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0100_u32, # On/Off Light
        revision: 2_u16
      )
      bridged_light.add_server(Matter::Cluster::Identify)
        .add_server(Matter::Cluster::OnOff)
      bridged_light.server_list << 0x0039_u32 # Bridged Device Basic Information (not yet implemented)

      # Controller can discover all bridged devices
      bridged_endpoints = read_tlv(root, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list
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
      switch = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(1_u16))

      # Device Type: On/Off Light Switch (0x0103)
      switch.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0103_u32,
        revision: 2_u16
      )

      # Server clusters (capabilities this device provides)
      switch.add_server(Matter::Cluster::Identify)
      switch.server_list << 0x003B_u32 # Switch (not yet implemented)

      # Client clusters (this device can control other devices)
      switch.add_client(Matter::Cluster::OnOff)
        .add_client(Matter::Cluster::LevelControl)

      # Verify binding capabilities
      switch.has_client_cluster?(Matter::Cluster::OnOff).should be_true
      switch.has_client_cluster?(Matter::Cluster::LevelControl).should be_true

      # Controller reads client list to know what this device can control
      clients = read_tlv(switch, Matter::Cluster::Descriptor::ATTR_CLIENT_LIST).as_list
      clients.size.should eq(2)

      client_ids = clients.map { |client| extract_int_value(client) }

      # Controller knows this switch can be bound to On/Off and Level Control devices
      client_ids.should contain(Matter::Cluster::OnOff::CLUSTER_ID)
      client_ids.should contain(Matter::Cluster::LevelControl::CLUSTER_ID)
    end
  end

  describe "commissioning discovery flow" do
    it "simulates controller discovering device during commissioning" do
      # This simulates what a controller does during commissioning

      # Step 1: Controller reads endpoint 0 descriptor
      root = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 1_u16
      )
      root.add_server(Matter::Cluster::AccessControl)
        .add_server(Matter::Cluster::BasicInformation)
        .add_part(1_u16)
        .add_part(2_u16)

      # Step 2: Discover device type
      types = read_tlv(root, Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST).as_list

      root_type_hash = types[0].value.as(TLV::Structure)
      root_type = extract_int_value(root_type_hash[0_u8])
      root_type.should eq(0x0016_u32) # It's a root node

      # Step 3: Discover mandatory clusters
      clusters = read_tlv(root, Matter::Cluster::Descriptor::ATTR_SERVER_LIST).as_list

      cluster_ids = clusters.map { |cluster| extract_int_value(cluster) }

      # Verify mandatory root clusters present
      cluster_ids.should contain(Matter::Cluster::Descriptor::CLUSTER_ID)
      cluster_ids.should contain(Matter::Cluster::AccessControl::CLUSTER_ID)
      cluster_ids.should contain(Matter::Cluster::BasicInformation::CLUSTER_ID)

      # Step 4: Discover child endpoints
      parts = read_tlv(root, Matter::Cluster::Descriptor::ATTR_PARTS_LIST).as_list

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
      descriptor = Matter::Cluster::Descriptor.new(endpoint)

      # Extended Color Light
      descriptor.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x010D_u32, # Extended Color Light
        revision: 2_u16
      )

      # Full featured color light clusters
      descriptor.add_server(Matter::Cluster::Identify)
        .add_server(Matter::Cluster::Groups)
        .add_server(Matter::Cluster::ScenesManagement)
        .add_server(Matter::Cluster::OnOff)
        .add_server(Matter::Cluster::LevelControl)
      descriptor.server_list << 0x0300_u32 # Color Control (not yet implemented)

      # Controller determines capabilities:
      capabilities = {
        on_off:      descriptor.has_server_cluster?(Matter::Cluster::OnOff),
        dimming:     descriptor.has_server_cluster?(Matter::Cluster::LevelControl),
        color:       descriptor.has_server_cluster?(0x0300_u32), # Color Control (not yet implemented)
        groups:      descriptor.has_server_cluster?(Matter::Cluster::Groups),
        scenes:      descriptor.has_server_cluster?(Matter::Cluster::ScenesManagement),
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

      root = Matter::Cluster::Descriptor.new(Matter::DataType::EndpointNumber.new(0_u16))
      root.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: 0x0016_u32, # Root Node
        revision: 1_u16
      )

      # Add all mandatory clusters for root endpoint
      root.add_server(Matter::Cluster::AccessControl)
        .add_server(Matter::Cluster::BasicInformation)
        .add_server(Matter::Cluster::GeneralCommissioning)

      # Add remaining mandatory clusters (not yet implemented)
      root.server_list << 0x0031_u32 # Network Commissioning
      root.server_list << 0x003C_u32 # Administrator Commissioning
      root.server_list << 0x003E_u32 # Operational Credentials
      root.server_list << 0x0033_u32 # Group Key Management

      # Verify all mandatory clusters present
      root.has_server_cluster?(Matter::Cluster::Descriptor).should be_true
      root.has_server_cluster?(Matter::Cluster::AccessControl).should be_true
      root.has_server_cluster?(Matter::Cluster::BasicInformation).should be_true
      root.has_server_cluster?(Matter::Cluster::GeneralCommissioning).should be_true
      root.has_server_cluster?(0x0031_u32).should be_true # Network Commissioning (not yet implemented)
      root.has_server_cluster?(0x003C_u32).should be_true # Administrator Commissioning (not yet implemented)
      root.has_server_cluster?(0x003E_u32).should be_true # Operational Credentials (not yet implemented)
      root.has_server_cluster?(0x0033_u32).should be_true # Group Key Management (not yet implemented)

      # Read and verify via TLV
      clusters = read_tlv(root, Matter::Cluster::Descriptor::ATTR_SERVER_LIST).as_list

      # Should have all 8 mandatory clusters
      clusters.size.should be >= 8
    end
  end
end
