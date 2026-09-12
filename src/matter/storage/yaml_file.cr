require "yaml"
require "base64"
require "./file_backend"

module Matter
  module Storage
    # A store persisted as one YAML document: `{collection: {id: document}}`.
    #
    # Encoding (chosen so a plain-vs-quoted scalar decides the type):
    #
    # * `nil` -> plain `null`; `Bool` -> plain `true` / `false`
    # * `Int64` / `UInt64` -> plain decimal; `Float64` -> plain (`.inf`, `-.inf`, `.nan` for non-finite)
    # * `String` -> always double-quoted, so `"123"`, `"true"` and `"null"` stay strings
    # * `Bytes` -> `!!binary` tagged strict base64
    # * `Time` -> `!!timestamp` tagged RFC 3339 UTC scalar with nine fractional digits
    #   (nanosecond precision, matching `JsonFile`)
    #
    # Decoding uses `YAML::Nodes` so the scalar style is visible: a quoted
    # scalar is always a `String`; a plain scalar is `nil`, `Bool`, `Int64`
    # (`UInt64` when it does not fit) or `Float64` by its content, and a plain
    # scalar that is none of those is kept as a `String`. Anchors and aliases
    # are rejected.
    class YamlFile < FileBackend
      BINARY_TAG    = "tag:yaml.org,2002:binary"
      TIMESTAMP_TAG = "tag:yaml.org,2002:timestamp"
      STRING_TAG    = "tag:yaml.org,2002:str"

      NULL_SCALARS  = {"null", "Null", "NULL", "~", ""}
      TRUE_SCALARS  = {"true", "True", "TRUE"}
      FALSE_SCALARS = {"false", "False", "FALSE"}

      POSITIVE_INFINITY_SCALAR = ".inf"
      NEGATIVE_INFINITY_SCALAR = "-.inf"
      NAN_SCALAR               = ".nan"
      INTEGER_PATTERN          = /\A[-+]?[0-9]+\z/

      TIME_FRACTION_DIGITS = 9

      protected def encode(tree : Tree) : String
        YAML.build do |yaml|
          yaml.mapping do
            tree.keys.sort!.each do |collection|
              documents = tree[collection]
              yaml.scalar(collection)
              yaml.mapping do
                documents.keys.sort!.each do |id|
                  yaml.scalar(id)
                  encode_value(yaml, documents[id])
                end
              end
            end
          end
        end
      end

      protected def decode(content : String) : Tree
        tree = Tree.new
        root = YAML::Nodes.parse(content).nodes.first?
        return tree unless root

        each_pair(expect_mapping(root, "store")) do |collection, collection_node|
          documents = Hash(String, Document).new
          each_pair(expect_mapping(collection_node, "collection #{collection.inspect}")) do |id, document_node|
            documents[id] = decode_mapping(expect_mapping(document_node, "document #{collection}/#{id}"))
          end
          tree[collection] = documents
        end
        tree
      end

      private def encode_value(yaml : YAML::Builder, value : Type) : Nil
        case value
        in Nil
          yaml.scalar(NULL_SCALARS.first)
        in Bool, Int64, UInt64
          yaml.scalar(value.to_s)
        in Float64
          yaml.scalar(encode_float(value))
        in String
          yaml.scalar(value, style: YAML::ScalarStyle::DOUBLE_QUOTED)
        in Bytes
          yaml.scalar(Base64.strict_encode(value), tag: BINARY_TAG)
        in Time
          yaml.scalar(Time::Format::RFC_3339.format(value.to_utc, fraction_digits: TIME_FRACTION_DIGITS), tag: TIMESTAMP_TAG)
        in Array(Type)
          yaml.sequence { value.each { |element| encode_value(yaml, element) } }
        in Hash(String, Type)
          yaml.mapping do
            value.each do |key, element|
              yaml.scalar(key)
              encode_value(yaml, element)
            end
          end
        end
      end

      private def encode_float(value : Float64) : String
        if value.nan?
          NAN_SCALAR
        elsif value.infinite?
          value.positive? ? POSITIVE_INFINITY_SCALAR : NEGATIVE_INFINITY_SCALAR
        else
          value.to_s
        end
      end

      private def decode_node(node : YAML::Nodes::Node) : Type
        case node
        in YAML::Nodes::Scalar
          decode_scalar(node)
        in YAML::Nodes::Sequence
          node.nodes.map { |element| decode_node(element).as(Type) }
        in YAML::Nodes::Mapping
          decode_mapping(node)
        in YAML::Nodes::Alias, YAML::Nodes::Document, YAML::Nodes::Node
          raise StorageError.new("Unsupported YAML node #{node.class} at line #{node.start_line + 1}")
        end
      end

      private def decode_mapping(node : YAML::Nodes::Mapping) : Document
        document = Document.new
        each_pair(node) { |key, value| document[key] = decode_node(value) }
        document
      end

      private def decode_scalar(node : YAML::Nodes::Scalar) : Type
        value = node.value

        case node.tag
        when BINARY_TAG
          return Base64.decode(value)
        when TIMESTAMP_TAG
          return Time::Format::RFC_3339.parse(value)
        when STRING_TAG
          return value
        end

        return value unless node.style.plain?

        if NULL_SCALARS.includes?(value)
          nil
        elsif TRUE_SCALARS.includes?(value)
          true
        elsif FALSE_SCALARS.includes?(value)
          false
        elsif value.matches?(INTEGER_PATTERN)
          decode_integer(value, node)
        else
          decode_float(value) || value
        end
      end

      private def decode_integer(value : String, node : YAML::Nodes::Scalar) : Int64 | UInt64
        value.to_i64? || value.to_u64? ||
          raise StorageError.new("Integer #{value} at line #{node.start_line + 1} does not fit in 64 bits")
      end

      private def decode_float(value : String) : Float64?
        case value
        when POSITIVE_INFINITY_SCALAR then Float64::INFINITY
        when NEGATIVE_INFINITY_SCALAR then -Float64::INFINITY
        when NAN_SCALAR               then Float64::NAN
        else                               value.to_f64?(whitespace: false)
        end
      end

      private def expect_mapping(node : YAML::Nodes::Node, what : String) : YAML::Nodes::Mapping
        node.as?(YAML::Nodes::Mapping) ||
          raise StorageError.new("Expected #{what} to be a YAML mapping at line #{node.start_line + 1}")
      end

      private def each_pair(node : YAML::Nodes::Mapping, & : String, YAML::Nodes::Node -> Nil) : Nil
        node.each do |key_node, value_node|
          key = key_node.as?(YAML::Nodes::Scalar) ||
                raise StorageError.new("Expected a scalar key at line #{key_node.start_line + 1}")
          yield key.value, value_node
        end
      end
    end
  end
end
