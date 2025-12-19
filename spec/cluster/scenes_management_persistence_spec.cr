require "../spec_helper"
require "../../src/matter/cluster/scenes_management_cluster"
require "../../src/matter/persistence/storage_manager"
require "../../src/matter/storage/memory_backend"

describe Matter::Cluster::ScenesManagementCluster do
  describe "state persistence" do
    describe "#save_state" do
      it "returns JSON string with scene data" do
        endpoint = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

        # Add scenes directly to the internal storage for testing
        add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8, scene_name: "Morning")
        add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 2_u8, scene_name: "Evening")
        add_scene_direct(cluster, fabric_index: 1_u8, group_id: 2_u16, scene_id: 1_u8, scene_name: "Night")

        json = cluster.save_state
        json.should_not be_nil
        json.not_nil!.should contain("Morning")
        json.not_nil!.should contain("Evening")
        json.not_nil!.should contain("Night")
      end

      it "includes data_version in saved state" do
        endpoint = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

        add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8)
        cluster.data_version = 5_u32 # Manually set for test

        json = cluster.save_state
        json.should_not be_nil

        # Parse JSON to verify data_version is included
        parsed = JSON.parse(json.not_nil!)
        parsed["data_version"].as_i.should eq(5)
      end
    end

    describe "#restore_state" do
      it "restores scenes from JSON" do
        endpoint = Matter::DataType::EndpointNumber.new(1_u16)
        cluster1 = Matter::Cluster::ScenesManagementCluster.new(endpoint)

        # Add scenes to first cluster
        add_scene_direct(cluster1, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8, scene_name: "Test Scene")
        add_scene_direct(cluster1, fabric_index: 1_u8, group_id: 1_u16, scene_id: 2_u8, scene_name: "Another Scene")

        json = cluster1.save_state
        cluster1.scene_count.should eq(2)

        # Create a new cluster and restore state
        cluster2 = Matter::Cluster::ScenesManagementCluster.new(endpoint)
        cluster2.scene_count.should eq(0) # Empty initially

        cluster2.restore_state(json.not_nil!)

        cluster2.scene_count.should eq(2)
        cluster2.has_scene?(1_u16, 1_u8).should be_true
        cluster2.has_scene?(1_u16, 2_u8).should be_true
      end

      it "restores data_version from JSON" do
        endpoint = Matter::DataType::EndpointNumber.new(1_u16)
        cluster1 = Matter::Cluster::ScenesManagementCluster.new(endpoint)

        # Add several scenes
        add_scene_direct(cluster1, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8)
        add_scene_direct(cluster1, fabric_index: 1_u8, group_id: 1_u16, scene_id: 2_u8)
        add_scene_direct(cluster1, fabric_index: 1_u8, group_id: 1_u16, scene_id: 3_u8)
        cluster1.data_version = 10_u32 # Manually set for test

        json = cluster1.save_state

        # Create a new cluster and restore state
        cluster2 = Matter::Cluster::ScenesManagementCluster.new(endpoint)
        cluster2.data_version.should eq(0)

        cluster2.restore_state(json.not_nil!)

        cluster2.data_version.should eq(10)
      end

      it "handles invalid JSON gracefully" do
        endpoint = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

        # Should not raise, just log error
        cluster.restore_state("invalid json")
        cluster.scene_count.should eq(0)
      end

      it "handles empty JSON gracefully" do
        endpoint = Matter::DataType::EndpointNumber.new(1_u16)
        cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

        # Should not raise
        cluster.restore_state("{}")
      end
    end

    describe "#persistence_key" do
      it "returns unique key based on endpoint and cluster ID" do
        endpoint1 = Matter::DataType::EndpointNumber.new(1_u16)
        cluster1 = Matter::Cluster::ScenesManagementCluster.new(endpoint1)

        endpoint2 = Matter::DataType::EndpointNumber.new(2_u16)
        cluster2 = Matter::Cluster::ScenesManagementCluster.new(endpoint2)

        cluster1.persistence_key.should eq("endpoint_1_cluster_98") # 0x0062 = 98
        cluster2.persistence_key.should eq("endpoint_2_cluster_98")

        cluster1.persistence_key.should_not eq(cluster2.persistence_key)
      end
    end
  end

  describe "integration with StorageManager" do
    it "saves and restores cluster state via storage manager" do
      storage = Matter::Storage::MemoryBackend.new
      storage.start

      # Create a test persistence manager
      manager = TestPersistenceManager.new(storage)

      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      # Add scenes
      add_scene_direct(cluster, fabric_index: 1_u8, group_id: 1_u16, scene_id: 1_u8, scene_name: "Saved Scene")
      cluster.scene_count.should eq(1)

      # Save via storage manager
      manager.save_cluster_state(cluster).should be_true

      # Create a new cluster instance
      new_cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)
      new_cluster.scene_count.should eq(0)

      # Restore via storage manager
      manager.restore_cluster_state(new_cluster).should be_true

      new_cluster.scene_count.should eq(1)
      new_cluster.has_scene?(1_u16, 1_u8).should be_true
    end

    it "returns false when no state to save" do
      storage = Matter::Storage::MemoryBackend.new
      storage.start

      manager = TestPersistenceManager.new(storage)

      # OnOffCluster doesn't implement save_state (returns nil)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      on_off = Matter::Cluster::OnOffCluster.new(endpoint)

      manager.save_cluster_state(on_off).should be_false
    end

    it "returns false when no state to restore" do
      storage = Matter::Storage::MemoryBackend.new
      storage.start

      manager = TestPersistenceManager.new(storage)

      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      # No state saved yet
      manager.restore_cluster_state(cluster).should be_false
    end
  end
end

# Helper to add scenes directly to the cluster's internal storage
private def add_scene_direct(
  cluster : Matter::Cluster::ScenesManagementCluster,
  fabric_index : UInt8,
  group_id : UInt16,
  scene_id : UInt8,
  scene_name : String = "",
  transition_time : UInt32 = 0_u32,
)
  scene_data = Matter::Cluster::ScenesManagementCluster::SceneData.new(
    transition_time: transition_time,
    scene_name: scene_name,
    extension_field_sets: [] of Matter::Cluster::ScenesManagementCluster::ExtensionFieldSet
  )
  cluster.scenes[{fabric_index, group_id, scene_id}] = scene_data
end

# Minimal test persistence manager
class TestPersistenceManager
  CLUSTER_STATE_CONTEXT = ["cluster_state"] of String

  def initialize(@storage : Matter::Storage::Base)
  end

  def save_cluster_state(cluster : Matter::Cluster::Base) : Bool
    if json = cluster.save_state
      @storage.set(CLUSTER_STATE_CONTEXT, cluster.persistence_key, json)
      true
    else
      false
    end
  end

  def restore_cluster_state(cluster : Matter::Cluster::Base) : Bool
    stored = @storage.get(CLUSTER_STATE_CONTEXT, cluster.persistence_key)

    if stored.is_a?(String) && !stored.empty?
      cluster.restore_state(stored)
      true
    else
      false
    end
  end
end
