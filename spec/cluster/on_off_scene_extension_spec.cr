require "../spec_helper"

describe Matter::Cluster::OnOffCluster do
  it "exports and applies ScenesManagement extension field sets" do
    endpoint = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)

    field_set = cluster.store_scene_extension_field_set
    field_set.should_not be_nil
    field_set = field_set.not_nil!
    field_set.cluster_id.should eq(Matter::Cluster::OnOffCluster::CLUSTER_ID)

    applied = cluster.apply_scene_extension_field_set(field_set)
    applied.should be_true
    cluster.on_off.should be_false

    on_field_set = Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet.new(
      cluster_id: Matter::Cluster::OnOffCluster::CLUSTER_ID,
      attribute_list: [{Matter::Cluster::OnOffCluster::ATTR_ON_OFF, true.to_tlv}]
    )

    applied = cluster.apply_scene_extension_field_set(on_field_set)
    applied.should be_true
    cluster.on_off.should be_true
  end
end
