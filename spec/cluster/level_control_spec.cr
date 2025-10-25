require "../spec_helper"
require "../../src/matter/cluster/level_control_cluster"

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

      current_level = attributes.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::ATTR_CURRENT_LEVEL }
      current_level.should_not be_nil
      current_level.not_nil!.name.should eq("CurrentLevel")
      current_level.not_nil!.writable.should be_false

      min_level = attributes.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::ATTR_MIN_LEVEL }
      min_level.should_not be_nil

      max_level = attributes.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::ATTR_MAX_LEVEL }
      max_level.should_not be_nil
    end

    it "reads CurrentLevel attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_CURRENT_LEVEL)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[100])
    end

    it "reads MinLevel attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, min_level: 5_u8)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_MIN_LEVEL)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[5])
    end

    it "reads MaxLevel attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, max_level: 200_u8)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_MAX_LEVEL)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[200])
    end

    it "reads RemainingTime attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ATTR_REMAINING_TIME)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0, 0]) # 0 in little-endian UInt16
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      commands = cluster.commands
      commands.size.should be >= 4

      move_to_level = commands.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL }
      move_to_level.should_not be_nil
      move_to_level.not_nil!.name.should eq("MoveToLevel")

      move = commands.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_MOVE }
      move.should_not be_nil

      step = commands.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_STEP }
      step.should_not be_nil

      stop = commands.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_STOP }
      stop.should_not be_nil
    end

    it "executes MoveToLevel command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 0_u8)

      cluster.current_level.should eq(0_u8)

      # MoveToLevel(level=200, transition_time=10, options_mask=0, options_override=0)
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Bytes[200, 10, 0, 0, 0] # level, transition_time (little-endian), options...
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_level.should eq(200_u8)
    end

    it "executes Move command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      # Move(mode=Up, rate=10, options_mask=0, options_override=0)
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE,
        Bytes[
          Matter::Cluster::LevelControlCluster::MoveMode::Up.value,
          10,   # rate
          0, 0, # options
        ]
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
    end

    it "executes Step command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      # Step(mode=Up, step_size=20, transition_time=5, options_mask=0, options_override=0)
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        Bytes[
          Matter::Cluster::LevelControlCluster::StepMode::Up.value,
          20,   # step_size
          5, 0, # transition_time (little-endian)
          0, 0, # options
        ]
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_level.should eq(120_u8)
    end

    it "executes Stop command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id)

      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STOP,
        Bytes[0, 0] # options_mask, options_override
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
      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Bytes[10, 0, 0, 0, 0]
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
      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Bytes[250, 0, 0, 0, 0]
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
        Bytes[
          Matter::Cluster::LevelControlCluster::StepMode::Up.value,
          50, 0, 0, 0, 0,
        ]
      )

      cluster.current_level.should eq(150_u8)
    end

    it "steps down within range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 100_u8)

      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        Bytes[
          Matter::Cluster::LevelControlCluster::StepMode::Down.value,
          30, 0, 0, 0, 0,
        ]
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
        Bytes[
          Matter::Cluster::LevelControlCluster::StepMode::Up.value,
          50, 0, 0, 0, 0,
        ]
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
        Bytes[
          Matter::Cluster::LevelControlCluster::StepMode::Down.value,
          50, 0, 0, 0, 0,
        ]
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
        Bytes[100, 0, 0, 0, 0]
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
        Bytes[100, 0, 0, 0, 0]
      )

      cluster.data_version.should eq(initial_version + 1)
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
        Bytes[127, 10, 0, 0, 0] # Move to 50% over 1 second
      )

      light.current_level.should eq(127_u8)
    end

    it "brightens a light gradually" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::LevelControlCluster.new(endpoint_id, current_level: 50_u8)

      5.times do
        light.invoke_command(
          Matter::Cluster::LevelControlCluster::CMD_STEP,
          Bytes[
            Matter::Cluster::LevelControlCluster::StepMode::Up.value,
            10, 2, 0, 0, 0, # Step up by 10 over 0.2 seconds
          ]
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
        Bytes[10, 20, 0, 0, 0] # Fade to min over 2 seconds
      )

      light.current_level.should eq(10_u8)
    end
  end
end
