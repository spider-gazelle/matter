require "../spec_helper"
require "../../src/matter/cluster/access_control_cluster"
require "../../src/matter/protocol/im_handler"

describe Matter::Cluster::AccessControlCluster do
  describe "iPhone ACL write request" do
    # This is the actual decrypted WriteRequest payload captured from an iPhone during commissioning
    # The full TLV payload from the log is:
    # 1528002801360215370124020024031f2404001836021524010524020236030701001d32fdffffff060498fabe183404181524010324020236030701002b4ffdffffff18340418181818280324ff0c18
    it "parses ACL write request from iPhone" do
      # Full WriteRequest TLV payload (without the protocol header)
      write_request_hex = "1528002801360215370124020024031f2404001836021524010524020236030701001d32fdffffff060498fabe183404181524010324020236030701002b4ffdffffff18340418181818280324ff0c18"
      write_request_bytes = write_request_hex.hexbytes

      # Parse the WriteRequest using im_handler
      request = Matter::Protocol::IMHandler.parse_write_request(write_request_bytes)
      request.should_not be_nil

      # Should have 1 write request
      request.not_nil!.write_requests.size.should eq(1)

      # Extract the value that will be passed to write_attribute
      acl_value = request.not_nil!.write_requests[0].value
      puts "ACL value size: #{acl_value.size} bytes"
      puts "ACL value hex: #{acl_value.hexstring}"

      # Now try to decode it with the access control cluster
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      status = cluster.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, acl_value)
      puts "Write status: #{status.status}"

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)

      # Verify we got 2 ACL entries
      cluster.acl.size.should eq(2)

      # First entry should be Administer privilege
      cluster.acl[0].privilege.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer)
      cluster.acl[0].auth_mode.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE)

      # Second entry should be Operate privilege
      cluster.acl[1].privilege.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate)
      cluster.acl[1].auth_mode.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE)
    end

    it "decodes ACL TLV value directly" do
      # This is a minimal test case - just the ACL array portion encoded as TLV
      # Two entries: Administer with subject, Operate with subject
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # First, let's see what the encoded format looks like for a known entry
      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x12345678_u64],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
      puts "Encoded ACL: #{encoded.as(Bytes).hexstring}"

      # Try round-trip
      cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
      status = cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, encoded.as(Bytes))
      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster2.acl.size.should eq(1)
    end
  end

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
      # Empty list should be encoded as empty TLV array (not just Bytes.new(0))
      value.as(Bytes).size.should be > 0
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
      # Value is TLV-encoded
      parsed = TLV::Any.from_slice(value.as(Bytes))
      subjects = parsed.value.as(Int).to_u16
      subjects.should eq(4_u16)
    end

    it "reads TargetsPerAccessControlEntry attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_TARGETS_PER_ACCESS_CONTROL_ENTRY)
      value.should be_a(Bytes)
      # Value is TLV-encoded
      parsed = TLV::Any.from_slice(value.as(Bytes))
      targets = parsed.value.as(Int).to_u16
      targets.should eq(3_u16)
    end

    it "reads AccessControlEntriesPerFabric attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACCESS_CONTROL_ENTRIES_PER_FABRIC)
      value.should be_a(Bytes)
      # Value is TLV-encoded
      parsed = TLV::Any.from_slice(value.as(Bytes))
      entries = parsed.value.as(Int).to_u16
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

  describe "CaseAuthenticatedTag (CAT) subject matching" do
    it "matches CAT subjects with same identity and version" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # Create CAT-encoded subject (identity=0x1234, version=0x0001)
      cat = Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32)
      cat_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(cat)

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [cat_node_id.id],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      # Should match with same identity and version
      cluster.check_access(
        subject: cat_node_id.id,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      ).should be_true
    end

    it "matches CAT subjects when incoming version is higher" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # ACL has CAT with version 0x0001
      acl_cat = Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32)
      acl_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(acl_cat)

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [acl_node_id.id],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      # Incoming request has CAT with version 0x0005 (higher than ACL version)
      incoming_cat = Matter::DataType::CaseAuthenticatedTag.new(0x12340005_u32)
      incoming_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(incoming_cat)

      cluster.check_access(
        subject: incoming_node_id.id,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      ).should be_true
    end

    it "denies CAT subjects when incoming version is lower" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # ACL has CAT with version 0x0005
      acl_cat = Matter::DataType::CaseAuthenticatedTag.new(0x12340005_u32)
      acl_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(acl_cat)

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [acl_node_id.id],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      # Incoming request has CAT with version 0x0001 (lower than ACL version)
      incoming_cat = Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32)
      incoming_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(incoming_cat)

      cluster.check_access(
        subject: incoming_node_id.id,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      ).should be_false
    end

    it "denies CAT subjects with different identity" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # ACL has CAT with identity 0x1234
      acl_cat = Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32)
      acl_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(acl_cat)

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [acl_node_id.id],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      # Incoming request has CAT with different identity 0x5678
      incoming_cat = Matter::DataType::CaseAuthenticatedTag.new(0x56780001_u32)
      incoming_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(incoming_cat)

      cluster.check_access(
        subject: incoming_node_id.id,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      ).should be_false
    end

    it "requires exact match when mixing CAT and regular NodeIds" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

      # ACL has regular NodeId
      regular_node_id = 0x1122334455667788_u64

      entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [regular_node_id],
        targets: nil,
        fabric_index: 1_u8
      )
      cluster.acl << entry

      # Incoming request with CAT-encoded NodeId should not match
      cat = Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32)
      cat_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(cat)

      cluster.check_access(
        subject: cat_node_id.id,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      ).should be_false

      # Regular NodeId should still match exactly
      cluster.check_access(
        subject: regular_node_id,
        fabric_index: 1_u8,
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
      ).should be_true
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

  describe "TLV encoding/decoding" do
    describe "ACL list" do
      it "encodes and decodes empty ACL list" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Read empty ACL list
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
        encoded.should be_a(Bytes)

        # Write it back
        status = cluster.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, encoded.as(Bytes))
        status.status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.acl.should be_empty
      end

      it "encodes and decodes single ACL entry" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Add ACL entry
        entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
          privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
          auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
          subjects: [0x1111_u64],
          targets: nil,
          fabric_index: 1_u8
        )
        cluster.acl << entry

        # Encode
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
        encoded.should be_a(Bytes)
        encoded.as(Bytes).size.should be > 0

        # Decode into new cluster
        cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
        status = cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, encoded.as(Bytes))
        status.status.should eq(Matter::InteractionModel::StatusCode::Success)

        # Verify decoded entry
        cluster2.acl.size.should eq(1)
        decoded_entry = cluster2.acl[0]
        decoded_entry.privilege.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer)
        decoded_entry.auth_mode.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE)
        decoded_entry.subjects.should eq([0x1111_u64])
        decoded_entry.targets.should be_nil
        decoded_entry.fabric_index.should eq(1_u8)
      end

      it "encodes and decodes ACL entry with multiple subjects" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Add ACL entry with multiple subjects
        entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
          privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
          auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
          subjects: [0x1111_u64, 0x2222_u64, 0x3333_u64],
          targets: nil,
          fabric_index: 2_u8
        )
        cluster.acl << entry

        # Round-trip
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
        cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
        cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, encoded.as(Bytes))

        # Verify
        cluster2.acl.size.should eq(1)
        cluster2.acl[0].subjects.size.should eq(3)
        cluster2.acl[0].subjects.should eq([0x1111_u64, 0x2222_u64, 0x3333_u64])
      end

      it "encodes and decodes ACL entry with targets" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Add ACL entry with targets
        targets = [
          Matter::Cluster::AccessControlCluster::Target.new(
            cluster: 0x0006_u32,
            endpoint: 1_u16,
            device_type: nil
          ),
          Matter::Cluster::AccessControlCluster::Target.new(
            cluster: nil,
            endpoint: nil,
            device_type: 0x0100_u32
          ),
        ]

        entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
          privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Manage,
          auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
          subjects: [0x4444_u64],
          targets: targets,
          fabric_index: 1_u8
        )
        cluster.acl << entry

        # Round-trip
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
        cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
        cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, encoded.as(Bytes))

        # Verify
        cluster2.acl.size.should eq(1)
        decoded_targets = cluster2.acl[0].targets
        decoded_targets.should_not be_nil
        decoded_targets.not_nil!.size.should eq(2)

        # First target
        decoded_targets.not_nil![0].cluster.should eq(0x0006_u32)
        decoded_targets.not_nil![0].endpoint.should eq(1_u16)
        decoded_targets.not_nil![0].device_type.should be_nil

        # Second target
        decoded_targets.not_nil![1].cluster.should be_nil
        decoded_targets.not_nil![1].endpoint.should be_nil
        decoded_targets.not_nil![1].device_type.should eq(0x0100_u32)
      end

      it "encodes and decodes multiple ACL entries" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Add multiple entries
        3.times do |i|
          entry = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
            privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
            auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
            subjects: [(i + 1).to_u64 * 0x1111],
            targets: nil,
            fabric_index: 1_u8
          )
          cluster.acl << entry
        end

        # Round-trip
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
        cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
        cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, encoded.as(Bytes))

        # Verify
        cluster2.acl.size.should eq(3)
        cluster2.acl[0].subjects.should eq([0x1111_u64])
        cluster2.acl[1].subjects.should eq([0x2222_u64])
        cluster2.acl[2].subjects.should eq([0x3333_u64])
      end

      it "handles invalid TLV data gracefully" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Try to write invalid data
        invalid_data = Bytes[0xFF, 0xFF, 0xFF]
        status = cluster.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, invalid_data)

        status.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end
    end

    describe "Extension list" do
      it "encodes and decodes empty extension list" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Read empty extension list
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION)
        encoded.should be_a(Bytes)

        # Write it back
        status = cluster.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION, encoded.as(Bytes))
        status.status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.extension.should be_empty
      end

      it "encodes and decodes single extension entry" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Add extension entry
        extension = Matter::Cluster::AccessControlCluster::ExtensionEntry.new(
          data: Bytes[0x01, 0x02, 0x03, 0x04],
          fabric_index: 1_u8
        )
        cluster.extension << extension

        # Round-trip
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION)
        cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
        status = cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION, encoded.as(Bytes))
        status.status.should eq(Matter::InteractionModel::StatusCode::Success)

        # Verify
        cluster2.extension.size.should eq(1)
        cluster2.extension[0].data.should eq(Bytes[0x01, 0x02, 0x03, 0x04])
        cluster2.extension[0].fabric_index.should eq(1_u8)
      end

      it "encodes and decodes multiple extension entries" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Add multiple extensions
        cluster.extension << Matter::Cluster::AccessControlCluster::ExtensionEntry.new(
          data: Bytes[0xAA, 0xBB],
          fabric_index: 1_u8
        )
        cluster.extension << Matter::Cluster::AccessControlCluster::ExtensionEntry.new(
          data: Bytes[0xCC, 0xDD, 0xEE],
          fabric_index: 2_u8
        )

        # Round-trip
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION)
        cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
        cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION, encoded.as(Bytes))

        # Verify
        cluster2.extension.size.should eq(2)
        cluster2.extension[0].data.should eq(Bytes[0xAA, 0xBB])
        cluster2.extension[0].fabric_index.should eq(1_u8)
        cluster2.extension[1].data.should eq(Bytes[0xCC, 0xDD, 0xEE])
        cluster2.extension[1].fabric_index.should eq(2_u8)
      end

      it "handles invalid TLV data gracefully" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Try to write invalid data
        invalid_data = Bytes[0xFF, 0xFF, 0xFF]
        status = cluster.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_EXTENSION, invalid_data)

        status.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end
    end

    describe "fabric-scoped encoding" do
      it "preserves fabric index in ACL entries" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::AccessControlCluster.new(endpoint_id)

        # Add entries for different fabrics
        cluster.acl << Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
          privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
          auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
          subjects: [0x1111_u64],
          targets: nil,
          fabric_index: 1_u8
        )
        cluster.acl << Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
          privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Operate,
          auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
          subjects: [0x2222_u64],
          targets: nil,
          fabric_index: 2_u8
        )

        # Round-trip
        encoded = cluster.read_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL)
        cluster2 = Matter::Cluster::AccessControlCluster.new(endpoint_id)
        cluster2.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, encoded.as(Bytes))

        # Verify fabric isolation is preserved
        cluster2.acl.size.should eq(2)
        cluster2.acl[0].fabric_index.should eq(1_u8)
        cluster2.acl[1].fabric_index.should eq(2_u8)
      end
    end
  end
end
