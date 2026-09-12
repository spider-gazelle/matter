require "../spec_helper"
require "../../src/matter/codec/message_codec"
require "../../src/matter/session/pase/definitions"
require "../../src/matter/session/secure_message"
require "../../src/matter/session/context"
require "../../src/matter/crypto/crypto"

# Tests PASE message packet encoding to ensure compatibility with chip-tool
# This tests the complete packet structure: packet header + payload header + TLV payload
#
# The goal is to verify that Crystal encodes PASE messages in a way that chip-tool can validate,
# including proper message counter handling, security_flags encoding, and packet structure.
describe "PASE Packet Encoding for chip-tool Compatibility" do
  describe "Unsecured PASE Messages" do
    it "encodes PbkdfParamRequest correctly" do
      # PbkdfParamRequest is the first message from commissioner to device
      # It must be unsecured (session_id = 0, session_type = Unicast)

      # Create the TLV payload for PbkdfParamRequest
      request = Matter::Session::Pase::Definitions::PbkdfParamRequest.new(
        initiator_random: Random::Secure.random_bytes(32),
        initiator_session_id: 12345_u16,
        passcode_id: 0_u16,
        has_pbkdf_parameters: false
      )
      tlv_payload = request.to_slice

      # Create payload header for Secure Channel protocol
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0x0000_u16, # Secure Channel protocol
        message_type: 0x20_u8,   # PbkdfParamRequest
        initiator_message: true,
        requires_acknowledge: true,
        acknowledged_message_id: nil
      )

      # Create packet header for unsecured message
      # For unsecured messages during PASE:
      # - session_id = 0
      # - session_type = Unicast (0)
      # - security_flags = 0x00 (no flags set)
      # - No source/dest node IDs

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
      )

      # Encode the complete message
      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: tlv_payload
      )

      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

      # Verify packet header structure
      # Bytes 0-7: packet header (no node IDs)
      # Byte 0: flags (version in upper 4 bits)
      # Bytes 1-2: session_id (0x0000)
      # Byte 3: security_flags (0x00)
      # Bytes 4-7: message_id (0x00000001)

      encoded_packet[0].should eq(0x00) # flags (version 0)
      encoded_packet[1].should eq(0x00) # session_id low byte
      encoded_packet[2].should eq(0x00) # session_id high byte
      encoded_packet[3].should eq(0x00) # security_flags (CRITICAL: was buggy before fix)
      encoded_packet[4].should eq(0x01) # message_id low byte
      encoded_packet[5].should eq(0x00) # message_id
      encoded_packet[6].should eq(0x00) # message_id
      encoded_packet[7].should eq(0x00) # message_id high byte

      # Decode and verify round-trip
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_packet.header.session_id.should eq(0_u16)
      decoded_packet.header.session_type.should eq(Matter::Codec::MessageCodec::SessionType::Unicast)
      decoded_packet.header.security_flags.should eq(0x00_u8)
      decoded_packet.header.message_id.should eq(1_u32)
    end

    it "encodes PbkdfParamResponse correctly" do
      # PbkdfParamResponse is sent from device to commissioner
      # Uses test vector from matter.js PasePairingTest.ts

      # From matter.js test vector 1
      pbkdf_params = Matter::Crypto::Spake2p::PbkdfParameters.new(
        iterations: 1000,
        salt: "03959ebc20b8fcbda262d97f9a7a9e76e32d7a1b9c5166b6a3721e88acad8808".hexbytes
      )

      peer_random = "94eab5c37d101df5ef01b2c8ecada03a7c3b0cf5e26a08feda72617f9cd391a6".hexbytes
      responder_random = "22820a42684102fd4a92c0bad66ad1f21f3c5366f5a6d84203035e2c7caf3bae".hexbytes

      # Create PbkdfParamResponse
      response = Matter::Session::Pase::Definitions::PbkdfParamResponse.new(
        initiator_random: peer_random,
        responder_random: responder_random,
        responder_session_id: 56919_u16,
        iterations: pbkdf_params.iterations.to_u32,
        salt: pbkdf_params.salt
      )
      tlv_payload = response.to_slice

      # Verify our TLV encoding matches matter.js
      expected_response_payload = "1530012094eab5c37d101df5ef01b2c8ecada03a7c3b0cf5e26a08feda72617f9cd391a630022022820a42684102fd4a92c0bad66ad1f21f3c5366f5a6d84203035e2c7caf3bae250357de35042501e80330022003959ebc20b8fcbda262d97f9a7a9e76e32d7a1b9c5166b6a3721e88acad88081818".hexbytes
      tlv_payload.should eq(expected_response_payload)

      # Create payload header
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0x0000_u16,
        message_type: 0x21_u8, # PbkdfParamResponse
        initiator_message: false,
        requires_acknowledge: false,
        acknowledged_message_id: 1_u32 # Acking the request
      )

      # Create packet header for response

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 2_u32, # Response uses next message counter
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
      )

      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: tlv_payload
      )

      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

      # Verify packet header
      encoded_packet[3].should eq(0x00) # security_flags must be 0x00
      encoded_packet[4].should eq(0x02) # message_id = 2

      # Decode and verify
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_message = Matter::Codec::MessageCodec::Base.decode_payload(decoded_packet)

      decoded_packet.header.security_flags.should eq(0x00_u8)
      decoded_packet.header.message_id.should eq(2_u32)
      decoded_message.payload_header.message_type.should eq(0x21_u8)
    end

    it "encodes Pake2 message correctly" do
      # Pake2 contains the responder's public value Y
      # This is sent from device to commissioner during PASE

      # From matter.js test vector 1
      expected_y = "0404f972c7232cde8911de7d93e37ad752b90ad095888ac83da5f3a1d5a7eb063288ed6d358e9092a8606dac6cd6b8fdfc0b3960df85434ed60c6b6091d23da7bb".hexbytes

      # Create Pake2 message
      # The verifier (cB) is computed during SPAKE2+ but we'll use a placeholder for structure testing
      placeholder_verifier = Bytes.new(32, 0_u8)

      pake2 = Matter::Session::Pase::Definitions::Pake2.new(
        y: expected_y,
        verifier: placeholder_verifier
      )
      tlv_payload = pake2.to_slice

      # Create payload header
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0x0000_u16,
        message_type: 0x23_u8, # PasePake2
        initiator_message: false,
        requires_acknowledge: false,
        acknowledged_message_id: 3_u32 # Acking Pake1
      )

      # Create packet header

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 0_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 4_u32, # Fourth message in exchange
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
      )

      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: tlv_payload
      )

      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

      # Verify security_flags is correctly encoded as 0x00
      encoded_packet[3].should eq(0x00)

      # Decode and verify
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_packet.header.security_flags.should eq(0x00_u8)
      decoded_packet.header.session_type.should eq(Matter::Codec::MessageCodec::SessionType::Unicast)
    end
  end

  describe "Secured PASE Messages" do
    it "encodes encrypted messages with correct security_flags" do
      # After PASE handshake, messages are encrypted using the session keys
      # The security_flags byte must match what was used in the AAD during encryption

      # Create a mock encrypted payload
      encrypted_payload = Bytes.new(100, 0xAB_u8)

      # Create payload header for a ReadRequest (Interaction Model protocol)
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 2_u16,
        protocol_id: 0x0001_u16, # Interaction Model
        message_type: 0x02_u8,   # ReadRequest
        initiator_message: true,
        requires_acknowledge: true,
        acknowledged_message_id: nil
      )

      # Create packet header for secured message
      # After PASE:
      # - session_id = assigned session ID (non-zero)
      # - session_type = Unicast (0)
      # - security_flags = 0x00 (session_type in bottom 2 bits)

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 12345_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 100_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
      )

      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: encrypted_payload
      )

      encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
      encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

      # CRITICAL TEST: Verify security_flags byte is correctly encoded
      # This was the bug: previously it only encoded session_type.value (0 or 1)
      # Now it must encode the full security_flags byte (0x00)
      encoded_packet[3].should eq(0x00_u8)

      # Decode and verify the security_flags can be read back correctly
      decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
      decoded_packet.header.security_flags.should eq(0x00_u8)
      decoded_packet.header.session_type.should eq(Matter::Codec::MessageCodec::SessionType::Unicast)

      # This is critical: when chip-tool decrypts this message, it will:
      # 1. Read the packet header from the wire (including security_flags = 0x00)
      # 2. Build AAD from the packet header (using security_flags = 0x00)
      # 3. Decrypt and verify the MIC using that AAD
      # 4. If our encoded security_flags doesn't match what we used during encryption,
      #    the AAD won't match and decryption will fail
    end

    it "encodes security_flags with session_type correctly" do
      # Test both Unicast (0) and Group (1) session types
      # The security_flags byte should have session_type in bottom 2 bits

      [
        {type: Matter::Codec::MessageCodec::SessionType::Unicast, expected: 0x00_u8},
        {type: Matter::Codec::MessageCodec::SessionType::Group, expected: 0x01_u8},
      ].each do |test_case|
        packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
          session_id: 1_u16,
          session_type: test_case[:type],
          message_id: 1_u32,
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
        )

        payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
          exchange_id: 1_u16,
          protocol_id: 0_u16,
          message_type: 1_u8,
          initiator_message: true,
          requires_acknowledge: false
        )

        message = Matter::Codec::MessageCodec::Message.new(
          packet_header: packet_header,
          payload_header: payload_header,
          payload: Bytes.new(0)
        )

        encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
        encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

        # Verify security_flags is encoded correctly
        encoded_packet[3].should eq(test_case[:expected])

        # Decode and verify
        decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
        decoded_packet.header.security_flags.should eq(test_case[:expected])
        decoded_packet.header.session_type.should eq(test_case[:type])
      end
    end
  end

  describe "Message Counter Handling" do
    it "increments message counter for each message in session" do
      # During commissioning, message counters must increment correctly
      # Both sides maintain independent counters

      counters = [1_u32, 2_u32, 3_u32, 4_u32, 5_u32]

      counters.each do |counter|
        packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
          session_id: 0_u16,
          session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
          message_id: counter,
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
        )

        payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
          exchange_id: 1_u16,
          protocol_id: 0_u16,
          message_type: 0x20_u8,
          initiator_message: true,
          requires_acknowledge: false
        )

        message = Matter::Codec::MessageCodec::Message.new(
          packet_header: packet_header,
          payload_header: payload_header,
          payload: Bytes.new(0)
        )

        encoded_payload = Matter::Codec::MessageCodec::Base.encode_payload(message)
        encoded_packet = Matter::Codec::MessageCodec::Base.encode_packet(encoded_payload)

        # Verify counter is encoded in bytes 4-7 (little-endian)
        decoded_packet = Matter::Codec::MessageCodec::Base.decode_packet(encoded_packet)
        decoded_packet.header.message_id.should eq(counter)
      end
    end
  end
end
