require "./spec_helper"
require "tlv"

# Test how TLV encodes arrays inside hashes
describe "TLV Array Encoding in Hash" do
  it "encodes array as list-form when inside hash" do
    # Create array as TLV::List (Array(TLV::Any)) using as_array: true
    arr_values = [TLV::Any.new(0, nil), TLV::Any.new(40, nil), TLV::Any.new(9, nil)]
    arr = TLV::Any.new(arr_values, 1_u8, as_array: true)

    # Create hash containing the array (cast to proper TLV::Structure type)
    hash_data = {1_u8.as(TLV::TagId) => arr} of TLV::TagId => TLV::Any
    hash = TLV::Any.new(hash_data, nil)

    # Encode
    encoded = hash.to_slice

    puts "\nEncoded hash with array:"
    puts "  Hex: #{encoded.hexstring}"

    # Decode
    decoded = TLV::Any.from_slice(encoded)
    root = decoded.value.as(TLV::Structure)

    puts "  Decoded tag 1 type: #{root[1_u8].value.class}"
    puts "  Decoded tag 1 value: #{root[1_u8].value.inspect[0, 80]}"

    # Check if it's an array
    arr_value = root[1_u8].value
    arr_value.should be_a(Array(TLV::Any))

    arr_decoded = arr_value.as(Array(TLV::Any))
    arr_decoded.size.should eq(3)
    arr_decoded[0].value.as(Int).should eq(0)
    arr_decoded[1].value.as(Int).should eq(40)
    arr_decoded[2].value.as(Int).should eq(9)

    puts "  ✅ Encoded as array (list-form)"
  end
end
