require "../backend"
require "../tree_backend"
require "./format"
require "./json_parser"
require "./fields"
require "./fabric_import"
require "./protocol_import"
require "./cluster_import"

module Matter
  module Storage
    module Legacy
      # A read-only `Storage::Backend` view of a pre-refactor JSON storage file.
      #
      # `open` parses the file once into the new collection/document layout;
      # copy it into a real store with `Storage::Migrator.copy`. Unknown
      # contexts, keys and cluster ids are preserved under
      # `app/legacy-<context>-<key>` with a warning so nothing is dropped
      # silently; an inner document that cannot be converted is skipped with a
      # warning naming only its collection and id.
      class JsonImport < Backend
        READ_ONLY_MESSAGE = "is a read-only view of a legacy storage file"

        # Joins `context/key` and `collection/id` in log messages.
        ENTRY_SEPARATOR = "/"

        getter path : String

        @tree = Tree.new
        @open = false

        def initialize(@path : String)
        end

        def open : Nil
          return if @open

          raise StorageError.new("Legacy storage file #{@path} does not exist") unless File.exists?(@path)
          @tree = Tree.new
          import(JsonParser.parse_object(File.read(@path)))
          @tree[Collections::META] = {Collections::META_SCHEMA_ID => Backend.schema_document}
          @open = true
        end

        def close : Nil
          @open = false
        end

        def open? : Bool
          @open
        end

        def read(collection : String, id : String) : Document?
          validate(collection, id)
          ensure_open
          @tree[collection]?.try(&.[id]?).try { |document| Storage.deep_copy(document) }
        end

        def ids(collection : String) : Array(String)
          validate_collection(collection)
          ensure_open
          @tree[collection]?.try(&.keys.sort!) || [] of String
        end

        def all(collection : String) : Hash(String, Document)
          validate_collection(collection)
          ensure_open
          result = Hash(String, Document).new
          if documents = @tree[collection]?
            documents.keys.sort!.each { |id| result[id] = Storage.deep_copy(documents[id]) }
          end
          result
        end

        def collections : Array(String)
          ensure_open
          @tree.compact_map { |name, documents| name unless documents.empty? }.sort!
        end

        def transaction(& : -> Nil) : Nil
          ensure_open
          yield
        end

        def write(collection : String, id : String, document : Document) : Nil
          read_only
        end

        def delete(collection : String, id : String) : Nil
          read_only
        end

        def clear(collection : String) : Nil
          read_only
        end

        def clear_all : Nil
          read_only
        end

        def destroy! : Nil
          read_only
        end

        private def read_only : NoReturn
          raise StorageError.new("#{self.class.name} #{READ_ONLY_MESSAGE}")
        end

        # -- conversion -------------------------------------------------------

        private def import(root : Document) : Nil
          root.each do |context, entries|
            if entries.is_a?(Document)
              entries.each { |key, value| import_entry(context, key, value) }
            else
              preserve_unknown(context, nil, entries)
            end
          end
        end

        private def import_entry(context : String, key : String, value : Type) : Nil
          case {context, key}
          when {Format::DEVICE_IDENTITY_CONTEXT, .in?(Format::IDENTITY_KEYS)}
            guard(Collections::DEVICE, Target::IDENTITY_ID) do
              document(Collections::DEVICE, Target::IDENTITY_ID)[key] = expect_string(value, key)
            end
          when {Format::FABRICS_CONTEXT, Format::FABRIC_TABLE_KEY}
            each_inner(value, Collections::FABRICS) { |legacy| FabricImport.convert(legacy) }
          when {Format::PROTOCOL_CONTEXT, Format::CASE_SESSIONS_KEY}
            each_inner(value, Collections::SESSIONS) { |legacy| ProtocolImport.convert_session(legacy) }
          when {Format::PROTOCOL_CONTEXT, Format::ACTIVE_SUBSCRIPTIONS_KEY}
            each_inner(value, Collections::SUBSCRIPTIONS) { |legacy| ProtocolImport.convert_subscription(legacy) }
          when {Format::PROTOCOL_CONTEXT, Format::NEXT_SUBSCRIPTION_ID_KEY}
            guard(Collections::DEVICE, Target::COUNTERS_ID) do
              counter = value.as?(Int64 | UInt64) || raise ImportError.new("#{key.inspect} is not an integer")
              document(Collections::DEVICE, Target::COUNTERS_ID)[Target::NEXT_SUBSCRIPTION_ID_KEY] = counter
            end
          when {Format::BRIDGE_CONTEXT, Format::BRIDGED_DEVICES_KEY}
            guard(Collections::APP, Target::BRIDGED_DEVICES_ID) do
              store(Collections::APP, Target::BRIDGED_DEVICES_ID, Fields.compact(inner_object(value, key)))
            end
          else
            if context == Format::CLUSTER_STATE_CONTEXT && (match = key.match(Format::CLUSTER_STATE_KEY))
              import_cluster(key, match[1], match[2], value)
            else
              preserve_unknown(context, key, value)
            end
          end
        end

        private def import_cluster(key : String, endpoint : String, cluster : String, value : Type) : Nil
          id = "#{endpoint}#{Target::ID_SEPARATOR}#{cluster}"
          guard(Collections::CLUSTERS, id) do
            cluster_id = cluster.to_i64? || raise ImportError.new("Cluster id in #{key.inspect} does not fit in Int64")
            if converted = ClusterImport.convert(cluster_id, JsonParser.parse(expect_string(value, key)))
              store(Collections::CLUSTERS, id, converted)
            else
              preserve_unknown(Format::CLUSTER_STATE_CONTEXT, key, value)
            end
          end
        end

        # Parses the JSON string *value* as `{ "<id>": {...} }` and stores the
        # block's conversion of each entry under *collection*/`<id>`.
        private def each_inner(value : Type, collection : String, & : Document -> Document) : Nil
          table = guard(collection, nil) { inner_object(value, collection) }
          return unless table

          table.each do |id, entry|
            guard(collection, id) { store(collection, id, yield(JsonParser.object(entry))) }
          end
        end

        private def inner_object(value : Type, key : String) : Document
          JsonParser.parse_object(expect_string(value, key))
        end

        private def expect_string(value : Type, key : String) : String
          value.as?(String) || raise ImportError.new("#{key.inspect} is not a JSON string (got #{value.class})")
        end

        private def preserve_unknown(context : String, key : String?, value : Type) : Nil
          id = [Target::UNKNOWN_ID_PREFIX, context, key].compact.join(Target::ID_SEPARATOR)
          id = id.gsub(Target::INVALID_NAME_CHARACTERS, Target::NAME_REPLACEMENT)
          Log.warn { "Legacy storage entry #{[context, key].compact.join(ENTRY_SEPARATOR)} is not recognised; keeping it as #{Collections::APP}/#{id}" }
          store(Collections::APP, id, Document{Target::RAW_VALUE_KEY => value})
        end

        # Runs the block, logging and swallowing conversion errors so one bad
        # document does not abort the import. Returns `nil` on failure.
        private def guard(collection : String, id : String?, & : -> T) : T? forall T
          yield
        rescue ex : ImportError | JSON::ParseException | ArgumentError | OverflowError
          Log.warn { "Skipping legacy #{[collection, id].compact.join(ENTRY_SEPARATOR)}: #{ex.class} while converting" }
          nil
        end

        private def store(collection : String, id : String, document : Document) : Nil
          Storage.validate_name(collection, "collection")
          Storage.validate_name(id, "id")
          (@tree[collection] ||= Hash(String, Document).new)[id] = document
        end

        # The document at *collection*/*id*, created empty when absent.
        private def document(collection : String, id : String) : Document
          (@tree[collection] ||= Hash(String, Document).new)[id] ||= Document.new
        end
      end
    end
  end
end
