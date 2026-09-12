require "../spec_helper"

# Tag numbers from Matter Core 10.6.9 (EventDataIB), 10.6.10 (EventReportIB),
# 10.6.15 (EventStatusIB) and 10.6.6 (EventFilterIB), cross-checked against
# matter.js `TlvEventData`, `TlvEventReport`, `TlvEventStatus`, `TlvEventFilter`.
private TAG_EVENT_STATUS = 0_u8
private TAG_EVENT_DATA   = 1_u8

private TAG_DATA_PATH             = 0_u8
private TAG_DATA_EVENT_NUMBER     = 1_u8
private TAG_DATA_PRIORITY         = 2_u8
private TAG_DATA_EPOCH_TIMESTAMP  = 3_u8
private TAG_DATA_SYSTEM_TIMESTAMP = 4_u8
private TAG_DATA_PAYLOAD          = 7_u8

private TAG_STATUS_PATH   = 0_u8
private TAG_STATUS_STATUS = 1_u8

private TAG_FILTER_NODE      = 0_u8
private TAG_FILTER_EVENT_MIN = 1_u8

private TAG_REPORT_EVENT_REPORTS = 2_u8

private def structure(bytes : Bytes) : Hash(UInt8, TLV::Any)
  fields = {} of UInt8 => TLV::Any
  TLV::Any.from_slice(bytes).as_structure.each do |tag, value|
    fields[tag.as(Int).to_u8] = value
  end
  fields
end

private def event_data : Matter::InteractionModel::EventDataIB
  Matter::InteractionModel::EventDataIB.new(
    path: Matter::InteractionModel::EventPath.new(endpoint: 1_u16, cluster: 0x0101_u32, event: 0x02_u32),
    event_number: 9_u64,
    priority: Matter::InteractionModel::EventPriority::Critical,
    data: TLV::Any.new(42_u32, nil),
    epoch_timestamp: 1_700_000_000_000_u64
  )
end

describe Matter::InteractionModel::EventDataIB do
  it "encodes each field at its spec tag" do
    fields = structure(event_data.to_slice)

    fields.keys.sort!.should eq([TAG_DATA_PATH, TAG_DATA_EVENT_NUMBER, TAG_DATA_PRIORITY, TAG_DATA_EPOCH_TIMESTAMP, TAG_DATA_PAYLOAD])
    fields[TAG_DATA_EVENT_NUMBER].as_u64.should eq(9_u64)
    fields[TAG_DATA_PRIORITY].as_u64.should eq(Matter::InteractionModel::EventPriority::Critical.value)
    fields[TAG_DATA_EPOCH_TIMESTAMP].as_u64.should eq(1_700_000_000_000_u64)
    fields[TAG_DATA_PAYLOAD].as_u64.should eq(42_u64)
    fields.has_key?(TAG_DATA_SYSTEM_TIMESTAMP).should be_false
  end

  it "round trips" do
    decoded = Matter::InteractionModel::EventDataIB.from_slice(event_data.to_slice)

    decoded.event_number.should eq(9_u64)
    decoded.priority.critical?.should be_true
    decoded.path.endpoint.should eq(1_u16)
    decoded.path.cluster.should eq(0x0101_u32)
    decoded.path.event.should eq(0x02_u32)
    decoded.data.as(TLV::Any).as_u64.should eq(42_u64)
  end

  it "omits isUrgent from the reported path, as matter.js does" do
    # EventPathIB tags 0..3 are node/endpoint/cluster/event; tag 4 (isUrgent)
    # is optional and a report never asks for urgency.
    path = Matter::InteractionModel::EventDataIB.from_slice(event_data.to_slice).path

    path.is_urgent_raw.should be_nil
    path.is_urgent?.should be_false
  end
end

describe Matter::InteractionModel::EventStatusIB do
  it "encodes path and status at tags 0 and 1" do
    status = Matter::InteractionModel::EventStatusIB.new(
      path: Matter::InteractionModel::EventPath.new(endpoint: 1_u16, cluster: 6_u32, event: 0_u32),
      status: Matter::InteractionModel::StatusIB.new(status: Matter::InteractionModel::StatusCode::UnsupportedEvent.value)
    )

    fields = structure(status.to_slice)
    fields.keys.sort!.should eq([TAG_STATUS_PATH, TAG_STATUS_STATUS])

    decoded = Matter::InteractionModel::EventStatusIB.from_slice(status.to_slice)
    decoded.status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedEvent.value)
  end
end

describe Matter::InteractionModel::EventReportIB do
  it "carries event data at tag 1 and nothing else" do
    fields = structure(Matter::InteractionModel::EventReportIB.new(event_data: event_data).to_slice)

    fields.keys.should eq([TAG_EVENT_DATA])
  end

  it "carries an event status at tag 0" do
    report = Matter::InteractionModel::EventReportIB.new(
      event_status: Matter::InteractionModel::EventStatusIB.new(
        path: Matter::InteractionModel::EventPath.new(endpoint: 1_u16, cluster: 6_u32, event: 0_u32),
        status: Matter::InteractionModel::StatusIB.new(status: Matter::InteractionModel::StatusCode::UnsupportedCluster.value)
      )
    )

    structure(report.to_slice).keys.should eq([TAG_EVENT_STATUS])
  end
end

describe Matter::InteractionModel::EventFilterIB do
  it "encodes the optional node at tag 0 and the minimum at tag 1" do
    structure(Matter::InteractionModel::EventFilterIB.new(event_min: 5_u64).to_slice).keys.should eq([TAG_FILTER_EVENT_MIN])

    fields = structure(Matter::InteractionModel::EventFilterIB.new(event_min: 5_u64, node: 7_u64).to_slice)
    fields.keys.sort!.should eq([TAG_FILTER_NODE, TAG_FILTER_EVENT_MIN])
    fields[TAG_FILTER_EVENT_MIN].as_u64.should eq(5_u64)
  end
end

describe Matter::InteractionModel::ReportDataMessage do
  it "carries typed event reports at tag 2" do
    message = Matter::InteractionModel::ReportDataMessage.new(
      event_reports: [Matter::InteractionModel::EventReportIB.new(event_data: event_data)]
    )

    structure(message.to_slice).has_key?(TAG_REPORT_EVENT_REPORTS).should be_true

    decoded = Matter::InteractionModel::ReportDataMessage.from_slice(message.to_slice)
    reports = decoded.event_reports.as(Array(Matter::InteractionModel::EventReportIB))
    reports.size.should eq(1)
    reports.first.event_data.as(Matter::InteractionModel::EventDataIB).event_number.should eq(9_u64)
  end
end
