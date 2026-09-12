require "json"
require "base64"
require "../document"
require "./format"

module Matter
  module Storage
    module Legacy
      # Parses legacy JSON text into `Storage::Type` values.
      #
      # Integers are read from the raw token so values above `Int64::MAX`
      # (fabric ids, node ids) become `UInt64` instead of failing. `__type__`
      # wrapper objects are unwrapped to `Bytes` or integers.
      module JsonParser
        def self.parse(content : String) : Type
          pull = JSON::PullParser.new(content)
          value = read(pull)
          raise ImportError.new("Trailing content after the JSON document") unless pull.kind.eof?
          value
        end

        # Parses *content* and requires the result to be a JSON object.
        def self.parse_object(content : String) : Document
          object(parse(content))
        end

        # Requires *value* to be a JSON object.
        def self.object(value : Type) : Document
          value.as?(Document) || raise ImportError.new("Expected a JSON object, got #{value.class}")
        end

        # Requires *value* to be a JSON array.
        def self.array(value : Type) : Array(Type)
          value.as?(Array(Type)) || raise ImportError.new("Expected a JSON array, got #{value.class}")
        end

        # Parses decimal text, widening to `UInt64` only when the value does
        # not fit in an `Int64`.
        def self.integer(text : String) : Int64 | UInt64
          text.to_i64? || text.to_u64? || raise ImportError.new("Integer does not fit in 64 bits")
        end

        private def self.read(pull : JSON::PullParser) : Type
          case pull.kind
          in .null?
            pull.read_null
          in .bool?
            pull.read_bool
          in .int?
            integer(pull.read_raw)
          in .float?
            pull.read_float
          in .string?
            pull.read_string
          in .begin_array?
            array = [] of Type
            pull.read_array { array << read(pull) }
            array
          in .begin_object?
            hash = Document.new
            pull.read_object { |key| hash[key] = read(pull) }
            unwrap(hash)
          in .end_array?, .end_object?, .eof?
            raise ImportError.new("Unexpected JSON token #{pull.kind} at line #{pull.line_number}")
          end
        end

        private def self.unwrap(hash : Document) : Type
          type = hash[Format::TYPE_FIELD]?.as?(String)
          text = hash[Format::VALUE_FIELD]?.as?(String)
          return hash unless type && text

          case type
          when Format::BYTES_TYPE                       then Base64.decode(text)
          when Format::BIGINT_TYPE, Format::UINT64_TYPE then integer(text)
          else                                               hash
          end
        end
      end
    end
  end
end
