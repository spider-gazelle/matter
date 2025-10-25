require "../src/matter/cluster/groups_cluster"
require "../src/matter/datatype/endpoint_number"

# Groups Cluster Example
#
# The Groups cluster (0x0004) manages group membership for multicast
# communication, allowing devices to be controlled as a group.
# This is commonly used for controlling multiple lights together.

puts "Matter Groups Cluster Example"
puts "=" * 60

# Example 1: Creating a Groups Cluster
# -------------------------------------
puts "\n1. Creating a Groups Cluster"

endpoint = Matter::DataType::EndpointNumber.new(1_u16)
groups = Matter::Cluster::GroupsCluster.new(endpoint)

puts "  Cluster ID: 0x#{groups.cluster_id.id.to_s(16).upcase.rjust(4, '0')}"
puts "  Name: #{groups.name}"
puts "  Name Support: #{groups.name_support}"
puts "  Group Count: #{groups.group_count}"

# Example 2: Adding Groups
# -------------------------
puts "\n2. Adding Groups"

groups = Matter::Cluster::GroupsCluster.new(endpoint)

puts "  Initial group count: #{groups.group_count}"

# Add a group with ID 0x0001 and name "Living Room"
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
io.write("Living Room".to_slice)

result = groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_ADD_GROUP,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[1, 2])

  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "\n  Successfully added group:"
    puts "    Group ID: 0x#{group_id.to_s(16).upcase.rjust(4, '0')}"
    puts "    Group Name: Living Room"
    puts "    Total groups: #{groups.group_count}"
  end
end

# Add more groups
[
  {0x0002_u16, "Bedroom"},
  {0x0003_u16, "Kitchen"},
  {0x0004_u16, "Bathroom"},
].each do |group_id, group_name|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  io.write(group_name.to_slice)

  result = groups.invoke_command(
    Matter::Cluster::GroupsCluster::CMD_ADD_GROUP,
    io.to_slice
  )

  if result.is_a?(Bytes) && result[0] == Matter::InteractionModel::StatusCode::Success.value
    puts "    Added group 0x#{group_id.to_s(16).upcase.rjust(4, '0')}: #{group_name}"
  end
end

puts "  Final group count: #{groups.group_count}"

# Example 3: Viewing Groups
# --------------------------
puts "\n3. Viewing Groups"

# View an existing group
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)

result = groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_VIEW_GROUP,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[1, 2])

  if status == Matter::InteractionModel::StatusCode::Success.value
    group_name = String.new(result[3..])
    puts "  Group 0x#{group_id.to_s(16).upcase.rjust(4, '0')}: #{group_name}"
  end
end

# Try to view a non-existent group
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x9999_u16, io)

result = groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_VIEW_GROUP,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]

  if status == Matter::InteractionModel::StatusCode::NotFound.value
    puts "  Group 0x9999 not found (as expected)"
  end
end

# Example 4: Getting Group Membership
# ------------------------------------
puts "\n4. Getting Group Membership"

result = groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_GET_GROUP_MEMBERSHIP,
  Bytes.new(0)
)

if result.is_a?(Bytes)
  capacity = result[0]
  count = result[1]

  puts "  Remaining capacity: #{capacity}"
  puts "  Current group count: #{count}"
  puts "  Member of groups:"

  count.times do |i|
    group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[2 + i*2, 2])
    puts "    - 0x#{group_id.to_s(16).upcase.rjust(4, '0')}"
  end
end

# Example 5: Checking Group Membership
# -------------------------------------
puts "\n5. Checking Group Membership"

puts "  Is member of group 0x0001? #{groups.member_of?(0x0001_u16)}"
puts "  Is member of group 0x0002? #{groups.member_of?(0x0002_u16)}"
puts "  Is member of group 0x9999? #{groups.member_of?(0x9999_u16)}"

# Example 6: Removing Groups
# ---------------------------
puts "\n6. Removing Groups"

puts "  Current group count: #{groups.group_count}"

# Remove a specific group
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0004_u16, io)

result = groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_REMOVE_GROUP,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  group_id = IO::ByteFormat::LittleEndian.decode(UInt16, result[1, 2])

  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "\n  Successfully removed group 0x#{group_id.to_s(16).upcase.rjust(4, '0')}"
    puts "  Remaining groups: #{groups.group_count}"
  end
end

# Example 7: Remove All Groups
# -----------------------------
puts "\n7. Remove All Groups"

puts "  Groups before removal: #{groups.group_count}"

result = groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_REMOVE_ALL_GROUPS,
  Bytes.new(0)
)

if result.is_a?(Matter::InteractionModel::Status) && result.success?
  puts "  All groups removed successfully"
  puts "  Groups after removal: #{groups.group_count}"
end

# Example 8: Group Capacity Management
# -------------------------------------
puts "\n8. Group Capacity Management"

# Create a cluster with limited capacity
limited_groups = Matter::Cluster::GroupsCluster.new(endpoint, max_groups: 3_u8)

puts "  Cluster with max 3 groups"
puts "  Adding groups..."

# Add up to capacity
[0x0001_u16, 0x0002_u16, 0x0003_u16].each_with_index do |group_id, i|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  io.write("Group #{i + 1}".to_slice)

  result = limited_groups.invoke_command(
    Matter::Cluster::GroupsCluster::CMD_ADD_GROUP,
    io.to_slice
  )

  if result.is_a?(Bytes)
    status = result[0]
    if status == Matter::InteractionModel::StatusCode::Success.value
      puts "    Added group #{i + 1} (total: #{limited_groups.group_count})"
    end
  end
end

# Try to add beyond capacity
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0004_u16, io)
io.write("Group 4".to_slice)

result = limited_groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_ADD_GROUP,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  if status == Matter::InteractionModel::StatusCode::ResourceExhausted.value
    puts "    Cannot add group 4: capacity exhausted"
  end
end

# Update an existing group (should work even at capacity)
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
io.write("Updated Group 1".to_slice)

result = limited_groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_ADD_GROUP,
  io.to_slice
)

if result.is_a?(Bytes)
  status = result[0]
  if status == Matter::InteractionModel::StatusCode::Success.value
    puts "    Updated group 1 (still #{limited_groups.group_count} groups)"
  end
end

# Example 9: AddGroupIfIdentifying Command
# -----------------------------------------
puts "\n9. AddGroupIfIdentifying Command"

groups = Matter::Cluster::GroupsCluster.new(endpoint)

puts "  Adding group conditionally..."

io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0010_u16, io)
io.write("Conditional Group".to_slice)

result = groups.invoke_command(
  Matter::Cluster::GroupsCluster::CMD_ADD_GROUP_IF_IDENTIFYING,
  io.to_slice
)

if result.is_a?(Matter::InteractionModel::Status) && result.success?
  puts "  Group added (simplified: always adds in this implementation)"
  puts "  Is member of 0x0010? #{groups.member_of?(0x0010_u16)}"
end

# Example 10: Practical Use Case - Multi-Room Lighting
# -----------------------------------------------------
puts "\n10. Practical Use Case: Multi-Room Lighting Control"

# Simulate multiple light endpoints
light_endpoints = {
  1_u16 => "Living Room Light 1",
  2_u16 => "Living Room Light 2",
  3_u16 => "Bedroom Light",
  4_u16 => "Kitchen Light",
}

# Create groups cluster for each light
light_groups = light_endpoints.keys.map do |ep_id|
  Matter::Cluster::GroupsCluster.new(Matter::DataType::EndpointNumber.new(ep_id))
end

# Define room groups
GROUP_ALL_LIGHTS  = 0x0001_u16
GROUP_LIVING_ROOM = 0x0010_u16
GROUP_BEDROOM     = 0x0020_u16
GROUP_KITCHEN     = 0x0030_u16

puts "\n  Setting up room groups..."

# Add lights to appropriate groups
room_assignments = [
  {endpoint: 0, groups: [GROUP_ALL_LIGHTS, GROUP_LIVING_ROOM]},
  {endpoint: 1, groups: [GROUP_ALL_LIGHTS, GROUP_LIVING_ROOM]},
  {endpoint: 2, groups: [GROUP_ALL_LIGHTS, GROUP_BEDROOM]},
  {endpoint: 3, groups: [GROUP_ALL_LIGHTS, GROUP_KITCHEN]},
]

room_assignments.each do |assignment|
  light = light_groups[assignment[:endpoint]]

  assignment[:groups].each do |group_id|
    io = IO::Memory.new
    IO::ByteFormat::LittleEndian.encode(group_id, io)
    light.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
  end
end

puts "  Group memberships configured:"
light_endpoints.each_with_index do |(ep_id, name), i|
  light = light_groups[i]
  puts "    #{name}:"
  puts "      - All Lights: #{light.member_of?(GROUP_ALL_LIGHTS)}"
  puts "      - Living Room: #{light.member_of?(GROUP_LIVING_ROOM)}"
  puts "      - Bedroom: #{light.member_of?(GROUP_BEDROOM)}"
  puts "      - Kitchen: #{light.member_of?(GROUP_KITCHEN)}"
end

# Example 11: Data Versioning
# ----------------------------
puts "\n11. Data Versioning (Change Tracking)"

groups = Matter::Cluster::GroupsCluster.new(endpoint)

puts "  Initial data version: #{groups.data_version}"

# Add a group
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
io.write("Test Group".to_slice)
groups.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

puts "  After adding group: #{groups.data_version} (incremented)"

# Remove the group
io = IO::Memory.new
IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
groups.invoke_command(Matter::Cluster::GroupsCluster::CMD_REMOVE_GROUP, io.to_slice)

puts "  After removing group: #{groups.data_version} (incremented)"

# Example 12: Reading Attributes
# -------------------------------
puts "\n12. Reading Attributes"

groups = Matter::Cluster::GroupsCluster.new(endpoint, name_support: true)

puts "  Reading NameSupport attribute:"
result = groups.read_attribute(Matter::Cluster::GroupsCluster::NAME_SUPPORT)
if result.is_a?(Bytes)
  value = result[0]
  supports_names = (value & 0x80) != 0
  puts "    Value: 0x#{value.to_s(16).upcase.rjust(2, '0')}"
  puts "    Supports group names: #{supports_names}"
end

puts "\n  Reading ClusterRevision attribute:"
result = groups.read_attribute(Matter::Cluster::GroupsCluster::CLUSTER_REVISION)
if result.is_a?(Bytes)
  revision = IO::ByteFormat::LittleEndian.decode(UInt16, result)
  puts "    Value: #{revision}"
end

puts "\n  Reading FeatureMap attribute:"
result = groups.read_attribute(Matter::Cluster::GroupsCluster::FEATURE_MAP)
if result.is_a?(Bytes)
  features = IO::ByteFormat::LittleEndian.decode(UInt32, result)
  puts "    Value: 0x#{features.to_s(16).upcase.rjust(8, '0')}"
end

# Example 13: Different Use Cases
# --------------------------------
puts "\n13. Different Device Types Using Groups"

# Smart home zones
puts "\n  Use Case 1: Smart Home Zones"
zones_groups = Matter::Cluster::GroupsCluster.new(endpoint)

zones = {
  0x0100_u16 => "Downstairs",
  0x0200_u16 => "Upstairs",
  0x0300_u16 => "Outdoor",
  0x0400_u16 => "Security",
}

zones.each do |group_id, zone_name|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  io.write(zone_name.to_slice)
  zones_groups.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
end

puts "    Configured #{zones_groups.group_count} zones"

# Activity-based groups
puts "\n  Use Case 2: Activity-Based Groups"
activity_groups = Matter::Cluster::GroupsCluster.new(endpoint)

activities = {
  0x1000_u16 => "Movie Night",
  0x1001_u16 => "Reading",
  0x1002_u16 => "Dinner",
  0x1003_u16 => "Party",
}

activities.each do |group_id, activity_name|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  io.write(activity_name.to_slice)
  activity_groups.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
end

puts "    Configured #{activity_groups.group_count} activity scenes"

# Commercial/Office spaces
puts "\n  Use Case 3: Office Space Management"
office_groups = Matter::Cluster::GroupsCluster.new(endpoint)

offices = {
  0x2000_u16 => "Conference Room A",
  0x2001_u16 => "Conference Room B",
  0x2010_u16 => "Open Office Area",
  0x2020_u16 => "Private Offices",
  0x2030_u16 => "Break Room",
}

offices.each do |group_id, space_name|
  io = IO::Memory.new
  IO::ByteFormat::LittleEndian.encode(group_id, io)
  io.write(space_name.to_slice)
  office_groups.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
end

puts "    Configured #{office_groups.group_count} office spaces"

puts "\n" + "=" * 60
puts "Example complete!"
puts "\nKey Takeaways:"
puts "  • Groups enable multicast control of multiple devices"
puts "  • Each device tracks which groups it belongs to"
puts "  • Group IDs are 16-bit values (0x0000-0xFFFF)"
puts "  • Groups support optional naming (NameSupport attribute)"
puts "  • AddGroup, RemoveGroup commands manage membership"
puts "  • GetGroupMembership returns all groups device belongs to"
puts "  • RemoveAllGroups clears all group memberships"
puts "  • AddGroupIfIdentifying adds only during identification"
puts "  • Capacity limits prevent resource exhaustion"
puts "  • Data versioning tracks membership changes"
puts "  • Use groups for rooms, zones, scenes, activities, etc."
