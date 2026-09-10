require "tlv"

module Matter
  module DataType
    # Declares an immutable value struct wrapping a single unsigned integer
    # identifier:
    #
    #     define_id AttributeId, UInt32
    #     define_id EndpointNumber, UInt16, number
    #
    # Instances compare and hash by value and print as fixed-width hex.
    #
    # On the wire an identifier is a bare unsigned integer (context-tagged by
    # the structure that carries it), never a structure. `TLV::Serializable`
    # can only emit structures/lists for the types that include it and its
    # generated `to_tlv` cannot be overridden, so the struct does not include
    # the module; it offers the same `to_tlv`/`from_tlv`/`to_slice`/`from_slice`
    # surface itself and registers type-specific `serialize_value` and
    # `deserialize_value` overloads so it can be used as a field of any
    # `TLV::Serializable` structure.
    macro define_id(name, type, field = id)
      {% hex = {"UInt8" => "u8", "UInt16" => "u16", "UInt32" => "u32", "UInt64" => "u64"}[type.stringify] %}
      {% raise "define_id: #{type} is not an unsigned integer type" unless hex %}

      struct {{ name }}
        getter {{ field.id }} : {{ type }}

        def initialize(@{{ field.id }} : {{ type }})
        end

        def_equals_and_hash {{ field.id }}

        def self.from_tlv(any : TLV::Any) : self
          new(TLV::Serializable.deserialize_value(any, {{ type }}))
        end

        def self.from_slice(bytes : Bytes) : self
          from_tlv(TLV::Any.from_slice(bytes))
        end

        def to_tlv(outer_tag : TLV::TagId? = nil) : TLV::Any
          TLV::Any.new(@{{ field.id }}, outer_tag)
        end

        def to_slice : Bytes
          to_tlv.to_slice
        end

        def to_s(io : IO) : Nil
          io << Hex.{{ hex.id }}(@{{ field.id }})
        end

        def inspect(io : IO) : Nil
          io << {{ name.stringify }} << '('
          to_s(io)
          io << ')'
        end
      end

      module ::TLV::Serializable
        def self.serialize_value(value : {{ @type }}::{{ name }}, tag, fixed_size : Bool = false) : TLV::Any
          value.to_tlv(tag)
        end

        def self.deserialize_value(any : TLV::Any, type : {{ @type }}::{{ name }}.class) : {{ @type }}::{{ name }}
          type.from_tlv(any)
        end
      end
    end
  end
end
