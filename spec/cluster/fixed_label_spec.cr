require "../spec_helper"
require "../../src/matter/cluster/fixed_label_cluster"
require "../../src/matter/cluster/definitions/label_struct"

describe Matter::Cluster::FixedLabelCluster do
  it "creates a FixedLabel cluster with label list" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    labels = [
      Matter::Cluster::LabelStruct.new("room", "kitchen"),
      Matter::Cluster::LabelStruct.new("control", "playpause"),
    ]

    cluster = Matter::Cluster::FixedLabelCluster.new(endpoint_id, labels)

    cluster.cluster_id.id.should eq(0x0040_u32)
    cluster.name.should eq("FixedLabel")
    cluster.label_list.size.should eq(2)
  end

  it "exposes LabelList as read-only attribute" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::FixedLabelCluster.new(endpoint_id, [] of Matter::Cluster::LabelStruct)

    meta = cluster.attributes.find { |attr| attr.id.id == Matter::Cluster::FixedLabelCluster::ATTR_LABEL_LIST }
    meta.should_not be_nil
    meta = meta.as(Matter::Cluster::AttributeMetadata)
    meta.name.should eq("LabelList")
    meta.type.should eq(:list)
    meta.writable?.should be_false
  end

  it "encodes LabelList as a TLV list of LabelStruct entries" do
    endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
    labels = [
      Matter::Cluster::LabelStruct.new("k", "v"),
    ]
    cluster = Matter::Cluster::FixedLabelCluster.new(endpoint_id, labels)

    list = read_tlv(cluster, Matter::Cluster::FixedLabelCluster::ATTR_LABEL_LIST).as_list
    list.size.should eq(1)

    entry = Matter::Cluster::LabelStruct.from_tlv(list[0])
    entry.label.should eq("k")
    entry.value.should eq("v")
  end
end
