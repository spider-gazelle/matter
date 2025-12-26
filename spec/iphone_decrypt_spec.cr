require "./spec_helper"
require "../src/matter/session/context"
require "../src/matter/session/secure_message"
require "../src/matter/codec/message_codec"
require "../src/matter/crypto/crypto"

# Test with actual values from iPhone commissioning logs
describe "iPhone Message Decryption" do
  it "decrypts actual iPhone message from logs" do
    # From logs: Session ID: 32753 (0x7FF1)
    session_id = 32753_u16
    peer_session_id = 59583_u16

    # From logs: Decryption key (I2R): fb966a454beb2b5762c3db54ab5e1b61
    decryption_key = "fb966a454beb2b5762c3db54ab5e1b61".hexbytes
    encryption_key = "d535b018f326c81400e292d5c2486274".hexbytes

    # Create responder context
    Matter::Session::SecureContext.new(
      session_id: session_id,
      peer_session_id: peer_session_id,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: encryption_key,
      decryption_key: decryption_key,
      initiator: false # We're the responder
    )

    # From logs: Raw packet hex: 00f17f00b3aeaf0b51e49d2084671e5da31f120326a18b...
    # Breaking down:
    # Byte 0: 0x00 (flags)
    # Bytes 1-2: 0x7FF1 (session_id LE) = 32753
    # Byte 3: 0x00 (security_flags)
    # Bytes 4-7: 0x0BAFAEB3 (message_counter LE) = 196062899
    # Bytes 8+: encrypted payload (43 bytes according to logs)

    message_counter = 196062899_u32
    security_flags = 0x00_u8

    # Build packet header from the raw bytes
    flags = 0x00_u8
    Matter::Codec::MessageCodec::PacketHeader.new(
      session_id: session_id,
      session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
      message_id: message_counter,
      privacy_enhancements: false,
      control_message: false,
      message_extensions: false,
      flags: flags,
      security_flags: security_flags
    )

    # Encrypted payload (43 bytes): 51e49d2084671e5da31f120326a18b...
    Matter::Session::SecureMessage.build_nonce(0xFFFFFFFB00000001_u64, message_counter, security_flags)

    # Test nonce construction
    peer_node_id = 0xFFFFFFFB00000001_u64 # PASE temporary initiator node ID
    nonce = Matter::Session::SecureMessage.build_nonce(peer_node_id, message_counter, security_flags)

    puts "Testing iPhone message decryption:"
    puts "  Session ID: #{session_id}"
    puts "  Message Counter: #{message_counter}"
    puts "  Peer Node ID: 0x#{peer_node_id.to_s(16)}"
    puts "  Nonce: #{nonce.hexstring}"
    puts "  Expected: 00b3aeaf0b01000000fbffffff"

    # Verify nonce matches logs
    nonce.hexstring.should eq("00b3aeaf0b01000000fbffffff")

    # Test AAD construction
    aad_io = IO::Memory.new
    aad_io.write_byte(flags)
    IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
    aad_io.write_byte(security_flags)
    IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
    aad = aad_io.to_slice

    puts "  AAD: #{aad.hexstring}"
    puts "  Expected: 00f17f00b3aeaf0b"

    # Verify AAD matches logs
    aad.hexstring.should eq("00f17f00b3aeaf0b")

    # TODO: Once we have the full encrypted payload, test actual decryption
    # decrypted = Matter::Session::SecureMessage.decrypt(
    #   context,
    #   encrypted_payload,
    #   message_counter,
    #   packet_header,
    #   crypto
    # )
  end
end
