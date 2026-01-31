require "./spec_helper"
require "../src/matter/protocol/im_handler"
require "../src/matter/interaction_model/paths"
require "../src/matter/interaction_model/tlv_messages"

# Test ReadResponse encoding against matter.js expectations
describe "ReadResponse matter.js Compatibility" do
  it "encodes attribute data matching matter.js AttributeReportData format" do
    # Create a simple attribute: VendorID=0xFFF1
    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: 0x0028_u32,  # BasicInformation
      attribute: 0x0002_u32 # VendorID
    )

    # Encode value as TLV::Any
    data = TLV::Any.new(0xFFF1_u16, nil)

    # Create AttributeDataIB
    attr_data = Matter::InteractionModel::AttributeDataIB.new(path, data, 0_u32)
    attribute_report = Matter::InteractionModel::AttributeReportIB.new(attribute_data: attr_data)

    # Encode
    encoded = Matter::Protocol::IMHandler.encode_report_data([attribute_report])

    # Decode and verify structure matches matter.js TlvDataReportForSend
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)

    # Verify structure
    # Tag 1: attributeReports (array)
    decoded.attribute_reports.should_not be_nil
    attr_reports = decoded.attribute_reports.as(Array(Matter::InteractionModel::AttributeReportIB))
    attr_reports.size.should eq(1)

    # Each report is AttributeReport: {1: AttributeData}
    report = attr_reports[0]

    # AttributeReport contains AttributeData at tag 1
    report.attribute_data.should_not be_nil
    attr_data_ib = report.attribute_data.as(Matter::InteractionModel::AttributeDataIB)

    puts "AttributeDataIB: path=#{attr_data_ib.path.inspect[0, 100]}"

    # Per matter.js TlvAttributeData:
    # Tag 0: dataVersion (optional)
    # Tag 1: path
    # Tag 2: data

    # Verify dataVersion value
    attr_data_ib.data_version.should eq(0_u32)

    # Verify path structure
    attr_data_ib.path.endpoint.should eq(0_u16)
    attr_data_ib.path.cluster.should eq(0x0028_u32)
    attr_data_ib.path.attribute.should eq(0x0002_u32)

    # Verify data value
    attr_data_ib.data.value.as(Int).should eq(0xFFF1)

    # Tag 0xFF: interactionModelRevision
    decoded.interaction_model_revision.should eq(12_u8)
  end

  it "matches matter.js TlvDataReportForSend schema exactly" do
    # Per matter.js packages/types/src/protocol/messages/TlvDataReportForSend.ts:
    # TlvDataReportForSend = TlvObject({
    #   subscriptionId: TlvOptionalField(0, TlvUInt32),
    #   attributeReports: TlvOptionalField(1, TlvArray(TlvAny)),
    #   eventReports: TlvOptionalField(2, TlvArray(TlvAny)),
    #   moreChunkedMessages: TlvOptionalField(3, TlvBoolean),
    #   suppressResponse: TlvOptionalField(4, TlvBoolean),
    #   interactionModelRevision: TlvField(0xff, TlvUInt8),
    # });

    # Our ReportDataMessage should match this exactly
    report_msg = Matter::InteractionModel::ReportDataMessage.new
    report_msg.interaction_model_revision = 12_u8

    encoded = report_msg.to_slice

    # Should encode to just interactionModelRevision when no reports
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)

    # Should have tag 0xFF
    decoded.interaction_model_revision.should eq(12_u8)

    # Should not have attribute reports (nil)
    decoded.attribute_reports.should be_nil
  end
end
