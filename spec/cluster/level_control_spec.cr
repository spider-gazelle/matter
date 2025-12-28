require "../spec_helper"
require "../../src/matter/cluster/level_control_cluster"

# Note: Time-based transition tests from matter.js behavioral tests
# (packages/node/test/behaviors/level-control/LevelControlServerTest.ts)
# require transition manager support with gradual level updates over time.
# Current implementation performs instant level changes.
# These tests can be added when transition support is implemented.

describe Matter::Cluster::LevelControlCluster do
  describe "initialization" do
    it "creates level control cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0008_u32)
      cluster.name.should eq("LevelControl")
      cluster.current_level.should eq(0_u8)
      cluster.min_level.should eq(0_u8)
      cluster.max_level.should eq(254_u8)
    end

    it "initializes with custom values" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 127_u8,
        min_level: 10_u8,
        max_level: 200_u8
      )

      cluster.current_level.should eq(127_u8)
      cluster.min_level.should eq(10_u8)
      cluster.max_level.should eq(200_u8)
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 3

      current_level = attributes.find { |attr| attr.id.id == Matter::Cluster::LevelControlCluster::ATTR_CURRENT_LEVEL }
      current_level.should_not be_nil
      current_level_attr = current_level.as(Matter::Cluster::AttributeMetadata)
      current_level_attr.name.should eq("currentLevel")
      current_level_attr.writable?.should be_false

      min_level = attributes.find { |attr| attr.id.id == Matter::Cluster::LevelControlCluster::ATTR_MIN_LEVEL }
      min_level.should_not be_nil

      max_level = attributes.find { |attr| attr.id.id == Matter::Cluster::LevelControlCluster::ATTR_MAX_LEVEL }
      max_level.should_not be_nil
    end

    it "reads CurrentLevel attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_CURRENT_LEVEL)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(100_u8)
    end

    it "reads MinLevel attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, min_level: 5_u8)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_MIN_LEVEL)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(5_u8)
    end

    it "reads MaxLevel attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, max_level: 200_u8)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_MAX_LEVEL)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(200_u8)
    end

    it "reads RemainingTime attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_REMAINING_TIME)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(0_u16)
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      commands = cluster.commands
      commands.size.should be >= 4

      move_to_level = commands.find { |cmd| cmd.id.id == Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL }
      move_to_level.should_not be_nil
      move_to_level.as(Matter::Cluster::CommandMetadata).name.should eq("moveToLevel")

      move = commands.find { |cmd| cmd.id.id == Matter::Cluster::LevelControlCluster::CMD_MOVE }
      move.should_not be_nil

      step = commands.find { |cmd| cmd.id.id == Matter::Cluster::LevelControlCluster::CMD_STEP }
      step.should_not be_nil

      stop = commands.find { |cmd| cmd.id.id == Matter::Cluster::LevelControlCluster::CMD_STOP }
      stop.should_not be_nil
    end

    it "executes MoveToLevel command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 0_u8)

      cluster.current_level.should eq(0_u8)

      request = Matter::Cluster::Definitions::LevelControl::MoveToLevelRequest.new(
        level: 200_u8,
        transition_time: 10_u16,
        mask: 0_u8,
        override: 0_u8
      )
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        request.to_slice
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_level.should eq(200_u8)
    end

    it "executes Move command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      request = Matter::Cluster::Definitions::LevelControl::MoveRequest.new(
        move_mode: Matter::Cluster::Definitions::LevelControl::MoveMode::Up,
        rate: 10_u8,
        mask: 0_u8,
        override: 0_u8
      )
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE,
        request.to_slice
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
    end

    it "executes Step command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      request = Matter::Cluster::Definitions::LevelControl::StepRequest.new(
        step_mode: Matter::Cluster::Definitions::LevelControl::StepMode::Up,
        step_size: 20_u8,
        transition_time: 5_u16,
        mask: 0_u8,
        override: 0_u8
      )
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        request.to_slice
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_level.should eq(120_u8)
    end

    it "executes Stop command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      request = Matter::Cluster::Definitions::LevelControl::StopRequest.new(
        mask: 0_u8,
        override: 0_u8
      )
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STOP,
        request.to_slice
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
    end
  end

  describe "MoveMode enum" do
    it "has move modes" do
      Matter::Cluster::LevelControlCluster::MoveMode::Up.value.should eq(0)
      Matter::Cluster::LevelControlCluster::MoveMode::Down.value.should eq(1)
    end
  end

  describe "StepMode enum" do
    it "has step modes" do
      Matter::Cluster::LevelControlCluster::StepMode::Up.value.should eq(0)
      Matter::Cluster::LevelControlCluster::StepMode::Down.value.should eq(1)
    end
  end

  describe "level boundaries" do
    it "clamps level to min boundary" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 100_u8,
        min_level: 50_u8
      )

      # Try to move below min
      request = Matter::Cluster::Definitions::LevelControl::MoveToLevelRequest.new(
        level: 10_u8,
        transition_time: 0_u16,
        mask: 0_u8,
        override: 0_u8
      )
      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        request.to_slice
      )

      cluster.current_level.should eq(50_u8) # Clamped to min
    end

    it "clamps level to max boundary" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 100_u8,
        max_level: 200_u8
      )

      # Try to move above max
      request = Matter::Cluster::Definitions::LevelControl::MoveToLevelRequest.new(
        level: 250_u8,
        transition_time: 0_u16,
        mask: 0_u8,
        override: 0_u8
      )
      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        request.to_slice
      )

      cluster.current_level.should eq(200_u8) # Clamped to max
    end
  end

  describe "step command boundaries" do
    it "steps up within range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        Matter::Cluster::Definitions::LevelControl::StepRequest.new(
          step_mode: Matter::Cluster::Definitions::LevelControl::StepMode::Up,
          step_size: 50_u8,
          transition_time: 0_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      cluster.current_level.should eq(150_u8)
    end

    it "steps down within range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        Matter::Cluster::Definitions::LevelControl::StepRequest.new(
          step_mode: Matter::Cluster::Definitions::LevelControl::StepMode::Down,
          step_size: 30_u8,
          transition_time: 0_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      cluster.current_level.should eq(70_u8)
    end

    it "clamps step up to max" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 240_u8,
        max_level: 254_u8
      )

      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        Matter::Cluster::Definitions::LevelControl::StepRequest.new(
          step_mode: Matter::Cluster::Definitions::LevelControl::StepMode::Up,
          step_size: 50_u8,
          transition_time: 0_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      cluster.current_level.should eq(254_u8) # Clamped to max
    end

    it "clamps step down to min" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 10_u8,
        min_level: 0_u8
      )

      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        Matter::Cluster::Definitions::LevelControl::StepRequest.new(
          step_mode: Matter::Cluster::Definitions::LevelControl::StepMode::Down,
          step_size: 50_u8,
          transition_time: 0_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      cluster.current_level.should eq(0_u8) # Clamped to min
    end
  end

  describe "callbacks" do
    it "calls level changed callback" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 50_u8)

      old_level = 0_u8
      new_level = 0_u8

      cluster.on_level_changed do |old, new|
        old_level = old
        new_level = new
      end

      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Matter::Cluster::Definitions::LevelControl::MoveToLevelRequest.new(
          level: 100_u8,
          transition_time: 0_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      old_level.should eq(50_u8)
      new_level.should eq(100_u8)
    end
  end

  describe "data versioning" do
    it "increments version when level changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 50_u8)

      initial_version = cluster.data_version

      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Matter::Cluster::Definitions::LevelControl::MoveToLevelRequest.new(
          level: 100_u8,
          transition_time: 0_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      cluster.data_version.should eq(initial_version + 1)
    end
  end

  describe "persistence" do
    it "saves and restores state" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 50_u8,
        min_level: 1_u8,
        max_level: 200_u8,
        feature_map: Matter::Cluster::LevelControlCluster::Feature::OnOff |
                     Matter::Cluster::LevelControlCluster::Feature::Lighting |
                     Matter::Cluster::LevelControlCluster::Feature::Frequency
      )

      cluster.on_level = 42_u8
      cluster.options = 3_u8
      cluster.remaining_time = 9_u16
      cluster.on_off_transition_time = 5_u16
      cluster.on_transition_time = 7_u16
      cluster.off_transition_time = 8_u16
      cluster.default_move_rate = 10_u8
      cluster.start_up_current_level = 12_u8
      cluster.current_frequency = 111_u16
      cluster.min_frequency = 100_u16
      cluster.max_frequency = 120_u16
      cluster.data_version = 12_u32

      saved = cluster.save_state
      saved.should_not be_nil

      restored = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 1_u8,
        min_level: 1_u8,
        max_level: 254_u8,
        feature_map: Matter::Cluster::LevelControlCluster::Feature::OnOff |
                     Matter::Cluster::LevelControlCluster::Feature::Lighting |
                     Matter::Cluster::LevelControlCluster::Feature::Frequency
      )
      restored.restore_state(saved.as(String))

      restored.current_level.should eq(50_u8)
      restored.min_level.should eq(1_u8)
      restored.max_level.should eq(200_u8)
      restored.on_level.should eq(42_u8)
      restored.options.should eq(3_u8)
      restored.remaining_time.should eq(9_u16)
      restored.on_off_transition_time.should eq(5_u16)
      restored.on_transition_time.should eq(7_u16)
      restored.off_transition_time.should eq(8_u16)
      restored.default_move_rate.should eq(10_u8)
      restored.start_up_current_level.should eq(12_u8)
      restored.current_frequency.should eq(111_u16)
      restored.min_frequency.should eq(100_u16)
      restored.max_frequency.should eq(120_u16)
      restored.data_version.should eq(12_u32)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end

    it "returns error for unsupported command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      result = cluster.invoke_command(0x99_u32, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedCommand
      )
    end
  end

  describe "practical scenarios" do
    it "dims a light from full to half" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 254_u8)

      light.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Matter::Cluster::Definitions::LevelControl::MoveToLevelRequest.new(
          level: 127_u8,
          transition_time: 10_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      light.current_level.should eq(127_u8)
    end

    it "brightens a light gradually" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 50_u8)

      5.times do
        light.invoke_command(
          Matter::Cluster::LevelControlCluster::CMD_STEP,
          Matter::Cluster::Definitions::LevelControl::StepRequest.new(
            step_mode: Matter::Cluster::Definitions::LevelControl::StepMode::Up,
            step_size: 10_u8,
            transition_time: 2_u16,
            mask: 0_u8,
            override: 0_u8
          ).to_slice
        )
      end

      light.current_level.should eq(100_u8)
    end

    it "fades out to minimum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::LevelControlCluster.new(
        endpoint_id,
        current_level: 200_u8,
        min_level: 10_u8
      )

      light.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Matter::Cluster::Definitions::LevelControl::MoveToLevelRequest.new(
          level: 10_u8,
          transition_time: 20_u16,
          mask: 0_u8,
          override: 0_u8
        ).to_slice
      )

      light.current_level.should eq(10_u8)
    end
  end
end
