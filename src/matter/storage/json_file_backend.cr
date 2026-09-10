require "json"
require "file_utils"
require "base64"
require "big"

require "./base"
require "./type"

module Matter
  module Storage
    # A simple JSON file backed storage implementation.
    #
    # Persists the same context-key model as `MemoryBackend` to a single JSON file.
    # This is intended as a low-friction default for devices/examples and as the
    # foundation for future DB-backed implementations.
    class JsonFileBackend < Base
      Log = ::Log.for("matter.storage.json_file_backend")

      # Root JSON keys used to preserve non-JSON-native types
      TYPE_FIELD  = "__type__"
      VALUE_FIELD = "value"

      # Suffix timestamp for a corrupt file that is moved aside on load.
      TIMESTAMP_FORMAT = "%Y%m%dT%H%M%S"

      getter path : String
      getter? initialized : Bool = false

      @store : Hash(String, Hash(String, LegacyType)) = {} of String => Hash(String, LegacyType)

      def initialize(@path : String = "matter_storage.json")
      end

      def start : Nil
        load_from_disk
        @initialized = true
      end

      def stop : Nil
        flush
        @initialized = false
      end

      def get(contexts : Array(String), key : String) : LegacyType
        raise Matter::StorageError.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)
        @store[context_key]?.try(&.[key]?)
      end

      def set(contexts : Array(String), key : String, value : LegacyType) : Nil
        raise Matter::StorageError.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)
        @store[context_key] ||= {} of String => LegacyType
        @store[context_key][key] = value
        flush
      end

      def delete(contexts : Array(String), key : String) : Nil
        raise Matter::StorageError.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)
        if ctx = @store[context_key]?
          ctx.delete(key)
          @store.delete(context_key) if ctx.empty?
          flush
        end
      end

      def keys(contexts : Array(String)) : Array(String)
        context_key = create_context_key(contexts)
        @store[context_key]?.try(&.keys.sort!) || ([] of String)
      end

      # Get all key-value pairs in a context
      def values(contexts : Array(String)) : Hash(String, LegacyType)
        context_key = create_context_key(contexts)
        @store[context_key]?.try(&.dup) || ({} of String => LegacyType)
      end

      # Get list of immediate subcontext names
      def contexts(contexts : Array(String)) : Array(String)
        context_key = contexts.size == 0 ? "" : create_context_key(contexts)
        prefix = context_key.size == 0 ? "" : "#{context_key}."

        subcontexts = Set(String).new

        @store.keys.each do |key|
          if context_key.size == 0
            if dot_index = key.index('.')
              subcontexts << key[0...dot_index]
            else
              subcontexts << key
            end
          elsif key.starts_with?(prefix)
            remainder = key[prefix.size..-1]
            if dot_index = remainder.index('.')
              subcontexts << remainder[0...dot_index]
            else
              subcontexts << remainder
            end
          end
        end

        subcontexts.to_a.sort
      end

      # Clears all stored contexts and keys.
      def clear : Nil
        @store.clear
        flush
      end

      def clear_all(contexts : Array(String)) : Nil
        if contexts.size == 0
          clear
          return
        end

        context_key = create_context_key(contexts)
        prefix = "#{context_key}."

        keys_to_delete = @store.keys.select do |key|
          key == context_key || key.starts_with?(prefix)
        end

        keys_to_delete.each { |key| @store.delete(key) }
        flush
      end

      private def load_from_disk : Nil
        @store.clear
        return unless File.exists?(@path)

        content = File.read(@path)
        return if content.strip.empty?

        parsed = JSON.parse(content)
        root = parsed.as_h?
        return unless root

        root.each do |context_key, ctx_any|
          ctx_hash_any = ctx_any.as_h?
          next unless ctx_hash_any

          ctx_hash = {} of String => LegacyType
          ctx_hash_any.each do |key, value_any|
            ctx_hash[key] = type_from_json(value_any)
          end

          @store[context_key] = ctx_hash
        end
      rescue ex
        # Keep the corrupt file for inspection and start empty (the device can
        # re-commission / recreate its state).
        corrupt_path = "#{@path}.corrupt-#{Time.utc.to_s(TIMESTAMP_FORMAT)}"
        Log.error(exception: ex) { "Storage file is corrupt; moving it to #{corrupt_path} and starting empty" }
        File.rename(@path, corrupt_path)
        @store.clear
      end

      private def flush : Nil
        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir) unless dir == "."

        tmp_path = "#{@path}.tmp"

        File.open(tmp_path, "w") do |io|
          JSON.build(io) do |json|
            json.object do
              @store.each do |context_key, ctx|
                json.field(context_key) do
                  json.object do
                    ctx.each do |key, value|
                      json.field(key) do
                        write_type(json, value)
                      end
                    end
                  end
                end
              end
            end
          end
        end

        File.rename(tmp_path, @path)
      end

      private def type_from_json(any : JSON::Any) : LegacyType
        case raw = any.raw
        when Nil
          nil
        when Bool
          raw
        when Int64
          raw
        when Float64
          raw
        when String
          raw
        when Array
          arr = [] of LegacyType
          raw.each do |v|
            arr << type_from_json(v)
          end
          arr
        when Hash
          if (type_any = raw[TYPE_FIELD]?) && type_any.raw.is_a?(String)
            type = type_any.as_s
            case type
            when "bytes"
              Base64.decode(raw[VALUE_FIELD].as_s)
            when "bigint"
              BigInt.new(raw[VALUE_FIELD].as_s)
            when "uint64"
              raw[VALUE_FIELD].as_s.to_u64
            else
              # Unknown typed object - keep as a normal hash
              decode_hash(raw)
            end
          else
            decode_hash(raw)
          end
        else
          raw.to_s
        end
      end

      private def decode_hash(raw : Hash(String, JSON::Any)) : LegacyType
        h = {} of String => LegacyType
        raw.each do |k, v|
          next if k == TYPE_FIELD || k == VALUE_FIELD
          h[k] = type_from_json(v)
        end
        h
      end

      private def write_type(json : JSON::Builder, value : LegacyType) : Nil
        case value
        when Nil
          json.null
        when Bool
          json.bool(value)
        when String
          json.string(value)
        when Int8
          json.number(value.to_i64)
        when Int16
          json.number(value.to_i64)
        when Int32
          json.number(value.to_i64)
        when Int64
          json.number(value)
        when UInt8
          json.number(value.to_i64)
        when UInt16
          json.number(value.to_i64)
        when UInt32
          json.number(value.to_i64)
        when UInt64
          if value > Int64::MAX.to_u64
            json.object do
              json.field(TYPE_FIELD, "uint64")
              json.field(VALUE_FIELD, value.to_s)
            end
          else
            json.number(value.to_i64)
          end
        when Float32
          json.number(value.to_f64)
        when Float64
          json.number(value)
        when BigInt
          json.object do
            json.field(TYPE_FIELD, "bigint")
            json.field(VALUE_FIELD, value.to_s)
          end
        when Slice(UInt8)
          json.object do
            json.field(TYPE_FIELD, "bytes")
            json.field(VALUE_FIELD, Base64.strict_encode(value))
          end
        when Array(LegacyType)
          json.array do
            value.each do |v|
              write_type(json, v)
            end
          end
        when Hash(String, LegacyType)
          json.object do
            value.each do |k, v|
              json.field(k) { write_type(json, v) }
            end
          end
        else
          json.string(value.to_s)
        end
      end
    end
  end
end
