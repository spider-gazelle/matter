require "./spec_helper"
require "tlv"

# Reproduce exact matter.js vector manually
describe "Exact matter.js Vector Reproduction" do
  it "manually encodes to match matter.js exactly" do
    # From matter.js test: endpoint=0, cluster=0x28, attribute=9, value=true, dataVersion=926954325

    # Build path as list [0, 40, 9]
    path_list = [0_u16, 40_u32, 9_u32] of TLV::Value

    # Build AttributeDataIB
    attr_data_ib = {
      0_u8 => 926954325_u32, # dataVersion
      1_u8 => path_list,     # path
      2_u8 => true,          # data
    } of TLV::Tag => TLV::Value

    # Wrap in AttributeReportIB
    attr_report_ib = {
      1_u8 => attr_data_ib,
    } of TLV::Tag => TLV::Value

    # Build DataReport
    data_report = {
         1_u8 => [attr_report_ib] of TLV::Value, # attributeReports
      0xFF_u8 => 1_u8,                           # interactionModelRevision
    } of TLV::Tag => TLV::Value

    # Encode
    io = IO::Memory.new
    writer = TLV::Writer.new(io)
    writer.put(nil, data_report)
    encoded = io.rewind.to_slice

    puts "\nOur encoding:"
    puts "  Hex: #{encoded.hexstring}"
    puts "  Size: #{encoded.size} bytes"
    puts ""
    puts "matter.js expected:"
    puts "  Hex: 153601153501260055156878370124020024032824040918240201181818290424ff0118"
    puts "  Size: 36 bytes"
    puts ""

    # Should match matter.js
    expected = "153601153501260055156878370124020024032824040918240201181818290424ff0118"
    if encoded.hexstring == expected
      puts "  ✅ EXACT MATCH!"
    else
      puts "  ❌ Mismatch - differences:"
      expected_bytes = expected.hexbytes
      encoded.size.times do |i|
        if encoded[i] != expected_bytes[i]?
          puts "    Position #{i}: got=0x#{encoded[i].to_s(16).rjust(2, '0')}, expected=0x#{expected_bytes[i].to_s(16).rjust(2, '0')}"
        end
      end
    end
  end
end
