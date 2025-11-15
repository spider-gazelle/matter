require "./spec_helper"
require "../src/matter/protocol/im_handler"
require "../src/matter/interaction_model/messages"
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

    # Encode value as TLV
    io = IO::Memory.new
    writer = TLV::Writer.new(io)
    writer.put(nil, 0xFFF1_u16)
    value_bytes = io.rewind.to_slice

    # Create AttributeData
    attr_data = Matter::InteractionModel::AttributeData.new(path, 0_u32, value_bytes)

    response = Matter::InteractionModel::ReadResponse.new(
      attribute_reports: [attr_data]
    )

    # Encode
    encoded = Matter::Protocol::IMHandler.encode_read_response(response)

    # Decode and verify structure matches matter.js TlvDataReportForSend
    reader = TLV::Reader.new(encoded)
    decoded = reader.get
    root = decoded.as(Hash(TLV::Tag, TLV::Value))["Any"].as(Hash(TLV::Tag, TLV::Value))

    # Verify structure
    # Tag 1: attributeReports (array)
    root.has_key?(1_u8).should be_true
    attr_reports = root[1_u8].as(Array(TLV::Value))
    attr_reports.size.should eq(1)

    # Each report should be AttributeDataIB: {0: dataVersion, 1: path, 2: data}
    report = attr_reports[0].as(Hash(TLV::Tag, TLV::Value))

    puts "Report structure: #{report.inspect[0, 100]}"

    # Per matter.js TlvAttributeReportData:
    # Tag 0: dataVersion (optional)
    # Tag 1: path
    # Tag 2: data

    # Verify all expected tags present
    report.has_key?(0_u8).should be_true # dataVersion
    report.has_key?(1_u8).should be_true # path
    report.has_key?(2_u8).should be_true # data

    # Verify dataVersion value
    report[0_u8].should eq(0_u32)

    # Verify path structure
    path_data = report[1_u8].as(Hash(TLV::Tag, TLV::Value))
    path_data[2_u8].should eq(0_u16)      # endpoint
    path_data[3_u8].should eq(0x0028_u32) # cluster
    path_data[4_u8].should eq(0x0002_u32) # attribute

    # Verify data value
    report[2_u8].should eq(0xFFF1_u16)

    # Tag 0xFF: interactionModelRevision
    root[0xFF_u8].should eq(12_u8)
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
    reader = TLV::Reader.new(encoded)
    decoded = reader.get
    root = decoded.as(Hash(TLV::Tag, TLV::Value))["Any"].as(Hash(TLV::Tag, TLV::Value))

    # Should have tag 0xFF
    root.has_key?(0xFF_u8).should be_true
    root[0xFF_u8].should eq(12_u8)

    # Should not have tag 1 (no attribute reports)
    root.has_key?(1_u8).should be_false
  end
end
