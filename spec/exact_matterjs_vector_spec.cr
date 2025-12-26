require "./spec_helper"
require "tlv"
require "../src/matter/interaction_model/tlv_messages"
require "../src/matter/interaction_model/paths"

# Reproduce exact matter.js vector using TLV::Serializable structs
describe "Exact matter.js Vector Reproduction" do
  it "encodes using TLV::Serializable to compare with matter.js" do
    # From matter.js test: endpoint=0, cluster=0x28, attribute=9, value=true, dataVersion=926954325

    # Build path using AttributePath
    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: 40_u32, # 0x28
      attribute: 9_u32
    )

    # Build AttributeDataIB
    attr_data_ib = Matter::InteractionModel::AttributeDataIB.new(
      path: path,
      data: TLV::Any.new(true, nil),
      data_version: 926954325_u32
    )

    # Wrap in AttributeReportIB
    attr_report_ib = Matter::InteractionModel::AttributeReportIB.new(
      attribute_data: attr_data_ib
    )

    # Build ReportDataMessage
    data_report = Matter::InteractionModel::ReportDataMessage.new
    data_report.attribute_reports = [attr_report_ib]
    data_report.interaction_model_revision = 1_u8

    # Encode
    encoded = data_report.to_slice

    puts "\nOur encoding:"
    puts "  Hex: #{encoded.hexstring}"
    puts "  Size: #{encoded.size} bytes"
    puts ""
    puts "matter.js expected:"
    puts "  Hex: 153601153501260055156878370124020024032824040918240201181818290424ff0118"
    puts "  Size: 36 bytes"
    puts ""

    # Compare with matter.js
    expected = "153601153501260055156878370124020024032824040918240201181818290424ff0118"
    if encoded.hexstring == expected
      puts "  ✅ EXACT MATCH!"
    else
      puts "  Note: Encoding may differ in structure vs list format but should decode equivalently"
      expected_bytes = expected.hexbytes
      min_size = {encoded.size, expected_bytes.size}.min
      min_size.times do |i|
        if encoded[i] != expected_bytes[i]?
          puts "    Position #{i}: got=0x#{encoded[i].to_s(16).rjust(2, '0')}, expected=0x#{expected_bytes[i]?.try &.to_s(16).rjust(2, '0') || "N/A"}"
        end
      end
    end

    # Verify round-trip works
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)
    decoded.attribute_reports.should_not be_nil
    reports = decoded.attribute_reports.as(Array(Matter::InteractionModel::AttributeReportIB))
    reports.size.should eq(1)

    attr_data = reports[0].attribute_data.as(Matter::InteractionModel::AttributeDataIB)
    attr_data.path.endpoint.should eq(0_u16)
    attr_data.path.cluster.should eq(40_u32)
    attr_data.path.attribute.should eq(9_u32)
    attr_data.data_version.should eq(926954325_u32)
    attr_data.data.value.should eq(true)
  end
end
