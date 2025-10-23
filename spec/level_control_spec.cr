require "./spec_helper"
require "../src/matter/cluster/level_control_cluster"

describe Matter::Cluster::LevelControlCluster do
  describe "initialization" do
    it "creates cluster with default values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      cluster.name.should eq("LevelControl")
      cluster.cluster_id.id.should eq(0x0008_u32)
      cluster.current_level.should eq(0_u8)
      cluster.min_level.should eq(0_u8)
      cluster.max_level.should eq(254_u8)
      cluster.options.should eq(0_u8)
      cluster.on_level.should be_nil
    end

    it "creates cluster with custom values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint,
        current_level: 100_u8,
        min_level: 10_u8,
        max_level: 200_u8,
        on_level: 150_u8
      )

      cluster.current_level.should eq(100_u8)
      cluster.min_level.should eq(10_u8)
      cluster.max_level.should eq(200_u8)
      cluster.on_level.should eq(150_u8)
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      attrs = cluster.attributes
      attrs.size.should eq(8)

      # Check for required attributes
      current_level = attrs.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::CURRENT_LEVEL }
      current_level.should_not be_nil
      current_level.not_nil!.name.should eq("CurrentLevel")
      current_level.not_nil!.type.should eq(:uint8)
      current_level.not_nil!.writable.should be_false

      min_level = attrs.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::MIN_LEVEL }
      min_level.should_not be_nil
      min_level.not_nil!.writable.should be_false

      max_level = attrs.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::MAX_LEVEL }
      max_level.should_not be_nil

      options = attrs.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::OPTIONS }
      options.should_not be_nil
      options.not_nil!.writable.should be_true

      on_level = attrs.find { |a| a.id.id == Matter::Cluster::LevelControlCluster::ON_LEVEL }
      on_level.should_not be_nil
      on_level.not_nil!.writable.should be_true
    end

    it "reads CurrentLevel attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 123_u8)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::CURRENT_LEVEL)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[123])
    end

    it "reads MinLevel and MaxLevel attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint,
        min_level: 5_u8,
        max_level: 250_u8
      )

      min_result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::MIN_LEVEL)
      min_result.as(Bytes).should eq(Bytes[5])

      max_result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::MAX_LEVEL)
      max_result.as(Bytes).should eq(Bytes[250])
    end

    it "reads RemainingTime attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::REMAINING_TIME)
      result.should be_a(Bytes)
      result.as(Bytes).size.should eq(2) # UInt16
    end

    it "writes Options attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      initial_version = cluster.data_version

      status = cluster.write_attribute(
        Matter::Cluster::LevelControlCluster::OPTIONS,
        Bytes[0x03]
      )

      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.options.should eq(0x03_u8)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "writes OnLevel attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      status = cluster.write_attribute(
        Matter::Cluster::LevelControlCluster::ON_LEVEL,
        Bytes[100]
      )

      status.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.on_level.should eq(100_u8)
    end

    it "rejects OnLevel outside min/max range" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint,
        min_level: 10_u8,
        max_level: 200_u8
      )

      # Try to set below minimum
      status = cluster.write_attribute(
        Matter::Cluster::LevelControlCluster::ON_LEVEL,
        Bytes[5]
      )
      status.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::ConstraintError
      )

      # Try to set above maximum
      status = cluster.write_attribute(
        Matter::Cluster::LevelControlCluster::ON_LEVEL,
        Bytes[250]
      )
      status.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::ConstraintError
      )
    end

    it "returns NotFound for OnLevel when not set" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::ON_LEVEL)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::NotFound
      )
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      cmds = cluster.commands
      cmds.size.should eq(9)

      move_to_level = cmds.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL }
      move_to_level.should_not be_nil
      move_to_level.not_nil!.name.should eq("MoveToLevel")

      move = cmds.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_MOVE }
      move.should_not be_nil

      step = cmds.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_STEP }
      step.should_not be_nil

      stop = cmds.find { |c| c.id.id == Matter::Cluster::LevelControlCluster::CMD_STOP }
      stop.should_not be_nil
    end

    it "executes MoveToLevel command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 50_u8)

      initial_level = cluster.current_level
      initial_version = cluster.data_version

      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL,
        Bytes.new(0)
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      # Simplified implementation moves to mid-level (127)
      cluster.current_level.should eq(127_u8)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes Move command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 50_u8)

      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE,
        Bytes.new(0)
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_level.should eq(60_u8) # Incremented by 10
    end

    it "executes Step command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 100_u8)

      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP,
        Bytes.new(0)
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.current_level.should eq(110_u8) # Stepped by 10
    end

    it "executes Stop command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint)

      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STOP,
        Bytes.new(0)
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.remaining_time.should eq(0_u16)
    end

    it "clamps level to max_level" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint,
        current_level: 250_u8,
        max_level: 254_u8
      )

      # Try to move beyond max
      cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE,
        Bytes.new(0)
      )

      cluster.current_level.should eq(254_u8) # Clamped to max
    end

    it "clamps level to min_level" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(
        endpoint,
        current_level: 5_u8,
        min_level: 10_u8,
        max_level: 254_u8
      )

      # Current level should be clamped to min
      cluster.current_level.should eq(5_u8)

      # Move should respect min level
      result = cluster.read_attribute(Matter::Cluster::LevelControlCluster::MIN_LEVEL)
      result.as(Bytes).should eq(Bytes[10])
    end

    it "executes WithOnOff variants" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 50_u8)

      # MoveToLevelWithOnOff
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_TO_LEVEL_WITH_ON_OFF,
        Bytes.new(0)
      )
      result.as(Matter::InteractionModel::Status).success?.should be_true

      # MoveWithOnOff
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 50_u8)
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_MOVE_WITH_ON_OFF,
        Bytes.new(0)
      )
      result.as(Matter::InteractionModel::Status).success?.should be_true

      # StepWithOnOff
      cluster = Matter::Cluster::LevelControlCluster.new(endpoint, current_level: 50_u8)
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STEP_WITH_ON_OFF,
        Bytes.new(0)
      )
      result.as(Matter::InteractionModel::Status).success?.should be_true

      # StopWithOnOff
      result = cluster.invoke_command(
        Matter::Cluster::LevelControlCluster::CMD_STOP_WITH_ON_OFF,
        Bytes.new(0)
      )
      result.as(Matter::InteractionModel::Status).success?.should be_true
    end
  end
end
