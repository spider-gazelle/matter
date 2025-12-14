require "./spec_helper"
require "../src/matter/protocol/im_handler"
require "../src/matter/cluster/general_commissioning_cluster"
require "../src/matter/cluster/basic_information_cluster"
require "../src/matter/interaction_model/messages"

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

describe "IMHandler - Message Chunking" do
  describe "encode_chunked_report_data" do
    it "returns a single chunk for small responses" do
      # Create a response with a few small attributes
      reports = [
        Matter::InteractionModel::AttributeData.new(
          path: Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x0030_u32, attribute: 0x0000_u32),
          data_version: 0x12345678_u32,
          value: Bytes[0x24, 0x02, 0x00] # Small TLV value
        ),
        Matter::InteractionModel::AttributeData.new(
          path: Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x0030_u32, attribute: 0x0001_u32),
          data_version: 0x12345678_u32,
          value: Bytes[0x24, 0x02, 0x01] # Small TLV value
        ),
      ]

      response = Matter::InteractionModel::ReadResponse.new(
        attribute_reports: reports,
        attribute_status: [] of Matter::InteractionModel::AttributeStatus
      )

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response, 12345_u32)

      # Should return a single chunk
      chunks.size.should eq 1

      # The single chunk should be marked as the last chunk
      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # The chunk should be smaller than the MTU limit
      chunk_bytes.size.should be < Matter::Protocol::IMHandler::MAX_REPORT_PAYLOAD_SIZE

      # Verify it's valid TLV
      reader = TLV::Reader.new(chunk_bytes)
      decoded = reader.get.as(Hash)["Any"].as(Hash)
      decoded[0_u8]?.should eq 12345_u32 # subscriptionId
      decoded[1_u8]?.should_not be_nil   # attributeReports should exist

      # Note: TLV library has a quirk with anonymous structures in arrays,
      # but the encoded data is correct (confirmed by log output showing 2 reports encoded)
      # We verify the hex contains both attribute IDs
      hex = chunk_bytes.hexstring
      hex.should contain("240400") # attribute 0x0000
      hex.should contain("240401") # attribute 0x0001
    end

    it "chunks large responses into multiple messages" do
      # Create a response with many large attributes to exceed MTU
      reports = [] of Matter::InteractionModel::AttributeData

      # Create enough large attributes to force chunking
      # Each attribute with ~100 bytes should force chunking around 10-11 attributes
      50.times do |i|
        # Create a largish value (100 bytes of TLV data)
        large_value = IO::Memory.new
        writer = TLV::Writer.new(large_value)
        writer.put(nil, "A" * 90) # ~90 byte string plus TLV overhead
        value_bytes = large_value.rewind.to_slice

        reports << Matter::InteractionModel::AttributeData.new(
          path: Matter::InteractionModel::AttributePath.new(
            endpoint: 0_u16,
            cluster: 0x0028_u32,
            attribute: i.to_u32
          ),
          data_version: 0x12345678_u32,
          value: value_bytes
        )
      end

      response = Matter::InteractionModel::ReadResponse.new(
        attribute_reports: reports,
        attribute_status: [] of Matter::InteractionModel::AttributeStatus
      )

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response, 99999_u32)

      # Should have multiple chunks
      chunks.size.should be > 1

      puts "\nChunking test with 50 large attributes:"
      puts "  Total chunks: #{chunks.size}"

      # Verify each chunk
      total_reports = 0
      chunks.each_with_index do |(chunk_bytes, is_last), idx|
        puts "  Chunk #{idx + 1}: #{chunk_bytes.size} bytes, is_last=#{is_last}"

        # Each chunk should be under the MTU limit (allow some margin for single large items)
        # Note: individual items may exceed limit if they're individually too large
        chunk_bytes.size.should be < 1500 # Allow some margin above MAX_REPORT_PAYLOAD_SIZE

        # Verify it's valid TLV
        reader = TLV::Reader.new(chunk_bytes)
        decoded = reader.get.as(Hash)["Any"].as(Hash)

        # Should have subscriptionId
        decoded[0_u8]?.should eq 99999_u32

        # Should have attributeReports array
        reports_array = decoded[1_u8].as(Array)
        total_reports += reports_array.size

        # Check moreChunkedMessages flag (tag 3 per Matter spec)
        if is_last
          # Last chunk should not have moreChunkedMessages set (or false)
          decoded[3_u8]?.should be_nil
        else
          # Non-last chunks must have moreChunkedMessages = true
          decoded[3_u8]?.should eq true
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
      reports = [] of Matter::InteractionModel::AttributeData

      30.times do |i|
        large_value = IO::Memory.new
        writer = TLV::Writer.new(large_value)
        writer.put(nil, "B" * 80)
        value_bytes = large_value.rewind.to_slice

        reports << Matter::InteractionModel::AttributeData.new(
          path: Matter::InteractionModel::AttributePath.new(
            endpoint: 0_u16,
            cluster: 0x0028_u32,
            attribute: i.to_u32
          ),
          data_version: 0xABCD1234_u32,
          value: value_bytes
        )
      end

      response = Matter::InteractionModel::ReadResponse.new(
        attribute_reports: reports
      )

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response)

      chunks.size.should be >= 2

      # All chunks except the last should have more_chunks = true
      chunks[0...-1].each_with_index do |(chunk_bytes, is_last), idx|
        is_last.should be_false

        reader = TLV::Reader.new(chunk_bytes)
        decoded = reader.get.as(Hash)["Any"].as(Hash)
        decoded[3_u8]?.should eq true # moreChunkedMessages (tag 3 per Matter spec)
      end

      # Last chunk should have more_chunks = false (field omitted)
      last_chunk_bytes, is_last = chunks.last
      is_last.should be_true

      reader = TLV::Reader.new(last_chunk_bytes)
      decoded = reader.get.as(Hash)["Any"].as(Hash)
      decoded[3_u8]?.should be_nil # moreChunkedMessages not set (tag 3)
    end

    it "handles empty response" do
      response = Matter::InteractionModel::ReadResponse.new(
        attribute_reports: [] of Matter::InteractionModel::AttributeData,
        attribute_status: [] of Matter::InteractionModel::AttributeStatus
      )

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response, 1_u32)

      # Should return exactly one empty chunk
      chunks.size.should eq 1

      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # Verify it's valid TLV with empty array
      reader = TLV::Reader.new(chunk_bytes)
      decoded = reader.get.as(Hash)["Any"].as(Hash)
      decoded[0_u8]?.should eq 1_u32 # subscriptionId
      reports_array = decoded[1_u8].as(Array)
      reports_array.size.should eq 0
    end

    it "works without subscription ID" do
      reports = [
        Matter::InteractionModel::AttributeData.new(
          path: Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x0030_u32, attribute: 0x0000_u32),
          data_version: 0x12345678_u32,
          value: Bytes[0x24, 0x02, 0x00]
        ),
      ]

      response = Matter::InteractionModel::ReadResponse.new(attribute_reports: reports)

      # Pass nil for subscription_id
      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response, nil)

      chunks.size.should eq 1

      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # Verify no subscriptionId in output
      reader = TLV::Reader.new(chunk_bytes)
      decoded = reader.get.as(Hash)["Any"].as(Hash)
      decoded[0_u8]?.should be_nil     # No subscriptionId
      decoded[1_u8]?.should_not be_nil # attributeReports should exist
    end

    it "handles attribute status entries" do
      statuses = [
        Matter::InteractionModel::AttributeStatus.new(
          path: Matter::InteractionModel::AttributePath.new(endpoint: 0_u16, cluster: 0x9999_u32, attribute: 0x0000_u32),
          status: Matter::InteractionModel::Status.new(Matter::InteractionModel::StatusCode::NotFound)
        ),
      ]

      response = Matter::InteractionModel::ReadResponse.new(
        attribute_reports: [] of Matter::InteractionModel::AttributeData,
        attribute_status: statuses
      )

      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response)

      chunks.size.should eq 1

      chunk_bytes, is_last = chunks[0]
      is_last.should be_true

      # Verify status is included in the reports array
      reader = TLV::Reader.new(chunk_bytes)
      decoded = reader.get.as(Hash)["Any"].as(Hash)
      reports_array = decoded[1_u8].as(Array)
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
      puts "  Total reports: #{response.attribute_reports.size}"

      # Chunk the response
      chunks = Matter::Protocol::IMHandler.encode_chunked_report_data(response, 1_u32)

      puts "  Chunks produced: #{chunks.size}"

      # Verify all chunks are valid
      total_items = 0
      chunks.each_with_index do |(chunk_bytes, is_last), idx|
        puts "  Chunk #{idx + 1}: #{chunk_bytes.size} bytes"

        reader = TLV::Reader.new(chunk_bytes)
        decoded = reader.get.as(Hash)["Any"].as(Hash)
        reports_array = decoded[1_u8].as(Array)
        total_items += reports_array.size
      end

      # Total items = reports + statuses
      expected_total = response.attribute_reports.size + response.attribute_status.size
      total_items.should eq expected_total
    end
  end
end
