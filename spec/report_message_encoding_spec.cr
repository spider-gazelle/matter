require "./spec_helper"
require "../src/matter/interaction_model/tlv_messages"
require "../src/matter/interaction_model/paths"

# Test ReportDataMessage encoding with list-form path
describe "ReportDataMessage Encoding" do
  it "preserves list-form path when encoding" do
    # Create attribute data with proper TLV::Serializable structs
    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: 40_u32,
      attribute: 9_u32
    )

    attr_data = Matter::InteractionModel::AttributeDataIB.new(
      path: path,
      data: TLV::Any.new(true, nil),
      data_version: 12345678_u32
    )

    attr_report = Matter::InteractionModel::AttributeReportIB.new(
      attribute_data: attr_data
    )

    # Create ReportDataMessage
    report_msg = Matter::InteractionModel::ReportDataMessage.new
    report_msg.attribute_reports = [attr_report]
    report_msg.interaction_model_revision = 1_u8

    # Encode using to_slice
    encoded = report_msg.to_slice

    puts "\nEncoded ReportDataMessage:"
    puts "  Hex: #{encoded.hexstring}"

    # Decode and verify structure
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)

    # Get first attribute report
    decoded.attribute_reports.should_not be_nil
    reports = decoded.attribute_reports.not_nil!
    reports.size.should eq(1)

    report = reports[0]
    report.attribute_data.should_not be_nil
    attr_data_ib = report.attribute_data.not_nil!

    # Check path values preserved
    attr_data_ib.path.endpoint.should eq(0_u16)
    attr_data_ib.path.cluster.should eq(40_u32)
    attr_data_ib.path.attribute.should eq(9_u32)

    # Check data version preserved
    attr_data_ib.data_version.should eq(12345678_u32)

    # Check data preserved
    attr_data_ib.data.value.should eq(true)

    puts "  ✅ Path and data preserved correctly!"
  end
end
