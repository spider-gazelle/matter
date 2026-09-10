require "../spec_helper"
require "../../src/matter/cluster/scenes_management_cluster"
require "../../src/matter/device/persistence"

# Helper to add scenes directly to the cluster's internal storage
private def add_scene_direct(
  cluster : Matter::Cluster::ScenesManagementCluster,
  fabric_index : UInt8,
  group_id : UInt16,
  scene_id : UInt8,
  scene_name : String = "",
  transition_time : UInt32 = 0_u32,
  extension_field_sets : Array(Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet) = [] of Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet,
)
  cluster.scenes[{fabric_index, group_id, scene_id}] = Matter::Cluster::ScenesManagementCluster::SceneData.new(
    transition_time: transition_time,
    scene_name: scene_name,
    extension_field_sets: extension_field_sets
  )
end

describe Matter::Cluster::ScenesManagementCluster do
  describe "#save_state" do
    it "returns a document with one entry per scene" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8, scene_name: "Morning")
      add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 2_u8, scene_name: "Evening")
      add_scene_direct(cluster, fabric_index: 2_u8, group_id: 2_u16, scene_id: 1_u8, scene_name: "Night", transition_time: 500_u32)
      cluster.data_version = 5_u32

      document = cluster.save_state.as(Matter::Storage::Document)
      document["data_version"].should eq(5_i64)

      scenes = document["scenes"].as(Array(Matter::Storage::Type)).map(&.as(Matter::Storage::Document))
      scenes.map(&.["scene_name"]).should eq(["Morning", "Evening", "Night"])
      scenes[2].should eq(Matter::Storage::Document{
        "fabric_index"         => 2_i64,
        "group_id"             => 2_i64,
        "scene_id"             => 1_i64,
        "transition_time"      => 500_i64,
        "scene_name"           => "Night",
        "extension_field_sets" => [] of Matter::Storage::Type,
      })
    end

    it "stores extension field set attribute values as bytes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)
      field_set = Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet.new(6_u32, [{0_u32, TLV::Any.new(1_u8)}])
      add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8, extension_field_sets: [field_set])

      document = cluster.save_state.as(Matter::Storage::Document)
      scene = document["scenes"].as(Array(Matter::Storage::Type)).first.as(Matter::Storage::Document)
      scene["extension_field_sets"].should eq([
        Matter::Storage::Document{
          "cluster_id" => 6_i64,
          "attributes" => [Matter::Storage::Document{"attribute_id" => 0_i64, "value" => TLV::Any.new(1_u8).to_slice}] of Matter::Storage::Type,
        },
      ] of Matter::Storage::Type)
    end
  end

  describe "#restore_state" do
    it "restores scenes, field sets and fabric scene info" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster1 = Matter::Cluster::ScenesManagementCluster.new(endpoint)
      field_set = Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet.new(6_u32, [{0_u32, TLV::Any.new(1_u8)}])
      add_scene_direct(cluster1, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8, scene_name: "Test Scene", extension_field_sets: [field_set])
      add_scene_direct(cluster1, fabric_index: 1_u8, group_id: 1_u16, scene_id: 2_u8, scene_name: "Another Scene")
      cluster1.scene_info_by_fabric[1_u8] = Matter::Cluster::ScenesManagementCluster::SceneInfo.new(scene_count: 2_u8, fabric_index: 1_u8)
      cluster1.data_version = 10_u32

      document = cluster1.save_state.as(Matter::Storage::Document)

      cluster2 = Matter::Cluster::ScenesManagementCluster.new(endpoint)
      cluster2.scene_count.should eq(0)
      cluster2.restore_state(document)

      cluster2.scene_count.should eq(2)
      cluster2.has_scene?(1_u16, 1_u8).should be_true
      cluster2.has_scene?(1_u16, 2_u8).should be_true
      restored = cluster2.scenes[{1_u8, 1_u16, 1_u8}]
      restored.scene_name.should eq("Test Scene")
      restored.extension_field_sets.size.should eq(1)
      restored.extension_field_sets[0].cluster_id.should eq(6_u32)
      restored.extension_field_sets[0].attribute_value_list.map { |id, value| {id, value.value} }.should eq([{0_u32, 1_u8}])
      cluster2.scene_info_by_fabric[1_u8].scene_count.should eq(2_u8)
      cluster2.data_version.should eq(10_u32)
    end

    it "starts fresh when the document is malformed" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      cluster.restore_state(Matter::Storage::Document{"scenes" => "bogus"})
      cluster.scene_count.should eq(0)

      cluster.restore_state(Matter::Storage::Document.new)
      cluster.scene_count.should eq(0)
    end
  end

  describe "#persistence_key" do
    it "is the endpoint and cluster id joined by the separator" do
      cluster1 = Matter::Cluster::ScenesManagementCluster.new(Matter::DataType::EndpointNumber.new(1_u16))
      cluster2 = Matter::Cluster::ScenesManagementCluster.new(Matter::DataType::EndpointNumber.new(2_u16))

      cluster1.persistence_key.should eq("1-98") # 0x0062 = 98
      cluster2.persistence_key.should eq("2-98")
      Matter::Cluster::Base.persistence_key(2_u16, 98_u32).should eq(cluster2.persistence_key)
    end
  end

  describe "with Device::Persistence" do
    it "saves and restores cluster state" do
      storage = Matter::Storage::Memory.new
      persistence = Matter::Device::Persistence.new(storage)

      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)
      add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8, scene_name: "Saved Scene")

      persistence.save_cluster(cluster).should be_true
      storage.ids(Matter::Storage::Collections::CLUSTERS).should eq([cluster.persistence_key])

      new_cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)
      persistence.restore_clusters([new_cluster] of Matter::Cluster::Base).should eq(1)

      new_cluster.scene_count.should eq(1)
      new_cluster.has_scene?(1_u16, 1_u8).should be_true
    end

    it "returns false when a cluster has no state to save" do
      persistence = Matter::Device::Persistence.new(Matter::Storage::Memory.new)

      # IdentifyCluster doesn't implement save_state (returns nil)
      identify = Matter::Cluster::IdentifyCluster.new(Matter::DataType::EndpointNumber.new(1_u16))
      persistence.save_cluster(identify).should be_false
    end

    it "restores nothing when no state is stored" do
      persistence = Matter::Device::Persistence.new(Matter::Storage::Memory.new)
      cluster = Matter::Cluster::ScenesManagementCluster.new(Matter::DataType::EndpointNumber.new(1_u16))
      persistence.restore_clusters([cluster] of Matter::Cluster::Base).should eq(0)
    end
  end
end
