require "../spec_helper"
require "../../src/matter/cluster/access_control_cluster"

describe Matter::Cluster::AccessControlCluster do
  describe "initialization" do
    it "creates access control cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x001F_u32)
      cluster.name.should eq("AccessControl")
      cluster.acl.should be_empty
      cluster.extension.should be_empty
      cluster.subjects_per_access_control_entry.should eq(4_u16)
      cluster.targets_per_access_control_entry.should eq(3_u16)
      cluster.access_control_entries_per_fabric.should eq(4_u16)
    end
  end

  describe "attributes" do
    it "reads ACL attribute when empty" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes.new(0)) # Empty list
    end

    it "reads Extension attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION)
      value.should be_a(Bytes)
    end

    it "reads SubjectsPerAccessControlEntry attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_SUBJECTS_PER_ACCESS_CONTROL_ENTRY)
      value.should be_a(Bytes)
      io = IO::Memory.new(value.as(Bytes))
      subjects = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
      subjects.should eq(4_u16)
    end

    it "reads TargetsPerAccessControlEntry attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_TARGETS_PER_ACCESS_CONTROL_ENTRY)
      value.should be_a(Bytes)
      io = IO::Memory.new(value.as(Bytes))
      targets = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
      targets.should eq(3_u16)
    end

    it "reads AccessControlEntriesPerFabric attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACCESS_CONTROL_ENTRIES_PER_FABRIC)
      value.should be_a(Bytes)
      io = IO::Memory.new(value.as(Bytes))
      entries = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
      entries.should eq(4_u16)
    end

    it "returns status for unsupported attribute write" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::AccessControlCluster::ATTR_SUBJECTS_PER_ACCESS_CONTROL_ENTRY,
        Bytes[10, 0]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 5

      acl_attr = attributes.find { |a| a.id.id == Matter::Cluster::AccessControlCluster::ATTR_ACL }
      acl_attr.should_not be_nil
      acl_attr.not_nil!.name.should eq("ACL")
      acl_attr.not_nil!.writable.should be_true
    end
  end

  describe "AccessControlEntry" do
    it "creates access control entry" do
      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1122334455667788_u64],
        targets: nil,
        fabric_index: 1_u8
      )

      entry.privilege.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer)
      entry.auth_mode.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE)
      entry.subjects.should eq([0x1122334455667788_u64])
      entry.targets.should be_nil
      entry.fabric_index.should eq(1_u8)
    end

    it "creates entry with multiple subjects" do
      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64, 0x2222_u64, 0x3333_u64],
        targets: nil,
        fabric_index: 1_u8
      )

      entry.subjects.size.should eq(3)
    end

    it "creates entry with targets" do
      target = Matter::Cluster::AccessControlCluster::Target.new(
        cluster: 0x0006_u32,
        endpoint: 1_u16,
        device_type: nil
      )

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Manage,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x4444_u64],
        targets: [target],
        fabric_index: 1_u8
      )

      entry.targets.should_not be_nil
      entry.targets.not_nil!.size.should eq(1)
    end
  end

  describe "Target" do
    it "creates cluster target" do
      target = Matter::Cluster::AccessControlCluster::Target.new(
        cluster: 0x0006_u32,
        endpoint: nil,
        device_type: nil
      )

      target.cluster.should eq(0x0006_u32)
      target.endpoint.should be_nil
      target.device_type.should be_nil
    end

    it "creates endpoint target" do
      target = Matter::Cluster::AccessControlCluster::Target.new(
        cluster: nil,
        endpoint: 1_u16,
        device_type: nil
      )

      target.cluster.should be_nil
      target.endpoint.should eq(1_u16)
      target.device_type.should be_nil
    end

    it "creates device type target" do
      target = Matter::Cluster::AccessControlCluster::Target.new(
        cluster: nil,
        endpoint: nil,
        device_type: 0x0100_u32
      )

      target.cluster.should be_nil
      target.endpoint.should be_nil
      target.device_type.should eq(0x0100_u32)
    end
  end

  describe "AccessControlEntryPrivilege" do
    it "defines privilege levels" do
      Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View.value.should eq(1_u8)
      Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::ProxyView.value.should eq(2_u8)
      Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate.value.should eq(3_u8)
      Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Manage.value.should eq(4_u8)
      Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer.value.should eq(5_u8)
    end
  end

  describe "AccessControlEntryAuthMode" do
    it "defines auth modes" do
      Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::PASE.value.should eq(1_u8)
      Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE.value.should eq(2_u8)
      Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::Group.value.should eq(3_u8)
    end
  end

  describe "ACL management" do
    it "adds ACL entry" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 1_u8
      )

      cluster.acl << entry
      cluster.acl.size.should eq(1)
    end

    it "tracks multiple ACL entries" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      3.times do |i|
        entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
          privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
          auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
          subjects: [(i + 1).to_u64],
          targets: nil,
          fabric_index: 1_u8
        )
        cluster.acl << entry
      end

      cluster.acl.size.should eq(3)
    end
  end

  describe "access checking" do
    it "checks if subject has access" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      has_access = cluster.check_access(
        subject: 0x1111_u64,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      )

      has_access.should be_true
    end

    it "denies access for non-matching subject" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      has_access = cluster.check_access(
        subject: 0x2222_u64,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      )

      has_access.should be_false
    end

    it "checks privilege hierarchy" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # User has Operate privilege
      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      # Should have View access (lower privilege)
      cluster.check_access(
        subject: 0x1111_u64,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      ).should be_true

      # Should NOT have Administer access (higher privilege)
      cluster.check_access(
        subject: 0x1111_u64,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer
      ).should be_false
    end
  end

  describe "fabric isolation" do
    it "isolates ACL entries by fabric" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # Entry for fabric 1
      entry1 = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry1

      # Entry for fabric 2
      entry2 = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 2_u8
      )
      cluster.acl << entry2

      # Subject should have different privileges on different fabrics
      cluster.check_access(
        subject: 0x1111_u64,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer
      ).should be_true

      cluster.check_access(
        subject: 0x1111_u64,
        fabric_index: 2_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer
      ).should be_false
    end
  end

  describe "extension entries" do
    it "stores extension entries" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      extension = Matter::Cluster::AccessControlCluster::ExtensionEntry.new(
        data: Bytes[0x01, 0x02, 0x03],
        fabric_index: 1_u8
      )

      cluster.extension << extension
      cluster.extension.size.should eq(1)
    end
  end
end
