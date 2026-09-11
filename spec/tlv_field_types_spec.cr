require "./spec_helper"

# A structural guard over every `TLV::Serializable` field in the library.
#
# The door-lock bug was a payload declaring a field with a datatype wrapper the
# TLV shard cannot put on the wire, which turned every lock command into a
# `Failure` against a real controller. Nothing caught it, because a field type
# the shard does not know about is only a problem at the moment a message is
# actually encoded or decoded - and an event that no spec exercises end to end
# never reaches that moment.
#
# So walk the declarations instead of the traffic: every includer of
# `TLV::Serializable`, every instance variable carrying a `TLV::Field`
# annotation, flattened through nilable unions, `Array(...)` and tuples, and
# assert that nothing is left over.
#
# The two directions are checked separately, because the decode side is the
# stricter of the two - see `DECODABLE_UNION_MEMBERS`.
module TLVFieldTypes
  # The union members `TLV::Serializable.deserialize_value` knows how to produce
  # when its target type is a union (`lib/tlv/src/tlv/serializable.cr`, the
  # `T.union?` branch). That branch enumerates a closed set and falls through to
  # `raise "Cannot deserialize TLV element type ..."` with no `else`, so this
  # list cannot be discovered from the shard the way the encode set can.
  #
  # Enums, `Array(...)` and non-`@[TLV::ListFormat]` `TLV::Serializable` structs
  # are handled by that branch too, and are allowed below in addition to these.
  #
  # The asymmetry that matters: a type registered externally through the
  # `define_id` macro (`src/matter/datatype/id.cr`) installs its own
  # `serialize_value`/`deserialize_value` overloads, so `NodeId` encodes AND
  # decodes, but `NodeId?` is a union - it encodes fine and then raises on
  # `from_slice`, because the union branch never reaches the overload.
  DECODABLE_UNION_MEMBERS = %w[
    Nil Bool String Slice(UInt8)
    Int8 Int16 Int32 Int64
    UInt8 UInt16 UInt32 UInt64
    Float32 Float64
    TLV::Any
  ]

  # Fields whose type the encoder cannot serialize.
  #
  # The supported set is read out of the shard at macro time rather than
  # hand-maintained: every `TLV::Serializable.serialize_value` overload, which
  # includes the ones `define_id` registers from this library.
  def self.encode_violations : Array(String)
    violations = [] of String

    # One `{% begin %}` for the whole walk: macro variables do not survive
    # across sibling `{% %}` blocks in a method body.
    {% begin %}
      {%
        encodable = ::TLV::Serializable.class.methods
          .select { |method| method.name.stringify == "serialize_value" }
          .map(&.args.[0].restriction.resolve?)
          .reject(&.==(nil))
      %}
      {% for struct_type in ::TLV::Serializable.includers %}
        {% for ivar in struct_type.instance_vars %}
          {% if ivar.annotation(::TLV::Field) %}
            # Flatten the declaration to the scalar types actually handed to the
            # encoder: union members, then one level of Array/Tuple element type,
            # then that element type's own union members or element types.
            {% leaves = [] of Nil %}
            {% members = ivar.type.union? ? ivar.type.union_types : [ivar.type] %}
            {% for member in members %}
              {% if member.name.starts_with?("Array(") || member.name.starts_with?("Tuple(") %}
                {% for element in member.type_vars %}
                  {% if element.union? %}
                    {% for inner in element.union_types %}{% leaves << inner %}{% end %}
                  {% elsif element.name.starts_with?("Array(") || element.name.starts_with?("Tuple(") %}
                    {% for inner in element.type_vars %}{% leaves << inner %}{% end %}
                  {% else %}
                    {% leaves << element %}
                  {% end %}
                {% end %}
              {% else %}
                {% leaves << member %}
              {% end %}
            {% end %}

            {% for leaf in leaves %}
              {% unless encodable.includes?(leaf) || leaf < Enum || leaf < ::TLV::Serializable %}
                violations << {{ "#{struct_type.name}##{ivar.name} : #{ivar.type} - no TLV::Serializable.serialize_value overload for #{leaf.name}" }}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}

    violations
  end

  # Union-typed fields the decoder cannot reconstruct. Narrower than the encode
  # set: a non-union field dispatches to a registered `deserialize_value`
  # overload, a union member has to be one the shard's union branch enumerates.
  def self.decode_violations : Array(String)
    violations = [] of String

    {% begin %}
      {% for struct_type in ::TLV::Serializable.includers %}
        {% for ivar in struct_type.instance_vars %}
          {% if ivar.annotation(::TLV::Field) && ivar.type.union? %}
            {% for member in ivar.type.union_types %}
              {% unless DECODABLE_UNION_MEMBERS.includes?(member.name.stringify) ||
                          member < Enum ||
                          member.name.starts_with?("Array(") ||
                          (member < ::TLV::Serializable && !member.annotation(::TLV::ListFormat)) %}
                violations << {{ "#{struct_type.name}##{ivar.name} : #{ivar.type} - union member #{member.name} is not decodable inside a union" }}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}

    violations
  end
end

describe "TLV::Serializable field types" do
  it "declares no field the encoder cannot serialize" do
    TLVFieldTypes.encode_violations.should be_empty
  end

  it "declares no union member the decoder cannot deserialize" do
    TLVFieldTypes.decode_violations.should be_empty
  end
end
