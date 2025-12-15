require "./spec_helper"
require "../src/matter/interaction_model/paths"
require "tlv"

# Test that AttributePath can encode to list-form for responses
describe "AttributePath List-Form Encoding" do
  it "encodes path as list-form using TLV::Serializable" do
    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: 40_u32,
      attribute: 9_u32
    )

    # When used in responses, path should encode as list format
    # (tagged fields but encoded as LIST structure type 0x17)
    encoded = path.to_slice

    # Decode to verify structure
    decoded = TLV::Any.from_slice(encoded)

    # Should be a list (array with tagged fields)
    decoded.value.should be_a(Array(TLV::Any))
    fields = decoded.value.as(Array(TLV::Any))

    # In list format, elements have context tags in their headers
    # Find elements by their context tag
    endpoint_elem = fields.find { |e| e.header.context.tag_id == 2 }
    cluster_elem = fields.find { |e| e.header.context.tag_id == 3 }
    attribute_elem = fields.find { |e| e.header.context.tag_id == 4 }

    endpoint_elem.should_not be_nil
    cluster_elem.should_not be_nil
    attribute_elem.should_not be_nil

    # Verify the path field values
    endpoint_elem.not_nil!.value.as(Int).should eq(0)
    cluster_elem.not_nil!.value.as(Int).should eq(40)
    attribute_elem.not_nil!.value.as(Int).should eq(9)
  end

  it "round-trips AttributePath through serialization" do
    original = Matter::InteractionModel::AttributePath.new(
      endpoint: 1_u16,
      cluster: 0x0028_u32,
      attribute: 0x0002_u32
    )

    # Encode and decode
    encoded = original.to_slice
    decoded = Matter::InteractionModel::AttributePath.from_slice(encoded)

    # Verify values preserved
    decoded.endpoint.should eq(1_u16)
    decoded.cluster.should eq(0x0028_u32)
    decoded.attribute.should eq(0x0002_u32)
  end
end
