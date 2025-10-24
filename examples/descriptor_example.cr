require "../src/matter/cluster/descriptor_cluster"
require "../src/matter/datatype/endpoint_number"

# Descriptor Cluster Example
#
# The Descriptor cluster is required on all endpoints and provides
# device composition information. This example demonstrates:
# - Creating a root endpoint with device types
# - Configuring server and client clusters
# - Setting up endpoint hierarchy with parts list
# - Reading descriptor attributes

puts "Matter Descriptor Cluster Example"
puts "=" * 50

# Example 1: Root Node Endpoint (Endpoint 0)
# --------------------------------------------
puts "\n1. Root Node Endpoint (Endpoint 0)"

root_endpoint = Matter::DataType::EndpointNumber.new(0_u16)
root_descriptor = Matter::Cluster::DescriptorCluster.new(root_endpoint)

# Set device type: Root Node (0x0016)
root_descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
  device_type: 0x0016_u32, # Root Node
  revision: 1_u16
)

# Add mandatory server clusters for root node
# (Descriptor is already added automatically)
root_descriptor.server_list << 0x001F_u32 # Access Control
root_descriptor.server_list << 0x0028_u32 # Basic Information
root_descriptor.server_list << 0x0030_u32 # General Commissioning
root_descriptor.server_list << 0x0031_u32 # Network Commissioning
root_descriptor.server_list << 0x003C_u32 # Administrator Commissioning
root_descriptor.server_list << 0x003E_u32 # Operational Credentials

# Add child endpoints
root_descriptor.parts_list << 1_u16
root_descriptor.parts_list << 2_u16

puts "  Cluster ID: 0x#{root_descriptor.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Device Type: 0x#{root_descriptor.primary_device_type.not_nil!.device_type.to_s(16).upcase.rjust(4, '0')} (Root Node)"
puts "  Server Clusters: #{root_descriptor.server_list.size}"
root_descriptor.server_list.each do |cluster_id|
  puts "    - 0x#{cluster_id.to_s(16).upcase.rjust(4, '0')}"
end
puts "  Child Endpoints: #{root_descriptor.parts_list.join(", ")}"

# Example 2: On/Off Light Endpoint (Endpoint 1)
# ----------------------------------------------
puts "\n2. On/Off Light Endpoint (Endpoint 1)"

light_endpoint = Matter::DataType::EndpointNumber.new(1_u16)
light_descriptor = Matter::Cluster::DescriptorCluster.new(light_endpoint)

# Set device type: On/Off Light (0x0100)
light_descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
  device_type: 0x0100_u32, # On/Off Light
  revision: 2_u16
)

# Add server clusters
light_descriptor.server_list << 0x0003_u32 # Identify
light_descriptor.server_list << 0x0004_u32 # Groups
light_descriptor.server_list << 0x0005_u32 # Scenes
light_descriptor.server_list << 0x0006_u32 # On/Off

# No client clusters for this light
# No child endpoints (leaf endpoint)

puts "  Cluster ID: 0x#{light_descriptor.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Device Type: 0x#{light_descriptor.primary_device_type.not_nil!.device_type.to_s(16).upcase.rjust(4, '0')} (On/Off Light)"
puts "  Server Clusters: #{light_descriptor.server_list.size}"
light_descriptor.server_list.each do |cluster_id|
  puts "    - 0x#{cluster_id.to_s(16).upcase.rjust(4, '0')}"
end
puts "  Client Clusters: #{light_descriptor.client_list.size}"
puts "  Parts List: empty (leaf endpoint)"

# Example 3: Dimmable Light Endpoint (Endpoint 2)
# -----------------------------------------------
puts "\n3. Dimmable Light Endpoint (Endpoint 2)"

dimmable_endpoint = Matter::DataType::EndpointNumber.new(2_u16)
dimmable_descriptor = Matter::Cluster::DescriptorCluster.new(dimmable_endpoint)

# Set device type: Dimmable Light (0x0101)
dimmable_descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
  device_type: 0x0101_u32, # Dimmable Light
  revision: 2_u16
)

# Add server clusters
dimmable_descriptor.server_list << 0x0003_u32 # Identify
dimmable_descriptor.server_list << 0x0004_u32 # Groups
dimmable_descriptor.server_list << 0x0005_u32 # Scenes
dimmable_descriptor.server_list << 0x0006_u32 # On/Off
dimmable_descriptor.server_list << 0x0008_u32 # Level Control

puts "  Cluster ID: 0x#{dimmable_descriptor.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Device Type: 0x#{dimmable_descriptor.primary_device_type.not_nil!.device_type.to_s(16).upcase.rjust(4, '0')} (Dimmable Light)"
puts "  Server Clusters: #{dimmable_descriptor.server_list.size}"
dimmable_descriptor.server_list.each do |cluster_id|
  puts "    - 0x#{cluster_id.to_s(16).upcase.rjust(4, '0')}"
end

# Example 4: Using Helper Methods
# --------------------------------
puts "\n4. Helper Methods"

puts "  Root endpoint has server cluster 0x001F? #{root_descriptor.has_server_cluster?(0x001F_u32)}"
puts "  Root endpoint has server cluster 0x9999? #{root_descriptor.has_server_cluster?(0x9999_u32)}"
puts "  Root endpoint has part 1? #{root_descriptor.has_part?(1_u16)}"
puts "  Root endpoint has part 99? #{root_descriptor.has_part?(99_u16)}"

# Example 5: Reading Attributes
# ------------------------------
puts "\n5. Reading Attributes"

device_type_result = light_descriptor.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST)
if device_type_result.is_a?(Bytes)
  puts "  DeviceTypeList attribute: #{device_type_result.size} bytes"
  puts "  (Simplified implementation - TODO: TLV encoding)"
end

server_list_result = light_descriptor.read_attribute(Matter::Cluster::DescriptorCluster::ATTR_SERVER_LIST)
if server_list_result.is_a?(Bytes)
  puts "  ServerList attribute: #{server_list_result.size} bytes"
  puts "  (Simplified implementation - TODO: TLV encoding)"
end

# Example 6: Multi-Device Type Endpoint
# --------------------------------------
puts "\n6. Bridge with Multiple Device Types"

bridge_endpoint = Matter::DataType::EndpointNumber.new(0_u16)
bridge_descriptor = Matter::Cluster::DescriptorCluster.new(bridge_endpoint)

# A bridge can have multiple device types
bridge_descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
  device_type: 0x0016_u32, # Root Node
  revision: 1_u16
)
bridge_descriptor.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
  device_type: 0x000E_u32, # Aggregator (Bridge)
  revision: 1_u16
)

puts "  Device Types: #{bridge_descriptor.device_type_list.size}"
bridge_descriptor.device_type_list.each do |dt|
  puts "    - 0x#{dt.device_type.to_s(16).upcase.rjust(4, '0')} (revision #{dt.revision})"
end

puts "\n" + "=" * 50
puts "Example complete!"
