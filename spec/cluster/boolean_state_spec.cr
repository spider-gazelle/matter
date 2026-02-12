require "../spec_helper"
require "../../src/matter/cluster/boolean_state_cluster"

describe Matter::Cluster::BooleanStateCluster do
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

  describe "initialization" do
    it "creates with default false state" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0045_u32)
      cluster.name.should eq("BooleanState")
      cluster.state_value?.should be_false
    end

    it "creates with true state" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id, state_value: true)
      cluster.state_value?.should be_true
    end
  end

  describe "attributes" do
    it "exposes StateValue attribute metadata" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id)
      attrs = cluster.attributes

      attrs.size.should eq(1)
      attrs[0].id.id.should eq(Matter::Cluster::BooleanStateCluster::ATTR_STATE_VALUE)
      attrs[0].name.should eq("StateValue")
      attrs[0].writable?.should be_false
    end

    it "reads state as TLV bool" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id, state_value: true)
      result = cluster.read_attribute(Matter::Cluster::BooleanStateCluster::ATTR_STATE_VALUE)

      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(true)
    end

    it "returns unsupported for unknown attribute" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id)
      result = cluster.read_attribute(0x9999_u32)

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end
  end

  describe "update_state" do
    it "updates state and increments data version" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id, state_value: false)
      initial_version = cluster.data_version

      cluster.update_state(true)

      cluster.state_value?.should be_true
      cluster.data_version.should eq(initial_version + 1)
    end

    it "does not change data version when value is unchanged" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id, state_value: true)
      initial_version = cluster.data_version

      cluster.update_state(true)

      cluster.data_version.should eq(initial_version)
    end

    it "invokes on_state_changed when value changes" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id, state_value: false)

      old_value : Bool? = nil
      new_value : Bool? = nil
      cluster.on_state_changed do |old, new|
        old_value = old
        new_value = new
      end

      cluster.update_state(true)

      old_value.should eq(false)
      new_value.should eq(true)
    end

    it "notifies attribute subscribers when value changes" do
      cluster = Matter::Cluster::BooleanStateCluster.new(endpoint_id, state_value: false)

      notified = false
      notified_endpoint : UInt16 = 0_u16
      notified_cluster : UInt32 = 0_u32
      notified_attribute : UInt32 = 0_u32

      cluster.on_attribute_changed = ->(ep : UInt16, cl : UInt32, attr : UInt32) {
        notified = true
        notified_endpoint = ep
        notified_cluster = cl
        notified_attribute = attr
      }

      cluster.update_state(true)

      notified.should be_true
      notified_endpoint.should eq(1_u16)
      notified_cluster.should eq(Matter::Cluster::BooleanStateCluster::CLUSTER_ID)
      notified_attribute.should eq(Matter::Cluster::BooleanStateCluster::ATTR_STATE_VALUE)
    end
  end
end
