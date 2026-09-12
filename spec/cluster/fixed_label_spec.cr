require "../spec_helper"
require "../../src/matter/cluster/fixed_label"
require "../../src/matter/cluster/label_struct"

describe Matter::Cluster::FixedLabel do
  it "creates a FixedLabel cluster with label list" do
    labels = [
      Matter::Cluster::LabelStruct.new("room", "kitchen"),
      Matter::Cluster::LabelStruct.new("control", "playpause"),
    ]

    cluster = build(Matter::Cluster::FixedLabel, label_list: labels)

    cluster.cluster_id.id.should eq(0x0040_u32)
    cluster.name.should eq("FixedLabel")
    cluster.label_list.size.should eq(2)
  end

  it "exposes LabelList as read-only attribute" do
    cluster = build(Matter::Cluster::FixedLabel, label_list: [] of Matter::Cluster::LabelStruct)

    meta = cluster.attributes.find { |attr| attr.id.id == Matter::Cluster::FixedLabel::ATTR_LABEL_LIST }
    meta.should_not be_nil
    meta = meta.as(Matter::Cluster::AttributeMetadata)
    meta.name.should eq("labelList")
    meta.type.should eq(:array)
    meta.writable?.should be_false
  end

  it "encodes LabelList as a TLV list of LabelStruct entries" do
    labels = [
      Matter::Cluster::LabelStruct.new("k", "v"),
    ]
    cluster = build(Matter::Cluster::FixedLabel, label_list: labels)

    list = read_tlv(cluster, Matter::Cluster::FixedLabel::ATTR_LABEL_LIST).as_list
    list.size.should eq(1)

    entry = Matter::Cluster::LabelStruct.from_tlv(list[0])
    entry.label.should eq("k")
    entry.value.should eq("v")
  end
end
