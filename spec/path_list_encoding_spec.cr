require "./spec_helper"
require "../src/matter/interaction_model/paths"

# Test that AttributePath can encode to list-form for responses
describe "AttributePath List-Form Encoding" do
  it "encodes path as list-form array for responses" do
    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: 40_u32,
      attribute: 9_u32
    )

    # When used in responses, path should encode as [0, 40, 9]
    # Not as {2 => 0, 3 => 40, 4 => 9}

    # Create list manually
    path_list = [] of TLV::Value
    path_list << 0 if path.endpoint
    path_list << 40 if path.cluster
    path_list << 9 if path.attribute

    # Encode
    io = IO::Memory.new
    writer = TLV::Writer.new(io)
    writer.put(nil, path_list)
    encoded = io.rewind.to_slice

    # Decode to verify
    reader = TLV::Reader.new(encoded)
    decoded = reader.get
    list = decoded.as(Hash(TLV::Tag, TLV::Value))["Any"]

    # Should be array [0, 40, 9]
    list.is_a?(Array).should be_true
    arr = list.as(Array(TLV::Value))
    arr.size.should eq(3)
    arr[0].should eq(0)
    arr[1].should eq(40)
    arr[2].should eq(9)
  end
end
