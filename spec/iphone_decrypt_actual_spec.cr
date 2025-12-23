require "./spec_helper"
require "../src/matter/session/context"
require "../src/matter/session/secure_message"
require "../src/matter/codec/message_codec"
require "../src/matter/crypto/crypto"

# Test with ACTUAL values from iPhone commissioning (2025-11-14 09:37:35)
describe "iPhone Message Decryption - Actual Data" do
  it "decrypts actual iPhone message from real commissioning" do
    crypto = Matter::Crypto::StandardCrypto.new

    # From logs (latest run)
    session_id = 35329_u16          # 0x8A01
    peer_session_id = 59585_u16     # 0xE8C1
    message_counter = 180049233_u32 # 0x0ABB5551

    # Keys derived during PASE
    decryption_key = "3da75aff02ed62359a8e6f4ef34cc5f8".hexbytes
    encryption_key = "df62a4b6885cf9f6809a3008468ef3ea".hexbytes

    # Full raw packet (51 bytes) from logs: 00dd50008f31630d304039f58ab16961f944fd347811d9df...
    # Breaking it down:
    # Bytes 0-7: packet header = 00dd50008f31630d
    # Bytes 8-50: encrypted payload (43 bytes)

    # Full encrypted payload from actual iPhone commissioning (latest run):
    # Session: 35329, Message Counter: 180049233
    encrypted_payload = "b834e9935d0fc1f8fbb2ff22cc3786ff4db90dcaa7116425d2ccbb288e011631a3af32abab73ed5df364d1".hexbytes
    # This is 43 bytes: 27 bytes ciphertext + 16 bytes MIC/tag

    # Build packet header
    flags = 0x00_u8
    security_flags = 0x00_u8

    packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
      session_id: session_id,
      session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
      message_id: message_counter,
      privacy_enhancements: false,
      control_message: false,
      message_extensions: false,
      flags: flags,
      security_flags: security_flags
    )

    # Create responder context
    context = Matter::Session::SecureContext.new(
      session_id: session_id,
      peer_session_id: peer_session_id,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: encryption_key,
      decryption_key: decryption_key,
      is_initiator: false # We're the responder
    )

    # Test nonce construction
    peer_node_id = 0xFFFFFFFB00000001_u64 # PASE temporary initiator node ID
    nonce = Matter::Session::SecureMessage.build_nonce(peer_node_id, message_counter, security_flags)

    puts "\n🔍 Testing iPhone message decryption:"
    puts "  Session ID: #{session_id}"
    puts "  Peer Session ID: #{peer_session_id}"
    puts "  Message Counter: #{message_counter}"
    puts "  Peer Node ID: 0x#{peer_node_id.to_s(16)}"
    puts "  Decryption Key: #{decryption_key.hexstring}"
    puts ""
    puts "  Nonce (computed): #{nonce.hexstring}"
    puts "  Nonce (expected): 005155bb0a01000000fbffffff"
    puts "  Match: #{nonce.hexstring == "005155bb0a01000000fbffffff"}"

    # Verify nonce matches logs
    nonce.hexstring.should eq("005155bb0a01000000fbffffff")

    # Test AAD construction
    aad_io = IO::Memory.new
    aad_io.write_byte(flags)
    IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
    aad_io.write_byte(security_flags)
    IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
    aad = aad_io.to_slice

    puts ""
    puts "  AAD (computed): #{aad.hexstring}"
    puts "  AAD (expected): 00018a005155bb0a"
    puts "  Match: #{aad.hexstring == "00018a005155bb0a"}"

    # Verify AAD matches logs
    aad.hexstring.should eq("00018a005155bb0a")

    puts ""
    puts "  Encrypted payload: #{encrypted_payload.hexstring}"
    puts "  Payload size: #{encrypted_payload.size} bytes (#{encrypted_payload.size - 16} ciphertext + 16 tag)"
    puts ""

    # Now attempt actual decryption
    puts "  Attempting AES-CCM decryption..."

    decrypted = Matter::Session::SecureMessage.decrypt(
      context,
      encrypted_payload,
      message_counter,
      packet_header,
      crypto
    )

    puts "  ✅ Decryption succeeded!"
    puts "  Decrypted payload: #{decrypted.hexstring}"
    puts "  Decrypted size: #{decrypted.size} bytes"

    # The decrypted payload should be a valid IM message
    # First byte should be exchange flags
    decrypted.size.should be > 0
  end
end
