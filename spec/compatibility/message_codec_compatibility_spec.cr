require "../spec_helper"
require "../../src/matter/codec/message_codec"

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
      packet.header.source_node_id.as(Matter::DataType::NodeId).id.should eq(0x52636ACBA7C8A07E_u64)

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

      # Re-encoding the decoded message must reproduce the matter.js bytes exactly
      re_encoded = Matter::Codec::MessageCodec::Base.encode_packet(Matter::Codec::MessageCodec::Base.encode_payload(decoded))
      re_encoded.hexstring.should eq(encoded.hexstring)
    end

    it "decodes message with matter.js test vector 2" do
      # Test vector from matter.js with destination_node_id instead of source_node_id
      encoded = "01000000218712797ea0c8a7cb6a63520621d36400000a4ff217153001204715a406c6b0496ad52039e347db8528cb69a1cb2fce6f2318552ae65e103aca3002201783302d95a4a9fb0decb8fdd6564b90a957681459aeee069961bea61d7b247125039d8935042501e80330022099f813dd41bd081a1c63e811828f0662594bca89cd9d4ed26f7427fdb2a027361835052501881325022c011818".hexbytes

      packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded)

      # Verify packet header
      packet.header.session_id.should eq(0_u16)
      packet.header.message_id.should eq(2031257377_u32)
      packet.header.destination_node_id.should_not be_nil
      packet.header.destination_node_id.as(Matter::DataType::NodeId).id.should eq(0x52636ACBA7C8A07E_u64)

      # Decode payload
      decoded = Matter::Codec::MessageCodec::Base.decode_payload(packet)

      # Verify payload header
      decoded.payload_header.protocol_id.should eq(0_u16)
      decoded.payload_header.initiator_message?.should be_false
      decoded.payload_header.exchange_id.should eq(25811_u16)
      decoded.payload_header.message_type.should eq(0x21_u8)
      decoded.payload_header.requires_acknowledge?.should be_true
      decoded.payload_header.acknowledged_message_id.should eq(401755914_u32)

      # Re-encoding the decoded message must reproduce the matter.js bytes exactly
      re_encoded = Matter::Codec::MessageCodec::Base.encode_packet(Matter::Codec::MessageCodec::Base.encode_payload(decoded))
      re_encoded.hexstring.should eq(encoded.hexstring)
    end

    it "encodes and decodes message round-trip" do
      # Create a test message
      source_node_id = Matter::DataType::NodeId.new(0x1122334455667788_u64)
      # Compute flags with source_node_id set

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x1234_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 42_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: source_node_id
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

      # Exact wire layout (all little-endian):
      #   04                 packet flags: version 0 | HasSourceNodeId
      #   3412               session id 0x1234
      #   00                 security flags: unicast
      #   2a000000           message id 42
      #   8877665544332211   source node id 0x1122334455667788
      #   03                 payload flags: IsInitiator | IsAck (acknowledged_message_id is non-nil)
      #   05                 message type 5
      #   6400               exchange id 100
      #   0100               protocol id 1
      #   00000000           acknowledged message id 0
      #   48656c6c6f...      "Hello Matter Protocol"
      encoded_packet.hexstring.should eq(
        "043412002a0000008877665544332211" \
        "0305640001000000000048656c6c6f204d61747465722050726f746f636f6c"
      )

      # Decode it back
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_message = Matter::Codec::MessageCodec::Base.decode_payload(decoded_packet)

      # Verify packet header matches
      decoded_message.packet_header.session_id.should eq(packet_header.session_id)
      decoded_message.packet_header.message_id.should eq(packet_header.message_id)
      decoded_message.packet_header.source_node_id.as(Matter::DataType::NodeId).id.should eq(0x1122334455667788_u64)

      # Verify payload header matches
      decoded_message.payload_header.exchange_id.should eq(payload_header.exchange_id)
      decoded_message.payload_header.protocol_id.should eq(payload_header.protocol_id)
      decoded_message.payload_header.message_type.should eq(payload_header.message_type)
      decoded_message.payload_header.initiator_message?.should eq(payload_header.initiator_message?)

      # Verify payload matches
      decoded_message.payload.should eq(test_payload)
    end

    it "handles group session type correctly" do
      dest_group_id = Matter::DataType::GroupId.new(0xABCD_u16)
      # Compute flags with destination_group_id set

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x5678_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Group,
        message_id: 99_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        destination_group_id: dest_group_id
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
      decoded_message.packet_header.destination_group_id.as(Matter::DataType::GroupId).id.should eq(0xABCD_u16)
    end

    # The Destination Group ID is a 16-bit field (Matter spec 4.4.1, matter.js
    # MessageCodec.ts `writer.writeUInt16(destGroupId)`). `encode_packet_header`
    # once wrote it as UInt32; the round-trip above never caught that because the
    # decoder consumed the two stray zero bytes as payload flags + message type.
    it "encodes group session packet with a 16-bit destination group id" do
      dest_group_id = Matter::DataType::GroupId.new(0xABCD_u16)

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x5678_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Group,
        message_id: 99_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        destination_group_id: dest_group_id
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

      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

      # Exact wire layout (all little-endian):
      #   02                 packet flags: version 0 | HasDestGroupId
      #   7856               session id 0x5678
      #   01                 security flags: group session
      #   63000000           message id 99
      #   cdab               destination group id 0xABCD (16-bit)
      #   02                 payload flags: IsAck (acknowledged_message_id is non-nil)
      #   0a                 message type 10
      #   c800               exchange id 200
      #   0200               protocol id 2
      #   00000000           acknowledged message id 0
      #   00 * 10            payload
      encoded_packet.hexstring.should eq(
        "0278560163000000cdab" \
        "020ac800020000000000" \
        "00000000000000000000"
      )

      decoded_message = Matter::Codec::MessageCodec::Base.decode_payload(Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet))
      decoded_message.payload_header.exchange_id.should eq(200_u16)
      decoded_message.payload_header.protocol_id.should eq(2_u16)
      decoded_message.payload_header.message_type.should eq(10_u8)
      decoded_message.payload.size.should eq(10)
    end

    it "handles control messages correctly" do
      # No source or destination node IDs, so flags is just version bits

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 1_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: true, # Control message flag
        message_extensions: false,
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

      # Exact wire layout (all little-endian):
      #   00                 packet flags: version 0, no node ids
      #   0100               session id 1
      #   40                 security flags: IsControlMessage | unicast
      #   01000000           message id 1
      #   03                 payload flags: IsInitiator | IsAck (acknowledged_message_id is non-nil)
      #   10                 message type 0x10
      #   0100               exchange id 1
      #   0000               protocol id 0
      #   00000000           acknowledged message id 0
      encoded_packet.hexstring.should eq("000100400100000003100100000000000000")

      # Verify the message encoded and decoded successfully
      decoded_message.packet_header.session_id.should eq(1_u16)
      decoded_message.payload_header.protocol_id.should eq(0_u16)
      decoded_message.packet_header.control_message?.should be_true
      decoded_message.payload_header.exchange_id.should eq(1_u16)
      decoded_message.payload_header.message_type.should eq(0x10_u8)
    end
  end
end
