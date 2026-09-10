require "base64"
require "../document"
require "./format"

module Matter
  module Storage
    module Legacy
      # Typed accessors over a parsed legacy JSON object. Every accessor raises
      # `ImportError` (naming only the key) when the value has the wrong shape;
      # the `?` variants return `nil` for an absent or `null` value.
      module Fields
        def self.string(document : Document, key : String) : String
          string?(document, key) || missing(key)
        end

        def self.string?(document : Document, key : String) : String?
          value = document[key]?
          return if value.nil?
          value.as?(String) || mismatch(key, "a string", value)
        end

        def self.integer(document : Document, key : String) : Int64 | UInt64
          integer?(document, key) || missing(key)
        end

        def self.integer?(document : Document, key : String) : (Int64 | UInt64)?
          value = document[key]?
          return if value.nil?
          value.as?(Int64 | UInt64) || mismatch(key, "an integer", value)
        end

        # An integer that must fit in an `Int64` (indexes, ports, counters).
        def self.int64(document : Document, key : String) : Int64
          int64?(document, key) || missing(key)
        end

        def self.int64?(document : Document, key : String) : Int64?
          value = integer?(document, key)
          return if value.nil?
          value.as?(Int64) || mismatch(key, "an integer within Int64", value)
        end

        def self.bool(document : Document, key : String) : Bool
          case value = document[key]?
          when Bool then value
          when Nil  then missing(key)
          else           mismatch(key, "a boolean", value)
          end
        end

        def self.array(document : Document, key : String) : Array(Type)
          value = document[key]?
          return [] of Type if value.nil?
          value.as?(Array(Type)) || mismatch(key, "an array", value)
        end

        def self.object(document : Document, key : String) : Document
          value = document[key]?
          return Document.new if value.nil?
          value.as?(Document) || mismatch(key, "an object", value)
        end

        # Strict base64 text; `""` and absence both mean no value.
        def self.base64?(document : Document, key : String) : Bytes?
          text = string?(document, key)
          return if text.nil? || text.empty?
          Base64.decode(text)
        rescue Base64::Error
          mismatch(key, "base64 text")
        end

        def self.base64(document : Document, key : String) : Bytes
          base64?(document, key) || missing(key)
        end

        # Lower or upper case hex text without a prefix.
        def self.hex?(document : Document, key : String) : Bytes?
          text = string?(document, key)
          return if text.nil?
          text.hexbytes? || mismatch(key, "hex text")
        end

        def self.hex(document : Document, key : String) : Bytes
          hex?(document, key) || missing(key)
        end

        # Unix seconds as UTC `Time`.
        def self.unix_time(document : Document, key : String) : Time
          Time.unix(int64(document, key))
        end

        # Returns *value* without any `null` object members, recursively.
        # Everything else is returned as-is.
        def self.compact(value : Type) : Type
          case value
          in Document
            compact(value)
          in Array(Type)
            value.map { |element| compact(element).as(Type) }
          in Nil, Bool, Int64, UInt64, Float64, String, Bytes, Time
            value
          end
        end

        # :ditto:
        def self.compact(document : Document) : Document
          result = Document.new(initial_capacity: document.size)
          document.each { |key, element| result[key] = compact(element) unless element.nil? }
          result
        end

        # Replaces the hex string at *from* with its bytes at *to*, when present.
        def self.hex_to_bytes!(document : Document, from : String, to : String = from) : Nil
          return unless document.has_key?(from)

          bytes = hex(document, from)
          document.delete(from)
          document[to] = bytes
        end

        # Yields every element of the array at *key* as an object, replacing it
        # with the block's result.
        def self.map_objects!(document : Document, key : String, & : Document -> Document) : Nil
          return unless document.has_key?(key)

          document[key] = array(document, key).map { |element| yield(JsonParser.object(element)).as(Type) }
        end

        private def self.missing(key : String) : NoReturn
          raise ImportError.new("Missing required field #{key.inspect}")
        end

        private def self.mismatch(key : String, expected : String, value : Type = nil) : NoReturn
          raise ImportError.new("Field #{key.inspect} is not #{expected}#{value.nil? ? "" : " (got #{value.class})"}")
        end
      end
    end
  end
end
