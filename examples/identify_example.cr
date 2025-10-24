require "../src/matter/cluster/identify_cluster"
require "../src/matter/datatype/endpoint_number"

# Identify Cluster Example
#
# The Identify cluster (0x0003) provides an interface for a device to
# identify itself to a user (e.g., by flashing a light, sounding a beep,
# displaying a message).
#
# Commonly required on many device types for commissioning and user interaction.

puts "Matter Identify Cluster Example"
puts "=" * 60

# Example 1: Creating Identify Clusters with Different Types
# -----------------------------------------------------------
puts "\n1. Different Identify Types"

endpoint = Matter::DataType::EndpointNumber.new(1_u16)

# Light-based identification
light_identify = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
)

puts "  Light Device:"
puts "    Cluster ID: 0x#{light_identify.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "    Identify Type: #{light_identify.identify_type}"
puts "    Currently Identifying: #{light_identify.identifying?}"

# LED-based identification
led_identify = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED
)

puts "\n  LED Device:"
puts "    Identify Type: #{led_identify.identify_type}"

# Audible identification
beep_identify = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::AudibleBeep
)

puts "\n  Beeper Device:"
puts "    Identify Type: #{beep_identify.identify_type}"

# Display-based identification
display_identify = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::Display
)

puts "\n  Display Device:"
puts "    Identify Type: #{display_identify.identify_type}"

# Actuator-based identification
actuator_identify = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::Actuator
)

puts "\n  Actuator Device (e.g., lock):"
puts "    Identify Type: #{actuator_identify.identify_type}"

# Example 2: Using the Identify Command
# --------------------------------------
puts "\n2. Executing Identify Command"

cluster = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
)

puts "  Initial state:"
puts "    Identify Time: #{cluster.identify_time}s"
puts "    Identifying?: #{cluster.identifying?}"

# Invoke identify command with 60 second duration
puts "\n  Invoking Identify command (60 seconds)..."
result = cluster.invoke_command(
  Matter::Cluster::IdentifyCluster::CMD_IDENTIFY,
  Bytes[60, 0] # 60 seconds in little-endian UInt16
)

if result.is_a?(Matter::InteractionModel::Status) && result.success?
  puts "    Command succeeded!"
  puts "    Identify Time: #{cluster.identify_time}s"
  puts "    Identifying?: #{cluster.identifying?}"
end

# Stop identifying
puts "\n  Stopping identification..."
cluster.invoke_command(
  Matter::Cluster::IdentifyCluster::CMD_IDENTIFY,
  Bytes[0, 0] # 0 seconds stops identification
)

puts "    Identify Time: #{cluster.identify_time}s"
puts "    Identifying?: #{cluster.identifying?}"

# Example 3: Writing IdentifyTime Attribute
# ------------------------------------------
puts "\n3. Writing IdentifyTime Attribute"

cluster = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED
)

puts "  Writing 30 seconds to IdentifyTime attribute..."
status = cluster.write_attribute(
  Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME,
  Bytes[30, 0]
)

if status.success?
  puts "    Write succeeded!"
  puts "    Identify Time: #{cluster.identify_time}s"
  puts "    Data Version: #{cluster.data_version}"
end

# Example 4: TriggerEffect Command
# ---------------------------------
puts "\n4. TriggerEffect Command"

cluster = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
)

puts "  Available Effects:"
Matter::Cluster::IdentifyCluster::EffectIdentifier.values.each do |effect|
  puts "    - #{effect} (#{effect.value})"
end

puts "\n  Triggering Blink effect..."
result = cluster.invoke_command(
  Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT,
  Bytes[
    Matter::Cluster::IdentifyCluster::EffectIdentifier::Blink.value,
    Matter::Cluster::IdentifyCluster::EffectVariant::Default.value,
  ]
)

if result.is_a?(Matter::InteractionModel::Status) && result.success?
  puts "    Blink effect triggered!"
end

puts "\n  Triggering Breathe effect..."
cluster.invoke_command(
  Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT,
  Bytes[
    Matter::Cluster::IdentifyCluster::EffectIdentifier::Breathe.value,
    Matter::Cluster::IdentifyCluster::EffectVariant::Default.value,
  ]
)
puts "    Breathe effect triggered!"

# Example 5: Using Callbacks
# ---------------------------
puts "\n5. Using Callbacks"

cluster = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED
)

# Set callback for when identification starts
cluster.on_identify_started do
  puts "  ➤ Identification STARTED!"
end

# Set callback for when identification stops
cluster.on_identify_stopped do
  puts "  ➤ Identification STOPPED!"
end

# Set callback for effects
cluster.on_trigger_effect do |effect, variant|
  puts "  ➤ Effect triggered: #{effect} (variant: #{variant})"
end

puts "\n  Starting identification for 5 seconds..."
cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, Bytes[5, 0])

puts "\n  Stopping identification..."
cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, Bytes[0, 0])

puts "\n  Triggering Okay effect..."
cluster.invoke_command(
  Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT,
  Bytes[
    Matter::Cluster::IdentifyCluster::EffectIdentifier::Okay.value,
    Matter::Cluster::IdentifyCluster::EffectVariant::Default.value,
  ]
)

# Example 6: Timer Tick Functionality
# ------------------------------------
puts "\n6. Timer Tick Functionality"

cluster = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::AudibleBeep
)

callback_count = 0
cluster.on_identify_stopped do
  callback_count += 1
  puts "  ➤ Stopped callback triggered (count: #{callback_count})"
end

puts "\n  Setting identify time to 3 seconds..."
cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, Bytes[3, 0])
puts "    Identify Time: #{cluster.identify_time}s"

puts "\n  Simulating timer ticks (1 second intervals)..."
3.times do |i|
  puts "    Tick #{i + 1}..."
  cluster.tick
  puts "      Remaining: #{cluster.identify_time}s, Identifying?: #{cluster.identifying?}"
end

puts "    Final state - Identifying?: #{cluster.identifying?}"

# Example 7: Reading Attributes
# ------------------------------
puts "\n7. Reading Attributes"

cluster = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::Display
)

cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, Bytes[120, 0])

puts "  Reading IdentifyTime attribute:"
result = cluster.read_attribute(Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME)
if result.is_a?(Bytes)
  time = IO::ByteFormat::LittleEndian.decode(UInt16, result)
  puts "    Value: #{time} seconds"
  puts "    Encoded as: #{result.to_a.inspect}"
end

puts "\n  Reading IdentifyType attribute:"
result = cluster.read_attribute(Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TYPE)
if result.is_a?(Bytes)
  type_value = result[0]
  type = Matter::Cluster::IdentifyCluster::IdentifyType.from_value(type_value)
  puts "    Value: #{type} (#{type_value})"
end

# Example 8: Practical Use Case - Smart Light
# --------------------------------------------
puts "\n8. Practical Use Case: Smart Light Commissioning"

light_cluster = Matter::Cluster::IdentifyCluster.new(
  endpoint,
  identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
)

light_cluster.on_identify_started do
  puts "  💡 Light is now FLASHING to identify itself!"
end

light_cluster.on_identify_stopped do
  puts "  💡 Light stopped flashing"
end

light_cluster.on_trigger_effect do |effect, _variant|
  case effect
  when Matter::Cluster::IdentifyCluster::EffectIdentifier::Blink
    puts "  💡 Light: Quick blink!"
  when Matter::Cluster::IdentifyCluster::EffectIdentifier::Breathe
    puts "  💡 Light: Breathing effect (fade in/out)"
  when Matter::Cluster::IdentifyCluster::EffectIdentifier::Okay
    puts "  💡 Light: 'Okay' confirmation flash"
  else
    puts "  💡 Light: Effect #{effect}"
  end
end

puts "\n  User initiates commissioning..."
puts "  Controller asks light to identify itself for 30 seconds:"
light_cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, Bytes[30, 0])

puts "\n  User confirms correct device..."
light_cluster.invoke_command(
  Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT,
  Bytes[
    Matter::Cluster::IdentifyCluster::EffectIdentifier::Okay.value,
    Matter::Cluster::IdentifyCluster::EffectVariant::Default.value,
  ]
)

puts "\n  Commissioning proceeds, stop identification:"
light_cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, Bytes[0, 0])

# Example 9: Attribute Metadata
# ------------------------------
puts "\n9. Attribute Metadata"

cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

puts "  Attributes:"
cluster.attributes.each do |attr|
  puts "    - #{attr.name} (0x#{attr.id.id.to_s(16).upcase.rjust(4, '0')})"
  puts "      Type: #{attr.type}, Writable: #{attr.writable}"
end

puts "\n  Commands:"
cluster.commands.each do |cmd|
  puts "    - #{cmd.name} (0x#{cmd.id.id.to_s(16).upcase.rjust(2, '0')})"
end

puts "\n" + "=" * 60
puts "Example complete!"
puts "\nKey Takeaways:"
puts "  • IdentifyTime is writable - can be set directly or via command"
puts "  • IdentifyType is read-only - set during cluster creation"
puts "  • Use callbacks to implement device-specific identification behavior"
puts "  • TriggerEffect provides visual/audible confirmation effects"
puts "  • tick() method simulates passage of time for countdown"
