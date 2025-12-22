require "./base"
require "../fabric_table"
require "../protocol/persistence"
require "../cluster/cluster"

module Matter
  module Storage
    # Device persistence manager.
    #
    # Wraps a `Storage::Base` backend and exposes higher-level persistence for:
    # - `FabricTable`
    # - protocol persistence (CASE sessions + subscriptions)
    # - per-cluster state (scenes, groups, etc.)
    #
    # Future DB-backed implementations should implement `Storage::Base`.
    class Manager
      Log = ::Log.for("matter.storage.manager")

      CLUSTER_STATE_CONTEXT = ["cluster_state"] of String

      getter storage : Storage::Base
      getter fabric_table : FabricTable
      getter protocol_persistence : Protocol::Persistence::Base

      def initialize(
        @storage : Storage::Base,
        max_fabrics : UInt8 = FabricTable::DEFAULT_MAX_FABRICS,
      )
        @storage.start unless @storage.initialized?
        @fabric_table = FabricTable.new(@storage, max_fabrics: max_fabrics)
        @protocol_persistence = Protocol::Persistence::StorageBackend.new(@storage)
      end

      def stop : Nil
        @storage.stop
      end

      def save_cluster_state(cluster : Cluster::Base) : Bool
        if json = cluster.save_state
          @storage.set(CLUSTER_STATE_CONTEXT, cluster.persistence_key, json)
          Log.debug { "Saved state for cluster #{cluster.name} (#{cluster.persistence_key})" }
          true
        else
          false
        end
      rescue ex
        Log.error(exception: ex) { "Failed to save cluster state (cluster=#{cluster.name} key=#{cluster.persistence_key})" }
        false
      end

      def restore_cluster_state(cluster : Cluster::Base) : Bool
        key = cluster.persistence_key
        stored = @storage.get(CLUSTER_STATE_CONTEXT, key)

        if stored.is_a?(String) && !stored.empty?
          cluster.restore_state(stored)
          Log.debug { "Restored state for cluster #{cluster.name} (#{key})" }
          true
        else
          false
        end
      rescue ex
        Log.error(exception: ex) { "Failed to restore cluster state (cluster=#{cluster.name} key=#{cluster.persistence_key} stored=#{stored.inspect})" }
        false
      end

      def save_all_cluster_states(clusters : Enumerable(Cluster::Base)) : Int32
        saved = 0
        clusters.each do |cluster|
          saved += 1 if save_cluster_state(cluster)
        end
        Log.info { "Saved state for #{saved} cluster(s)" } if saved > 0
        saved
      end

      def restore_all_cluster_states(clusters : Enumerable(Cluster::Base)) : Int32
        restored = 0
        clusters.each do |cluster|
          restored += 1 if restore_cluster_state(cluster)
        end
        Log.info { "Restored state for #{restored} cluster(s)" } if restored > 0
        restored
      end

      def delete_cluster_state(cluster : Cluster::Base) : Nil
        @storage.delete(CLUSTER_STATE_CONTEXT, cluster.persistence_key)
      rescue ex
        Log.error(exception: ex) { "Failed to delete cluster state (cluster=#{cluster.name} key=#{cluster.persistence_key})" }
      end

      def clear_all_cluster_states : Nil
        @storage.clear_all(CLUSTER_STATE_CONTEXT)
        Log.info { "Cleared all cluster state" }
      rescue ex
        Log.error(exception: ex) { "Failed to clear cluster state (context=#{CLUSTER_STATE_CONTEXT})" }
      end
    end
  end
end
