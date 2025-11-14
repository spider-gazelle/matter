require "./spec_helper"
require "../src/matter/protocol/im_handler"
require "../src/matter/interaction_model/messages"
require "../src/matter/interaction_model/paths"

# Test ReadResponse encoding with multiple attributes (reproducing chip-tool issue)
describe "ReadResponse Encoding" do
  it "encodes ReadResponse with multiple valid attributes" do
    # Create multiple attribute reports like chip-tool would request
    reports = [] of Matter::InteractionModel::AttributeData

    # Report 1: GeneralCommissioning.Breadcrumb (0x30.0x00)
    path1 = Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x30_u32, attribute: 0x00_u32)
    io1 = IO::Memory.new
    writer1 = TLV::Writer.new(io1)
    writer1.put(nil, 0_u64) # Breadcrumb value
    reports << Matter::InteractionModel::AttributeData.new(path1, 0_u32, io1.rewind.to_slice)

    # Report 2: BasicInformation.VendorID (0x28.0x02)
    path2 = Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x28_u32, attribute: 0x02_u32)
    io2 = IO::Memory.new
    writer2 = TLV::Writer.new(io2)
    writer2.put(nil, 0xFFF1_u16)
    reports << Matter::InteractionModel::AttributeData.new(path2, 0_u32, io2.rewind.to_slice)

    # Report 3: Empty value (should be skipped with error handling)
    path3 = Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x30_u32, attribute: 0x01_u32)
    reports << Matter::InteractionModel::AttributeData.new(path3, 0_u32, Bytes.new(0))

    response = Matter::InteractionModel::ReadResponse.new(
      attribute_reports: reports
    )

    # Encode using TLV::Serializable
    encoded = Matter::Protocol::IMHandler.encode_read_response(response)

    # Should succeed despite empty value in report 3
    encoded.size.should be > 0

    # Decode to verify structure
    reader = TLV::Reader.new(encoded)
    data = reader.get

    # Should have root structure
    data.is_a?(Hash).should be_true
    root = data.as(Hash(TLV::Tag, TLV::Value))["Any"].as(Hash(TLV::Tag, TLV::Value))

    # Should have attribute reports (tag 1)
    root.has_key?(1_u8).should be_true

    # Should have interactionModelRevision (tag 0xFF)
    root.has_key?(0xFF_u8).should be_true
    root[0xFF_u8].should eq(12_u8)
  end

  it "handles completely empty response" do
    response = Matter::InteractionModel::ReadResponse.new(
      attribute_reports: [] of Matter::InteractionModel::AttributeData
    )

    encoded = Matter::Protocol::IMHandler.encode_read_response(response)

    # Should still encode with just interactionModelRevision
    encoded.size.should be > 0

    reader = TLV::Reader.new(encoded)
    data = reader.get
    root = data.as(Hash(TLV::Tag, TLV::Value))["Any"].as(Hash(TLV::Tag, TLV::Value))

    # Should have interactionModelRevision
    root[0xFF_u8].should eq(12_u8)
  end
end
