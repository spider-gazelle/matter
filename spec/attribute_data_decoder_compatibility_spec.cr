require "./spec_helper"
require "tlv"

# Port matter.js AttributeDataDecoderTest to verify byte-level compatibility
# Source: matter.js/packages/protocol/test/protocol/interaction/AttributeDataDecoderTest.ts
describe "AttributeDataDecoder matter.js Compatibility" do
  it "decodes DataReport from matter.js test vector" do
    # From AttributeDataDecoderTest.ts line 68
    # This is a complete TlvDataReport with one attribute
    tlv_hex = "153601153501260055156878370124020024032824040918240201181818290424ff0118"
    tlv_data = tlv_hex.hexbytes

    puts "\n🔍 Decoding matter.js DataReport test vector:"
    puts "  Hex: #{tlv_hex}"
    puts "  Size: #{tlv_data.size} bytes"
    puts ""

    # Decode
    reader = TLV::Reader.new(tlv_data)
    decoded = reader.get
    root = decoded.as(Hash(TLV::Tag, TLV::Value))["Any"].as(Hash(TLV::Tag, TLV::Value))

    # Verify structure
    # Tag 1: attributeReports (array)
    root.has_key?(1_u8).should be_true
    attr_reports = root[1_u8].as(Array(TLV::Value))
    attr_reports.size.should eq(1)

    # First report
    report = attr_reports[0].as(Hash(TLV::Tag, TLV::Value))

    # Tag 0: dataVersion
    report.has_key?(0_u8).should be_true
    report[0_u8].should eq(926954325_u32) # 0x37786855 in little-endian

    # Tag 1: path
    report.has_key?(1_u8).should be_true
    path = report[1_u8].as(Hash(TLV::Tag, TLV::Value))
    path[2_u8].should eq(0_u16)      # endpoint
    path[3_u8].should eq(0x28_u32)   # cluster
    path[4_u8].should eq(9_u32)      # attribute

    # Tag 2: data (the actual value)
    report.has_key?(2_u8).should be_true
    report[2_u8].should eq(true) # Boolean value

    # Tag 0xFF: interactionModelRevision
    root.has_key?(0xFF_u8).should be_true
    root[0xFF_u8].should eq(1_u8)

    puts "  ✅ Successfully decoded matter.js test vector!"
    puts "  Structure matches expected:"
    puts "    - 1 attribute report"
    puts "    - endpoint=0, cluster=0x28, attribute=9"
    puts "    - value=true (boolean)"
    puts "    - dataVersion=926954325"
    puts "    - interactionModelRevision=1"
  end

  it "can encode and decode round-trip matching matter.js structure" do
    # Create a simple attribute response like matter.js
    # We should be able to encode it and get the same structure back

    # Create AttributeDataIB as plain hash (no TLV::Serializable wrapper)
    path_hash = {
      2_u8 => 0_u16,      # endpoint
      3_u8 => 0x28_u32,   # cluster
      4_u8 => 9_u32,      # attribute
    } of TLV::Tag => TLV::Value

    attr_data = {
      0_u8 => 926954325_u32, # dataVersion
      1_u8 => path_hash,       # path
      2_u8 => true,            # data (boolean value)
    } of TLV::Tag => TLV::Value

    # Create DataReport
    data_report = {
      1_u8 => [attr_data] of TLV::Value, # attributeReports
      0xFF_u8 => 1_u8,                     # interactionModelRevision
    } of TLV::Tag => TLV::Value

    # Encode
    io = IO::Memory.new
    writer = TLV::Writer.new(io)
    writer.put(nil, data_report)
    encoded = io.rewind.to_slice

    # Should match matter.js vector
    encoded.hexstring.should eq("153601153501260055156878370124020024032824040918240201181818290424ff0118")
  end
end
