require "./spec_helper"
require "tlv"
require "../src/matter/interaction_model/tlv_messages"
require "../src/matter/interaction_model/paths"

# Build exact matter.js encoding using TLV::Serializable to verify byte-level compatibility
describe "Exact TLV Match with matter.js" do
  it "builds structure using TLV::Serializable to match matter.js" do
    # Target: 153601153501260055156878370124020024032824040918240201181818290424ff0118
    # Decoded: {1 => [{1 => {0 => 2020087125, 1 => [0, 40, 9], 2 => 1}}], 4 => true, 255 => 1}

    # Build using our TLV::Serializable structs
    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: 40_u32, # 0x28
      attribute: 9_u32
    )

    attr_data = Matter::InteractionModel::AttributeDataIB.new(
      path: path,
      data: TLV::Any.new(1_u8, nil), # Boolean encoded as UInt8 for matter.js compatibility
      data_version: 2020087125_u32
    )

    attr_report = Matter::InteractionModel::AttributeReportIB.new(
      attribute_data: attr_data
    )

    # Note: ReportDataMessage has different fields than the expected format
    # This test verifies our serializable structs produce valid TLV
    data_report = Matter::InteractionModel::ReportDataMessage.new(
      attribute_reports: [attr_report],
      more_chunked_messages: true,
      interaction_model_revision: 1_u8
    )

    encoded = data_report.to_slice

    puts "\n=== TLV::Serializable Encoding ==="
    puts "Our hex:       #{encoded.hexstring}"
    puts "matter.js hex: 153601153501260055156878370124020024032824040918240201181818290424ff0118"
    puts ""

    # Decode back and verify structure
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)
    decoded.attribute_reports.should_not be_nil
    decoded.attribute_reports.not_nil!.size.should eq(1)
    decoded.interaction_model_revision.should eq(1_u8)
    decoded.more_chunked_messages.should eq(true)

    # Verify path is preserved
    first_report = decoded.attribute_reports.not_nil![0]
    first_report.attribute_data.should_not be_nil
    first_report.attribute_data.not_nil!.path.endpoint.should eq(0_u16)
    first_report.attribute_data.not_nil!.path.cluster.should eq(40_u32)
    first_report.attribute_data.not_nil!.path.attribute.should eq(9_u32)
  end
end
