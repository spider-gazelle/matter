require "./spec_helper"
require "../src/matter/interaction_model/tlv_messages"

# Test ReportDataMessage encoding with list-form path
describe "ReportDataMessage Encoding" do
  it "preserves list-form path when encoding" do
    # Create attribute data with list-form path
    path_list = [0, 40, 9] of TLV::Value

    attr_data = {
      0_u8 => 12345678_u32, # dataVersion
      1_u8 => path_list,     # path as list
      2_u8 => true,          # data
    } of TLV::Tag => TLV::Value

    # Create ReportDataMessage
    report_msg = Matter::InteractionModel::ReportDataMessage.new
    report_msg.attribute_reports = [attr_data.as(TLV::Value)]
    report_msg.interaction_model_revision = 1_u8

    # Encode using to_slice
    encoded = report_msg.to_slice

    puts "\nEncoded ReportDataMessage:"
    puts "  Hex: #{encoded.hexstring}"

    # Decode
    reader = TLV::Reader.new(encoded)
    decoded = reader.get
    root = decoded.as(Hash(TLV::Tag, TLV::Value))["Any"].as(Hash(TLV::Tag, TLV::Value))

    # Get first attribute report
    reports = root[1_u8].as(Array(TLV::Value))
    report = reports[0].as(Hash(TLV::Tag, TLV::Value))

    # Check if path is still list-form
    path = report[1_u8]

    puts "  Path type: #{path.class}"
    puts "  Path value: #{path.inspect[0, 80]}"

    if path.is_a?(Array)
      puts "  ✅ Path preserved as list-form!"
      path.as(Array(TLV::Value)).should eq([0, 40, 9])
    else
      puts "  ❌ Path converted to structure!"
      fail "Path should be list-form array, got #{path.class}"
    end
  end
end
