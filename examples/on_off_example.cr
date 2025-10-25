require "../src/matter/cluster/on_off_cluster"
require "../src/matter/datatype/endpoint_number"

# On/Off Cluster Example
#
# The On/Off cluster (0x0006) provides binary on/off control functionality
# for lights, switches, outlets, and other devices with on/off states.

puts "Matter On/Off Cluster Example"
puts "=" * 60

# Example 1: Creating a Basic On/Off Light
# -----------------------------------------
puts "\n1. Creating a Basic On/Off Light"

endpoint = Matter::DataType::EndpointNumber.new(1_u16)
light = Matter::Cluster::OnOffCluster.new(endpoint)

puts "  Cluster ID: 0x#{light.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Name: #{light.name}"
puts "  Initial state: #{light.on_off ? "On" : "Off"}"

# Example 2: On and Off Commands
# -------------------------------
puts "\n2. On and Off Commands"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

puts "  Initial state: #{light.on_off ? "On" : "Off"}"

# Turn on
puts "\n  Turning light on..."
result = light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

if result.is_a?(Matter::InteractionModel::Status) && result.success?
  puts "    Command succeeded!"
  puts "    New state: #{light.on_off ? "On" : "Off"}"
end

# Turn off
puts "\n  Turning light off..."
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
puts "    New state: #{light.on_off ? "On" : "Off"}"

# Example 3: Toggle Command
# -------------------------
puts "\n3. Toggle Command"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

puts "  Initial state: #{light.on_off ? "On" : "Off"}"

5.times do |i|
  light.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
  puts "  Toggle #{i + 1}: #{light.on_off ? "On" : "Off"}"
end

# Example 4: Using Callbacks
# ---------------------------
puts "\n4. Using Callbacks for State Changes"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

light.on_state_changed do |state|
  status = state ? "ON" : "OFF"
  symbol = state ? "💡" : "⚫"
  puts "  #{symbol} Light is now #{status}"
end

puts "\n  Changing states with callback:"
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0)) # No change - already on
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))

# Example 5: Reading Attributes
# ------------------------------
puts "\n5. Reading Attributes"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: true)

puts "  Reading OnOff attribute:"
result = light.read_attribute(Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
if result.is_a?(Bytes)
  state = result[0] == 1
  puts "    Value: #{state ? "On" : "Off"} (raw: #{result[0]})"
end

puts "\n  Reading ClusterRevision attribute:"
result = light.read_attribute(Matter::Cluster::OnOffCluster::CLUSTER_REVISION)
if result.is_a?(Bytes)
  revision = IO::ByteFormat::LittleEndian.decode(UInt16, result)
  puts "    Value: #{revision}"
end

puts "\n  Reading FeatureMap attribute:"
result = light.read_attribute(Matter::Cluster::OnOffCluster::FEATURE_MAP)
if result.is_a?(Bytes)
  features = IO::ByteFormat::LittleEndian.decode(UInt32, result)
  puts "    Value: 0x#{features.to_s(16).upcase.rjust(8, '0')}"
end

# Example 6: OffWithEffect Command
# ---------------------------------
puts "\n6. OffWithEffect Command (Graceful Shutdown)"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: true)

puts "  Light is: #{light.on_off ? "On" : "Off"}"
puts "  Sending OffWithEffect command..."

# In a full implementation, this would trigger a fade-out effect
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF_EFFECT, Bytes.new(0))
puts "  Light is now: #{light.on_off ? "On" : "Off"}"

# Example 7: OnWithRecallGlobalScene Command
# -------------------------------------------
puts "\n7. OnWithRecallGlobalScene Command"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

puts "  Light is: #{light.on_off ? "On" : "Off"}"
puts "  Sending OnWithRecallGlobalScene command..."

# In a full implementation, this would restore the last scene state
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON_RECALL, Bytes.new(0))
puts "  Light is now: #{light.on_off ? "On" : "Off"}"

# Example 8: OnWithTimedOff Command
# ----------------------------------
puts "\n8. OnWithTimedOff Command (Auto-Off Timer)"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

puts "  Light is: #{light.on_off ? "On" : "Off"}"
puts "  Sending OnWithTimedOff command..."

# In a full implementation, this would turn on the light with an auto-off timer
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON_TIMED, Bytes.new(0))
puts "  Light is now: #{light.on_off ? "On" : "Off"}"
puts "  (In a real device, would automatically turn off after timeout)"

# Example 9: Practical Use Cases
# -------------------------------
puts "\n9. Practical Use Cases"

# Use case 1: Wall Switch
puts "\n  Use Case 1: Wall Switch Toggle"
wall_switch = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

puts "    Initial state: #{wall_switch.on_off ? "On" : "Off"}"
puts "    User presses switch..."
wall_switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
puts "    State after press: #{wall_switch.on_off ? "On" : "Off"}"
puts "    User presses switch again..."
wall_switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
puts "    State after press: #{wall_switch.on_off ? "On" : "Off"}"

# Use case 2: Smart Outlet
puts "\n  Use Case 2: Smart Outlet with Power Monitoring"
outlet = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

outlet.on_state_changed do |state|
  if state
    puts "    Outlet powered ON - Device can now draw power"
  else
    puts "    Outlet powered OFF - Device disconnected from power"
  end
end

puts "    Turning outlet on..."
outlet.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

puts "    Turning outlet off for safety..."
outlet.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))

# Use case 3: Automation Scene
puts "\n  Use Case 3: Automation Scene (Turn Off All Lights)"

lights = [
  Matter::Cluster::OnOffCluster.new(Matter::DataType::EndpointNumber.new(1_u16), on_off: true),
  Matter::Cluster::OnOffCluster.new(Matter::DataType::EndpointNumber.new(2_u16), on_off: true),
  Matter::Cluster::OnOffCluster.new(Matter::DataType::EndpointNumber.new(3_u16), on_off: false),
]

puts "    Initial states:"
lights.each_with_index do |light, i|
  puts "      Light #{i + 1}: #{light.on_off ? "On" : "Off"}"
end

puts "\n    Executing 'All Off' scene..."
lights.each do |light|
  light.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
end

puts "    Final states:"
lights.each_with_index do |light, i|
  puts "      Light #{i + 1}: #{light.on_off ? "On" : "Off"}"
end

# Example 10: State Tracking with Multiple Devices
# -------------------------------------------------
puts "\n10. State Tracking with Multiple Devices"

# Create multiple devices
devices = {
  "Living Room" => Matter::Cluster::OnOffCluster.new(Matter::DataType::EndpointNumber.new(1_u16), on_off: false),
  "Bedroom"     => Matter::Cluster::OnOffCluster.new(Matter::DataType::EndpointNumber.new(2_u16), on_off: false),
  "Kitchen"     => Matter::Cluster::OnOffCluster.new(Matter::DataType::EndpointNumber.new(3_u16), on_off: true),
  "Bathroom"    => Matter::Cluster::OnOffCluster.new(Matter::DataType::EndpointNumber.new(4_u16), on_off: false),
}

# Add callbacks to track state changes
devices.each do |name, device|
  device.on_state_changed do |state|
    puts "    [#{name}] changed to: #{state ? "On" : "Off"}"
  end
end

puts "\n  Current status:"
devices.each do |name, device|
  puts "    #{name}: #{device.on_off ? "On" : "Off"}"
end

puts "\n  Turning on all lights..."
devices.each do |name, device|
  device.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
end

puts "\n  Final status:"
devices.each do |name, device|
  puts "    #{name}: #{device.on_off ? "On" : "Off"}"
end

# Example 11: Data Versioning
# ----------------------------
puts "\n11. Data Versioning (Change Detection)"

light = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

puts "  Initial data version: #{light.data_version}"
puts "  Initial state: #{light.on_off ? "On" : "Off"}"

# Change state
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
puts "\n  After turning on:"
puts "    Data version: #{light.data_version} (incremented)"
puts "    State: #{light.on_off ? "On" : "Off"}"

# Try to turn on again (no state change)
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
puts "\n  After turning on again (already on):"
puts "    Data version: #{light.data_version} (not incremented - no change)"
puts "    State: #{light.on_off ? "On" : "Off"}"

# Change state again
light.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
puts "\n  After toggle:"
puts "    Data version: #{light.data_version} (incremented)"
puts "    State: #{light.on_off ? "On" : "Off"}"

# Example 12: Different Device Types
# -----------------------------------
puts "\n12. Different Device Types Using On/Off"

# Fan
fan = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)
puts "\n  Ceiling Fan Control:"
puts "    Current state: #{fan.on_off ? "Running" : "Stopped"}"
fan.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
puts "    New state: #{fan.on_off ? "Running" : "Stopped"}"

# Coffee maker
coffee = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)
puts "\n  Coffee Maker Control:"
puts "    Current state: #{coffee.on_off ? "Brewing" : "Off"}"
coffee.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
puts "    New state: #{coffee.on_off ? "Brewing" : "Off"}"

# Outdoor lights
outdoor = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)
puts "\n  Outdoor Lights Control:"
puts "    Current state: #{outdoor.on_off ? "On" : "Off"}"
outdoor.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
puts "    New state: #{outdoor.on_off ? "On" : "Off"}"

puts "\n" + "=" * 60
puts "Example complete!"
puts "\nKey Takeaways:"
puts "  • On/Off cluster provides simple binary control (true/false)"
puts "  • Toggle command is useful for switches that don't track state"
puts "  • Callbacks enable reactive behavior on state changes"
puts "  • Callbacks only fire when state actually changes (optimized)"
puts "  • Data version increments only on actual state changes"
puts "  • OffWithEffect, OnWithRecallGlobalScene, OnWithTimedOff for advanced use"
puts "  • Same cluster works for lights, outlets, fans, and other on/off devices"
