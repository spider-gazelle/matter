require "../spec_helper"
require "../../src/matter/protocol/im_handler"
require "../../src/matter/interaction_model/paths"
require "../../src/matter/interaction_model/tlv_messages"

# Test ReadResponse encoding with multiple attributes (reproducing chip-tool issue)
describe "ReadResponse Encoding" do
  it "encodes ReadResponse with multiple valid attributes" do
    # Create multiple attribute reports using TLV types directly
    reports = [] of Matter::InteractionModel::AttributeReportIB

    # Report 1: GeneralCommissioning.Breadcrumb (0x30.0x00)
    path1 = Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x30_u32, attribute: 0x00_u32)
    data1 = TLV::Any.new(0_u64, nil)
    attr_data1 = Matter::InteractionModel::AttributeDataIB.new(path1, data1, 0_u32)
    reports << Matter::InteractionModel::AttributeReportIB.new(attribute_data: attr_data1)

    # Report 2: BasicInformation.VendorID (0x28.0x02)
    path2 = Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x28_u32, attribute: 0x02_u32)
    data2 = TLV::Any.new(0xFFF1_u16, nil)
    attr_data2 = Matter::InteractionModel::AttributeDataIB.new(path2, data2, 0_u32)
    reports << Matter::InteractionModel::AttributeReportIB.new(attribute_data: attr_data2)

    # Encode using encode_report_data
    encoded = Matter::Protocol::IMHandler.encode_report_data(reports)

    # Should succeed
    encoded.size.should be > 0

    # Decode to verify structure using TLV::Serializable
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)

    # Should have attribute reports (tag 1)
    if attr_reports = decoded.attribute_reports
      attr_reports.size.should eq 2
    else
      fail "Expected attribute_reports to not be nil"
    end

    # Should have interactionModelRevision (tag 0xFF)
    decoded.interaction_model_revision.should eq(12_u8)
  end

  it "handles completely empty response" do
    # Encode empty array
    encoded = Matter::Protocol::IMHandler.encode_report_data([] of Matter::InteractionModel::AttributeReportIB)

    # Should still encode with just interactionModelRevision
    encoded.size.should be > 0

    # Decode to verify structure using TLV::Serializable
    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)

    # Should have interactionModelRevision
    decoded.interaction_model_revision.should eq(12_u8)
  end
end
