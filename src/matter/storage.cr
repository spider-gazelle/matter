# Persistent storage.
#
# The document model (`Storage::Type` / `Storage::Document`), the `Backend`
# interface with its `Memory`, `YamlFile` and `JsonFile` implementations, the
# `Record` mapping macro and the `Migrator` depend on nothing outside this
# directory (plus `matter/error`). Device-level persistence lives in
# `Device::Persistence`.
require "log"
require "./storage/document"
require "./storage/backend"
require "./storage/tree_backend"
require "./storage/memory"
require "./storage/file_backend"
require "./storage/yaml_file"
require "./storage/json_file"
require "./storage/record"
require "./storage/migrator"

module Matter
  module Storage
    Log = ::Log.for("matter.storage")
  end
end
