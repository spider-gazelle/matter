require "../spec_helper"
require "../../src/matter/protocol/im_handler"
require "../../src/matter/cluster/fan_control_cluster"
require "../../src/matter/cluster/on_off_cluster"
require "../../src/matter/interaction_model/tlv_messages"

describe "IMHandler - TLV value extraction regression" do
  # Regression test for the bug where request.data.to_slice returned full TLV-encoded
  # bytes (header+tag+value) instead of raw value bytes. Clusters check value.size
  # (e.g. != 1 for UInt8), so the extra TLV overhead caused InvalidDataType errors.

  it "writes UInt8 attribute via TLV-encoded WriteRequest (FanControl PercentSetting)" do
    endpoint = Matter::DataType::EndpointNumber.new(1_u16)
    fan = Matter::Cluster::FanControlCluster.new(
      endpoint,
      fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off,
      fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHigh,
      percent_setting: 0_u8,
      percent_current: 0_u8,
      speed_max: 4_u8,
    )

    clusters = {
      {1_u16, 0x0202_u32} => fan.as(Matter::Cluster::Base),
    }

    # Build a WriteRequestMessage with a TLV::Any holding a UInt8 value (like iOS sends)
    # PercentSetting attribute (0x02) = 75
    write_requests = [
      Matter::InteractionModel::AttributeDataIB.new(
        path: Matter::InteractionModel::AttributePath.new(
          endpoint: 1_u16,
          cluster: 0x0202_u32,
          attribute: 0x0002_u32, # PercentSetting
        ),
        data: TLV::Any.new(75_u8),
      ),
    ]

    results = Matter::Protocol::IMHandler.write_attributes(write_requests, clusters)
    results.size.should eq 1
    results[0].status.status.should eq 0_u8 # Success

    fan.percent_setting.should eq 75_u8
    fan.percent_current.should eq 75_u8
  end

  it "writes UInt8 attribute via round-tripped TLV bytes (simulating iOS wire format)" do
    endpoint = Matter::DataType::EndpointNumber.new(1_u16)
    fan = Matter::Cluster::FanControlCluster.new(
      endpoint,
      fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off,
      fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHigh,
      percent_setting: 0_u8,
      percent_current: 0_u8,
      speed_max: 4_u8,
    )

    clusters = {
      {1_u16, 0x0202_u32} => fan.as(Matter::Cluster::Base),
    }

    # Build a WriteRequestMessage, serialize to TLV, then parse it back —
    # this is exactly what happens on the wire from iOS Home
    original_msg = Matter::InteractionModel::WriteRequestMessage.new(
      suppress_response: false,
      timed_request: false,
      write_requests: [
        Matter::InteractionModel::AttributeDataIB.new(
          path: Matter::InteractionModel::AttributePath.new(
            endpoint: 1_u16,
            cluster: 0x0202_u32,
            attribute: 0x0002_u32,
          ),
          data: TLV::Any.new(100_u8),
        ),
      ],
    )

    # Serialize and re-parse (simulates network round-trip)
    wire_bytes = original_msg.to_slice
    parsed_msg = Matter::Protocol::IMHandler.parse_write_request(wire_bytes)
    parsed_msg.should_not be_nil
    parsed_msg = parsed_msg.as(Matter::InteractionModel::WriteRequestMessage)

    # Now write through the full path
    results = Matter::Protocol::IMHandler.write_attributes(parsed_msg.write_requests, clusters)
    results.size.should eq 1
    results[0].status.status.should eq 0_u8 # Success — NOT 0x8d (InvalidDataType)

    fan.percent_setting.should eq 100_u8
  end

  it "writes FanMode enum via TLV round-trip" do
    endpoint = Matter::DataType::EndpointNumber.new(1_u16)
    fan = Matter::Cluster::FanControlCluster.new(
      endpoint,
      fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off,
      fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHigh,
      percent_setting: 0_u8,
      percent_current: 0_u8,
      speed_max: 4_u8,
    )

    clusters = {
      {1_u16, 0x0202_u32} => fan.as(Matter::Cluster::Base),
    }

    # Write FanMode (attribute 0x00) = 3 (High)
    original_msg = Matter::InteractionModel::WriteRequestMessage.new(
      suppress_response: false,
      timed_request: false,
      write_requests: [
        Matter::InteractionModel::AttributeDataIB.new(
          path: Matter::InteractionModel::AttributePath.new(
            endpoint: 1_u16,
            cluster: 0x0202_u32,
            attribute: 0x0000_u32, # FanMode
          ),
          data: TLV::Any.new(3_u8), # High
        ),
      ],
    )

    wire_bytes = original_msg.to_slice
    parsed_msg = Matter::Protocol::IMHandler.parse_write_request(wire_bytes).as(Matter::InteractionModel::WriteRequestMessage)

    results = Matter::Protocol::IMHandler.write_attributes(parsed_msg.write_requests, clusters)
    results.size.should eq 1
    results[0].status.status.should eq 0_u8

    fan.fan_mode.should eq Matter::Cluster::FanControlCluster::FanMode::High
  end

  it "writes Bool attribute via TLV round-trip (OnOff cluster)" do
    endpoint = Matter::DataType::EndpointNumber.new(1_u16)
    on_off = Matter::Cluster::OnOffCluster.new(endpoint)

    clusters = {
      {1_u16, 0x0006_u32} => on_off.as(Matter::Cluster::Base),
    }

    # OnOff attribute (0x0000) = true
    original_msg = Matter::InteractionModel::WriteRequestMessage.new(
      suppress_response: false,
      timed_request: false,
      write_requests: [
        Matter::InteractionModel::AttributeDataIB.new(
          path: Matter::InteractionModel::AttributePath.new(
            endpoint: 1_u16,
            cluster: 0x0006_u32,
            attribute: 0x0000_u32, # OnOff
          ),
          data: TLV::Any.new(true),
        ),
      ],
    )

    wire_bytes = original_msg.to_slice
    parsed_msg = Matter::Protocol::IMHandler.parse_write_request(wire_bytes).as(Matter::InteractionModel::WriteRequestMessage)

    results = Matter::Protocol::IMHandler.write_attributes(parsed_msg.write_requests, clusters)
    results.size.should eq 1
    # OnOff is typically read-only (set via commands), so UnsupportedWrite is expected
    # The important thing is we do NOT get InvalidDataType (0x8d)
    results[0].status.status.should_not eq 0x8d_u8
  end
end
