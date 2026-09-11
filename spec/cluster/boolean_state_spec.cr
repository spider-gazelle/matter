require "../spec_helper"
require "../../src/matter/cluster/boolean_state"

private alias BooleanState = Matter::Cluster::BooleanState

describe Matter::Cluster::BooleanState do
  describe "initialization" do
    it "creates with default false state" do
      cluster = BooleanState.new(endpoint(1))

      cluster.cluster_id.id.should eq(0x0045_u32)
      cluster.name.should eq("BooleanState")
      cluster.state_value?.should be_false
    end

    it "creates with true state" do
      cluster = BooleanState.new(endpoint(1), state_value: true)
      cluster.state_value?.should be_true
    end
  end

  describe "attributes" do
    it "exposes StateValue attribute metadata" do
      cluster = BooleanState.new(endpoint(1))
      attrs = cluster.attributes

      attrs.size.should eq(1)
      attrs[0].id.id.should eq(BooleanState::ATTR_STATE_VALUE)
      attrs[0].name.should eq("stateValue")
      attrs[0].writable?.should be_false
    end

    it "reads state as TLV bool" do
      cluster = BooleanState.new(endpoint(1), state_value: true)
      read(cluster, BooleanState::ATTR_STATE_VALUE).should be_true
    end

    it "returns unsupported for unknown attribute" do
      cluster = BooleanState.new(endpoint(1))
      read_status(cluster, 0x9999_u32).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "update_state" do
    it "updates state and increments data version" do
      cluster = BooleanState.new(endpoint(1), state_value: false)

      version_delta(cluster) { cluster.update_state(true) }.should eq(1)
      cluster.state_value?.should be_true
    end

    it "does not change data version when value is unchanged" do
      cluster = BooleanState.new(endpoint(1), state_value: true)

      version_delta(cluster) { cluster.update_state(true) }.should eq(0)
    end

    it "invokes on_state_changed when value changes" do
      cluster = BooleanState.new(endpoint(1), state_value: false)

      old_value : Bool? = nil
      new_value : Bool? = nil
      cluster.on_state_changed do |old, new|
        old_value = old
        new_value = new
      end

      cluster.update_state(true)

      old_value.should be_false
      new_value.should be_true
    end

    it "notifies attribute subscribers when value changes" do
      cluster = BooleanState.new(endpoint(1), state_value: false)

      changes = capture_changes(cluster) { cluster.update_state(true) }

      changes.size.should eq(1)
      changes[0].endpoint.should eq(1_u16)
      changes[0].cluster.should eq(BooleanState::CLUSTER_ID)
      changes[0].attribute.should eq(BooleanState::ATTR_STATE_VALUE)
    end
  end
end
