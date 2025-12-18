require "./storage_manager"
require "../storage/json_file_backend"

module Matter
  module Persistence
    class JsonStorage < StorageManager
      getter path : String

      def initialize(
        @path : String = "matter_storage.json",
        max_fabrics : UInt8 = FabricTable::DEFAULT_MAX_FABRICS,
      )
        super(Storage::JsonFileBackend.new(@path), max_fabrics: max_fabrics)
      end
    end
  end
end
