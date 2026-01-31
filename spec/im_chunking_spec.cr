require "./spec_helper"
require "../src/matter/protocol/im_handler"
require "../src/matter/cluster/general_commissioning_cluster"
require "../src/matter/cluster/basic_information_cluster"
require "../src/matter/interaction_model/tlv_messages"

# Helper to create a cluster registry with test clusters
private def create_test_clusters : Hash(Tuple(UInt16, UInt32), Matter::Cluster::Base)
  clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base

  # GeneralCommissioning cluster (0x0030) on endpoint 0
  general_commissioning = Matter::Cluster::GeneralCommissioningCluster.new(
    Matter::DataType::EndpointNumber.new(0_u16)
  )
  general_commissioning.data_version = 0xd34496b8_u32
  clusters[{0_u16, 0x0030_u32}] = general_commissioning

  # BasicInformation cluster (0x0028) on endpoint 0
  basic_info = Matter::Cluster::BasicInformationCluster.new(
    endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
    vendor_id: 65521_u16,
    product_id: 32768_u16,
    vendor_name: "matter-node.js",
    product_name: "node-matter OnOff Light"
  )
  basic_info.data_version = 0xe2c160c8_u32
  clusters[{0_u16, 0x0028_u32}] = basic_info

  clusters
end

# Helper to decode chunk TLV and get the root structure
private def decode_chunk(chunk_bytes : Bytes) : TLV::Structure
  decoded = TLV::Any.from_slice(chunk_bytes)
  decoded.value.as(TLV::Structure)
end

# Helper to create an AttributeReportIB from path and value
private def create_attribute_report(endpoint : UInt16, cluster : UInt32, attribute : UInt32, data_version : UInt32, value : TLV::Any) : Matter::InteractionModel::AttributeReportIB
  path = Matter::InteractionModel::AttributePath.new(endpoint: endpoint, cluster: cluster, attribute: attribute)
  attr_data = Matter::InteractionModel::AttributeDataIB.new(path, value, data_version)
  Matter::InteractionModel::AttributeReportIB.new(attribute_data: attr_data)
end

describe "IMHandler - Message Chunking" do
  describe "encode_chunked_report_data" do
    it "returns a single chunk for small responses" do
      # Create a response with a few small attributes
      reports = [
        create_attribute_report(0_u16, 0x0030_u32, 0x0000_u32, 0x12345678_u32, TLV::Any.new(0_u8, nil)),
        create_attribute_report(0_u16, 0x0030_u32, 0x0001_u32, 0x12345678_u32, TLV::Any.new(1_u8, nil)),
      ]

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(reports, 12345_u32)

      # Should return a single chunk
      chunks.size.should eq 1

      # The single chunk should be marked as the last chunk
      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # The chunk should be smaller than the MTU limit
      chunk_bytes.size.should be < Matter::Protocol::IMHandler::MAX_REPORT_PAYLOAD_SIZE

      # Verify it's valid TLV
      root = decode_chunk(chunk_bytes)
      root[0_u8].value.as(Int).should eq 12345 # subscriptionId
      root[1_u8]?.should_not be_nil            # attributeReports should exist

      # Verify the hex contains both attribute IDs (encoded as UInt32 with fixed_size)
      hex = chunk_bytes.hexstring
      hex.should contain("2604000000") # attribute 0x0000 as UInt32
      hex.should contain("2604010000") # attribute 0x0001 as UInt32
    end

    it "chunks large responses into multiple messages" do
      # Create a response with many large attributes to exceed MTU
      reports = [] of Matter::InteractionModel::AttributeReportIB

      # Create enough large attributes to force chunking
      # Each attribute with ~100 bytes should force chunking around 10-11 attributes
      50.times do |i|
        # Create a largish value (100 bytes of TLV data)
        value = TLV::Any.new("A" * 90, nil)
        reports << create_attribute_report(0_u16, 0x0028_u32, i.to_u32, 0x12345678_u32, value)
      end

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(reports, 99999_u32)

      # Should have multiple chunks
      chunks.size.should be > 1

      puts "\nChunking test with 50 large attributes:"
      puts "  Total chunks: #{chunks.size}"

      # Verify each chunk
      total_reports = 0
      chunks.each_with_index do |(chunk_bytes, is_last), idx|
        puts "  Chunk #{idx + 1}: #{chunk_bytes.size} bytes, is_last=#{is_last}"

        # Each chunk should be under the MTU limit (allow some margin for single large items)
        chunk_bytes.size.should be < 1500 # Allow some margin above MAX_REPORT_PAYLOAD_SIZE

        # Verify it's valid TLV
        root = decode_chunk(chunk_bytes)

        # Should have subscriptionId
        root[0_u8].value.as(Int).should eq 99999

        # Should have attributeReports array
        reports_array = root[1_u8].value.as(Array(TLV::Any))
        total_reports += reports_array.size

        # Check moreChunkedMessages flag (tag 3 per Matter spec)
        if is_last
          # Last chunk should not have moreChunkedMessages set (or false)
          root[3_u8]?.should be_nil
        else
          # Non-last chunks must have moreChunkedMessages = true
          root[3_u8].value.should eq true
        end

        # Last chunk marker should match position
        is_last.should eq(idx == chunks.size - 1)
      end

      # All 50 reports should be included across all chunks
      total_reports.should eq 50
      puts "  Total reports across chunks: #{total_reports}"
    end

    it "sets more_chunks flag correctly for multi-chunk responses" do
      # Create enough attributes to force 2-3 chunks
      reports = [] of Matter::InteractionModel::AttributeReportIB

      30.times do |i|
        value = TLV::Any.new("B" * 80, nil)
        reports << create_attribute_report(0_u16, 0x0028_u32, i.to_u32, 0xABCD1234_u32, value)
      end

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(reports)

      chunks.size.should be >= 2

      # All chunks except the last should have more_chunks = true
      chunks[0...-1].each do |(chunk_bytes, is_last)|
        is_last.should be_false

        root = decode_chunk(chunk_bytes)
        root[3_u8].value.should eq true # moreChunkedMessages (tag 3 per Matter spec)
      end

      # Last chunk should have more_chunks = false (field omitted)
      last_chunk_bytes, is_last = chunks.last
      is_last.should be_true

      root = decode_chunk(last_chunk_bytes)
      root[3_u8]?.should be_nil # moreChunkedMessages not set (tag 3)
    end

    it "handles empty response" do
      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data([] of Matter::InteractionModel::AttributeReportIB, 1_u32)

      # Should return exactly one empty chunk
      chunks.size.should eq 1

      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # Verify it's valid TLV - empty attribute_reports is omitted (nil) per TLV encoding rules
      root = decode_chunk(chunk_bytes)
      root[0_u8].value.as(Int).should eq 1 # subscriptionId
      # When there are no reports, the attribute_reports field is omitted (set to nil)
      # So either tag 1 doesn't exist, or if it exists it's an empty array
      reports_entry = root[1_u8]?
      if reports_entry
        reports_array = reports_entry.value.as(Array(TLV::Any))
        reports_array.size.should eq 0
      end
    end

    it "works without subscription ID" do
      reports = [
        create_attribute_report(0_u16, 0x0030_u32, 0x0000_u32, 0x12345678_u32, TLV::Any.new(0_u8, nil)),
      ]

      # Pass nil for subscription_id
      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(reports, nil)

      chunks.size.should eq 1

      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # Verify no subscriptionId in output
      root = decode_chunk(chunk_bytes)
      root[0_u8]?.should be_nil     # No subscriptionId
      root[1_u8]?.should_not be_nil # attributeReports should exist
    end

    it "handles attribute status entries" do
      # Create a status report (error case)
      path = Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x9999_u32, attribute: 0x0000_u32)
      status_ib = Matter::InteractionModel::StatusIB.new(status: Matter::InteractionModel::StatusCode::NotFound.value)
      attr_status = Matter::InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
      status_report = Matter::InteractionModel::AttributeReportIB.new(attribute_status: attr_status)

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data([status_report])

      chunks.size.should eq 1

      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # Verify status is included in the reports array
      root = decode_chunk(chunk_bytes)
      reports_array = root[1_u8].value.as(Array(TLV::Any))
      reports_array.size.should eq 1
    end
  end

  describe "MAX_REPORT_PAYLOAD_SIZE constant" do
    it "is set to a value that fits within IPv6 MTU" do
      # IPv6 minimum MTU is 1280 bytes
      # Overhead: UDP (8) + IPv6 header (40) + Matter packet header (~12) +
      # Matter payload header (~13) + MAC tag (16) = ~89 bytes
      # So max TLV payload should be around 1191 bytes
      Matter::Protocol::IMHandler::MAX_REPORT_PAYLOAD_SIZE.should be <= 1191
      Matter::Protocol::IMHandler::MAX_REPORT_PAYLOAD_SIZE.should be >= 1000 # Should be reasonably large
    end
  end

  describe "integration with read_attributes" do
    it "chunks real cluster data that would exceed MTU" do
      clusters = create_test_clusters

      # Create wildcard request for all attributes on all clusters
      paths = [
        Matter::InteractionModel::AttributePath.new(
          endpoint: 0_u16,
          cluster: nil,  # All clusters
          attribute: nil # All attributes
        ),
      ]

      # Read all attributes
      response = Matter::Protocol::IMHandler.read_attributes(paths, clusters)

      puts "\nReal cluster wildcard read:"
      puts "  Total reports: #{response.size}"

      # Chunk the response
      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response, 1_u32)

      puts "  Chunks produced: #{chunks.size}"

      # Verify all chunks are valid
      total_items = 0
      chunks.each_with_index do |(chunk_bytes, is_last), idx|
        puts "  Chunk #{idx + 1}: #{chunk_bytes.size} bytes"

        root = decode_chunk(chunk_bytes)
        reports_array = root[1_u8].value.as(Array(TLV::Any))
        total_items += reports_array.size
      end

      # Total items = reports (array already contains both data and status reports)
      total_items.should eq response.size
    end
  end
end
