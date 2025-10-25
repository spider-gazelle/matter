require "../src/matter/cluster/color_control_cluster"
require "../src/matter/datatype/endpoint_number"

# Color Control Cluster Example
#
# The Color Control cluster (0x0300) provides color control functionality
# for RGB and tunable white lights. It supports multiple color modes:
# - Hue/Saturation (HS) - Traditional HSV color model
# - XY Color - CIE 1931 color space
# - Color Temperature (CT) - Tunable white in Mireds/Kelvin

puts "Matter Color Control Cluster Example"
puts "=" * 60

# Example 1: Creating a Color Control Cluster
# --------------------------------------------
puts "\n1. Creating a Color Control Cluster"

endpoint = Matter::DataType::EndpointNumber.new(1_u16)
light = Matter::Cluster::ColorControlCluster.new(endpoint)

puts "  Cluster ID: 0x#{light.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Name: #{light.name}"
puts "  Current Hue: #{light.current_hue}"
puts "  Current Saturation: #{light.current_saturation}"
puts "  Color Temperature: #{light.color_temperature_mireds} mireds (#{light.color_temperature_kelvin}K)"
puts "  Color Mode: #{light.color_mode}"

# Example 2: Hue/Saturation Control
# ----------------------------------
puts "\n2. Hue/Saturation Control (HSV Model)"

light = Matter::Cluster::ColorControlCluster.new(endpoint)

puts "  Initial: Hue=#{light.current_hue}, Sat=#{light.current_saturation}"

# Set to red (hue=0, saturation=254)
puts "\n  Setting to RED..."
light.invoke_command(
  Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
  Bytes[0, 254]
)
puts "    Hue: #{light.current_hue} (0=red)"
puts "    Saturation: #{light.current_saturation}"

# Set to green (hue=85, saturation=254)
puts "\n  Setting to GREEN..."
light.invoke_command(
  Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
  Bytes[85, 254]
)
puts "    Hue: #{light.current_hue} (85=green)"
puts "    Saturation: #{light.current_saturation}"

# Set to blue (hue=170, saturation=254)
puts "\n  Setting to BLUE..."
light.invoke_command(
  Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
  Bytes[170, 254]
)
puts "    Hue: #{light.current_hue} (170=blue)"
puts "    Saturation: #{light.current_saturation}"

# Example 3: Step Hue (Gradual Color Change)
# -------------------------------------------
puts "\n3. Step Hue (Gradual Color Transitions)"

light = Matter::Cluster::ColorControlCluster.new(endpoint, current_hue: 0_u8, current_saturation: 254_u8)

puts "  Starting at RED (hue=0)"
puts "  Stepping through rainbow:"

6.times do |i|
  step_size = 42 # 255 / 6 ≈ 42.5
  light.invoke_command(
    Matter::Cluster::ColorControlCluster::CMD_STEP_HUE,
    Bytes[
      Matter::Cluster::Definitions::ColorControl::StepMode::Up.value,
      step_size.to_u8,
    ]
  )

  color_names = ["Orange", "Yellow", "Green", "Cyan", "Blue", "Magenta"]
  puts "    Step #{i + 1}: Hue=#{light.current_hue} (#{color_names[i]})"
end

# Example 4: Saturation Control
# ------------------------------
puts "\n4. Saturation Control (Color Intensity)"

light = Matter::Cluster::ColorControlCluster.new(endpoint, current_hue: 0_u8, current_saturation: 0_u8)

puts "  Starting with RED hue, varying saturation:"

[50, 100, 150, 200, 254].each do |sat|
  light.invoke_command(
    Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_SATURATION,
    Bytes[sat.to_u8]
  )

  intensity = (sat * 100 / 254).to_i
  puts "    Saturation #{sat}: #{intensity}% intensity"
end

# Example 5: Color Temperature Control
# -------------------------------------
puts "\n5. Color Temperature Control (Tunable White)"

light = Matter::Cluster::ColorControlCluster.new(endpoint)

puts "  Color temperature presets:"

# Warm white (2700K = cozy/evening light)
light.set_color_temperature_kelvin(2700_u32)
puts "    Warm White: #{light.color_temperature_mireds} mireds (#{light.color_temperature_kelvin}K)"

# Neutral white (4000K = natural daylight)
light.set_color_temperature_kelvin(4000_u32)
puts "    Neutral White: #{light.color_temperature_mireds} mireds (#{light.color_temperature_kelvin}K)"

# Cool white (6500K = bright/energizing)
light.set_color_temperature_kelvin(6500_u32)
puts "    Cool White: #{light.color_temperature_mireds} mireds (#{light.color_temperature_kelvin}K)"

# Example 6: Step Color Temperature
# ----------------------------------
puts "\n6. Step Color Temperature (Gradual Warmth Change)"

light = Matter::Cluster::ColorControlCluster.new(endpoint, color_temperature_mireds: 200_u16)

puts "  Starting at #{light.color_temperature_kelvin}K"
puts "  Stepping warmer:"

5.times do |i|
  io = IO::Memory.new
  io.write_byte(Matter::Cluster::Definitions::ColorControl::StepMode::Up.value)
  IO::ByteFormat::LittleEndian.encode(30_u16, io)

  light.invoke_command(
    Matter::Cluster::ColorControlCluster::CMD_STEP_COLOR_TEMPERATURE,
    io.to_slice
  )

  puts "    Step #{i + 1}: #{light.color_temperature_mireds} mireds (#{light.color_temperature_kelvin}K)"
end

# Example 7: XY Color Space
# --------------------------
puts "\n7. XY Color Space (CIE 1931)"

light = Matter::Cluster::ColorControlCluster.new(endpoint)

puts "  Setting colors using XY coordinates:"

# Red: x=0.64, y=0.33 (in 0-65535 range: x=41943, y=21626)
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(41943_u16, io)
IO::ByteFormat::LittleEndian.encode(21626_u16, io)
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR, io.to_slice)
puts "    Red: X=#{light.current_x}, Y=#{light.current_y}"

# Green: x=0.30, y=0.60 (in 0-65535 range: x=19660, y=39321)
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(19660_u16, io)
IO::ByteFormat::LittleEndian.encode(39321_u16, io)
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR, io.to_slice)
puts "    Green: X=#{light.current_x}, Y=#{light.current_y}"

# Blue: x=0.15, y=0.06 (in 0-65535 range: x=9830, y=3932)
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(9830_u16, io)
IO::ByteFormat::LittleEndian.encode(3932_u16, io)
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR, io.to_slice)
puts "    Blue: X=#{light.current_x}, Y=#{light.current_y}"

# Example 8: Enhanced Hue (16-bit precision)
# -------------------------------------------
puts "\n8. Enhanced Hue (16-bit Precision)"

light = Matter::Cluster::ColorControlCluster.new(endpoint)

puts "  Standard hue: 8-bit (0-255)"
puts "  Enhanced hue: 16-bit (0-65535)"
puts ""
puts "  Setting enhanced hue to 32768 (50% through color wheel):"

io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(32768_u16, io)
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_ENHANCED_MOVE_TO_HUE, io.to_slice)

puts "    Enhanced Hue: #{light.enhanced_current_hue}"
puts "    Standard Hue: #{light.current_hue} (high byte)"
puts "    Color Mode: #{light.enhanced_color_mode}"

# Example 9: Color Mode Tracking
# -------------------------------
puts "\n9. Color Mode Tracking"

light = Matter::Cluster::ColorControlCluster.new(endpoint)

puts "  Color mode changes based on which attribute you set:"

# Set hue → mode becomes HS
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[100])
puts "    After setting hue: #{light.color_mode}"

# Set XY → mode becomes XY
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(30000_u16, io)
IO::ByteFormat::LittleEndian.encode(30000_u16, io)
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_COLOR, io.to_slice)
puts "    After setting XY: #{light.color_mode}"

# Set CT → mode becomes CT
light.set_color_temperature_kelvin(4000_u32)
puts "    After setting temp: #{light.color_mode}"

# Example 10: Using Callbacks
# ----------------------------
puts "\n10. Using Callbacks"

light = Matter::Cluster::ColorControlCluster.new(endpoint, current_hue: 0_u8, current_saturation: 254_u8)

light.on_color_changed do
  puts "    Color changed! Now: Hue=#{light.current_hue}, Sat=#{light.current_saturation}, Mode=#{light.color_mode}"
end

puts "\n  Changing colors with callback:"
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[50])
light.invoke_command(Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE, Bytes[100])

# Example 11: Physical Limits (Color Temperature)
# ------------------------------------------------
puts "\n11. Physical Limits (Color Temperature)"

light = Matter::Cluster::ColorControlCluster.new(
  endpoint,
  color_temp_physical_min_mireds: 147_u16, # 6800K max
  color_temp_physical_max_mireds: 500_u16  # 2000K min
)

puts "  Physical limits:"
puts "    Min: #{light.color_temp_physical_min_mireds} mireds (#{1_000_000 / light.color_temp_physical_min_mireds}K)"
puts "    Max: #{light.color_temp_physical_max_mireds} mireds (#{1_000_000 / light.color_temp_physical_max_mireds}K)"

# Try to go beyond limits
puts "\n  Attempting to set to 7000K (beyond max)..."
light.set_color_temperature_kelvin(7000_u32)
puts "    Clamped to: #{light.color_temperature_mireds} mireds (#{light.color_temperature_kelvin}K)"

puts "\n  Attempting to set to 1500K (beyond min)..."
light.set_color_temperature_kelvin(1500_u32)
puts "    Clamped to: #{light.color_temperature_mireds} mireds (#{light.color_temperature_kelvin}K)"

# Example 12: Reading Attributes
# -------------------------------
puts "\n12. Reading Attributes"

light = Matter::Cluster::ColorControlCluster.new(
  endpoint,
  current_hue: 127_u8,
  current_saturation: 200_u8,
  color_temperature_mireds: 250_u16
)

puts "  Reading CurrentHue:"
result = light.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_CURRENT_HUE)
if result.is_a?(Bytes)
  puts "    Value: #{result[0]}"
end

puts "\n  Reading CurrentSaturation:"
result = light.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_CURRENT_SATURATION)
if result.is_a?(Bytes)
  puts "    Value: #{result[0]}"
end

puts "\n  Reading ColorTemperatureMireds:"
result = light.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_COLOR_TEMPERATURE_MIREDS)
if result.is_a?(Bytes)
  mireds = IO::ByteFormat::LittleEndian.decode(UInt16, result)
  puts "    Value: #{mireds} mireds (#{1_000_000 / mireds}K)"
end

puts "\n  Reading ColorMode:"
result = light.read_attribute(Matter::Cluster::ColorControlCluster::ATTR_COLOR_MODE)
if result.is_a?(Bytes)
  mode = Matter::Cluster::Definitions::ColorControl::ColorMode.from_value(result[0])
  puts "    Value: #{mode}"
end

# Example 13: Practical Use Cases
# --------------------------------
puts "\n13. Practical Use Cases"

# Use Case 1: Sunrise Simulation
puts "\n  Use Case 1: Sunrise Simulation"
sunrise_light = Matter::Cluster::ColorControlCluster.new(endpoint)

puts "    Starting with warm, dim light..."
sunrise_light.set_color_temperature_kelvin(2000_u32) # Very warm
puts "      #{sunrise_light.color_temperature_kelvin}K"

puts "    Gradually increasing to daylight..."
[2500, 3000, 4000, 5500, 6500].each do |kelvin|
  sunrise_light.set_color_temperature_kelvin(kelvin.to_u32)
  puts "      #{sunrise_light.color_temperature_kelvin}K"
end

# Use Case 2: Mood Lighting
puts "\n  Use Case 2: Mood Lighting Scenes"

mood_light = Matter::Cluster::ColorControlCluster.new(endpoint)

moods = {
  "Relaxing"   => {hue: 30_u8, sat: 180_u8},  # Warm amber
  "Energizing" => {hue: 170_u8, sat: 254_u8}, # Bright blue
  "Romantic"   => {hue: 0_u8, sat: 200_u8},   # Soft red
  "Focus"      => {hue: 85_u8, sat: 100_u8},  # Muted green
}

moods.each do |name, color|
  mood_light.invoke_command(
    Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
    Bytes[color[:hue], color[:sat]]
  )
  puts "    #{name}: Hue=#{mood_light.current_hue}, Sat=#{mood_light.current_saturation}"
end

# Use Case 3: Party Mode (Color Cycle)
puts "\n  Use Case 3: Party Mode (Rapid Color Cycling)"

party_light = Matter::Cluster::ColorControlCluster.new(endpoint, current_hue: 0_u8, current_saturation: 254_u8)

puts "    Cycling through colors:"
12.times do |i|
  party_light.invoke_command(
    Matter::Cluster::ColorControlCluster::CMD_STEP_HUE,
    Bytes[
      Matter::Cluster::Definitions::ColorControl::StepMode::Up.value,
      21 # 255 / 12 ≈ 21
    ]
  )
  puts "      #{i + 1}. Hue=#{party_light.current_hue}"
end

# Use Case 4: Reading Light (Adjustable White)
puts "\n  Use Case 4: Reading Light Presets"

reading_light = Matter::Cluster::ColorControlCluster.new(endpoint)

presets = {
  "Morning Read"   => 6500_u32, # Cool white - alertness
  "Afternoon Read" => 5000_u32, # Neutral white - comfortable
  "Evening Read"   => 3500_u32, # Warm white - relaxing
  "Night Read"     => 2700_u32, # Very warm - minimal blue light
}

presets.each do |name, kelvin|
  reading_light.set_color_temperature_kelvin(kelvin)
  puts "    #{name}: #{reading_light.color_temperature_kelvin}K (#{reading_light.color_temperature_mireds} mireds)"
end

# Example 14: Multi-Light Coordination
# -------------------------------------
puts "\n14. Multi-Light Coordination"

# Create multiple lights
lights = {
  "Ceiling" => Matter::Cluster::ColorControlCluster.new(Matter::DataType::EndpointNumber.new(1_u16)),
  "Table"   => Matter::Cluster::ColorControlCluster.new(Matter::DataType::EndpointNumber.new(2_u16)),
  "Wall"    => Matter::Cluster::ColorControlCluster.new(Matter::DataType::EndpointNumber.new(3_u16)),
  "Floor"   => Matter::Cluster::ColorControlCluster.new(Matter::DataType::EndpointNumber.new(4_u16)),
}

puts "  Setting all lights to warm white (3000K)..."
lights.each do |name, light|
  light.set_color_temperature_kelvin(3000_u32)
  puts "    #{name}: #{light.color_temperature_kelvin}K"
end

puts "\n  Creating accent lighting (colored)..."
lights["Wall"].invoke_command(
  Matter::Cluster::ColorControlCluster::CMD_MOVE_TO_HUE_AND_SATURATION,
  Bytes[20, 200] # Orange accent
)
puts "    Wall light: Hue=#{lights["Wall"].current_hue} (orange accent)"

puts "\n" + "=" * 60
puts "Example complete!"
puts "\nKey Takeaways:"
puts "  • Three color modes: Hue/Saturation, XY, Color Temperature"
puts "  • Color mode automatically switches based on which attribute you set"
puts "  • Hue: 0-254 (8-bit) or 0-65535 (16-bit enhanced)"
puts "  • Saturation: 0-254 (0=white, 254=full color)"
puts "  • Color Temperature: Mireds (inverse Kelvin × 1,000,000)"
puts "  • 2700K = warm white (cozy), 6500K = cool white (energizing)"
puts "  • Physical limits prevent invalid color temperatures"
puts "  • Callbacks notify on color changes"
puts "  • Step commands enable smooth color transitions"
puts "  • XY color space for precise color control"
puts "  • Enhanced hue provides 256x more precision"
puts "  • Perfect for: RGB lights, tunable white lights, mood lighting"
