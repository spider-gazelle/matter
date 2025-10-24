require "../src/matter"

Log.setup(:info)

# Example: Access Control
#
# This example demonstrates how to use the Access Control cluster
# to manage fine-grained permissions for Matter devices.

module AccessControlExample
  # Create an Access Control cluster (always on endpoint 0)
  endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
  cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

  puts "Created Access Control Cluster"
  puts "  Cluster ID: 0x#{cluster.cluster_id.id.to_s(16)}"
  puts "  Max Subjects per ACE: #{cluster.subjects_per_access_control_entry}"
  puts "  Max Targets per ACE: #{cluster.targets_per_access_control_entry}"
  puts "  Max ACEs per Fabric: #{cluster.access_control_entries_per_fabric}"
  puts

  # Demonstrate usage
  puts "=== Access Control Example ==="
  puts

  # 1. Read cluster attributes
  puts "1. Reading cluster attributes..."
  acl = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
  puts "  ACL: #{acl.as(Bytes).size} bytes (empty)" if acl.is_a?(Bytes)

  subjects = cluster.read_attribute(
    Matter::Cluster::AccessControlCluster::ATTR_SUBJECTS_PER_ACCESS_CONTROL_ENTRY
  )
  if subjects.is_a?(Bytes)
    io = IO::Memory.new(subjects)
    count = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
    puts "  Max Subjects per Entry: #{count}"
  end

  targets = cluster.read_attribute(
    Matter::Cluster::AccessControlCluster::ATTR_TARGETS_PER_ACCESS_CONTROL_ENTRY
  )
  if targets.is_a?(Bytes)
    io = IO::Memory.new(targets)
    count = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
    puts "  Max Targets per Entry: #{count}"
  end

  entries_per_fabric = cluster.read_attribute(
    Matter::Cluster::AccessControlCluster::ATTR_ACCESS_CONTROL_ENTRIES_PER_FABRIC
  )
  if entries_per_fabric.is_a?(Bytes)
    io = IO::Memory.new(entries_per_fabric)
    count = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
    puts "  Max Entries per Fabric: #{count}"
  end
  puts

  # 2. Create ACL entry for administrator
  puts "2. Creating administrator ACL entry..."
  admin_subject = 0x1234567890ABCDEF_u64
  admin_entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
    auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
    subjects: [admin_subject],
    targets: nil, # All targets
    fabric_index: 1_u8
  )
  cluster.acl << admin_entry

  puts "  Added administrator entry:"
  puts "    Subject: 0x#{admin_subject.to_s(16)}"
  puts "    Privilege: Administer"
  puts "    Auth Mode: CASE"
  puts "    Targets: All"
  puts "    Fabric Index: 1"
  puts

  # 3. Create ACL entry for operator
  puts "3. Creating operator ACL entry..."
  operator_subject = 0xFEDCBA0987654321_u64
  operator_entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
    auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
    subjects: [operator_subject],
    targets: nil,
    fabric_index: 1_u8
  )
  cluster.acl << operator_entry

  puts "  Added operator entry:"
  puts "    Subject: 0x#{operator_subject.to_s(16)}"
  puts "    Privilege: Operate"
  puts "    Fabric Index: 1"
  puts

  # 4. Create ACL entry with specific target
  puts "4. Creating targeted ACL entry..."
  viewer_subject = 0xAAAABBBBCCCCDDDD_u64

  # Target specific cluster on specific endpoint
  light_target = Matter::Cluster::AccessControlCluster::Target.new(
    cluster: 0x0006_u32, # On/Off cluster
    endpoint: 1_u16,
    device_type: nil
  )

  viewer_entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View,
    auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
    subjects: [viewer_subject],
    targets: [light_target],
    fabric_index: 1_u8
  )
  cluster.acl << viewer_entry

  puts "  Added viewer entry with specific target:"
  puts "    Subject: 0x#{viewer_subject.to_s(16)}"
  puts "    Privilege: View"
  puts "    Target Cluster: 0x0006 (On/Off)"
  puts "    Target Endpoint: 1"
  puts

  # 5. Check access for administrator
  puts "5. Checking access for administrator..."
  has_admin = cluster.check_access(
    subject: admin_subject,
    fabric_index: 1_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer
  )
  puts "  Has Administer privilege: #{has_admin}"

  has_view = cluster.check_access(
    subject: admin_subject,
    fabric_index: 1_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
  )
  puts "  Has View privilege: #{has_view}"
  puts

  # 6. Check access for operator
  puts "6. Checking access for operator..."
  can_operate = cluster.check_access(
    subject: operator_subject,
    fabric_index: 1_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate
  )
  puts "  Has Operate privilege: #{can_operate}"

  can_admin = cluster.check_access(
    subject: operator_subject,
    fabric_index: 1_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer
  )
  puts "  Has Administer privilege: #{can_admin}"
  puts

  # 7. Check access for viewer with target
  puts "7. Checking access for viewer..."
  can_view_light = cluster.check_access(
    subject: viewer_subject,
    fabric_index: 1_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View,
    cluster: 0x0006_u32,
    endpoint: 1_u16
  )
  puts "  Can view On/Off cluster on endpoint 1: #{can_view_light}"

  can_view_other = cluster.check_access(
    subject: viewer_subject,
    fabric_index: 1_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View,
    cluster: 0x0008_u32, # Level Control cluster
    endpoint: 1_u16
  )
  puts "  Can view Level Control cluster on endpoint 1: #{can_view_other}"
  puts

  # 8. Check fabric isolation
  puts "8. Demonstrating fabric isolation..."
  fabric2_admin = 0x1111111111111111_u64
  fabric2_entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
    auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
    subjects: [fabric2_admin],
    targets: nil,
    fabric_index: 2_u8
  )
  cluster.acl << fabric2_entry

  # Admin from fabric 1 tries to access fabric 2's resources
  cross_fabric_access = cluster.check_access(
    subject: admin_subject,
    fabric_index: 2_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer
  )
  puts "  Fabric 1 admin accessing Fabric 2: #{cross_fabric_access}"

  # Admin from fabric 2 accessing fabric 2's resources
  same_fabric_access = cluster.check_access(
    subject: fabric2_admin,
    fabric_index: 2_u8,
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer
  )
  puts "  Fabric 2 admin accessing Fabric 2: #{same_fabric_access}"
  puts

  # 9. Multi-subject entry
  puts "9. Creating multi-subject ACL entry..."
  group_subjects = [0x2001_u64, 0x2002_u64, 0x2003_u64]
  group_entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
    privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
    auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
    subjects: group_subjects,
    targets: nil,
    fabric_index: 1_u8
  )
  cluster.acl << group_entry

  puts "  Added entry for #{group_subjects.size} subjects:"
  group_subjects.each do |subj|
    puts "    - 0x#{subj.to_s(16)}"
  end

  # Check each subject
  group_subjects.each do |subj|
    has_access = cluster.check_access(
      subject: subj,
      fabric_index: 1_u8,
      privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate
    )
    puts "  Subject 0x#{subj.to_s(16)} has Operate: #{has_access}"
  end
  puts

  # 10. Current ACL state
  puts "10. Current ACL state:"
  puts "  Total ACL entries: #{cluster.acl.size}"
  puts "  Entries by fabric:"
  (1_u8..2_u8).each do |fabric|
    entries = cluster.get_acl_for_fabric(fabric)
    puts "    Fabric #{fabric}: #{entries.size} entries"
    entries.each_with_index do |entry, idx|
      puts "      Entry #{idx + 1}:"
      puts "        Privilege: #{entry.privilege}"
      puts "        Subjects: #{entry.subjects.size}"
      if targets = entry.targets
        puts "        Targets: #{targets.size}"
      else
        puts "        Targets: All"
      end
    end
  end
  puts

  # 11. Privilege hierarchy demonstration
  puts "11. Demonstrating privilege hierarchy:"
  privilege_levels = [
    Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View,
    Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::ProxyView,
    Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
    Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Manage,
    Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
  ]

  puts "  Admin has the following privileges:"
  privilege_levels.each do |priv|
    has_priv = cluster.check_access(
      subject: admin_subject,
      fabric_index: 1_u8,
      privilege: priv
    )
    puts "    #{priv}: #{has_priv}"
  end

  puts
  puts "  Operator has the following privileges:"
  privilege_levels.each do |priv|
    has_priv = cluster.check_access(
      subject: operator_subject,
      fabric_index: 1_u8,
      privilege: priv
    )
    puts "    #{priv}: #{has_priv}"
  end
  puts

  # 12. Remove fabric ACL
  puts "12. Removing all ACL entries for Fabric 2..."
  before_count = cluster.acl.size
  cluster.remove_fabric_acl(2_u8)
  after_count = cluster.acl.size
  puts "  Removed #{before_count - after_count} entries"
  puts "  Total entries remaining: #{after_count}"
  puts

  # 13. Check cluster metadata
  puts "13. Cluster metadata:"
  puts "  Name: #{cluster.name}"
  puts "  Attributes: #{cluster.attributes.size}"
  cluster.attributes.each do |attr|
    puts "    - #{attr.name} (0x#{attr.id.id.to_s(16)}): writable=#{attr.writable}"
  end
  puts

  # 14. Use case: Device sharing
  puts "14. Use case: Device sharing scenario"
  puts "  Scenario: Primary user shares light control with family member"
  puts

  puts "  Primary user (0x#{admin_subject.to_s(16)}):"
  puts "    - Has Administer privilege (full control)"
  puts "    - Can manage all device functions"
  puts "    - Can modify ACL entries"

  puts
  puts "  Family member (0x#{operator_subject.to_s(16)}):"
  puts "    - Has Operate privilege"
  puts "    - Can control lights (on/off, brightness)"
  puts "    - Cannot change device settings or ACLs"

  puts
  puts "  Guest (0x#{viewer_subject.to_s(16)}):"
  puts "    - Has View privilege on specific cluster"
  puts "    - Can only see light status"
  puts "    - Cannot control or modify anything"

  puts
  puts "  This demonstrates Matter's flexible access control for"
  puts "  secure device sharing within and across households."
  puts

  puts "=== Example Complete ==="
end
