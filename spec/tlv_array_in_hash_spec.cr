require "./spec_helper"
require "tlv"

# Test how TLV::Writer encodes arrays inside hashes
describe "TLV Array Encoding in Hash" do
  it "encodes array as list-form when inside hash" do
    # Create hash with array value
    hash = {
      1_u8 => [0, 40, 9] of TLV::Value
    } of TLV::Tag => TLV::Value

    # Encode
    io = IO::Memory.new
    writer = TLV::Writer.new(io)
    writer.put(nil, hash)
    encoded = io.rewind.to_slice

    puts "\nEncoded hash with array:"
    puts "  Hex: #{encoded.hexstring}"

    # Decode
    reader = TLV::Reader.new(encoded)
    decoded = reader.get
    root = decoded.as(Hash(TLV::Tag, TLV::Value))["Any"].as(Hash(TLV::Tag, TLV::Value))

    puts "  Decoded tag 1 type: #{root[1_u8].class}"
    puts "  Decoded tag 1 value: #{root[1_u8].inspect}"

    # Check if it's an array
    if root[1_u8].is_a?(Array)
      puts "  ✅ Encoded as array (list-form)"
      arr = root[1_u8].as(Array(TLV::Value))
      arr.size.should eq(3)
      arr[0].should eq(0)
      arr[1].should eq(40)
      arr[2].should eq(9)
    else
      puts "  ❌ Encoded as structure (not list-form)"
      puts "  This is why matter.js can't parse our responses!"
    end
  end
end
