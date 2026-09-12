require "../spec_helper"
require "../../src/matter/session/context"
require "../../src/matter/session/secure_message"
require "../../src/matter/codec/message_codec"

describe "Session Compatibility with matter.js" do
  describe "SecureMessage encryption/decryption" do
    it "encrypts and decrypts message with session context" do
      crypto = Matter::Crypto::StandardCrypto.new

      # Use the matter.js test keys
      encrypt_key = "66951379d0a6d151cf5472cccf13f360".hexbytes
      decrypt_key = "bacb178b2588443d5d5b1e4559e7accc".hexbytes

      # Create initiator context
      initiator_context = Matter::Session::SecureContext.new(
        session_id: 0x351d_u16,
        peer_session_id: 0x8d4b_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: encrypt_key,
        decryption_key: decrypt_key,
        initiator: true,
        local_node_id: Matter::DataType::NodeId.new(0x5261A3CBC8A07E17_u64),
        peer_node_id: Matter::DataType::NodeId.new(0_u64)
      )

      # Create responder context (keys swapped)
      responder_context = Matter::Session::SecureContext.new(
        session_id: 0x8d4b_u16,
        peer_session_id: 0x351d_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: decrypt_key,
        decryption_key: encrypt_key,
        initiator: false,
        local_node_id: Matter::DataType::NodeId.new(0_u64),
        peer_node_id: Matter::DataType::NodeId.new(0x5261A3CBC8A07E17_u64)
      )

      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16, protocol_id: 1_u16, message_type: 1_u8,
        initiator_message: true, requires_acknowledge: false
      )

      # Test payload
      payload = "Test Matter Protocol Message".to_slice

      encoded, counter = Matter::Session::SecureMessage.encode(initiator_context, payload_header, payload, crypto: crypto)
      counter.should eq(initiator_context.local_message_counter)
      packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded)
      decrypted = Matter::Session::SecureMessage.decode(responder_context, packet, crypto).payload

      decrypted.should eq(payload)
      String.new(decrypted).should eq("Test Matter Protocol Message")
    end

    it "uses correct nonce format" do
      # Test nonce construction matches matter.js
      source_node_id = 0x5261A3CBC8A07E17_u64
      message_counter = 12519906_u32
      security_flags = 0x00_u8

      nonce = Matter::Session::SecureMessage.build_nonce(
        source_node_id,
        message_counter,
        security_flags
      )

      # Verify nonce is 13 bytes
      nonce.size.should eq(13)

      # matter.js format: security_flags (1) | message_counter (4) | source_node_id (8)
      # Verify security flags
      nonce[0].should eq(security_flags)

      # Verify message counter (little-endian)
      IO::ByteFormat::LittleEndian.decode(UInt32, nonce[1, 4]).should eq(message_counter)

      # Verify source node ID (little-endian)
      IO::ByteFormat::LittleEndian.decode(UInt64, nonce[5, 8]).should eq(source_node_id)
    end

    it "increments message counter correctly" do
      context = Matter::Session::SecureContext.new(
        session_id: 1_u16,
        peer_session_id: 2_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: Bytes.new(16),
        decryption_key: Bytes.new(16)
      )

      # Get sequential counters
      counters = Array(UInt32).new
      5.times do
        counters << context.next_message_counter
      end

      # Verify they increment sequentially (starts at random value)
      4.times do |i|
        counters[i + 1].should eq(counters[i] + 1)
      end
      context.local_message_counter.should eq(counters.last)
    end
  end
end
