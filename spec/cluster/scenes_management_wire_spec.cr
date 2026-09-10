require "../spec_helper"

# Scene payloads keep their typed extension attributes through command and storage boundaries.
describe Matter::Cluster::ScenesManagementCluster do
  it "retains AddScene extension values when viewing, persisting and recalling a scene" do
    cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint(1))
    extension = Matter::Cluster::ExtensionFieldSetTlv.new(
      Matter::Cluster::ColorControlCluster::CLUSTER_ID,
      [Matter::Cluster::AttributeValuePairTlv.new(0_u32, value_unsigned8: 127_u8),
       Matter::Cluster::AttributeValuePairTlv.new(3_u32, value_unsigned16: 32768_u16),
       Matter::Cluster::AttributeValuePairTlv.new(4_u32, value_signed16: -500_i16)])
    request = Matter::Cluster::AddSceneRequest.new(group_id: 1_u16, scene_id: 2_u8, transition_time: 30_u32,
      scene_name: "Evening", extension_field_sets: [extension.to_tlv(nil)])
    added = invoke_response(cluster, Matter::Cluster::ScenesManagementCluster::CMD_ADD_SCENE,
      request, Matter::Cluster::SceneStatusResponse)
    added.status.should eq(Matter::InteractionModel::StatusCode::Success.value)

    restored = Matter::Cluster::ScenesManagementCluster.new(endpoint(1))
    restored.restore_state(cluster.save_state.as(Matter::Storage::Document))
    view = invoke_response(restored, Matter::Cluster::ScenesManagementCluster::CMD_VIEW_SCENE,
      Matter::Cluster::ViewSceneRequest.new(group_id: 1_u16, scene_id: 2_u8), Matter::Cluster::ViewSceneResponseTlv)
    view.transition_time.should eq(30_u32)
    view.scene_name.should eq("Evening")
    values = view.extension_field_sets.as(Array(Matter::Cluster::ExtensionFieldSetTlv)).first.attribute_value_list
    values[0].value_unsigned8.should eq(127_u8)
    values[1].value_unsigned16.should eq(32768_u16)
    values[2].value_signed16.should eq(-500_i16)

    applied = [] of Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet
    restored.apply_extension_field_sets = ->(fields : Array(Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet)) { applied.concat(fields); nil }
    expect_success(invoke(restored, Matter::Cluster::ScenesManagementCluster::CMD_RECALL_SCENE,
      Matter::Cluster::RecallSceneRequest.new(group_id: 1_u16, scene_id: 2_u8)))
    applied.first.attribute_value_list.map { |_, value| value.value }.should eq([127_u8, 32768_u16, -500_i16])
  end
end

describe "OnOff scene extension values" do
  [{0_u8, false}, {1_u8, true}, {UInt8::MAX, false}].each do |wire_value, expected|
    it "recalls the unsigned boolean scene value #{wire_value}" do
      scenes = Matter::Cluster::ScenesManagementCluster.new(endpoint(1))
      light = Matter::Cluster::OnOffCluster.new(endpoint(1), on_off: !expected)
      scenes.apply_extension_field_sets = ->(fields : Array(Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet)) {
        fields.each { |field| light.apply_scene_extension_field_set(field) }
        nil
      }
      extension = Matter::Cluster::ExtensionFieldSetTlv.new(
        Matter::Cluster::OnOffCluster::CLUSTER_ID,
        [Matter::Cluster::AttributeValuePairTlv.new(Matter::Cluster::OnOffCluster::ATTR_ON_OFF, value_unsigned8: wire_value)])
      request = Matter::Cluster::AddSceneRequest.new(group_id: 1_u16, scene_id: 2_u8, transition_time: 0_u32,
        scene_name: "Light", extension_field_sets: [extension.to_tlv(nil)])
      response = invoke_response(scenes, Matter::Cluster::ScenesManagementCluster::CMD_ADD_SCENE,
        request, Matter::Cluster::SceneStatusResponse)
      response.status.should eq(Matter::InteractionModel::StatusCode::Success.value)

      expect_success(invoke(scenes, Matter::Cluster::ScenesManagementCluster::CMD_RECALL_SCENE,
        Matter::Cluster::RecallSceneRequest.new(group_id: 1_u16, scene_id: 2_u8)))
      light.on_off?.should eq(expected)
    end
  end
end
