# One-shot importer for the pre-refactor JSON storage format.
#
# Temporary module: `require "matter/storage/legacy"` (it is not loaded by
# `require "matter"`) registers the `legacy:<file>` URI scheme with
# `Storage::Migrator`, so an old device store can be converted with
#
# ```text
# matter-storage migrate --from legacy:matter_storage.json --to yaml:matter_storage.yml
# ```
#
# Delete `src/matter/storage/legacy/` once every deployed device has migrated.
require "../storage"
require "./legacy/*"

module Matter
  module Storage
    module Legacy
      Log = ::Log.for("matter.storage.legacy")

      Migrator.register_scheme(Migrator::LEGACY_SCHEME) do |path|
        raise StorageError.new("Storage URI #{Migrator::LEGACY_SCHEME}: needs the path of the old JSON file after the scheme") if path.empty?
        JsonImport.new(path).tap(&.open)
      end
    end
  end
end
