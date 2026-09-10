# Persistent storage.
#
# The document model (`Storage::Type` / `Storage::Document`), the `Backend`
# interface with its `Memory`, `YamlFile` and `JsonFile` implementations, the
# `Record` mapping macro and the `Migrator` depend on nothing outside this
# directory (plus `matter/error`).
#
# The legacy context/key backends (`Storage::Base`, `MemoryBackend`,
# `JsonFileBackend`, `LegacyType`) are still loaded while their consumers are
# migrated. `storage/manager` is deliberately not loaded here: it depends on
# the fabric table, protocol persistence and clusters, so `matter.cr` loads it
# after the protocol layer.
require "log"
require "./storage/document"
require "./storage/backend"
require "./storage/tree_backend"
require "./storage/memory"
require "./storage/file_backend"
require "./storage/yaml_file"
require "./storage/json_file"
require "./storage/record"

require "./storage/type"
require "./storage/base"
require "./storage/memory_backend"
require "./storage/json_file_backend"

module Matter
  module Storage
    Log = ::Log.for("matter.storage")
  end
end
