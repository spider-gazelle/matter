require "../spec_helper"

describe Matter::Cluster::OnOff do
  it "exports and applies ScenesManagement extension field sets" do
    cluster = build(Matter::Cluster::OnOff, on_off: false)

    field_set = cluster.store_scene_extension_field_set
    field_set.should_not be_nil
    field_set_data = field_set.as(Matter::Cluster::ScenesManagement::ExtensionFieldSet)
    field_set_data.cluster_id.should eq(Matter::Cluster::OnOff::CLUSTER_ID)

    applied = cluster.apply_scene_extension_field_set(field_set_data)
    applied.should be_true
    cluster.on_off?.should be_false

    on_field_set = Matter::Cluster::ScenesManagement::ExtensionFieldSet.new(
      cluster_id: Matter::Cluster::OnOff::CLUSTER_ID,
      attribute_list: [{Matter::Cluster::OnOff::ATTR_ON_OFF, TLV::Any.new(true)}]
    )

    applied = cluster.apply_scene_extension_field_set(on_field_set)
    applied.should be_true
    cluster.on_off?.should be_true
  end
end
