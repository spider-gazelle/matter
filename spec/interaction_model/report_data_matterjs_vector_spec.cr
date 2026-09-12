require "../spec_helper"

# Byte-level compatibility of ReportDataMessage with matter.js.
#
# Vector source: matter.js/packages/protocol/test/protocol/interaction/AttributeDataDecoderTest.ts
# ("decode number attribute" - data captured from a chip-tool lighting device).
#
# Decoded TLV: {1 => [{1 => {0 => 2020087125, 1 => [0, 40, 9], 2 => 1}}], 4 => true, 255 => 1}
#
#   15                         structure (ReportData)
#   36 01                      tag 1: attribute_reports (array)
#     15                       structure (AttributeReportIB)
#     35 01                    tag 1: attribute_data (AttributeDataIB)
#       26 00 55 15 68 78      tag 0: data_version = 0x78681555 = 2020087125 (uint32)
#       37 01                  tag 1: path (list)
#         24 02 00             endpoint 0     (uint8)
#         24 03 28             cluster 40     (uint8)
#         24 04 09             attribute 9    (uint8)
#       18
#       24 02 01               tag 2: data = 1 (uint8, matter.js "number attribute")
#     18 18 18
#   29 04                      tag 4: suppress_response = true (bool)
#   24 ff 01                   tag 255: interaction_model_revision = 1
#   18
MATTERJS_REPORT_DATA_VECTOR = "153601153501260055156878370124020024032824040918240201181818290424ff0118"
MATTERJS_DATA_VERSION       = 2020087125_u32

# The same message as this library encodes it. Identical to the matter.js vector
# except inside the AttributePath list, where our path fields carry their declared
# width instead of the minimal one; see the last example below.
#
#   37 01                      tag 1: path (list)
#     25 02 00 00              endpoint 0     (uint16)
#     26 03 28 00 00 00        cluster 40     (uint32)
#     26 04 09 00 00 00        attribute 9    (uint32)
#   18
OUR_REPORT_DATA_ENCODING = "15360115350126005515687837012502000026032800000026040900000018240201181818290424ff0118"

private def assert_matches_vector(report : Matter::InteractionModel::ReportDataMessage)
  report.subscription_id.should be_nil
  report.event_reports.should be_nil
  report.more_chunked_messages.should be_nil
  report.suppress_response.should be_true
  report.interaction_model_revision.should eq(1_u8)

  reports = report.attribute_reports.should_not be_nil
  reports.size.should eq(1)
  reports[0].attribute_status.should be_nil

  attr_data = reports[0].attribute_data.should_not be_nil
  attr_data.data_version.should eq(MATTERJS_DATA_VERSION)
  attr_data.path.endpoint.should eq(0_u16)
  attr_data.path.cluster.should eq(40_u32)
  attr_data.path.attribute.should eq(9_u32)
  attr_data.path.list_index.should be_nil
  attr_data.data.value.should eq(1_u8)
end

private def build_vector_report : Matter::InteractionModel::ReportDataMessage
  path = Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 40_u32, attribute: 9_u32)
  attr_data = Matter::InteractionModel::AttributeDataIB.new(
    path: path,
    data: TLV::Any.new(1_u8, nil),
    data_version: MATTERJS_DATA_VERSION
  )
  attr_report = Matter::InteractionModel::AttributeReportIB.new(attribute_data: attr_data)

  Matter::InteractionModel::ReportDataMessage.new(
    attribute_reports: [attr_report],
    suppress_response: true,
    interaction_model_revision: 1_u8
  )
end

describe Matter::InteractionModel::ReportDataMessage do
  describe "matter.js DataReport vector" do
    it "decodes the matter.js vector" do
      report = Matter::InteractionModel::ReportDataMessage.from_slice(MATTERJS_REPORT_DATA_VECTOR.hexbytes)
      assert_matches_vector(report)
    end

    it "round-trips the decoded vector through our encoder" do
      report = Matter::InteractionModel::ReportDataMessage.from_slice(MATTERJS_REPORT_DATA_VECTOR.hexbytes)
      encoded = report.to_slice

      assert_matches_vector(Matter::InteractionModel::ReportDataMessage.from_slice(encoded))
    end

    it "round-trips a hand-built message equivalent to the vector" do
      encoded = build_vector_report.to_slice

      assert_matches_vector(Matter::InteractionModel::ReportDataMessage.from_slice(encoded))
    end

    it "emits every element outside the path byte-for-byte as matter.js does" do
      # Everything except the AttributePath list is expected to match exactly:
      # data_version and subscription_id are fixed 4 bytes in both encoders, and
      # the trailing suppress_response / interaction_model_revision are minimal.
      expected = MATTERJS_REPORT_DATA_VECTOR.hexbytes
      encoded = build_vector_report.to_slice

      # Up to and including the "37 01" path list opener (index 0..13)
      encoded[0, 14].hexstring.should eq(expected[0, 14].hexstring)

      # From the path list terminator (0x18) onwards: data, closers, tag 4, tag 255
      tail = "18240201181818290424ff0118"
      encoded[encoded.size - tail.bytesize // 2, tail.bytesize // 2].hexstring.should eq(tail)
      expected[expected.size - tail.bytesize // 2, tail.bytesize // 2].hexstring.should eq(tail)
    end

    # Our encoding of the path list is deliberately not matter.js's, and this pins
    # the divergence rather than leaving it as an unmet goal.
    #
    # `AttributePath` declares endpoint/cluster/attribute with `fixed_size: true`
    # (src/matter/interaction_model/paths.cr) so each field always encodes at its
    # declared width (uint16/uint32/uint32), whereas matter.js and chip-tool emit the
    # minimal TLV integer width. That is required, not incidental: Apple Home rejects
    # structures whose integers are narrower than the spec's declared type (the same
    # note sits on `Descriptor::DeviceTypeStruct`, where a narrow device type produces
    # "Not Supported"), and those fields also have to hold the Bool wildcard marker
    # iOS sends in place of an omitted field, so a width cannot be inferred from the
    # runtime value.
    #
    #   matter.js: 24 02 00        24 03 28           24 04 09           (9 bytes)
    #   ours:      25 02 00 00     26 03 28 00 00 00  26 04 09 00 00 00  (16 bytes)
    #
    # giving a 43-byte encoding instead of 36; first differing byte is index 14
    # (0x25 vs 0x24). Both decode to the same values, which the examples above prove.
    it "encodes the vector with fixed-width path fields, diverging from matter.js" do
      build_vector_report.to_slice.hexstring.should eq(OUR_REPORT_DATA_ENCODING)

      # The divergence is confined to the AttributePath list: the 14 bytes up to the
      # "37 01" list opener and the 13 bytes from its terminator on are identical.
      OUR_REPORT_DATA_ENCODING.should_not eq(MATTERJS_REPORT_DATA_VECTOR)
      OUR_REPORT_DATA_ENCODING[0, 28].should eq(MATTERJS_REPORT_DATA_VECTOR[0, 28])
      OUR_REPORT_DATA_ENCODING[-26..].should eq(MATTERJS_REPORT_DATA_VECTOR[-26..])
    end
  end
end
