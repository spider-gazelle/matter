require "../error"
require "./backend"
require "./memory"
require "./yaml_file"
require "./json_file"

module Matter
  module Storage
    # Copies stores between backends and opens backends from URIs.
    #
    # URI forms: `memory:`, `yaml:<path>`, `json:<path>`. Further schemes
    # (such as `legacy:`) plug in with `register_scheme`.
    module Migrator
      SCHEME_SEPARATOR = ':'

      MEMORY_SCHEME = "memory"
      YAML_SCHEME   = "yaml"
      JSON_SCHEME   = "json"
      LEGACY_SCHEME = "legacy"

      alias Opener = String -> Backend

      @@schemes = {} of String => Opener

      # Registers an opener for *scheme*; the block receives the part of the
      # URI after the scheme and must return an opened `Backend`.
      def self.register_scheme(scheme : String, &opener : Opener) : Nil
        @@schemes[scheme] = opener
      end

      # Opens the backend named by *uri*. Raises `Matter::StorageError` for an
      # unknown scheme or a missing path.
      def self.open(uri : String) : Backend
        scheme, _, rest = uri.partition(SCHEME_SEPARATOR)
        raise StorageError.new("Storage URI #{uri.inspect} has no scheme; expected memory:, yaml:<path> or json:<path>") if scheme.empty? || scheme == uri

        if opener = @@schemes[scheme]?
          return opener.call(rest)
        end

        case scheme
        when MEMORY_SCHEME
          Memory.new
        when YAML_SCHEME
          YamlFile.new(require_path(uri, rest)).tap(&.open)
        when JSON_SCHEME
          JsonFile.new(require_path(uri, rest)).tap(&.open)
        when LEGACY_SCHEME
          raise StorageError.new("Storage URI scheme #{LEGACY_SCHEME}: needs `require \"matter/storage/legacy\"` before it can be opened")
        else
          raise StorageError.new("Unknown storage URI scheme #{scheme.inspect} in #{uri.inspect}")
        end
      end

      # Copies every document in every collection except `meta` from *from*
      # into *to* inside one transaction. Returns the number of documents
      # copied per collection.
      def self.copy(from : Backend, to : Backend) : Hash(String, Int32)
        counts = {} of String => Int32
        to.transaction do
          from.collections.each do |collection|
            next if collection == Collections::META

            documents = from.all(collection)
            documents.each { |id, document| to.write(collection, id, document) }
            counts[collection] = documents.size
          end
        end
        counts
      end

      private def self.require_path(uri : String, path : String) : String
        raise StorageError.new("Storage URI #{uri.inspect} needs a file path after the scheme") if path.empty?
        path
      end
    end
  end
end
