require "../spec_helper"
require "../../src/matter/cluster/on_off_cluster"

describe Matter::Cluster::OnOffCluster do
  describe "initialization" do
    it "creates on/off cluster with default off state" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0006_u32)
      cluster.name.should eq("OnOff")
      cluster.on_off.should be_false
    end

    it "creates on/off cluster with initial on state" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

      cluster.on_off.should be_true
    end
  end

  describe "attributes" do
    it "has required OnOff attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty

      on_off_attr = attributes.find { |a| a.id.id == Matter::Cluster::OnOffCluster::ATTR_ON_OFF }
      on_off_attr.should_not be_nil
      on_off_attr.not_nil!.name.should eq("OnOff")
      on_off_attr.not_nil!.type.should eq(:bool)
      on_off_attr.not_nil!.writable.should be_false
    end

    it "reads OnOff attribute when off" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

      result = cluster.read_attribute(Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[0]) # false
    end

    it "reads OnOff attribute when on" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

      result = cluster.read_attribute(Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[1]) # true
    end

    it "rejects writing to read-only OnOff attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::OnOffCluster::ATTR_ON_OFF,
        Bytes[1]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id)

      commands = cluster.commands
      commands.size.should be >= 3

      off_cmd = commands.find { |c| c.id.id == Matter::Cluster::OnOffCluster::CMD_OFF }
      off_cmd.should_not be_nil
      off_cmd.not_nil!.name.should eq("Off")

      on_cmd = commands.find { |c| c.id.id == Matter::Cluster::OnOffCluster::CMD_ON }
      on_cmd.should_not be_nil
      on_cmd.not_nil!.name.should eq("On")

      toggle_cmd = commands.find { |c| c.id.id == Matter::Cluster::OnOffCluster::CMD_TOGGLE }
      toggle_cmd.should_not be_nil
      toggle_cmd.not_nil!.name.should eq("Toggle")
    end

    describe "Off command" do
      it "turns off when already off" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))

        result.should be_a(Matter::InteractionModel::Status)
        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_false
      end

      it "turns off when on" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

        cluster.on_off.should be_true

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_false
      end

      it "updates attribute value after Off command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

        cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))

        attr_value = cluster.read_attribute(Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
        attr_value.as(Bytes).should eq(Bytes[0]) # false
      end
    end

    describe "On command" do
      it "turns on when already on" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_true
      end

      it "turns on when off" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

        cluster.on_off.should be_false

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_true
      end

      it "updates attribute value after On command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

        cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

        attr_value = cluster.read_attribute(Matter::Cluster::OnOffCluster::ATTR_ON_OFF)
        attr_value.as(Bytes).should eq(Bytes[1]) # true
      end
    end

    describe "Toggle command" do
      it "toggles from off to on" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_true
      end

      it "toggles from on to off" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_false
      end

      it "toggles multiple times correctly" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

        cluster.on_off.should be_false

        cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
        cluster.on_off.should be_true

        cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
        cluster.on_off.should be_false

        cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
        cluster.on_off.should be_true
      end
    end

    describe "OffWithEffect command" do
      it "executes OffWithEffect command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF_EFFECT, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_false
      end
    end

    describe "OnWithRecallGlobalScene command" do
      it "executes OnWithRecallGlobalScene command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON_RECALL, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_true
      end
    end

    describe "OnWithTimedOff command" do
      it "executes OnWithTimedOff command" do
        endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

        result = cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON_TIMED, Bytes.new(0))

        result.as(Matter::InteractionModel::Status).success?.should be_true
        cluster.on_off.should be_true
      end
    end
  end

  describe "callbacks" do
    it "calls callback when turning on" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

      callback_called = false
      new_state = false

      cluster.on_state_changed do |state|
        callback_called = true
        new_state = state
      end

      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      callback_called.should be_true
      new_state.should be_true
    end

    it "calls callback when turning off" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

      callback_called = false
      new_state = true

      cluster.on_state_changed do |state|
        callback_called = true
        new_state = state
      end

      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))

      callback_called.should be_true
      new_state.should be_false
    end

    it "calls callback on each toggle" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

      call_count = 0
      states = [] of Bool

      cluster.on_state_changed do |state|
        call_count += 1
        states << state
      end

      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))

      call_count.should eq(3)
      states.should eq([true, false, true])
    end

    it "does not call callback if state doesn't change" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

      callback_called = false

      cluster.on_state_changed do |state|
        callback_called = true
      end

      # Turn on when already on - state doesn't change
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      callback_called.should be_false
    end

    # Behavioral test migrated from matter.js
    # packages/node/test/behaviors/on-off/OnOffServerTest.ts
    it "properly supports observers on toggle sequence" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

      observed_values = [] of Bool

      cluster.on_state_changed do |state|
        observed_values << state
      end

      # Toggle twice - should observe [true, false]
      2.times do
        cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      end

      observed_values.should eq([true, false])
    end
  end

  describe "data versioning" do
    it "increments version when state changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

      initial_version = cluster.data_version

      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      cluster.data_version.should eq(initial_version + 1)
    end

    it "increments version on each state change" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: false)

      initial_version = cluster.data_version

      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      cluster.data_version.should eq(initial_version + 3)
    end

    it "does not increment version if state unchanged" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id, on_off: true)

      initial_version = cluster.data_version

      cluster.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      cluster.data_version.should eq(initial_version)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id)

      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end

    it "returns error for unsupported command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::OnOffCluster.new(endpoint_id)

      result = cluster.invoke_command(0x99_u32, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedCommand
      )
    end
  end

  describe "practical scenarios" do
    it "simulates light switch sequence" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      light = Matter::Cluster::OnOffCluster.new(endpoint_id)

      # Initially off
      light.on_off.should be_false

      # User turns on light
      light.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
      light.on_off.should be_true

      # User turns off light
      light.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
      light.on_off.should be_false
    end

    it "simulates toggle button presses" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      outlet = Matter::Cluster::OnOffCluster.new(endpoint_id)

      states = [] of Bool

      # Simulate 5 button presses
      5.times do
        outlet.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
        states << outlet.on_off
      end

      states.should eq([true, false, true, false, true])
    end

    it "tracks state changes with callback" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      device = Matter::Cluster::OnOffCluster.new(endpoint_id)

      transitions = [] of String

      device.on_state_changed do |state|
        transitions << (state ? "ON" : "OFF")
      end

      device.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
      device.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
      device.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      device.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))

      transitions.should eq(["ON", "OFF", "ON", "OFF"])
    end
  end

  describe "integration with other clusters" do
    it "maintains state independently per endpoint" do
      endpoint1 = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint2 = Matter::DataType::EndpointNumber.new(2_u16)

      cluster1 = Matter::Cluster::OnOffCluster.new(endpoint1, on_off: false)
      cluster2 = Matter::Cluster::OnOffCluster.new(endpoint2, on_off: true)

      cluster1.on_off.should be_false
      cluster2.on_off.should be_true

      cluster1.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))

      cluster1.on_off.should be_true
      cluster2.on_off.should be_true # Unchanged
    end
  end
end
