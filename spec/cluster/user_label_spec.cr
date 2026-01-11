require "../spec_helper"
require "../../src/matter/cluster/user_label_cluster"
require "../../src/matter/cluster/definitions/label_struct"

describe Matter::Cluster::UserLabelCluster do
  it "creates a UserLabel cluster with empty label list by default" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabelCluster.new(endpoint_id)

    cluster.cluster_id.id.should eq(0x0041_u32)
    cluster.name.should eq("UserLabel")
    cluster.label_list.should be_empty
  end

  it "exposes LabelList as writable attribute" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabelCluster.new(endpoint_id)

    meta = cluster.attributes.find { |attr| attr.id.id == Matter::Cluster::UserLabelCluster::ATTR_LABEL_LIST }
    meta.should_not be_nil
    meta = meta.as(Matter::Cluster::AttributeMetadata)
    meta.name.should eq("LabelList")
    meta.type.should eq(:list)
    meta.writable?.should be_true
  end

  it "writes LabelList from TLV and updates stored value" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabelCluster.new(endpoint_id)

    new_labels = [
      Matter::Cluster::LabelStruct.new("room", "living"),
      Matter::Cluster::LabelStruct.new("control", "volume"),
    ]

    status = cluster.write_attribute(Matter::Cluster::UserLabelCluster::ATTR_LABEL_LIST, new_labels.to_tlv)
    status.success?.should be_true

    cluster.label_list.size.should eq(2)
    cluster.label_list[0].label.should eq("room")
    cluster.label_list[0].value.should eq("living")

    read_back = cluster.read_attribute(Matter::Cluster::UserLabelCluster::ATTR_LABEL_LIST)
    read_back.should be_a(Bytes)
    list = TLV::Any.from_slice(read_back.as(Bytes)).as_list
    list.size.should eq(2)
  end

  it "rejects invalid LabelList writes" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabelCluster.new(endpoint_id)

    status = cluster.write_attribute(Matter::Cluster::UserLabelCluster::ATTR_LABEL_LIST, 123_u8.to_tlv)
    status.status.should eq(Matter::InteractionModel::StatusCode::InvalidDataType)
  end

  it "persists and restores label list state" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabelCluster.new(endpoint_id, [
      Matter::Cluster::LabelStruct.new("a", "b"),
    ])

    json = cluster.save_state.as(String)

    restored = Matter::Cluster::UserLabelCluster.new(endpoint_id)
    restored.restore_state(json)
    restored.label_list.size.should eq(1)
    restored.label_list[0].label.should eq("a")
    restored.label_list[0].value.should eq("b")
  end
end
