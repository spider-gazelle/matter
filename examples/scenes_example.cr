require "../src/matter/cluster/scenes_cluster"
require "../src/matter/datatype/endpoint_number"

# Scenes Cluster Example
#
# The Scenes cluster (0x0005) provides scene storage and recall functionality.
# Scenes capture and restore device states across multiple clusters, enabling
# complex lighting and control scenarios with a single command.

puts "Matter Scenes Cluster Example"
puts "=" * 60

# Example 1: Creating a Scenes Cluster
# -------------------------------------
puts "\n1. Creating a Scenes Cluster"

endpoint = Matter::DataType::EndpointNumber.new(1_u16)
scenes = Matter::Cluster::ScenesCluster.new(endpoint)

puts "  Cluster ID: 0x#{scenes.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Name: #{scenes.name}"
puts "  Name Support: #{scenes.name_support}"
puts "  Scene Count: #{scenes.scene_count}"
puts "  Current Scene: #{scenes.current_scene}"
puts "  Current Group: 0x#{scenes.current_group.to_s(16).upcase.rjust(4, '0')}"
puts "  Scene Valid: #{scenes.scene_valid}"

# Example 2: Adding Scenes
# -------------------------
puts "\n2. Adding Scenes"

scenes = Matter::Cluster::ScenesCluster.new(endpoint)

puts "  Initial scene count: #{scenes.scene_count}"

# Add a scene: Group 0x0001, Scene 0x01, "Movie Night"
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io) # group_id
io.write_byte(0x01_u8)                              # scene_id
IO::ByteFormat::LittleEndian.encode(10_u16, io)     # transition_time (1.0 seconds)
io.write("Movie Night".to_slice)                    # scene_name

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_ADD_SCENE,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[1, 2])
  scene_id = result[3]

  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "\n  Successfully added scene:"
    puts "    Group ID: 0x#{group_id.to_s(16).upcase.rjust(4, '0')}"
    puts "    Scene ID: 0x#{scene_id.to_s(16).upcase.rjust(2, '0')}"
    puts "    Scene Name: Movie Night"
    puts "    Total scenes: #{scenes.scene_count}"
  end
end

# Add more scenes
[
  {0x0001_u16, 0x02_u8, 10_u16, "Reading"},
  {0x0001_u16, 0x03_u8, 5_u16, "Dinner"},
  {0x0001_u16, 0x04_u8, 20_u16, "Party"},
  {0x0002_u16, 0x01_u8, 30_u16, "Good Morning"},
  {0x0002_u16, 0x02_u8, 30_u16, "Good Night"},
].each do |group_id, scene_id, transition, scene_name|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  io.write_byte(scene_id)
  IO::ByteFormat::LittleEndian.encode(transition, io)
  io.write(scene_name.to_slice)

  result = scenes.invoke_command(
    Matter::Cluster::ScenesCluster::CMD_ADD_SCENE,
    io.to_slice
  )

  if result.is_a?(Bytes) && result[0] == Matter::InteractionModel::StatusCode::Success.value
    puts "    Added scene: Group 0x#{group_id.to_s(16).upcase}, Scene 0x#{scene_id.to_s(16).upcase} - #{scene_name}"
  end
end

puts "  Final scene count: #{scenes.scene_count}"

# Example 3: Viewing Scenes
# --------------------------
puts "\n3. Viewing Scenes"

# View an existing scene
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io) # group_id
io.write_byte(0x02_u8)                              # scene_id (Reading)

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_VIEW_SCENE,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[1, 2])
  scene_id = result[3]

  if status == Matter::InteractionModel::StatusCode::Success.value
    transition_time = IO::ByteFormat::LittleEndian.decode(UInt16, result[4, 2])
    scene_name = String.new(result[6..])
    puts "  Group 0x#{group_id.to_s(16).upcase}, Scene 0x#{scene_id.to_s(16).upcase}:"
    puts "    Name: #{scene_name}"
    puts "    Transition: #{transition_time / 10.0} seconds"
  end
end

# Try to view a non-existent scene
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x9999_u16, io)
io.write_byte(0x99_u8)

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_VIEW_SCENE,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  if status == Matter::InteractionModel::StatusCode::NotFound.value
    puts "  Scene 0x9999:0x99 not found (as expected)"
  end
end

# Example 4: Recalling Scenes
# ----------------------------
puts "\n4. Recalling Scenes"

scenes.on_recall_scene = ->(group_id : UInt16, scene_id : UInt8) do
  puts "  Callback: Applying scene 0x#{group_id.to_s(16).upcase}:0x#{scene_id.to_s(16).upcase}"
  puts "  (In real device: apply saved cluster states)"
end

puts "  Current scene valid: #{scenes.scene_valid}"

# Recall "Movie Night" scene
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
io.write_byte(0x01_u8)

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE,
  io.to_slice
)

if result.is_a?(Matter::InteractionModel::Status) && result.success?
  puts "\n  Scene recalled successfully!"
  puts "    Current Scene: 0x#{scenes.current_scene.to_s(16).upcase}"
  puts "    Current Group: 0x#{scenes.current_group.to_s(16).upcase}"
  puts "    Scene Valid: #{scenes.scene_valid}"
end

# Example 5: Storing Scenes
# --------------------------
puts "\n5. Storing Scenes"

puts "  Storing current device state as scene..."

# Store current state as Group 0x0003, Scene 0x01
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0003_u16, io)
io.write_byte(0x01_u8)

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_STORE_SCENE,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "    Scene stored successfully"
    puts "    Total scenes: #{scenes.scene_count}"
  end
end

# Example 6: Getting Scene Membership
# ------------------------------------
puts "\n6. Getting Scene Membership"

# Get all scenes for group 0x0001
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_GET_SCENE_MEMBERSHIP,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  capacity = result[1]
  group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[2, 2])
  scene_count = result[4]

  puts "  Group 0x#{group_id.to_s(16).upcase}:"
  puts "    Remaining capacity: #{capacity}"
  puts "    Scene count: #{scene_count}"
  puts "    Scenes:"

  scene_count.times do |i|
    scene_id = result[5 + i]
    puts "      - Scene 0x#{scene_id.to_s(16).upcase}"
  end
end

# Example 7: Checking Scene Existence
# ------------------------------------
puts "\n7. Checking Scene Existence"

puts "  Scene 0x0001:0x01 exists? #{scenes.has_scene?(0x0001_u16, 0x01_u8)}"
puts "  Scene 0x0001:0x02 exists? #{scenes.has_scene?(0x0001_u16, 0x02_u8)}"
puts "  Scene 0x9999:0x99 exists? #{scenes.has_scene?(0x9999_u16, 0x99_u8)}"

# Example 8: Removing Scenes
# ---------------------------
puts "\n8. Removing Scenes"

puts "  Current scene count: #{scenes.scene_count}"

# Remove a specific scene
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
io.write_byte(0x04_u8) # Remove "Party" scene

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_REMOVE_SCENE,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[1, 2])
  scene_id = result[3]

  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "\n  Successfully removed scene 0x#{group_id.to_s(16).upcase}:0x#{scene_id.to_s(16).upcase}"
    puts "  Remaining scenes: #{scenes.scene_count}"
  end
end

# Example 9: Remove All Scenes for a Group
# -----------------------------------------
puts "\n9. Remove All Scenes for a Group"

puts "  Scenes in group 0x0001:"
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
result = scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_GET_SCENE_MEMBERSHIP, io.to_slice)
if result.is_a?(Bytes)
  scene_count = result[4]
  puts "    Count: #{scene_count}"
end

# Remove all scenes from group 0x0001
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_REMOVE_ALL_SCENES,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "\n  All scenes removed from group 0x0001"
    puts "  Total remaining scenes: #{scenes.scene_count}"
  end
end

# Example 10: Copying Scenes
# ---------------------------
puts "\n10. Copying Scenes"

# First, add a scene to copy
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0010_u16, io)
io.write_byte(0x01_u8)
IO::ByteFormat::LittleEndian.encode(15_u16, io)
io.write("Original Scene".to_slice)
scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

puts "  Original scene: Group 0x0010, Scene 0x01"

# Copy scene from 0x0010:0x01 to 0x0020:0x01
io = IO::Memory.new
io.write_byte(0x00_u8)                              # mode (single copy)
IO::ByteFormat::LittleEndian.encode(0x0010_u16, io) # group_id_from
io.write_byte(0x01_u8)                              # scene_id_from
IO::ByteFormat::LittleEndian.encode(0x0020_u16, io) # group_id_to
io.write_byte(0x01_u8)                              # scene_id_to

result = scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_COPY_SCENE,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "  Scene copied successfully to Group 0x0020, Scene 0x01"
    puts "  Total scenes: #{scenes.scene_count}"
  end
end

# Example 11: Scene Capacity Management
# --------------------------------------
puts "\n11. Scene Capacity Management"

# Create a cluster with limited capacity
limited_scenes = Matter::Cluster::ScenesCluster.new(endpoint, max_scenes: 3_u8)

puts "  Cluster with max 3 scenes"
puts "  Adding scenes..."

# Add up to capacity
3.times do |i|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(0x0100_u16, io)
  io.write_byte((i + 1).to_u8)
  IO::ByteFormat::LittleEndian.encode(10_u16, io)
  io.write("Scene #{i + 1}".to_slice)

  result = limited_scenes.invoke_command(
    Matter::Cluster::ScenesCluster::CMD_ADD_SCENE,
    io.to_slice
  )

  if result.is_a?(Bytes)
    status = result[0]
    if status == Matter::InteractionModel::StatusCode::Success.value
      puts "    Added scene #{i + 1} (total: #{limited_scenes.scene_count})"
    end
  end
end

# Try to add beyond capacity
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0100_u16, io)
io.write_byte(0x04_u8)
IO::ByteFormat::LittleEndian.encode(10_u16, io)
io.write("Scene 4".to_slice)

result = limited_scenes.invoke_command(
  Matter::Cluster::ScenesCluster::CMD_ADD_SCENE,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  if status == Matter::InteractionModel::StatusCode::ResourceExhausted.value
    puts "    Cannot add scene 4: capacity exhausted"
  end
end

# Example 12: Scene Invalidation
# -------------------------------
puts "\n12. Scene Invalidation"

scenes = Matter::Cluster::ScenesCluster.new(endpoint)

# Add and recall a scene
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0050_u16, io)
io.write_byte(0x01_u8)
IO::ByteFormat::LittleEndian.encode(10_u16, io)
io.write("Test Scene".to_slice)
scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0050_u16, io)
io.write_byte(0x01_u8)
scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE, io.to_slice)

puts "  Scene recalled: Scene Valid = #{scenes.scene_valid}"

# Manually invalidate the scene (would happen when device state changes)
scenes.invalidate_current_scene
puts "  After manual change: Scene Valid = #{scenes.scene_valid}"

# Removing the current scene also invalidates it
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0050_u16, io)
io.write_byte(0x01_u8)
scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_REMOVE_SCENE, io.to_slice)
puts "  After removing scene: Scene Valid = #{scenes.scene_valid}"

# Example 13: Reading Attributes
# -------------------------------
puts "\n13. Reading Attributes"

scenes = Matter::Cluster::ScenesCluster.new(endpoint)

# Add a few scenes
2.times do |i|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
  io.write_byte((i + 1).to_u8)
  IO::ByteFormat::LittleEndian.encode(10_u16, io)
  io.write("Scene #{i + 1}".to_slice)
  scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)
end

puts "  Reading SceneCount attribute:"
result = scenes.read_attribute(Matter::Cluster::ScenesCluster::SCENE_COUNT)
if result.is_a?(Bytes)
  puts "    Value: #{result[0]}"
end

puts "\n  Reading CurrentScene attribute:"
result = scenes.read_attribute(Matter::Cluster::ScenesCluster::CURRENT_SCENE)
if result.is_a?(Bytes)
  puts "    Value: 0x#{result[0].to_s(16).upcase}"
end

puts "\n  Reading CurrentGroup attribute:"
result = scenes.read_attribute(Matter::Cluster::ScenesCluster::CURRENT_GROUP)
if result.is_a?(Bytes)
  group = IO::ByteFormat::LittleEndian.decode(UInt16, result)
  puts "    Value: 0x#{group.to_s(16).upcase}"
end

puts "\n  Reading SceneValid attribute:"
result = scenes.read_attribute(Matter::Cluster::ScenesCluster::SCENE_VALID)
if result.is_a?(Bytes)
  valid = result[0] == 1
  puts "    Value: #{valid}"
end

puts "\n  Reading NameSupport attribute:"
result = scenes.read_attribute(Matter::Cluster::ScenesCluster::NAME_SUPPORT)
if result.is_a?(Bytes)
  supports_names = (result[0] & 0x80) != 0
  puts "    Value: #{supports_names}"
end

# Example 14: Practical Use Case - Home Automation
# -------------------------------------------------
puts "\n14. Practical Use Case: Complete Home Automation Setup"

home_scenes = Matter::Cluster::ScenesCluster.new(endpoint)

# Define scene groups
GROUP_LIVING_ROOM = 0x0001_u16
GROUP_BEDROOM     = 0x0002_u16
GROUP_WHOLE_HOUSE = 0x0100_u16

puts "\n  Setting up home scenes..."

# Living room scenes
living_room_scenes = [
  {GROUP_LIVING_ROOM, 0x01_u8, 10_u16, "Movie Time"},
  {GROUP_LIVING_ROOM, 0x02_u8, 10_u16, "Reading"},
  {GROUP_LIVING_ROOM, 0x03_u8, 5_u16, "Entertaining"},
  {GROUP_LIVING_ROOM, 0x04_u8, 30_u16, "Relaxing"},
]

# Bedroom scenes
bedroom_scenes = [
  {GROUP_BEDROOM, 0x01_u8, 30_u16, "Wake Up"},
  {GROUP_BEDROOM, 0x02_u8, 30_u16, "Bedtime"},
  {GROUP_BEDROOM, 0x03_u8, 15_u16, "Reading in Bed"},
]

# Whole house scenes
house_scenes = [
  {GROUP_WHOLE_HOUSE, 0x01_u8, 20_u16, "Leaving Home"},
  {GROUP_WHOLE_HOUSE, 0x02_u8, 20_u16, "Arriving Home"},
  {GROUP_WHOLE_HOUSE, 0x03_u8, 30_u16, "Good Night"},
  {GROUP_WHOLE_HOUSE, 0x04_u8, 30_u16, "Good Morning"},
]

# Add all scenes
(living_room_scenes + bedroom_scenes + house_scenes).each do |group_id, scene_id, transition, name|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  io.write_byte(scene_id)
  IO::ByteFormat::LittleEndian.encode(transition, io)
  io.write(name.to_slice)

  home_scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)
end

puts "  Total scenes configured: #{home_scenes.scene_count}"

# List scenes by group
[
  {GROUP_LIVING_ROOM, "Living Room"},
  {GROUP_BEDROOM, "Bedroom"},
  {GROUP_WHOLE_HOUSE, "Whole House"},
].each do |group_id, group_name|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  result = home_scenes.invoke_command(
    Matter::Cluster::ScenesCluster::CMD_GET_SCENE_MEMBERSHIP,
    io.to_slice
  )

  if result.is_a?(Bytes)
    scene_count = result[4]
    puts "\n  #{group_name} (0x#{group_id.to_s(16).upcase}):"
    puts "    #{scene_count} scenes configured"
  end
end

# Simulate scene recall with callback
puts "\n  Simulating scene recall..."
home_scenes.on_recall_scene = ->(group_id : UInt16, scene_id : UInt8) do
  scene_names = {
    {GROUP_LIVING_ROOM, 0x01_u8} => "Movie Time",
    {GROUP_BEDROOM, 0x01_u8}     => "Wake Up",
    {GROUP_WHOLE_HOUSE, 0x04_u8} => "Good Morning",
  }

  if name = scene_names[{group_id, scene_id}]?
    puts "    Activating: #{name}"
  end
end

# Recall "Good Morning" scene
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(GROUP_WHOLE_HOUSE, io)
io.write_byte(0x04_u8)
home_scenes.invoke_command(Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE, io.to_slice)

puts "\n" + "=" * 60
puts "Example complete!"
puts "\nKey Takeaways:"
puts "  • Scenes store and recall device states across clusters"
puts "  • Each scene is identified by group ID + scene ID"
puts "  • Scenes support names and transition times"
puts "  • AddScene creates new scenes with specific settings"
puts "  • StoreScene captures current device state"
puts "  • RecallScene restores saved device state"
puts "  • Scenes track current active scene and validity"
puts "  • GetSceneMembership lists all scenes in a group"
puts "  • CopyScene duplicates scenes between groups"
puts "  • RemoveScene and RemoveAllScenes manage storage"
puts "  • SceneValid indicates if current scene matches device state"
puts "  • Use scenes for: mood lighting, automation, presets"
