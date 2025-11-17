require "./spec_helper"
require "../src/matter/cluster/groups_cluster"

describe Matter::Cluster::GroupsCluster do
  describe "initialization" do
    it "creates cluster with default values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      cluster.name.should eq("Groups")
      cluster.cluster_id.id.should eq(0x0004_u32)
      cluster.name_support.should be_true
      cluster.groups.should be_empty
      cluster.group_count.should eq(0)
    end

    it "creates cluster with custom values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(
        endpoint,
        name_support: false,
        max_groups: 8_u8
      )

      cluster.name_support.should be_false
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      attrs = cluster.attributes
      attrs.size.should eq(3)

      # Check NameSupport attribute
      name_support = attrs.find { |a| a.id.id == Matter::Cluster::GroupsCluster::NAME_SUPPORT }
      name_support.should_not be_nil
      name_support.not_nil!.name.should eq("NameSupport")
      name_support.not_nil!.type.should eq(:uint8)
      name_support.not_nil!.writable.should be_false
    end

    it "reads NameSupport attribute when enabled" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint, name_support: true)

      result = cluster.read_attribute(Matter::Cluster::GroupsCluster::NAME_SUPPORT)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(0x80_u8) # Bit 7 set
    end

    it "reads NameSupport attribute when disabled" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint, name_support: false)

      result = cluster.read_attribute(Matter::Cluster::GroupsCluster::NAME_SUPPORT)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(0x00_u8)
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      cmds = cluster.commands
      cmds.size.should eq(6)

      add_group = cmds.find { |c| c.id.id == Matter::Cluster::GroupsCluster::CMD_ADD_GROUP }
      add_group.should_not be_nil
      add_group.not_nil!.name.should eq("AddGroup")
    end

    it "executes AddGroup command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      initial_version = cluster.data_version

      # Encode group_id (0x0001) and group_name ("Living Room")
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write("Living Room".to_slice)

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_ADD_GROUP,
        io.to_slice
      )

      result.should be_a(Matter::Cluster::CommandResponse)
      response = result.as(Matter::Cluster::CommandResponse).data

      # Response: status (1 byte) + group_id (2 bytes)
      response.size.should eq(3)
      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0001_u16)

      cluster.group_count.should eq(1)
      cluster.member_of?(0x0001_u16).should be_true
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes ViewGroup command for existing group" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      # Add a group first
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)
      io.write("Kitchen".to_slice)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      # Now view it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_VIEW_GROUP,
        io.to_slice
      )

      result.should be_a(Matter::Cluster::CommandResponse)
      response = result.as(Matter::Cluster::CommandResponse).data

      # Response: status (1 byte) + group_id (2 bytes) + group_name
      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0002_u16)
      String.new(response[3..]).should eq("Kitchen")
    end

    it "executes ViewGroup command for non-existing group" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x9999_u16, io)

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_VIEW_GROUP,
        io.to_slice
      )

      result.should be_a(Matter::Cluster::CommandResponse)
      response = result.as(Matter::Cluster::CommandResponse).data

      response[0].should eq(Matter::InteractionModel::StatusCode::NotFound.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x9999_u16)
    end

    it "executes GetGroupMembership command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint, max_groups: 16_u8)

      # Add some groups
      [0x0001_u16, 0x0002_u16, 0x0003_u16].each do |group_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.write("Group #{group_id}".to_slice)
        cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
      end

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_GET_GROUP_MEMBERSHIP,
        Bytes.new(0)
      )

      result.should be_a(Matter::Cluster::CommandResponse)
      response = result.as(Matter::Cluster::CommandResponse).data

      # Response: capacity (1 byte) + count (1 byte) + group_ids (2 bytes each)
      capacity = response[0]
      count = response[1]

      capacity.should eq(13) # 16 - 3
      count.should eq(3)

      # Check group IDs
      group_ids = [] of UInt16
      3.times do |i|
        group_id = IO::ByteFormat::LittleEndian.decode(UInt16, response[2 + i*2, 2])
        group_ids << group_id
      end

      group_ids.should contain(0x0001_u16)
      group_ids.should contain(0x0002_u16)
      group_ids.should contain(0x0003_u16)
    end

    it "executes RemoveGroup command for existing group" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      # Add a group
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0010_u16, io)
      io.write("Bedroom".to_slice)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      cluster.group_count.should eq(1)
      initial_version = cluster.data_version

      # Remove it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0010_u16, io)

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_REMOVE_GROUP,
        io.to_slice
      )

      result.should be_a(Matter::Cluster::CommandResponse)
      response = result.as(Matter::Cluster::CommandResponse).data

      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0010_u16)

      cluster.group_count.should eq(0)
      cluster.member_of?(0x0010_u16).should be_false
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes RemoveGroup command for non-existing group" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x9999_u16, io)

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_REMOVE_GROUP,
        io.to_slice
      )

      result.should be_a(Matter::Cluster::CommandResponse)
      response = result.as(Matter::Cluster::CommandResponse).data

      response[0].should eq(Matter::InteractionModel::StatusCode::NotFound.value)
    end

    it "executes RemoveAllGroups command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      # Add multiple groups
      [0x0001_u16, 0x0002_u16, 0x0003_u16].each do |group_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
      end

      cluster.group_count.should eq(3)
      initial_version = cluster.data_version

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_REMOVE_ALL_GROUPS,
        Bytes.new(0)
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      cluster.group_count.should eq(0)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes AddGroupIfIdentifying command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0020_u16, io)
      io.write("Office".to_slice)

      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_ADD_GROUP_IF_IDENTIFYING,
        io.to_slice
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      cluster.member_of?(0x0020_u16).should be_true
    end

    it "rejects commands with invalid data" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      # Try AddGroup with only 1 byte (needs at least 2 for group_id)
      result = cluster.invoke_command(
        Matter::Cluster::GroupsCluster::CMD_ADD_GROUP,
        Bytes[0x01]
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::InvalidCommand
      )
    end
  end

  describe "capacity management" do
    it "respects max_groups limit" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint, max_groups: 3_u8)

      # Add groups up to the limit
      [0x0001_u16, 0x0002_u16, 0x0003_u16].each do |group_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        result = cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
        result.as(Matter::Cluster::CommandResponse).data[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      end

      # Try to add one more (should fail)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0004_u16, io)
      result = cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      result.as(Matter::Cluster::CommandResponse).data[0].should eq(Matter::InteractionModel::StatusCode::ResourceExhausted.value)
      cluster.group_count.should eq(3)
    end

    it "allows updating existing group when at capacity" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint, max_groups: 2_u8)

      # Fill to capacity
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write("Group 1".to_slice)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)
      io.write("Group 2".to_slice)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      # Update existing group (should succeed)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write("Updated Group 1".to_slice)
      result = cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      result.as(Matter::Cluster::CommandResponse).data[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      cluster.group_count.should eq(2)
    end
  end

  describe "helper methods" do
    it "checks group membership with member_of?" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      cluster.member_of?(0x0001_u16).should be_false

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      cluster.member_of?(0x0001_u16).should be_true
      cluster.member_of?(0x0002_u16).should be_false
    end

    it "returns correct group_count" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      cluster.group_count.should eq(0)

      # Add groups
      [0x0001_u16, 0x0002_u16].each do |group_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
      end

      cluster.group_count.should eq(2)
    end
  end

  describe "data versioning" do
    it "increments version on group additions" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      initial_version = cluster.data_version

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      cluster.data_version.should eq(initial_version + 1)
    end

    it "increments version on group removals" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      # Add a group
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)

      version_after_add = cluster.data_version

      # Remove it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_REMOVE_GROUP, io.to_slice)

      cluster.data_version.should eq(version_after_add + 1)
    end

    it "increments version on remove all groups" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::GroupsCluster.new(endpoint)

      # Add groups
      [0x0001_u16, 0x0002_u16].each do |group_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, io.to_slice)
      end

      version_before_clear = cluster.data_version

      cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_REMOVE_ALL_GROUPS, Bytes.new(0))

      cluster.data_version.should eq(version_before_clear + 1)
    end
  end
end
