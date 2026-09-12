require "../spec_helper"
require "../../src/matter/session/secure_message"
require "../../src/matter/session/context"
require "../../src/matter/codec/message_codec"
require "../../src/matter/crypto/crypto"
require "../../src/matter/datatype/node_id"

describe "ReadCommissioningInfo Response Encryption - matter.js Compatibility" do
  describe "Packet structure for PASE ReadResponse" do
    it "builds packet header correctly for PASE session" do
      # During PASE, responses should have:
      # - peer_session_id (not our session_id)
      # - No source_node_id in header (PASE uses temporary IDs)
      # - security_flags with SessionType::Unicast (0x00)

      session_context = Matter::Session::SecureContext.new(
        session_id: 0x1234_u16,
        peer_session_id: 0x180_u16, # Example from matter.js logs
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: Bytes.new(16, 0xFF_u8),
        decryption_key: Bytes.new(16, 0x00_u8),
        initiator: false # We're the responder
      )

      # Build packet header like send_im_response does
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: session_context.peer_session_id, # Use peer's session ID!
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 0_u32, # Will be set by message counter
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: nil, # PASE doesn't include source node ID in header
        destination_node_id: nil
      )

      packet_header.session_id.should eq 0x180_u16
      packet_header.session_type.value.should eq 0_u8 # Unicast
      packet_header.source_node_id.should be_nil
    end

    it "encodes packet header to correct byte sequence for PASE" do
      # PASE packet header (without node IDs) is 8 bytes:
      # flags (1) | session_id (2 LE) | security_flags (1) | message_id (4 LE)

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x0180_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 0x03863dca_u32, # Example message counter
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: nil,
        destination_node_id: nil
      )

      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      header_bytes = io.rewind.to_slice

      # Expected: 00 | 80 01 | 00 | ca 3d 86 03
      header_bytes.size.should eq 8
      header_bytes[0].should eq 0x00                             # flags
      header_bytes[1..2].should eq Bytes[0x80, 0x01]             # session_id LE
      header_bytes[3].should eq 0x00                             # security_flags
      header_bytes[4..7].should eq Bytes[0xca, 0x3d, 0x86, 0x03] # message_id LE
    end
  end

  describe "Nonce construction for PASE ReadResponse" do
    it "uses node_id=0 (UNSPECIFIED) for PASE sessions" do
      # Matter spec: During PASE, node ID is UNSPECIFIED (0)
      # This matches matter.js: sessionNodeId = this.isPase ? NodeId.UNSPECIFIED_NODE_ID : ...

      source_node_id = 0_u64 # UNSPECIFIED for PASE
      message_counter = 0x03863dca_u32
      security_flags = 0x00_u8

      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      # Expected: 00 | ca 3d 86 03 | 00 00 00 00 00 00 00 00
      nonce.should eq Bytes[0x00, 0xca, 0x3d, 0x86, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    end
  end

  describe "AAD construction for PASE ReadResponse" do
    it "uses full encoded packet header as AAD" do
      # AAD = complete packet header bytes
      # This is CRITICAL - matter.js does: aad = headerBytes
      # NOT manually reconstructed!

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x0180_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 0x03863dca_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: nil,
        destination_node_id: nil
      )

      # Encode to get AAD
      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      aad = io.rewind.to_slice

      aad.size.should eq 8 # PASE header is 8 bytes

      # Verify structure
      aad[0].should eq 0x00                             # flags
      aad[1..2].should eq Bytes[0x80, 0x01]             # session_id
      aad[3].should eq 0x00                             # security_flags (extracted from here)
      aad[4..7].should eq Bytes[0xca, 0x3d, 0x86, 0x03] # message_id
    end
  end

  describe "Full encryption flow for ReadCommissioningInfo response" do
    it "encrypts payload with correct AAD and nonce" do
      # Simulate a ReadCommissioningInfo response encryption

      # Setup session (PASE)
      encryption_key = Bytes[
        0x5e, 0x6d, 0x8f, 0x7a, 0x3b, 0x4c, 0x9e, 0x2f,
        0x1a, 0x8b, 0x6c, 0x5d, 0x9f, 0x4e, 0x3a, 0x7b,
      ]

      session = Matter::Session::SecureContext.new(
        session_id: 0x1234_u16,
        peer_session_id: 0x0180_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: encryption_key,
        decryption_key: Bytes.new(16, 0_u8),
        initiator: false
      )

      # Simulated ReadResponse TLV payload (simplified)
      # This would be the PayloadHeader + TLV-encoded ReadResponse
      application_payload = Bytes[
        # PayloadHeader (simplified)
        0x05, 0x00, 0x00, 0x00, # exchange flags + exchange_id
        0x01, 0x00,             # protocol_id (IM = 0x0001)
        0x05,                   # message_type (ReportData = 0x05)
        # TLV ReadResponse data would follow...
        0x15, 0x36, 0x01, 0x15, # Sample TLV data
      ]

      # Get message counter
      message_counter = session.next_message_counter

      # Build packet header
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: session.peer_session_id,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: message_counter,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: nil,
        destination_node_id: nil
      )

      # Encode packet header (becomes AAD)
      header_io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, header_io)
      header_bytes = header_io.rewind.to_slice

      # Extract security_flags from byte 3 (like matter.js)
      security_flags = header_bytes[3]

      # Build nonce
      source_node_id = 0_u64 # PASE uses UNSPECIFIED
      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      # Encrypt
      crypto = Matter::Crypto::StandardCrypto.new
      encrypted = crypto.encrypt(encryption_key, application_payload, nonce, header_bytes)

      # Verify encryption succeeded
      encrypted.should_not be_nil
      encrypted.size.should eq(application_payload.size + 16) # payload + 16-byte MIC

      # Final UDP packet would be: header_bytes + encrypted
      udp_packet = Bytes.join([header_bytes, encrypted])
      udp_packet.size.should eq(header_bytes.size + encrypted.size)
    end

    it "matches matter.js encryption pattern" do
      # This test verifies the pattern matches matter.js NodeSession.encode():
      # 1. Build packet header
      # 2. Encode packet header to bytes
      # 3. Extract security_flags from headerBytes[3]
      # 4. Build nonce from (security_flags, message_id, source_node_id)
      # 5. AAD = headerBytes (the full encoded header)
      # 6. Encrypt: crypto.encrypt(key, payload, nonce, headerBytes)

      encryption_key = Bytes.new(16, 0x42_u8)
      payload = Bytes[0x01, 0x02, 0x03, 0x04]
      message_counter = 5_u32
      peer_session_id = 0x100_u16

      # Step 1-2: Build and encode packet header
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: peer_session_id,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: message_counter,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: nil,
        destination_node_id: nil
      )

      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      header_bytes = io.rewind.to_slice

      # Step 3: Extract security_flags (matter.js: const securityFlags = headerBytes[3])
      security_flags = header_bytes[3]
      security_flags.should eq 0x00

      # Step 4: Build nonce (matter.js: Session.generateNonce(...))
      source_node_id = 0_u64 # PASE
      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      # Step 5: AAD = headerBytes
      aad = header_bytes

      # Step 6: Encrypt (matter.js: this.#crypto.encrypt(...))
      crypto = Matter::Crypto::StandardCrypto.new
      encrypted = crypto.encrypt(encryption_key, payload, nonce, aad)

      # Verify
      encrypted.size.should eq(payload.size + 16) # MIC is 16 bytes

      # This matches exactly how matter.js does it!
    end
  end

  describe "Real matter.js encryption test vectors" do
    it "validates encryption with captured matter.js ReadResponse vector #1" do
      # Real encryption test vector captured from matter.js during chip-tool commissioning
      # This is the first ReadResponse (ReportData) message sent during commissioning

      # Test vector data
      encryption_key = Bytes[
        0xcb, 0x93, 0x43, 0xcc, 0x93, 0x6e, 0xd4, 0xb5,
        0x51, 0x39, 0x85, 0x54, 0x33, 0xf9, 0x15, 0x33,
      ]

      nonce = Bytes[
        0x00, 0xba, 0x77, 0x87, 0x03, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
      ]

      aad = Bytes[0x00, 0x62, 0x71, 0x00, 0xba, 0x77, 0x87, 0x03]

      # Plaintext payload (first 64 bytes of 210 total)
      # This is PayloadHeader + TLV-encoded ReportData
      plaintext_start = Bytes[
        0x06, 0x05, 0xc3, 0xa6, 0x01, 0x00, 0xc8, 0x39,
        0x9b, 0x07, 0x15, 0x36, 0x01, 0x15, 0x35, 0x01,
        0x26, 0x00, 0xb8, 0x96, 0x44, 0xd3, 0x37, 0x01,
        0x24, 0x02, 0x00, 0x24, 0x03, 0x30, 0x24, 0x04,
        0x04, 0x18, 0x29, 0x02, 0x18, 0x18, 0x15, 0x35,
        0x01, 0x26, 0x00, 0xb8, 0x96, 0x44, 0xd3, 0x37,
        0x01, 0x24, 0x02, 0x00, 0x24, 0x03, 0x30, 0x24,
        0x04, 0x00, 0x18, 0x24, 0x02, 0x00, 0x18, 0x18,
      ]

      # Expected encrypted output (first 64 bytes of 226 = 210 + 16 MIC)
      expected_encrypted_start = Bytes[
        0x8f, 0xb9, 0x73, 0xd9, 0x66, 0x8f, 0x62, 0xc6,
        0x4c, 0x0c, 0x2a, 0x9b, 0x95, 0xda, 0xdd, 0xb0,
        0xb1, 0x0b, 0xc9, 0xca, 0x61, 0xe6, 0x05, 0xcd,
        0xca, 0xbb, 0xd2, 0x2f, 0x52, 0x6f, 0xcd, 0x41,
        0x52, 0xfb, 0x08, 0x86, 0x5e, 0x4f, 0x36, 0x00,
        0x41, 0x30, 0xc7, 0xcb, 0x4b, 0x94, 0x92, 0xa6,
        0xd0, 0xb3, 0x5e, 0xf5, 0x9b, 0x1a, 0xef, 0x69,
        0x79, 0xea, 0x0b, 0x43, 0x62, 0x80, 0xbe, 0xaf,
      ]

      # Encrypt the first 64 bytes to verify our implementation matches
      crypto = Matter::Crypto::StandardCrypto.new
      encrypted = crypto.encrypt(encryption_key, plaintext_start, nonce, aad)

      # Should match matter.js output (payload + 16-byte MIC = 80 bytes)
      encrypted.size.should eq(plaintext_start.size + 16)

      # First 64 bytes of encrypted output should match
      encrypted[0...64].should eq expected_encrypted_start

      # Verify decryption works
      decrypted = crypto.decrypt(encryption_key, encrypted, nonce, aad)
      decrypted.should eq plaintext_start
    end
  end

  describe "Error cases that chip-tool would reject" do
    it "fails if AAD doesn't match packet header" do
      # If we manually build AAD incorrectly, chip-tool will reject it
      encryption_key = Bytes.new(16, 0xFF_u8)
      payload = Bytes[0x01, 0x02]
      message_counter = 1_u32

      # Correct packet header
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x180_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: message_counter,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: nil,
        destination_node_id: nil
      )

      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      correct_aad = io.rewind.to_slice

      # WRONG AAD (manually built with different message_counter)
      wrong_aad_io = IO::Memory.new
      wrong_aad_io.write_byte(0x00_u8)                             # flags
      IO::ByteFormat::LittleEndian.encode(0x180_u16, wrong_aad_io) # session_id
      wrong_aad_io.write_byte(0x00_u8)                             # security_flags
      IO::ByteFormat::LittleEndian.encode(999_u32, wrong_aad_io)   # WRONG message_counter!
      wrong_aad = wrong_aad_io.to_slice

      # Build nonce with correct values
      nonce = Matter::Session::SecureMessage.build_nonce(0_u64, message_counter, 0x00_u8)

      # Encrypt with WRONG AAD
      crypto = Matter::Crypto::StandardCrypto.new
      encrypted_with_wrong_aad = crypto.encrypt(encryption_key, payload, nonce, wrong_aad)

      # Try to decrypt with CORRECT AAD (simulating chip-tool)
      # This should FAIL because AAD doesn't match
      expect_raises(Exception) do
        crypto.decrypt(encryption_key, encrypted_with_wrong_aad, nonce, correct_aad)
      end
    end

    it "fails if nonce uses wrong node_id" do
      encryption_key = Bytes.new(16, 0xAB_u8)
      payload = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      message_counter = 10_u32

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0x200_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: message_counter,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        source_node_id: nil,
        destination_node_id: nil
      )

      io = IO::Memory.new
      Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, io)
      aad = io.rewind.to_slice

      # WRONG: Use non-zero node_id for PASE
      wrong_nonce = Matter::Session::SecureMessage.build_nonce(0x123456_u64, message_counter, 0x00_u8)

      # Correct nonce for PASE
      correct_nonce = Matter::Session::SecureMessage.build_nonce(0_u64, message_counter, 0x00_u8)

      crypto = Matter::Crypto::StandardCrypto.new

      # Encrypt with wrong nonce
      encrypted_with_wrong_nonce = crypto.encrypt(encryption_key, payload, wrong_nonce, aad)

      # Try to decrypt with correct nonce (simulating chip-tool)
      # This should FAIL
      expect_raises(Exception) do
        crypto.decrypt(encryption_key, encrypted_with_wrong_nonce, correct_nonce, aad)
      end
    end
  end
end
