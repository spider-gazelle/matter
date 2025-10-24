require "../src/matter/cluster/basic_information_cluster"
require "../src/matter/datatype/endpoint_number"

# Basic Information Cluster Example
#
# The Basic Information cluster (0x0028) is required on endpoint 0 (root node)
# and provides device metadata including vendor info, product info, versions,
# and manufacturing details.

puts "Matter Basic Information Cluster Example"
puts "=" * 60

# Example 1: Minimal Configuration
# ---------------------------------
puts "\n1. Minimal Device Configuration"

endpoint = Matter::DataType::EndpointNumber.new(0_u16)
minimal = Matter::Cluster::BasicInformationCluster.new(endpoint)

puts "  Cluster ID: 0x#{minimal.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Name: #{minimal.name}"
puts "  Data Model Revision: #{minimal.data_model_revision}"
puts "  Vendor Name: '#{minimal.vendor_name}'"
puts "  Vendor ID: 0x#{minimal.vendor_id.to_s(16).upcase.rjust(4, '0')}"
puts "  Product Name: '#{minimal.product_name}'"
puts "  Product ID: 0x#{minimal.product_id.to_s(16).upcase.rjust(4, '0')}"
puts "  Location: #{minimal.location}"
puts "  Reachable: #{minimal.reachable}"

# Example 2: Complete Device Configuration
# -----------------------------------------
puts "\n2. Complete Device Configuration"

complete = Matter::Cluster::BasicInformationCluster.new(
  endpoint,
  vendor_name: "SmartHome Technologies Inc",
  vendor_id: 0xFFF1_u16,
  product_name: "WiFi Smart Bulb Pro",
  product_id: 0x8001_u16,
  node_label: "Living Room Light",
  location: "US",
  hardware_version: 3_u16,
  hardware_version_string: "3.1",
  software_version: 0x01020304_u32,
  software_version_string: "1.2.3.4",
  manufacturing_date: "20231215",
  part_number: "BULB-PRO-001",
  product_url: "https://smarthome.example/bulb-pro",
  product_label: "Premium Edition",
  serial_number: "SN987654321ABC",
  unique_id: "UUID-1234-5678-90AB-CDEF"
)

puts "  Vendor: #{complete.vendor_name} (0x#{complete.vendor_id.to_s(16).upcase.rjust(4, '0')})"
puts "  Product: #{complete.product_name} (0x#{complete.product_id.to_s(16).upcase.rjust(4, '0')})"
puts "  Node Label: '#{complete.node_label}'"
puts "  Location: #{complete.location}"
puts "  Hardware: v#{complete.hardware_version} (#{complete.hardware_version_string})"
puts "  Software: v#{complete.software_version} (#{complete.software_version_string})"
puts "  Manufacturing Date: #{complete.manufacturing_date}"
puts "  Part Number: #{complete.part_number}"
puts "  Serial Number: #{complete.serial_number}"
puts "  Product URL: #{complete.product_url}"
puts "  Product Label: #{complete.product_label}"
puts "  Unique ID: #{complete.unique_id}"
puts "  Reachable: #{complete.reachable}"

# Example 3: Product Appearance
# ------------------------------
puts "\n3. Product Appearance Configuration"

appearance = Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
  finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Matte,
  primary_color: Matter::Cluster::BasicInformationCluster::Color::White
)

device_with_appearance = Matter::Cluster::BasicInformationCluster.new(
  endpoint,
  vendor_name: "Design Co",
  product_name: "Modern Switch",
  product_appearance: appearance
)

if pa = device_with_appearance.product_appearance
  puts "  Product: #{device_with_appearance.product_name}"
  puts "  Finish: #{pa.finish}"
  puts "  Primary Color: #{pa.primary_color}"
end

# Example 4: Different Product Finishes and Colors
# -------------------------------------------------
puts "\n4. Available Product Finishes:"
Matter::Cluster::BasicInformationCluster::ProductFinish.values.each do |finish|
  puts "  - #{finish} (#{finish.value})"
end

puts "\n5. Available Colors:"
Matter::Cluster::BasicInformationCluster::Color.values.each do |color|
  puts "  - #{color} (#{color.value})"
end

# Example 6: Capability Minima
# -----------------------------
puts "\n6. Capability Minima Configuration"

capability = Matter::Cluster::BasicInformationCluster::CapabilityMinimaStruct.new(
  case_sessions_per_fabric: 5_u16,
  subscriptions_per_fabric: 5_u16
)

high_capability = Matter::Cluster::BasicInformationCluster.new(
  endpoint,
  vendor_name: "Enterprise Solutions",
  product_name: "Industrial Gateway",
  capability_minima: capability
)

puts "  Device: #{high_capability.product_name}"
puts "  CASE Sessions per Fabric: #{high_capability.capability_minima.case_sessions_per_fabric}"
puts "  Subscriptions per Fabric: #{high_capability.capability_minima.subscriptions_per_fabric}"

# Example 7: Reading Attributes
# ------------------------------
puts "\n7. Reading Attributes"

puts "  Reading VendorID attribute:"
vendor_id_result = complete.read_attribute(
  Matter::Cluster::BasicInformationCluster::ATTR_VENDOR_ID
)
if vendor_id_result.is_a?(Bytes)
  puts "    Encoded as #{vendor_id_result.size} bytes: #{vendor_id_result.to_a.inspect}"
end

puts "  Reading HardwareVersion attribute:"
hw_result = complete.read_attribute(
  Matter::Cluster::BasicInformationCluster::ATTR_HARDWARE_VERSION
)
if hw_result.is_a?(Bytes)
  puts "    Encoded as #{hw_result.size} bytes: #{hw_result.to_a.inspect}"
end

puts "  Reading Reachable attribute:"
reachable_result = complete.read_attribute(
  Matter::Cluster::BasicInformationCluster::ATTR_REACHABLE
)
if reachable_result.is_a?(Bytes)
  puts "    Encoded as #{reachable_result.size} bytes: #{reachable_result.to_a.inspect}"
end

# Example 8: Writing Attributes
# ------------------------------
puts "\n8. Writing User-Configurable Attributes"

writable_device = Matter::Cluster::BasicInformationCluster.new(
  endpoint,
  vendor_name: "Acme Corp",
  product_name: "Smart Sensor"
)

puts "  Initial node label: '#{writable_device.node_label}'"
puts "  Initial location: #{writable_device.location}"
puts "  Initial data version: #{writable_device.data_version}"

# Note: TLV encoding/decoding not implemented yet, so writes succeed but don't update values
status = writable_device.write_attribute(
  Matter::Cluster::BasicInformationCluster::ATTR_NODE_LABEL,
  "Bedroom Sensor".to_slice
)
puts "  Write NodeLabel status: #{status.as(Matter::InteractionModel::Status).success? ? "Success" : "Failed"}"
puts "  Data version after write: #{writable_device.data_version}"

status = writable_device.write_attribute(
  Matter::Cluster::BasicInformationCluster::ATTR_LOCATION,
  "UK".to_slice
)
puts "  Write Location status: #{status.as(Matter::InteractionModel::Status).success? ? "Success" : "Failed"}"
puts "  Data version after write: #{writable_device.data_version}"

# Example 9: Attribute Metadata
# ------------------------------
puts "\n9. Attribute Metadata"

device = Matter::Cluster::BasicInformationCluster.new(endpoint)
attrs = device.attributes

puts "  Total attributes: #{attrs.size}"
puts "  Writable attributes:"
attrs.select(&.writable).each do |attr|
  puts "    - #{attr.name} (0x#{attr.id.id.to_s(16).upcase.rjust(4, '0')})"
end

# Example 10: Events
# -------------------
puts "\n10. Supported Events"

events = device.events
puts "  Total events: #{events.size}"
events.each do |event|
  puts "    - #{event.name} (0x#{event.id.id.to_s(16).upcase.rjust(2, '0')}) - Priority: #{event.priority}"
end

# Example 11: Different Device Types
# -----------------------------------
puts "\n11. Different Device Type Examples"

# Smart Light
light = Matter::Cluster::BasicInformationCluster.new(
  endpoint,
  vendor_name: "Lighting Inc",
  product_name: "RGB Smart Bulb",
  product_id: 0x0100_u16,
  hardware_version: 2_u16,
  software_version: 0x00010203_u32,
  product_appearance: Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
    finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Polished,
    primary_color: Matter::Cluster::BasicInformationCluster::Color::White
  )
)

puts "\n  Smart Light:"
puts "    Product: #{light.product_name}"
puts "    HW Version: #{light.hardware_version}, SW Version: #{light.software_version}"

# Smart Lock
lock = Matter::Cluster::BasicInformationCluster.new(
  endpoint,
  vendor_name: "SecureHome",
  product_name: "Smart Deadbolt",
  product_id: 0x000A_u16,
  hardware_version: 5_u16,
  software_version: 0x02000100_u32,
  product_appearance: Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
    finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Satin,
    primary_color: Matter::Cluster::BasicInformationCluster::Color::Nickel
  )
)

puts "\n  Smart Lock:"
puts "    Product: #{lock.product_name}"
puts "    HW Version: #{lock.hardware_version}, SW Version: #{lock.software_version}"

# Thermostat
thermostat = Matter::Cluster::BasicInformationCluster.new(
  endpoint,
  vendor_name: "Climate Control Systems",
  product_name: "Smart Thermostat Pro",
  product_id: 0x0301_u16,
  hardware_version: 3_u16,
  hardware_version_string: "3.2",
  software_version: 0x03020100_u32,
  software_version_string: "3.2.1.0",
  product_appearance: Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
    finish: Matter::Cluster::BasicInformationCluster::ProductFinish::Matte,
    primary_color: Matter::Cluster::BasicInformationCluster::Color::White
  )
)

puts "\n  Smart Thermostat:"
puts "    Product: #{thermostat.product_name}"
puts "    HW Version: #{thermostat.hardware_version_string}"
puts "    SW Version: #{thermostat.software_version_string}"

puts "\n" + "=" * 60
puts "Example complete!"
puts "\nNote: String attributes return empty bytes (TODO: TLV encoding)"
puts "      Write operations succeed but don't update values (TODO: TLV decoding)"
