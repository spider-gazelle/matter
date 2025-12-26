require "./spec_helper"
require "../src/matter/session/secure_message"
require "../src/matter/codec/message_codec"
require "../src/matter/datatype/node_id"

describe "AAD and Nonce Generation - matter.js Compatibility" do
  describe "Nonce generation" do
    it "builds nonce in correct Matter format" do
      # Test vectors from matter.js behavior
      source_node_id = 0x0000000000000000_u64 # UNSPECIFIED_NODE_ID (for PASE)
      message_counter = 0x00000001_u32
      security_flags = 0x00_u8 # Unicast session

      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      # Expected: security_flags (1) + message_counter (4 LE) + source_node_id (8 LE)
      # 00 | 01 00 00 00 | 00 00 00 00 00 00 00 00
      expected = Bytes[0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

      nonce.should eq expected
      nonce.size.should eq 13
    end

    it "builds nonce for non-zero node ID" do
      source_node_id = 0x0123456789ABCDEF_u64
      message_counter = 0x12345678_u32
      security_flags = 0x00_u8

      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      # Expected (all little-endian):
      # 00 | 78 56 34 12 | EF CD AB 89 67 45 23 01
      expected = Bytes[0x00, 0x78, 0x56, 0x34, 0x12, 0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]

      nonce.should eq expected
    end

    it "includes security_flags in nonce byte 0" do
      source_node_id = 0_u64
      message_counter = 1_u32
      security_flags = 0x05_u8 # Some flags set

      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      nonce[0].should eq 0x05
    end
  end

  describe "AAD (Additional Authenticated Data) generation" do
    it "builds AAD from encoded packet header for PASE message" do
      # Simulating a PASE ReadResponse packet header (no node IDs)
      # This matches what matter.js does: AAD = headerBytes

      # Build packet header
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x1234_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 0x00000001_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: 0x00_u8,
        security_flags: 0x00_u8,
        source_node_id: nil, # PASE doesn't include node IDs
        destination_node_id: nil,
        destination_group_id: nil
      )

      # Encode packet header (like matter.js does)
      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      packet_header_bytes = io.rewind.to_slice

      # AAD should be the entire packet header bytes
      # Expected format (8 bytes for PASE without node IDs):
      # flags (1) | session_id (2 LE) | security_flags (1) | message_id (4 LE)
      # 00 | 34 12 | 00 | 01 00 00 00
      expected_aad = Bytes[0x00, 0x34, 0x12, 0x00, 0x01, 0x00, 0x00, 0x00]

      packet_header_bytes.should eq expected_aad
      packet_header_bytes.size.should eq 8
    end

    it "builds AAD from encoded packet header with source node ID" do
      # CASE message with source_node_id
      source_node_id = Matter::DataType::NodeId.new(0x0123456789ABCDEF_u64)

      # Compute flags for header with source_node_id
      flags = Matter::Codec::MessageCodec::Base.compute_flags(source_node_id, nil, nil)

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x5678_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 0x00000002_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: flags,
        security_flags: 0x00_u8,
        source_node_id: source_node_id,
        destination_node_id: nil,
        destination_group_id: nil
      )

      # Encode packet header
      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      packet_header_bytes = io.rewind.to_slice

      # Expected format (16 bytes with source_node_id):
      # flags (1) | session_id (2 LE) | security_flags (1) | message_id (4 LE) | source_node_id (8 LE)
      # Flags byte should have bit 2 set (HasSourceNodeId)
      packet_header_bytes[0].should eq(flags)                                                    # Verify flags byte
      packet_header_bytes[1..2].should eq Bytes[0x78, 0x56]                                      # session_id LE
      packet_header_bytes[3].should eq 0x00                                                      # security_flags
      packet_header_bytes[4..7].should eq Bytes[0x02, 0x00, 0x00, 0x00]                          # message_id LE
      packet_header_bytes[8..15].should eq Bytes[0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01] # source_node_id LE

      packet_header_bytes.size.should eq 16
    end

    it "extracts security_flags from encoded header byte 3" do
      # This is critical - matter.js does: const securityFlags = headerBytes[3]

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0xABCD_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 0x12345678_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: 0x00_u8,
        security_flags: 0x05_u8, # Test with non-zero value
        source_node_id: nil,
        destination_node_id: nil,
        destination_group_id: nil
      )

      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      packet_header_bytes = io.rewind.to_slice

      # Byte 3 should contain security_flags
      packet_header_bytes[3].should eq 0x05
    end
  end

  describe "Full encryption flow like matter.js" do
    it "matches matter.js encode() method AAD and nonce construction" do
      # Simulate how matter.js NodeSession.encode() works:
      # 1. Build packet header
      # 2. Encode packet header to bytes
      # 3. Extract security_flags from headerBytes[3]
      # 4. Build nonce from (security_flags, message_id, source_node_id)
      # 5. Encrypt with (key, payload, nonce, headerBytes as AAD)

      # Setup
      peer_session_id = 0x5678_u16
      message_counter = 0x00000003_u32
      source_node_id = 0_u64 # PASE uses UNSPECIFIED

      # Step 1: Build packet header (matching matter.js)
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: peer_session_id, # Matter sends with peer's session ID
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: message_counter,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: 0x00_u8,
        security_flags: 0x00_u8,
        source_node_id: nil,
        destination_node_id: nil,
        destination_group_id: nil
      )

      # Step 2: Encode packet header (becomes AAD)
      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      header_bytes = io.rewind.to_slice

      # Step 3: Extract security_flags (like matter.js)
      security_flags = header_bytes[3]

      # Step 4: Build nonce (like matter.js Session.generateNonce)
      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      # Verify values
      security_flags.should eq 0x00
      nonce.should eq Bytes[0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
      header_bytes.should eq Bytes[0x00, 0x78, 0x56, 0x00, 0x03, 0x00, 0x00, 0x00]

      # AAD is the full header_bytes
      aad = header_bytes
      aad.size.should eq 8

      # This is exactly how matter.js does it!
      # const encrypted = this.#crypto.encrypt(this.#encryptKey, applicationPayload, nonce, headerBytes);
    end
  end

  describe "Security flags encoding" do
    it "encodes session type in bits 0-1 of security_flags" do
      # Session type should be in the bottom 2 bits of security_flags byte

      # Unicast = 0
      unicast_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x1234_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: 0x00_u8,
        security_flags: 0x00_u8,
        source_node_id: nil,
        destination_node_id: nil
      )

      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(unicast_header, io)
      header_bytes = io.rewind.to_slice

      # Bits 0-1 of security_flags (byte 3) should be 0b00
      (header_bytes[3] & 0x03).should eq 0x00

      # Group = 1
      group_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x1234_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Group,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: 0x00_u8,
        security_flags: 0x01_u8,
        source_node_id: nil,
        destination_node_id: nil,
        destination_group_id: Matter::DataType::GroupId.new(0x1111_u16)
      )

      io2 = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(group_header, io2)
      header_bytes2 = io2.rewind.to_slice

      # Bits 0-1 of security_flags (byte 3) should be 0b01
      (header_bytes2[3] & 0x03).should eq 0x01
    end
  end
end
