require "../spec_helper"
require "../../src/matter/cluster/user_label"
require "../../src/matter/cluster/label_struct"

describe Matter::Cluster::UserLabel do
  it "creates a UserLabel cluster with empty label list by default" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabel.new(endpoint_id)

    cluster.cluster_id.id.should eq(0x0041_u32)
    cluster.name.should eq("UserLabel")
    cluster.label_list.should be_empty
  end

  it "exposes LabelList as writable attribute" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabel.new(endpoint_id)

    meta = cluster.attributes.find { |attr| attr.id.id == Matter::Cluster::UserLabel::ATTR_LABEL_LIST }
    meta.should_not be_nil
    meta = meta.as(Matter::Cluster::AttributeMetadata)
    meta.name.should eq("labelList")
    meta.type.should eq(:array)
    meta.writable?.should be_true
  end

  it "writes LabelList from TLV and updates stored value" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabel.new(endpoint_id)

    new_labels = [
      Matter::Cluster::LabelStruct.new("room", "living"),
      Matter::Cluster::LabelStruct.new("control", "volume"),
    ]

    status = write(cluster, Matter::Cluster::UserLabel::ATTR_LABEL_LIST, new_labels)
    status.success?.should be_true

    cluster.label_list.size.should eq(2)
    cluster.label_list[0].label.should eq("room")
    cluster.label_list[0].value.should eq("living")

    list = read_tlv(cluster, Matter::Cluster::UserLabel::ATTR_LABEL_LIST).as_list
    list.size.should eq(2)
  end

  it "rejects invalid LabelList writes" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabel.new(endpoint_id)

    status = write(cluster, Matter::Cluster::UserLabel::ATTR_LABEL_LIST, 123_u8)
    status.status.should eq(Matter::InteractionModel::StatusCode::InvalidDataType)
  end

  it "rejects LabelList entries longer than 16 bytes with ConstraintError" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabel.new(endpoint_id)

    too_long = [Matter::Cluster::LabelStruct.new("room", "a" * (Matter::Cluster::UserLabel::LABEL_MAX_LENGTH + 1))]
    status = write(cluster, Matter::Cluster::UserLabel::ATTR_LABEL_LIST, too_long)
    status.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
    cluster.label_list.should be_empty
  end

  it "persists and restores label list state" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::UserLabel.new(endpoint_id, [
      Matter::Cluster::LabelStruct.new("a", "b"),
    ])

    cluster.data_version = 3_u32
    document = cluster.save_state.as(Matter::Storage::Document)
    document["label_list"].should eq([Matter::Storage::Document{"label" => "a", "value" => "b"}] of Matter::Storage::Type)
    document["data_version"].should eq(3_i64)

    restored = Matter::Cluster::UserLabel.new(endpoint_id)
    restored.restore_state(document)
    restored.data_version.should eq(3_u32)
    restored.label_list.size.should eq(1)
    restored.label_list[0].label.should eq("a")
    restored.label_list[0].value.should eq("b")
  end
end
