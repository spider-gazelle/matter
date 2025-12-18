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
      # Root JSON keys used to preserve non-JSON-native types
      TYPE_FIELD  = "__type__"
      VALUE_FIELD = "value"
      NAME_FIELD  = "name"

      getter path : String
      getter? initialized : Bool = false

      @store : Hash(String, Hash(String, Type)) = {} of String => Hash(String, Type)

      def initialize(@path : String = "matter_storage.json")
      end

      def start : Void
        load_from_disk
        @initialized = true
      end

      def stop : Void
        flush
        @initialized = false
      end

      def get(contexts : Array(String), key : String) : Type
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)
        @store[context_key]?.try(&.[key]?)
      end

      def set(contexts : Array(String), key : String, value : Type) : Void
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)
        @store[context_key] ||= {} of String => Type
        @store[context_key][key] = value
        flush
      end

      # Set multiple key-value pairs at once
      def set(contexts : Array(String), values : Hash(String, Type)) : Void
        raise Exception.new("Context must not be empty!") if contexts.size == 0

        values.each do |key, value|
          set(contexts, key, value)
        end
      end

      def delete(contexts : Array(String), key : String) : Void
        raise Exception.new("Context and key must not be empty!") if contexts.size == 0 || key.size == 0

        context_key = create_context_key(contexts)
        if ctx = @store[context_key]?
          ctx.delete(key)
          @store.delete(context_key) if ctx.empty?
          flush
        end
      end

      def keys(contexts : Array(String)) : Array(String)
        raise Exception.new("Context must not be empty!") if contexts.size == 0

        context_key = create_context_key(contexts)
        @store[context_key]?.try(&.keys.sort) || ([] of String)
      end

      # Get all key-value pairs in a context
      def values(contexts : Array(String)) : Hash(String, Type)
        raise Exception.new("Context must not be empty!") if contexts.size == 0

        context_key = create_context_key(contexts)
        @store[context_key]?.try(&.dup) || ({} of String => Type)
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
      def clear : Void
        @store.clear
        flush
      end

      def clear_all(contexts : Array(String)) : Void
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

          ctx_hash = {} of String => Type
          ctx_hash_any.each do |key, value_any|
            ctx_hash[key] = type_from_json(value_any)
          end

          @store[context_key] = ctx_hash
        end
      rescue
        # If storage is corrupted, start empty (device can re-commission/recreate).
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

      private def type_from_json(any : JSON::Any) : Type
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
          arr = [] of Type
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
            when "matter_datatype"
              name = raw[NAME_FIELD].as_s
              value_any = raw[VALUE_FIELD]?
              decode_datatype(name, value_any)
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

      private def decode_hash(raw : Hash(String, JSON::Any)) : Type
        h = {} of String => Type
        raw.each do |k, v|
          next if k == TYPE_FIELD || k == VALUE_FIELD || k == NAME_FIELD
          h[k] = type_from_json(v)
        end
        h
      end

      private def decode_datatype(name : String, value_any : JSON::Any?) : Type
        value = value_any ? value_any.raw : nil

        case name
        when "AttributeId"
          DataType::AttributeId.new(parse_u64(value).to_u32)
        when "ClusterId"
          DataType::ClusterId.new(parse_u64(value).to_u32)
        when "CommandId"
          DataType::CommandId.new(parse_u64(value).to_u32)
        when "EndpointNumber"
          DataType::EndpointNumber.new(parse_u64(value).to_u16)
        when "EventId"
          DataType::EventId.new(parse_u64(value).to_u32)
        when "FabricId"
          DataType::FabricId.new(parse_u64(value))
        when "FabricIndex"
          if value.nil?
            DataType::FabricIndex.new(nil)
          else
            DataType::FabricIndex.new(parse_u64(value).to_u8)
          end
        when "GroupId"
          DataType::GroupId.new(parse_u64(value).to_u16)
        when "NodeId"
          DataType::NodeId.new(parse_u64(value))
        when "VendorId"
          DataType::VendorId.new(parse_u64(value).to_u16)
        else
          # Fallback to string to preserve information
          name
        end
      end

      private def write_type(json : JSON::Builder, value : Type) : Nil
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
        when DataType::AttributeId
          write_datatype(json, "AttributeId", value.id)
        when DataType::ClusterId
          write_datatype(json, "ClusterId", value.id)
        when DataType::CommandId
          write_datatype(json, "CommandId", value.id)
        when DataType::EndpointNumber
          write_datatype(json, "EndpointNumber", value.number)
        when DataType::EventId
          write_datatype(json, "EventId", value.id)
        when DataType::FabricId
          write_datatype(json, "FabricId", value.id)
        when DataType::FabricIndex
          write_datatype(json, "FabricIndex", value.index)
        when DataType::GroupId
          write_datatype(json, "GroupId", value.id)
        when DataType::NodeId
          write_datatype(json, "NodeId", value.id)
        when DataType::VendorId
          write_datatype(json, "VendorId", value.id)
        when Array(Type)
          json.array do
            value.each do |v|
              write_type(json, v)
            end
          end
        when Hash(String, Type)
          json.object do
            value.each do |k, v|
              json.field(k) { write_type(json, v) }
            end
          end
        when Hash(BaseType, Type)
          json.object do
            value.each do |k, v|
              json.field(k.to_s) { write_type(json, v) }
            end
          end
        else
          json.string(value.to_s)
        end
      end

      private def write_datatype(json : JSON::Builder, name : String, value : Int32 | Int64 | UInt16 | UInt32 | UInt64 | UInt8 | Nil) : Nil
        json.object do
          json.field(TYPE_FIELD, "matter_datatype")
          json.field(NAME_FIELD, name)
          json.field(VALUE_FIELD) do
            case value
            when Nil
              json.null
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
              # Use string to preserve values > Int64::MAX
              json.string(value.to_s)
            end
          end
        end
      end

      private def parse_u64(value : Nil | Bool | Int64 | Float64 | String | Array(JSON::Any) | Hash(String, JSON::Any)) : UInt64
        case value
        when Int64
          value.to_u64
        when Float64
          value.to_i64.to_u64
        when String
          value.to_u64
        else
          0_u64
        end
      end

      private def create_context_key(contexts : Array(String)) : String
        key = contexts.join(".")

        if key.size == 0 || key.includes?("..") || key.starts_with?(".") || key.ends_with?(".")
          raise Exception.new("Context must not be an empty string.")
        end

        key
      end
    end
  end
end
