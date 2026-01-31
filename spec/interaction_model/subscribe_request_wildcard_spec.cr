require "../spec_helper"
require "../../src/matter/interaction_model/tlv_messages"
require "../../src/matter/protocol/im_handler"

describe "SubscribeRequestMessage with wildcard paths" do
  # This test validates parsing of SubscribeRequest from iOS/iPhone which uses
  # Boolean `true` to indicate wildcard for path fields (like event_id)
  # instead of simply omitting the field.
  #
  # The Matter spec allows Boolean true as a wildcard indicator for path fields.

  it "parses SubscribeRequest with wildcard event path from iPhone" do
    # Real bytes captured from iPhone commissioning:
    # 15290024010025025802360317181836041729041818280724ff0c18
    #
    # Decoded structure:
    # - tag 0: keep_subscriptions = true (BooleanTrue)
    # - tag 1: min_interval_floor = 0
    # - tag 2: max_interval_ceiling = 600 (0x0258)
    # - tag 3: attribute_requests = [empty AttributePath (wildcard)]
    # - tag 4: event_requests = [EventPath with tag 4 (event) = true (wildcard)]
    # - tag 7: is_fabric_filtered = false
    # - tag 0xFF: interaction_model_revision = 12
    bytes = Bytes[
      0x15,                   # Structure start
      0x29, 0x00,             # tag 0, BooleanTrue (keep_subscriptions = true)
      0x24, 0x01, 0x00,       # tag 1, UInt8 = 0 (min_interval_floor)
      0x25, 0x02, 0x58, 0x02, # tag 2, UInt16 = 600 (max_interval_ceiling)
      0x36, 0x03,             # tag 3, Array start (attribute_requests)
      0x17,                   # List start (empty AttributePath - wildcard)
      0x18,                   # End list
      0x18,                   # End array
      0x36, 0x04,             # tag 4, Array start (event_requests)
      0x17,                   # List start (EventPath)
      0x29, 0x04,             # tag 4, BooleanTrue (event = wildcard!)
      0x18,                   # End list
      0x18,                   # End array
      0x28, 0x07,             # tag 7, BooleanFalse (is_fabric_filtered = false)
      0x24, 0xff, 0x0c,       # tag 255, UInt8 = 12 (interaction_model_revision)
      0x18,                   # End structure
    ]

    msg = Matter::InteractionModel::SubscribeRequestMessage.from_slice(bytes)

    msg.keep_subscriptions?.should be_true
    msg.min_interval_floor.should eq(0_u16)
    msg.max_interval_ceiling.should eq(600_u16)
    msg.is_fabric_filtered?.should be_false
    msg.interaction_model_revision.should eq(12_u8)

    # Verify attribute_requests
    attr_requests = msg.attribute_requests.as(Array(Matter::InteractionModel::AttributePath))
    attr_requests.size.should eq(1)

    # Empty path = wildcard
    attr_path = attr_requests[0]
    attr_path.endpoint.should be_nil
    attr_path.cluster.should be_nil
    attr_path.attribute.should be_nil
    attr_path.wildcard?.should be_true

    # Verify event_requests
    event_requests = msg.event_requests.as(Array(Matter::InteractionModel::EventPath))
    event_requests.size.should eq(1)

    # EventPath with event = wildcard (true)
    event_path = event_requests[0]
    event_path.endpoint.should be_nil
    event_path.cluster.should be_nil
    event_path.event.should be_nil # Wildcard true should be treated as nil/wildcard
    event_path.wildcard?.should be_true
  end

  it "parses EventPath with explicit event ID" do
    # EventPath with a specific event ID (not wildcard)
    # List with: tag 2 = endpoint 0, tag 3 = cluster 0x0028, tag 4 = event 0
    bytes = Bytes[
      0x17,                   # List start
      0x24, 0x02, 0x00,       # tag 2, UInt8 = 0 (endpoint)
      0x25, 0x03, 0x28, 0x00, # tag 3, UInt16 = 0x0028 (cluster)
      0x24, 0x04, 0x00,       # tag 4, UInt8 = 0 (event)
      0x18,                   # End list
    ]

    path = Matter::InteractionModel::EventPath.from_slice(bytes)

    path.endpoint.should eq(0_u16)
    path.cluster.should eq(0x0028_u32)
    path.event.should eq(0_u32)
    path.wildcard?.should be_false
  end

  it "parses AttributePath with wildcard boolean for attribute field" do
    # AttributePath with attribute = true (wildcard)
    # Some controllers may send this format
    bytes = Bytes[
      0x17,                   # List start
      0x24, 0x02, 0x00,       # tag 2, UInt8 = 0 (endpoint)
      0x25, 0x03, 0x06, 0x00, # tag 3, UInt16 = 0x0006 (cluster)
      0x29, 0x04,             # tag 4, BooleanTrue (attribute = wildcard)
      0x18,                   # End list
    ]

    path = Matter::InteractionModel::AttributePath.from_slice(bytes)

    path.endpoint.should eq(0_u16)
    path.cluster.should eq(0x0006_u32)
    path.attribute.should be_nil # Wildcard true should be treated as nil
    path.wildcard?.should be_true
  end

  describe "IMHandler.read_attributes with wildcard paths" do
    it "handles empty attribute requests array" do
      clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base
      reports = Matter::Protocol::IMHandler.read_attributes(
        [] of Matter::InteractionModel::AttributePath,
        clusters
      )
      reports.should be_empty
    end

    it "handles nil attribute requests" do
      clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base
      reports = Matter::Protocol::IMHandler.read_attributes(
        nil,
        clusters
      )
      reports.should be_empty
    end

    it "handles wildcard path with no matching clusters" do
      clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base

      # Wildcard path (all nil = match everything)
      wildcard_path = Matter::InteractionModel::AttributePath.new
      wildcard_path.wildcard?.should be_true

      reports = Matter::Protocol::IMHandler.read_attributes(
        [wildcard_path],
        clusters
      )
      reports.should be_empty
    end

    it "handles wildcard path expansion with OnOff cluster" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      on_off = Matter::Cluster::OnOffCluster.new(endpoint)

      clusters = {
        {1_u16, Matter::Cluster::OnOffCluster::CLUSTER_ID} => on_off.as(Matter::Cluster::Base),
      }

      # Wildcard path targeting all attributes on endpoint 1
      wildcard_path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: Matter::Cluster::OnOffCluster::CLUSTER_ID
      )

      reports = Matter::Protocol::IMHandler.read_attributes(
        [wildcard_path],
        clusters
      )

      # Should have reports for all OnOff attributes plus global attributes
      reports.size.should be > 0

      # All reports should have data (not status errors)
      reports.each do |report|
        # Either attribute_data or attribute_status should be present
        if data = report.attribute_data
          data.data.should_not be_nil
        end
      end
    end
  end
end
