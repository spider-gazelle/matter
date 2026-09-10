require "json"
require "base64"
require "./file_backend"

module Matter
  module Storage
    # A store persisted as one pretty-printed JSON object:
    # `{collection: {id: document}}` with collections and ids sorted and
    # document keys in insertion order.
    #
    # JSON has no byte, time or non-finite float types, so those are wrapped in
    # single-key objects:
    #
    # * `Bytes` -> `{"$bytes": "<strict base64>"}`
    # * `Time`  -> `{"$time": "<RFC 3339 UTC, nine fractional digits>"}` (nanosecond precision, matching `YamlFile`)
    # * non-finite `Float64` -> `{"$float": "NaN" | "Infinity" | "-Infinity"}`
    #
    # Integers are JSON numbers, read via the raw token so values above
    # `Int64::MAX` become `UInt64`. A document hash that happens to consist of
    # exactly one of the wrapper keys is decoded as the wrapped type.
    class JsonFile < FileBackend
      BYTES_KEY = "$bytes"
      TIME_KEY  = "$time"
      FLOAT_KEY = "$float"

      INDENT               = 2
      TIME_FRACTION_DIGITS = 9

      protected def encode(tree : Tree) : String
        JSON.build(indent: INDENT) do |json|
          json.object do
            tree.keys.sort!.each do |collection|
              documents = tree[collection]
              json.field(collection) do
                json.object do
                  documents.keys.sort!.each do |id|
                    json.field(id) { encode_value(json, documents[id]) }
                  end
                end
              end
            end
          end
        end
      end

      protected def decode(content : String) : Tree
        tree = Tree.new
        pull = JSON::PullParser.new(content)
        pull.read_object do |collection|
          documents = Hash(String, Document).new
          pull.read_object do |id|
            documents[id] = decode_value(pull).as?(Document) ||
                            raise StorageError.new("Document #{collection}/#{id} is not a JSON object")
          end
          tree[collection] = documents
        end
        tree
      end

      private def encode_value(json : JSON::Builder, value : Type) : Nil
        case value
        in Nil
          json.null
        in Bool
          json.bool(value)
        in Int64, UInt64
          json.number(value)
        in Float64
          encode_float(json, value)
        in String
          json.string(value)
        in Bytes
          json.object { json.field(BYTES_KEY, Base64.strict_encode(value)) }
        in Time
          json.object { json.field(TIME_KEY, Time::Format::RFC_3339.format(value.to_utc, fraction_digits: TIME_FRACTION_DIGITS)) }
        in Array(Type)
          json.array { value.each { |element| encode_value(json, element) } }
        in Hash(String, Type)
          json.object { value.each { |key, element| json.field(key) { encode_value(json, element) } } }
        end
      end

      private def encode_float(json : JSON::Builder, value : Float64) : Nil
        if value.finite?
          json.number(value)
        else
          json.object { json.field(FLOAT_KEY, value.to_s) }
        end
      end

      private def decode_value(pull : JSON::PullParser) : Type
        case pull.kind
        in .null?
          pull.read_null
        in .bool?
          pull.read_bool
        in .int?
          decode_integer(pull)
        in .float?
          pull.read_float
        in .string?
          pull.read_string
        in .begin_array?
          array = [] of Type
          pull.read_array { array << decode_value(pull) }
          array
        in .begin_object?
          hash = Document.new
          pull.read_object { |key| hash[key] = decode_value(pull) }
          unwrap(hash)
        in .end_array?, .end_object?, .eof?
          raise StorageError.new("Unexpected JSON token #{pull.kind} at line #{pull.line_number}")
        end
      end

      private def decode_integer(pull : JSON::PullParser) : Int64 | UInt64
        line = pull.line_number
        raw = pull.read_raw
        raw.to_i64? || raw.to_u64? ||
          raise StorageError.new("Integer #{raw} at line #{line} does not fit in 64 bits")
      end

      # Turns a single-key wrapper object back into the type it stands for.
      private def unwrap(hash : Document) : Type
        return hash unless hash.size == 1

        key, value = hash.first
        return hash unless value.is_a?(String)

        case key
        when BYTES_KEY then Base64.decode(value)
        when TIME_KEY  then Time::Format::RFC_3339.parse(value)
        when FLOAT_KEY then value.to_f64
        else                hash
        end
      end
    end
  end
end
