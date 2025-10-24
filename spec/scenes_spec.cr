require "./spec_helper"
require "../src/matter/cluster/scenes_cluster"

describe Matter::Cluster::ScenesCluster do
  describe "initialization" do
    it "creates cluster with default values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      cluster.name.should eq("Scenes")
      cluster.cluster_id.id.should eq(0x0005_u32)
      cluster.name_support.should be_true
      cluster.scenes.should be_empty
      cluster.scene_count.should eq(0)
      cluster.current_scene.should eq(0_u8)
      cluster.current_group.should eq(0_u16)
      cluster.scene_valid.should be_false
    end

    it "creates cluster with custom values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(
        endpoint,
        name_support: false,
        max_scenes: 8_u8
      )

      cluster.name_support.should be_false
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      attrs = cluster.attributes
      attrs.size.should eq(7)

      # Check SceneCount attribute
      scene_count = attrs.find { |a| a.id.id == Matter::Cluster::ScenesCluster::SCENE_COUNT }
      scene_count.should_not be_nil
      scene_count.not_nil!.name.should eq("SceneCount")
      scene_count.not_nil!.type.should eq(:uint8)
      scene_count.not_nil!.writable.should be_false

      # Check CurrentScene attribute
      current_scene = attrs.find { |a| a.id.id == Matter::Cluster::ScenesCluster::CURRENT_SCENE }
      current_scene.should_not be_nil
      current_scene.not_nil!.writable.should be_false

      # Check SceneValid attribute
      scene_valid = attrs.find { |a| a.id.id == Matter::Cluster::ScenesCluster::SCENE_VALID }
      scene_valid.should_not be_nil
      scene_valid.not_nil!.type.should eq(:bool)
    end

    it "reads SceneCount attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::ScenesCluster::SCENE_COUNT)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0]) # Initially 0
    end

    it "reads CurrentScene attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::ScenesCluster::CURRENT_SCENE)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0])
    end

    it "reads SceneValid attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::ScenesCluster::SCENE_VALID)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0]) # false
    end

    it "reads NameSupport attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint, name_support: true)

      result = cluster.read_attribute(Matter::Cluster::ScenesCluster::NAME_SUPPORT)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0x80]) # Bit 7 set
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      cmds = cluster.commands
      cmds.size.should eq(8)

      add_scene = cmds.find { |c| c.id.id == Matter::Cluster::ScenesCluster::CMD_ADD_SCENE }
      add_scene.should_not be_nil
      add_scene.not_nil!.name.should eq("AddScene")

      recall_scene = cmds.find { |c| c.id.id == Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE }
      recall_scene.should_not be_nil
    end

    it "executes AddScene command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      initial_version = cluster.data_version

      # Encode: group_id (2 bytes) + scene_id (1 byte) + transition_time (2 bytes) + scene_name
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io) # group_id
      io.write_byte(0x01_u8)                              # scene_id
      IO::ByteFormat::LittleEndian.encode(10_u16, io)     # transition_time (100ms units)
      io.write("Living Room Evening".to_slice)            # scene_name

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_ADD_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      # Response: status (1 byte) + group_id (2 bytes) + scene_id (1 byte)
      response.size.should eq(4)
      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0001_u16)
      response[3].should eq(0x01_u8)

      cluster.scene_count.should eq(1)
      cluster.has_scene?(0x0001_u16, 0x01_u8).should be_true
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes ViewScene command for existing scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add a scene first
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)
      io.write_byte(0x05_u8)
      IO::ByteFormat::LittleEndian.encode(20_u16, io)
      io.write("Kitchen Morning".to_slice)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      # Now view it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)
      io.write_byte(0x05_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_VIEW_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      # Response: status + group_id + scene_id + transition_time + scene_name
      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0002_u16)
      response[3].should eq(0x05_u8)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[4, 2]).should eq(20_u16)
      String.new(response[6..]).should eq("Kitchen Morning")
    end

    it "executes ViewScene command for non-existing scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x9999_u16, io)
      io.write_byte(0xFF_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_VIEW_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      response[0].should eq(Matter::InteractionModel::StatusCode::NotFound.value)
    end

    it "executes RemoveScene command for existing scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0010_u16, io)
      io.write_byte(0x03_u8)
      IO::ByteFormat::LittleEndian.encode(15_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      cluster.scene_count.should eq(1)
      initial_version = cluster.data_version

      # Remove it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0010_u16, io)
      io.write_byte(0x03_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_REMOVE_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0010_u16)
      response[3].should eq(0x03_u8)

      cluster.scene_count.should eq(0)
      cluster.has_scene?(0x0010_u16, 0x03_u8).should be_false
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes RemoveScene command for non-existing scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x9999_u16, io)
      io.write_byte(0xFF_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_REMOVE_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      response[0].should eq(Matter::InteractionModel::StatusCode::NotFound.value)
    end

    it "executes RemoveAllScenes command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add multiple scenes for the same group
      group_id = 0x0001_u16
      [0x01_u8, 0x02_u8, 0x03_u8].each do |scene_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.write_byte(scene_id)
        IO::ByteFormat::LittleEndian.encode(10_u16, io)
        cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)
      end

      # Add a scene for a different group
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)
      io.write_byte(0x01_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      cluster.scene_count.should eq(4)
      initial_version = cluster.data_version

      # Remove all scenes for group 0x0001
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(group_id, io)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_REMOVE_ALL_SCENES,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(group_id)

      cluster.scene_count.should eq(1) # Only scene from group 0x0002 remains
      cluster.has_scene?(group_id, 0x01_u8).should be_false
      cluster.has_scene?(0x0002_u16, 0x01_u8).should be_true
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes StoreScene command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      initial_version = cluster.data_version

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0005_u16, io)
      io.write_byte(0x10_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_STORE_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0005_u16)
      response[3].should eq(0x10_u8)

      cluster.scene_count.should eq(1)
      cluster.has_scene?(0x0005_u16, 0x10_u8).should be_true
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes RecallScene command for existing scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0003_u16, io)
      io.write_byte(0x07_u8)
      IO::ByteFormat::LittleEndian.encode(30_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      cluster.scene_valid.should be_false
      initial_version = cluster.data_version

      # Recall it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0003_u16, io)
      io.write_byte(0x07_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE,
        io.to_slice
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      cluster.current_group.should eq(0x0003_u16)
      cluster.current_scene.should eq(0x07_u8)
      cluster.scene_valid.should be_true
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes RecallScene command for non-existing scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x9999_u16, io)
      io.write_byte(0xFF_u8)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE,
        io.to_slice
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::NotFound
      )

      cluster.scene_valid.should be_false
    end

    it "executes GetSceneMembership command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint, max_scenes: 16_u8)

      # Add some scenes for group 0x0001
      group_id = 0x0001_u16
      [0x02_u8, 0x05_u8, 0x08_u8].each do |scene_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.write_byte(scene_id)
        IO::ByteFormat::LittleEndian.encode(10_u16, io)
        cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)
      end

      # Add scene for different group
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io)
      io.write_byte(0x01_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      # Get membership for group 0x0001
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(group_id, io)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_GET_SCENE_MEMBERSHIP,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      # Response: status + capacity + group_id + count + scene_ids
      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      capacity = response[1]
      capacity.should eq(12) # 16 - 4
      IO::ByteFormat::LittleEndian.decode(UInt16, response[2, 2]).should eq(group_id)

      count = response[4]
      count.should eq(3)

      # Check scene IDs
      scene_ids = [] of UInt8
      3.times do |i|
        scene_ids << response[5 + i]
      end

      scene_ids.should contain(0x02_u8)
      scene_ids.should contain(0x05_u8)
      scene_ids.should contain(0x08_u8)
    end

    it "executes CopyScene command for single scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add source scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      IO::ByteFormat::LittleEndian.encode(25_u16, io)
      io.write("Original Scene".to_slice)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      cluster.scene_count.should eq(1)
      initial_version = cluster.data_version

      # Copy scene: mode=0, from group 1 scene 5, to group 2 scene 10
      io = IO::Memory.new
      io.write_byte(0x00_u8)                              # mode (copy single)
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io) # group_id_from
      io.write_byte(0x05_u8)                              # scene_id_from
      IO::ByteFormat::LittleEndian.encode(0x0002_u16, io) # group_id_to
      io.write_byte(0x0A_u8)                              # scene_id_to

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_COPY_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      IO::ByteFormat::LittleEndian.decode(UInt16, response[1, 2]).should eq(0x0001_u16)
      response[3].should eq(0x05_u8)

      cluster.scene_count.should eq(2)
      cluster.has_scene?(0x0001_u16, 0x05_u8).should be_true
      cluster.has_scene?(0x0002_u16, 0x0A_u8).should be_true
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes CopyScene command for all scenes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add multiple scenes for group 0x0001
      [0x01_u8, 0x02_u8, 0x03_u8].each do |scene_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
        io.write_byte(scene_id)
        IO::ByteFormat::LittleEndian.encode(10_u16, io)
        cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)
      end

      cluster.scene_count.should eq(3)

      # Copy all scenes: mode=1 (copy all), from group 1 to group 3
      io = IO::Memory.new
      io.write_byte(0x01_u8)                              # mode (copy all)
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io) # group_id_from
      io.write_byte(0x00_u8)                              # scene_id_from (ignored)
      IO::ByteFormat::LittleEndian.encode(0x0003_u16, io) # group_id_to
      io.write_byte(0x00_u8)                              # scene_id_to (ignored)

      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_COPY_SCENE,
        io.to_slice
      )

      result.should be_a(Bytes)
      response = result.as(Bytes)

      response[0].should eq(Matter::InteractionModel::StatusCode::Success.value)

      cluster.scene_count.should eq(6) # 3 original + 3 copied
      cluster.has_scene?(0x0001_u16, 0x01_u8).should be_true
      cluster.has_scene?(0x0003_u16, 0x01_u8).should be_true
      cluster.has_scene?(0x0003_u16, 0x02_u8).should be_true
      cluster.has_scene?(0x0003_u16, 0x03_u8).should be_true
    end

    it "rejects commands with invalid data" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Try AddScene with only 2 bytes (needs at least 5)
      result = cluster.invoke_command(
        Matter::Cluster::ScenesCluster::CMD_ADD_SCENE,
        Bytes[0x01, 0x00]
      )

      result.should be_a(Bytes)
      result.as(Bytes)[0].should eq(Matter::InteractionModel::StatusCode::InvalidCommand.value)
    end
  end

  describe "capacity management" do
    it "respects max_scenes limit" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint, max_scenes: 3_u8)

      # Add scenes up to the limit
      [0x01_u8, 0x02_u8, 0x03_u8].each_with_index do |scene_id, idx|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
        io.write_byte(scene_id)
        IO::ByteFormat::LittleEndian.encode(10_u16, io)
        result = cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)
        result.as(Bytes)[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      end

      # Try to add one more (should fail)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x04_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      result = cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      result.as(Bytes)[0].should eq(Matter::InteractionModel::StatusCode::ResourceExhausted.value)
      cluster.scene_count.should eq(3)
    end

    it "allows updating existing scene when at capacity" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint, max_scenes: 2_u8)

      # Fill to capacity
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x01_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      io.write("Scene 1".to_slice)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x02_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      io.write("Scene 2".to_slice)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      # Update existing scene (should succeed)
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x01_u8)
      IO::ByteFormat::LittleEndian.encode(20_u16, io)
      io.write("Updated Scene 1".to_slice)
      result = cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      result.as(Bytes)[0].should eq(Matter::InteractionModel::StatusCode::Success.value)
      cluster.scene_count.should eq(2)
    end
  end

  describe "scene validation" do
    it "invalidates current scene when removed" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add and recall a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE, io.to_slice)

      cluster.scene_valid.should be_true

      # Remove the current scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_REMOVE_SCENE, io.to_slice)

      cluster.scene_valid.should be_false
    end

    it "invalidates current scene when group is cleared" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add and recall a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE, io.to_slice)

      cluster.scene_valid.should be_true

      # Remove all scenes for the group
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_REMOVE_ALL_SCENES, io.to_slice)

      cluster.scene_valid.should be_false
    end
  end

  describe "callback mechanism" do
    it "calls on_recall_scene callback when RecallScene command is executed" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0003_u16, io)
      io.write_byte(0x07_u8)
      IO::ByteFormat::LittleEndian.encode(30_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      callback_called = false
      callback_group_id : UInt16 = 0_u16
      callback_scene_id : UInt8 = 0_u8

      cluster.on_recall_scene = ->(group_id : UInt16, scene_id : UInt8) {
        callback_called = true
        callback_group_id = group_id
        callback_scene_id = scene_id
      }

      # Recall the scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0003_u16, io)
      io.write_byte(0x07_u8)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE, io.to_slice)

      callback_called.should be_true
      callback_group_id.should eq(0x0003_u16)
      callback_scene_id.should eq(0x07_u8)
    end
  end

  describe "helper methods" do
    it "checks scene existence with has_scene?" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      cluster.has_scene?(0x0001_u16, 0x05_u8).should be_false

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      cluster.has_scene?(0x0001_u16, 0x05_u8).should be_true
      cluster.has_scene?(0x0001_u16, 0x06_u8).should be_false
    end

    it "returns correct scene_count" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      cluster.scene_count.should eq(0)

      # Add scenes
      [0x01_u8, 0x02_u8].each do |scene_id|
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
        io.write_byte(scene_id)
        IO::ByteFormat::LittleEndian.encode(10_u16, io)
        cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)
      end

      cluster.scene_count.should eq(2)
    end

    it "manually invalidates current scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add and recall a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x05_u8)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE, io.to_slice)

      cluster.scene_valid.should be_true

      cluster.invalidate_current_scene

      cluster.scene_valid.should be_false
    end
  end

  describe "data versioning" do
    it "increments version on scene additions" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      initial_version = cluster.data_version

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x01_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      cluster.data_version.should eq(initial_version + 1)
    end

    it "increments version on scene recalls" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x01_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      version_after_add = cluster.data_version

      # Recall it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x01_u8)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_RECALL_SCENE, io.to_slice)

      cluster.data_version.should eq(version_after_add + 1)
    end

    it "increments version on scene removals" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesCluster.new(endpoint)

      # Add a scene
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x01_u8)
      IO::ByteFormat::LittleEndian.encode(10_u16, io)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_ADD_SCENE, io.to_slice)

      version_after_add = cluster.data_version

      # Remove it
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0x0001_u16, io)
      io.write_byte(0x01_u8)
      cluster.invoke_command(Matter::Cluster::ScenesCluster::CMD_REMOVE_SCENE, io.to_slice)

      cluster.data_version.should eq(version_after_add + 1)
    end
  end
end
