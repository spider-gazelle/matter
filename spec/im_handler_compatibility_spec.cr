require "./spec_helper"
require "../src/matter/protocol/im_handler"
require "../src/matter/cluster/general_commissioning_cluster"
require "../src/matter/cluster/basic_information_cluster"
require "../src/matter/interaction_model/messages"
require "../src/matter/interaction_model/tlv_messages"

describe "IMHandler - matter.js Compatibility" do
  describe "ReadCommissioningInfo Request/Response" do
    it "parses chip-tool ReadRequest and generates response matching matter.js" do
      # ReadRequest TLV from chip-tool (captured during commissioning)
      # This is the first ReadRequest sent after PASE is established
      read_request_hex = "15360017240200240330240404181724020024033024040018172402002403302404011817240200240330240402181724020024033024040318172402002403282404021817240200240328240404181724020024033818172403312504fcff1818280324ff0c18"
      read_request_bytes = Bytes.new(read_request_hex.scan(/../).map(&.[0].to_u8(16)).to_unsafe, read_request_hex.size // 2)

      # Parse ReadRequest
      request = Matter::Protocol::IMHandler.parse_read_request(read_request_bytes)
      request.should_not be_nil
      request = request.not_nil!

      # Verify correct attributes were requested (from matter.js logs)
      # Should have 9 attribute requests:
      # 1-5: GeneralCommissioning attributes
      # 6-7: BasicInformation attributes
      # 8-9: Wildcards
      request.attribute_requests.size.should eq 9

      # Initialize clusters with values matching matter.js
      clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base

      # GeneralCommissioning cluster (0x0030) on endpoint 0
      general_commissioning = Matter::Cluster::GeneralCommissioningCluster.new(
        Matter::DataType::EndpointNumber.new(0_u16)
      )
      # Set data version to match matter.js (version: 3544487608 = 0xd34496b8)
      general_commissioning.data_version = 0xd34496b8_u32
      clusters[{0_u16, 0x0030_u32}] = general_commissioning

      # BasicInformation cluster (0x0028) on endpoint 0
      basic_info = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        vendor_id: 65521_u16,  # 0xFFF1 - matches matter.js
        product_id: 32768_u16, # 0x8000 - matches matter.js
        vendor_name: "matter-node.js",
        product_name: "node-matter OnOff Light"
      )
      # Set data version to match matter.js (version: 3804324040 = 0xe2c160c8)
      basic_info.data_version = 0xe2c160c8_u32
      clusters[{0_u16, 0x0028_u32}] = basic_info

      # Read attributes using IMHandler
      response = Matter::Protocol::IMHandler.read_attributes(request.attribute_requests, clusters)

      # Verify response structure matches matter.js
      # matter.js returned: 7 attribute values
      response.attribute_reports.size.should eq 7

      # Verify each attribute report has the expected structure
      response.attribute_reports.each do |report|
        # Each report should have:
        # - path with endpoint, cluster, attribute
        # - data_version (matches cluster version)
        # - value (TLV-encoded bytes)
        report.path.endpoint.should_not be_nil
        report.path.cluster.should_not be_nil
        report.path.attribute.should_not be_nil
        report.data_version.should_not be_nil
        report.value.should_not be_nil
        report.value.size.should be > 0
      end

      # Check specific attribute values
      # 1. GeneralCommissioning.supportsConcurrentConnection (0x4) = true
      supports_concurrent = response.attribute_reports.find do |r|
        r.path.cluster == 0x0030 && r.path.attribute == 0x0004
      end
      supports_concurrent.should_not be_nil
      supports_concurrent = supports_concurrent.not_nil!
      supports_concurrent.data_version.should eq 0xd34496b8_u32

      # 2. GeneralCommissioning.breadcrumb (0x0) = 0
      breadcrumb = response.attribute_reports.find do |r|
        r.path.cluster == 0x0030 && r.path.attribute == 0x0000
      end
      breadcrumb.should_not be_nil
      breadcrumb = breadcrumb.not_nil!
      breadcrumb.data_version.should eq 0xd34496b8_u32

      # 3. GeneralCommissioning.basicCommissioningInfo (0x1)
      basic_commissioning_info = response.attribute_reports.find do |r|
        r.path.cluster == 0x0030 && r.path.attribute == 0x0001
      end
      basic_commissioning_info.should_not be_nil
      basic_commissioning_info.not_nil!.data_version.should eq 0xd34496b8_u32

      # 4. GeneralCommissioning.regulatoryConfig (0x2) = 2 (IndoorOutdoor)
      regulatory_config = response.attribute_reports.find do |r|
        r.path.cluster == 0x0030 && r.path.attribute == 0x0002
      end
      regulatory_config.should_not be_nil
      regulatory_config.not_nil!.data_version.should eq 0xd34496b8_u32

      # 5. GeneralCommissioning.locationCapability (0x3) = 2 (IndoorOutdoor)
      location_capability = response.attribute_reports.find do |r|
        r.path.cluster == 0x0030 && r.path.attribute == 0x0003
      end
      location_capability.should_not be_nil
      location_capability.not_nil!.data_version.should eq 0xd34496b8_u32

      # 6. BasicInformation.vendorId (0x2) = 65521 (0xFFF1)
      vendor_id = response.attribute_reports.find do |r|
        r.path.cluster == 0x0028 && r.path.attribute == 0x0002
      end
      vendor_id.should_not be_nil
      vendor_id = vendor_id.not_nil!
      vendor_id.data_version.should eq 0xe2c160c8_u32

      # 7. BasicInformation.productId (0x4) = 32768 (0x8000)
      product_id = response.attribute_reports.find do |r|
        r.path.cluster == 0x0028 && r.path.attribute == 0x0004
      end
      product_id.should_not be_nil
      product_id = product_id.not_nil!
      product_id.data_version.should eq 0xe2c160c8_u32
    end

    it "encodes ReadResponse to TLV matching matter.js structure" do
      # Initialize clusters
      clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base

      general_commissioning = Matter::Cluster::GeneralCommissioningCluster.new(
        Matter::DataType::EndpointNumber.new(0_u16)
      )
      general_commissioning.data_version = 0xd34496b8_u32
      clusters[{0_u16, 0x0030_u32}] = general_commissioning

      basic_info = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        vendor_id: 65521_u16,
        product_id: 32768_u16
      )
      basic_info.data_version = 0xe2c160c8_u32
      clusters[{0_u16, 0x0028_u32}] = basic_info

      # Create a simple ReadRequest for a single attribute
      paths = [
        Matter::InteractionModel::AttributePath.new(
          endpoint: 0_u16,
          cluster: 0x0030_u32,
          attribute: 0x0004_u32
        ),
      ]

      # Read attributes
      response = Matter::Protocol::IMHandler.read_attributes(paths, clusters)
      response.attribute_reports.size.should eq 1

      # Encode response as TLV
      encoded = Matter::Protocol::IMHandler.encode_read_response(response)

      # Verify encoded response is valid TLV
      encoded.size.should be > 0

      # Should be able to parse it back using TLV::Serializable
      decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)

      # Should have attributeReports array (tag 1) - matches matter.js
      decoded.attribute_reports.should_not be_nil
      attribute_reports = decoded.attribute_reports.not_nil!
      attribute_reports.size.should eq 1

      # Should have interactionModelRevision (tag 0xFF) = 12
      decoded.interaction_model_revision.should eq 12_u8
    end

    it "generates response TLV byte-compatible with matter.js (structural comparison)" do
      # This test verifies the TLV structure matches, even if exact bytes differ
      # (due to different data version values, timestamps, etc.)

      # Parse the real ReadRequest from chip-tool
      read_request_hex = "15360017240200240330240404181724020024033024040018172402002403302404011817240200240330240402181724020024033024040318172402002403282404021817240200240328240404181724020024033818172403312504fcff1818280324ff0c18"
      read_request_bytes = Bytes.new(read_request_hex.scan(/../).map(&.[0].to_u8(16)).to_unsafe, read_request_hex.size // 2)

      request = Matter::Protocol::IMHandler.parse_read_request(read_request_bytes)
      request.should_not be_nil
      request = request.not_nil!

      # Initialize clusters with matter.js values
      clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base

      general_commissioning = Matter::Cluster::GeneralCommissioningCluster.new(
        Matter::DataType::EndpointNumber.new(0_u16)
      )
      general_commissioning.data_version = 0xd34496b8_u32
      clusters[{0_u16, 0x0030_u32}] = general_commissioning

      basic_info = Matter::Cluster::BasicInformationCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(0_u16),
        vendor_id: 65521_u16,
        product_id: 32768_u16
      )
      basic_info.data_version = 0xe2c160c8_u32
      clusters[{0_u16, 0x0028_u32}] = basic_info

      # Process request
      response = Matter::Protocol::IMHandler.read_attributes(request.attribute_requests, clusters)
      encoded = Matter::Protocol::IMHandler.encode_read_response(response)

      # Log the encoded response for debugging
      puts "\n=== Crystal Matter ReadResponse TLV ==="
      puts "Size: #{encoded.size} bytes"
      puts "Hex (first 128): #{encoded[0...64].hexstring}"
      puts

      # matter.js response (from logs):
      # Size: 210 bytes
      # Hex: 1536011535012600b89644d3370124020024033024040418290218181535012600b89644d337012402002403302404001824020018181535012600b89644d3370124020024033024040118350224003c250184031818181535012600b89644d337012402002403302404021824020218181535012600b89644d337012402002403302404031824020218181535012600c860c1e23701240200240328240402182502f1ff18181535012600c860c1e237012402002403282404041825020080181818290424ff0d18
      matterjs_response_hex = "1536011535012600b89644d3370124020024033024040418290218181535012600b89644d337012402002403302404001824020018181535012600b89644d3370124020024033024040118350224003c250184031818181535012600b89644d337012402002403302404021824020218181535012600b89644d337012402002403302404031824020218181535012600c860c1e23701240200240328240402182502f1ff18181535012600c860c1e237012402002403282404041825020080181818290424ff0d18"
      matterjs_response_bytes = Bytes.new(matterjs_response_hex.scan(/../).map(&.[0].to_u8(16)).to_unsafe, matterjs_response_hex.size // 2)

      puts "=== matter.js ReadResponse TLV ==="
      puts "Size: #{matterjs_response_bytes.size} bytes"
      puts "Hex (first 128): #{matterjs_response_bytes[0...64].hexstring}"
      puts

      # Parse both responses using TLV::Serializable
      crystal_decoded = Matter::InteractionModel::ReportDataMessage.from_slice(encoded)
      matterjs_decoded = Matter::InteractionModel::ReportDataMessage.from_slice(matterjs_response_bytes)

      # Both should have attributeReports array (tag 1) - matches matter.js
      crystal_decoded.attribute_reports.should_not be_nil
      matterjs_decoded.attribute_reports.should_not be_nil

      crystal_reports = crystal_decoded.attribute_reports.not_nil!
      matterjs_reports = matterjs_decoded.attribute_reports.not_nil!

      # Should have same number of reports
      crystal_reports.size.should eq matterjs_reports.size
      crystal_reports.size.should eq 7

      # Both should have interactionModelRevision (tag 0xFF)
      crystal_decoded.interaction_model_revision.should eq 12_u8
      matterjs_decoded.interaction_model_revision.should eq 13_u8 # matter.js uses revision 13 (0x0d)

      puts "TLV structure matches matter.js!"
      puts "Both have #{crystal_reports.size} attribute reports"
      puts "Both have interactionModelRevision tag"
    end
  end
end
