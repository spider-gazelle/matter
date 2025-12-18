require "../storage/base"
require "../fabric_table"
require "../protocol/persistence"

module Matter
  module Persistence
    # Base class for device persistence providers.
    #
    # The goal is to keep example devices small by having the core library manage:
    # - Fabric table persistence
    # - CASE session persistence
    # - Subscription persistence
    #
    # Future implementations (PostgreSQL/SQLite) can share the same surface by
    # providing a `Storage::Base` implementation.
    abstract class StorageManager
      getter storage : Storage::Base
      getter fabric_table : FabricTable
      getter protocol_persistence : Protocol::Persistence::Base

      protected def initialize(
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
    end
  end
end
