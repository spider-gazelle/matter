require "./spec_helper"
require "tlv"
require "../src/matter/interaction_model/tlv_messages"
require "../src/matter/interaction_model/paths"

# Port matter.js AttributeDataDecoderTest to verify byte-level compatibility
# Source: matter.js/packages/protocol/test/protocol/interaction/AttributeDataDecoderTest.ts
describe "AttributeDataDecoder matter.js Compatibility" do
  it "decodes DataReport from matter.js test vector" do
    # From AttributeDataDecoderTest.ts line 68
    # This is a complete TlvDataReport with one attribute
    tlv_hex = "153601153501260055156878370124020024032824040918240201181818290424ff0118"
    tlv_data = tlv_hex.hexbytes

    puts "\nDecoding matter.js DataReport test vector:"
    puts "  Hex: #{tlv_hex}"
    puts "  Size: #{tlv_data.size} bytes"
    puts ""

    # Decode using TLV::Serializable struct
    report = Matter::InteractionModel::ReportDataMessage.from_slice(tlv_data)

    # Verify structure
    report.attribute_reports.should_not be_nil
    attr_reports = report.attribute_reports.as(Array(Matter::InteractionModel::AttributeReportIB))
    attr_reports.size.should eq(1)

    # First report should have attribute_data
    first_report = attr_reports[0]
    first_report.attribute_data.should_not be_nil
    attr_data = first_report.attribute_data.as(Matter::InteractionModel::AttributeDataIB)

    # Verify dataVersion
    attr_data.data_version.should eq(2020087125_u32) # 0x78681555 in little-endian

    # Verify path
    path = attr_data.path
    path.endpoint.should eq(0_u16)
    path.cluster.should eq(0x28_u32)
    path.attribute.should eq(9_u32)

    # Verify data value
    attr_data.data.value.as(Int).should eq(1) # Boolean as uint8

    # Verify interaction model revision
    report.interaction_model_revision.should eq(1_u8)

    puts "  Successfully decoded matter.js test vector!"
    puts "  Structure matches expected:"
    puts "    - 1 attribute report"
    puts "    - endpoint=0, cluster=0x28, attribute=9"
    puts "    - value=true (boolean)"
    puts "    - dataVersion=2020087125"
    puts "    - interactionModelRevision=1"
  end

  it "can encode and decode round-trip using TLV::Serializable" do
    # Create a DataReport matching the matter.js test vector structure
    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: 0x28_u32,
      attribute: 9_u32
    )

    attr_data = Matter::InteractionModel::AttributeDataIB.new(
      path: path,
      data: TLV::Any.new(1_u8, nil), # Boolean as uint8 for matter.js compatibility
      data_version: 2020087125_u32
    )

    attr_report = Matter::InteractionModel::AttributeReportIB.new(
      attribute_data: attr_data
    )

    data_report = Matter::InteractionModel::ReportDataMessage.new(
      attribute_reports: [attr_report],
      interaction_model_revision: 1_u8 # Match matter.js test vector
    )

    # Encode
    encoded = data_report.to_slice

    puts "\nEncoded hex: #{encoded.hexstring}"
    # With fixed_size: true, paths are encoded at full width (uint16 for endpoint, uint32 for cluster/attribute)
    puts "Encoded length: #{encoded.size} bytes"

    # Decode back and verify
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)
    decoded.attribute_reports.should_not be_nil
    decoded.attribute_reports.as(Array(Matter::InteractionModel::AttributeReportIB)).size.should eq(1)
    decoded.interaction_model_revision.should eq(1_u8)

    # Verify the path values are correct after round-trip
    report = decoded.attribute_reports.as(Array(Matter::InteractionModel::AttributeReportIB)).first
    report.attribute_data.should_not be_nil
    path = report.attribute_data.as(Matter::InteractionModel::AttributeDataIB).path
    path.endpoint.should eq(0_u16)
    path.cluster.should eq(0x28_u32)
    path.attribute.should eq(9_u32)
  end
end
