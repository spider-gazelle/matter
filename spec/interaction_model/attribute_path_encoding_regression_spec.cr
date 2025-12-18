require "../spec_helper"

describe "InteractionModel::AttributePath encoding" do
  it "encodes AttributePath as TLV list inside ReportData" do
    path = Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0x0000_u32)
    attr_data = Matter::InteractionModel::AttributeData.new(path: path, data_version: 11_u32, value: true.to_tlv)
    response = Matter::InteractionModel::ReadResponse.new(
      attribute_reports: [attr_data],
      attribute_status: [] of Matter::InteractionModel::AttributeStatus,
      suppress_response: false,
      more_chunks: false
    )

    report_bytes = Matter::Protocol::IMHandler.encode_report_data(response, 3_u32)

    root = TLV::Any.from_slice(report_bytes).value.as(TLV::Structure)
    reports = root[1_u8].not_nil!.value.as(TLV::List)
    report0 = reports[0].value.as(TLV::Structure)
    attribute_data = report0[1_u8].not_nil!.value.as(TLV::Structure)

    path_any = attribute_data[1_u8].not_nil!
    path_any.value.should be_a(TLV::List)
  end
end
