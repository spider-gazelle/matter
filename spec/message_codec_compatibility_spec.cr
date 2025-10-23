require "./spec_helper"
require "../src/matter/codec/message_codec"

describe "MessageCodec Compatibility with matter.js" do
  describe "Message encoding/decoding" do
    it "decodes message with matter.js test vector 1" do
      # Test vector from matter.js MessageCodecTest.ts
      encoded = "040000000a4ff2177ea0c8a7cb6a63520520d3640000153001204715a406c6b0496ad52039e347db8528cb69a1cb2fce6f2318552ae65e103aca250233dc240300280435052501881325022c011818".hexbytes

      packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded)

      # Verify packet header
      packet.header.session_id.should eq(0_u16)
      packet.header.session_type.should eq(Matter::Codec::MessageCodec::SessionType::Unicast)
      packet.header.message_id.should eq(401755914_u32)
      packet.header.source_node_id.should_not be_nil
      packet.header.source_node_id.not_nil!.id.should eq(0x52636ACBA7C8A07E_u64)

      # Verify flags
      packet.header.privacy_enhancements?.should be_false
      packet.header.control_message?.should be_false
      packet.header.message_extensions?.should be_false

      # Decode payload
      decoded = Matter::Codec::MessageCodec::Base.decode_payload(packet)

      # Verify payload header
      decoded.payload_header.protocol_id.should eq(0_u16)
      decoded.payload_header.initiator_message?.should be_true
      decoded.payload_header.exchange_id.should eq(25811_u16)
      decoded.payload_header.message_type.should eq(0x20_u8)
      decoded.payload_header.requires_acknowledge?.should be_true

      # Verify payload exists
      decoded.payload.size.should be > 0
    end

    it "decodes message with matter.js test vector 2" do
      # Test vector from matter.js with destination_node_id instead of source_node_id
      encoded = "01000000218712797ea0c8a7cb6a63520621d36400000a4ff217153001204715a406c6b0496ad52039e347db8528cb69a1cb2fce6f2318552ae65e103aca3002201783302d95a4a9fb0decb8fdd6564b90a957681459aeee069961bea61d7b247125039d8935042501e80330022099f813dd41bd081a1c63e811828f0662594bca89cd9d4ed26f7427fdb2a027361835052501881325022c011818".hexbytes

      packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded)

      # Verify packet header
      packet.header.session_id.should eq(0_u16)
      packet.header.message_id.should eq(2031257377_u32)
      packet.header.destination_node_id.should_not be_nil
      packet.header.destination_node_id.not_nil!.id.should eq(0x52636ACBA7C8A07E_u64)

      # Decode payload
      decoded = Matter::Codec::MessageCodec::Base.decode_payload(packet)

      # Verify payload header
      decoded.payload_header.protocol_id.should eq(0_u16)
      decoded.payload_header.initiator_message?.should be_false
      decoded.payload_header.exchange_id.should eq(25811_u16)
      decoded.payload_header.message_type.should eq(0x21_u8)
      decoded.payload_header.requires_acknowledge?.should be_true
      decoded.payload_header.acknowledged_message_id.should eq(401755914_u32)
    end

    it "encodes and decodes message round-trip" do
      # Create a test message
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x1234_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 42_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: Matter::DataType::NodeId.new(0x1122334455667788_u64)
      )

      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 100_u16,
        protocol_id: 1_u16,
        message_type: 5_u8,
        initiator_message: true,
        requires_acknowledge: false,
        acknowledged_message_id: 0_u32
      )

      test_payload = "Hello Matter Protocol".to_slice

      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: test_payload
      )

      # Encode the message
      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

      # Decode it back
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_message = Matter::Codec::MessageCodec::Base.decode_payload(decoded_packet)

      # Verify packet header matches
      decoded_message.packet_header.session_id.should eq(packet_header.session_id)
      decoded_message.packet_header.message_id.should eq(packet_header.message_id)
      decoded_message.packet_header.source_node_id.not_nil!.id.should eq(0x1122334455667788_u64)

      # Verify payload header matches
      decoded_message.payload_header.exchange_id.should eq(payload_header.exchange_id)
      decoded_message.payload_header.protocol_id.should eq(payload_header.protocol_id)
      decoded_message.payload_header.message_type.should eq(payload_header.message_type)
      decoded_message.payload_header.initiator_message?.should eq(payload_header.initiator_message?)

      # Verify payload matches
      decoded_message.payload.should eq(test_payload)
    end

    it "handles group session type correctly" do
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x5678_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Group,
        message_id: 99_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        destination_group_id: Matter::DataType::GroupId.new(0xABCD_u16)
      )

      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 200_u16,
        protocol_id: 2_u16,
        message_type: 10_u8,
        initiator_message: false,
        requires_acknowledge: false,
        acknowledged_message_id: 0_u32
      )

      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: Bytes.new(10)
      )

      # Encode and decode
      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_message = Matter::Codec::MessageCodec::Base.decode_payload(decoded_packet)

      # Verify group session
      decoded_message.packet_header.session_type.should eq(Matter::Codec::MessageCodec::SessionType::Group)
      decoded_message.packet_header.destination_group_id.should_not be_nil
      decoded_message.packet_header.destination_group_id.not_nil!.id.should eq(0xABCD_u16)
    end

    it "handles control messages correctly" do
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 1_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: true, # Control message flag
        message_extensions: false
      )

      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16, # Control protocol
        message_type: 0x10_u8,
        initiator_message: true,
        requires_acknowledge: false,
        acknowledged_message_id: 0_u32
      )

      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: Bytes.new(0)
      )

      # Encode and decode
      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_message = Matter::Codec::MessageCodec::Base.decode_payload(decoded_packet)

      # Verify the message encoded and decoded successfully
      decoded_message.packet_header.session_id.should eq(1_u16)
      decoded_message.payload_header.protocol_id.should eq(0_u16)
    end
  end
end
