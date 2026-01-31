require "../spec_helper"

describe "InteractionModel::AttributePath encoding" do
  it "encodes AttributePath as TLV list inside ReportData" do
    path = Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0x0000_u32)
    data = TLV::Any.from_slice(true.to_tlv)
    attr_data = Matter::InteractionModel::AttributeDataIB.new(path: path, data: data, data_version: 11_u32)
    attribute_report = Matter::InteractionModel::AttributeReportIB.new(attribute_data: attr_data)

    report_bytes = Matter::Protocol::IMHandler.encode_report_data([attribute_report], 3_u32)

    root = TLV::Any.from_slice(report_bytes).value.as(TLV::Structure)
    reports = root[1_u8].as(TLV::Any).value.as(TLV::List)
    report0 = reports[0].value.as(TLV::Structure)
    attribute_data = report0[1_u8].as(TLV::Any).value.as(TLV::Structure)

    path_any = attribute_data[1_u8].as(TLV::Any)
    path_any.value.should be_a(TLV::List)
  end
end
