require "../src/matter/cluster/level_control_cluster"
require "../src/matter/datatype/endpoint_number"

# Level Control Cluster Example
#
# The Level Control cluster (0x0008) provides level control (dimming)
# functionality for lights, volume controls, blinds, and other devices
# with adjustable levels.

puts "Matter Level Control Cluster Example"
puts "=" * 60

# Example 1: Creating a Dimmable Light
# -------------------------------------
puts "\n1. Creating a Dimmable Light"

endpoint = Matter::DataType::EndpointNumber.new(1_u16)
light = Matter::Cluster::LevelControlCluster.new(endpoint)

puts "  Cluster ID: 0x#{light.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Name: #{light.name}"
puts "  Current Level: #{light.current_level} (#{(light.current_level * 100 / 254).to_i}%)"
puts "  Min Level: #{light.min_level}"
puts "  Max Level: #{light.max_level}"

# Example 2: MoveToLevel Command
# -------------------------------
puts "\n2. MoveToLevel Command"

light = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 0_u8)

puts "  Initial level: #{light.current_level}"

# Move to 50% (127/254)
puts "\n  Moving to 50% brightness..."
result = light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
  Bytes[127, 0, 0, 0, 0] # level, transition_time (little-endian), options...
)

if result.is_a?(Matter::InteractionModel::Status) && result.success?
  puts "    Command succeeded!"
  puts "    New level: #{light.current_level} (#{(light.current_level * 100 / 254).to_i}%)"
end

# Move to full brightness
puts "\n  Moving to 100% brightness..."
light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
  Bytes[254, 0, 0, 0, 0]
)
puts "    New level: #{light.current_level} (#{(light.current_level * 100 / 254).to_i}%)"

# Example 3: Step Command
# -----------------------
puts "\n3. Step Command (Incremental Changes)"

light = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 127_u8)

puts "  Initial level: #{light.current_level} (50%)"

# Step up by 20
puts "\n  Stepping up by 20..."
light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_STEP,
  Bytes[
    Matter::Cluster::LevelControlCluster::StepMode::Up.value,
    20,   # step_size
    0, 0, # transition_time
    0, 0, # options
  ]
)
puts "    New level: #{light.current_level}"

# Step down by 30
puts "\n  Stepping down by 30..."
light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_STEP,
  Bytes[
    Matter::Cluster::LevelControlCluster::StepMode::Down.value,
    30, 0, 0, 0, 0,
  ]
)
puts "    New level: #{light.current_level}"

# Example 4: Level Boundaries and Clamping
# -----------------------------------------
puts "\n4. Level Boundaries and Clamping"

# Create a light with custom boundaries
custom_light = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 100_u8,
  min_level: 10_u8,
  max_level: 200_u8
)

puts "  Custom light boundaries:"
puts "    Min: #{custom_light.min_level}, Max: #{custom_light.max_level}"
puts "    Current: #{custom_light.current_level}"

# Try to go below minimum
puts "\n  Attempting to set level to 5 (below min of 10)..."
custom_light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
  Bytes[5, 0, 0, 0, 0]
)
puts "    Clamped to: #{custom_light.current_level}"

# Try to go above maximum
puts "\n  Attempting to set level to 250 (above max of 200)..."
custom_light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
  Bytes[250, 0, 0, 0, 0]
)
puts "    Clamped to: #{custom_light.current_level}"

# Example 5: Using Callbacks
# ---------------------------
puts "\n5. Using Callbacks for Level Changes"

light = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 50_u8)

light.on_level_changed do |old_level, new_level|
  old_pct = (old_level * 100 / 254).to_i
  new_pct = (new_level * 100 / 254).to_i
  direction = new_level > old_level ? "↑" : "↓"
  puts "  #{direction} Level changed: #{old_level} (#{old_pct}%) → #{new_level} (#{new_pct}%)"
end

puts "\n  Changing levels with callback:"
light.invoke_command(Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL, Bytes[100, 0, 0, 0, 0])
light.invoke_command(Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL, Bytes[200, 0, 0, 0, 0])
light.invoke_command(Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL, Bytes[150, 0, 0, 0, 0])

# Example 6: Reading Attributes
# ------------------------------
puts "\n6. Reading Attributes"

light = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 180_u8,
  min_level: 5_u8,
  max_level: 250_u8
)

puts "  Reading CurrentLevel attribute:"
result = light.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_CURRENT_LEVEL)
if result.is_a?(Bytes)
  level = result[0]
  puts "    Value: #{level} (#{(level * 100 / 254).to_i}%)"
end

puts "\n  Reading MinLevel attribute:"
result = light.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_MIN_LEVEL)
if result.is_a?(Bytes)
  puts "    Value: #{result[0]}"
end

puts "\n  Reading MaxLevel attribute:"
result = light.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_MAX_LEVEL)
if result.is_a?(Bytes)
  puts "    Value: #{result[0]}"
end

puts "\n  Reading RemainingTime attribute:"
result = light.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_REMAINING_TIME)
if result.is_a?(Bytes)
  time = IO::ByteFormat::LittleEndian.decode(UInt16, result)
  puts "    Value: #{time} (1/10s units)"
end

# Example 7: Practical Use Cases
# -------------------------------
puts "\n7. Practical Use Cases"

# Use case: Fade out to off
puts "\n  Use Case 1: Fade Out to Off"
bedroom_light = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 254_u8,
  min_level: 0_u8
)

puts "    Starting at: #{bedroom_light.current_level} (100%)"
bedroom_light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
  Bytes[0, 30, 0, 0, 0] # Fade to 0 over 3 seconds
)
puts "    Faded to: #{bedroom_light.current_level} (off)"

# Use case: Night light mode
puts "\n  Use Case 2: Night Light Mode (10%)"
bathroom_light = Matter::Cluster::LevelControlCluster.new(endpoint)

night_light_level = (254 * 0.1).to_u8 # 10%
bathroom_light.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
  Bytes[night_light_level, 0, 0, 0, 0]
)
puts "    Night light level: #{bathroom_light.current_level} (#{(bathroom_light.current_level * 100 / 254).to_i}%)"

# Use case: Gradual wake-up
puts "\n  Use Case 3: Gradual Wake-Up Simulation"
wake_light = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 0_u8
)

puts "    Starting at: #{wake_light.current_level}%"
[10, 20, 40, 60, 80, 100].each do |pct|
  level = (254 * pct / 100).to_u8
  wake_light.invoke_command(
    Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
    Bytes[level, 0, 0, 0, 0]
  )
  puts "      #{pct}%: level=#{wake_light.current_level}"
end

# Example 8: Move Mode Enums
# ---------------------------
puts "\n8. Move and Step Mode Enums"

puts "  MoveMode values:"
Matter::Cluster::LevelControlCluster::MoveMode.values.each do |mode|
  puts "    - #{mode} (#{mode.value})"
end

puts "\n  StepMode values:"
Matter::Cluster::LevelControlCluster::StepMode.values.each do |mode|
  puts "    - #{mode} (#{mode.value})"
end

# Example 9: Simulating a Dimmer Switch
# --------------------------------------
puts "\n9. Simulating a Dimmer Switch"

dimmer = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 127_u8
)

puts "  Initial brightness: #{(dimmer.current_level * 100 / 254).to_i}%"

# User presses "brighter" button multiple times
puts "\n  User presses 'Brighter' button:"
5.times do |i|
  dimmer.invoke_command(
    Matter::Cluster::LevelControlCluster::CMD_STEP,
    Bytes[
      Matter::Cluster::LevelControlCluster::StepMode::Up.value,
      25, 0, 0, 0, 0, # Step by 25
    ]
  )
  puts "    Press #{i + 1}: #{(dimmer.current_level * 100 / 254).to_i}% (level=#{dimmer.current_level})"
end

# User presses "dimmer" button
puts "\n  User presses 'Dimmer' button:"
3.times do |i|
  dimmer.invoke_command(
    Matter::Cluster::LevelControlCluster::CMD_STEP,
    Bytes[
      Matter::Cluster::LevelControlCluster::StepMode::Down.value,
      30, 0, 0, 0, 0, # Step by 30
    ]
  )
  puts "    Press #{i + 1}: #{(dimmer.current_level * 100 / 254).to_i}% (level=#{dimmer.current_level})"
end

# Example 10: Different Device Types
# -----------------------------------
puts "\n10. Different Device Types Using Level Control"

# Volume control
volume = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 127_u8, # 50% volume
  min_level: 0_u8,
  max_level: 254_u8
)
puts "\n  Speaker Volume Control:"
puts "    Current volume: #{(volume.current_level * 100 / 254).to_i}%"

# Blind position
blind = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 0_u8, # Fully closed
  min_level: 0_u8,
  max_level: 254_u8
)
puts "\n  Window Blind Position:"
puts "    Current position: #{(blind.current_level * 100 / 254).to_i}% open"
blind.invoke_command(
  Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
  Bytes[127, 0, 0, 0, 0] # 50% open
)
puts "    New position: #{(blind.current_level * 100 / 254).to_i}% open"

# Fan speed
fan = Matter::Cluster::LevelControlCluster.new(
  endpoint,
  current_level: 85_u8, # ~33% speed
  min_level: 0_u8,
  max_level: 254_u8
)
puts "\n  Fan Speed Control:"
puts "    Current speed: #{(fan.current_level * 100 / 254).to_i}%"

puts "\n" + "=" * 60
puts "Example complete!"
puts "\nKey Takeaways:"
puts "  • CurrentLevel ranges from 0-254 (not 0-255!)"
puts "  • Values are automatically clamped to min/max boundaries"
puts "  • Use MoveToLevel for absolute positioning"
puts "  • Use Step for relative incremental changes"
puts "  • Callbacks enable custom behavior on level changes"
puts "  • Same cluster works for lights, volume, blinds, fans, etc."
