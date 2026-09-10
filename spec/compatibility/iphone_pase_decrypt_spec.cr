require "../spec_helper"
require "../../src/matter/session/context"
require "../../src/matter/session/secure_message"
require "../../src/matter/codec/message_codec"
require "../../src/matter/crypto/crypto"

# Golden vector captured from a real iPhone (Apple Home) commissioning session
# on 2025-11-14: an encrypted PASE-session IM message received by the device.
describe "iPhone PASE message decryption" do
  it "decrypts an encrypted message captured from a real iPhone commissioning" do
    crypto = Matter::Crypto::StandardCrypto.new

    session_id = 35329_u16
    peer_session_id = 59585_u16
    message_counter = 180049233_u32

    # Session keys derived during PASE
    decryption_key = "3da75aff02ed62359a8e6f4ef34cc5f8".hexbytes
    encryption_key = "df62a4b6885cf9f6809a3008468ef3ea".hexbytes

    # Raw packet was 00dd50008f31630d || encrypted payload (ciphertext + MIC)
    encrypted_payload = "b834e9935d0fc1f8fbb2ff22cc3786ff4db90dcaa7116425d2ccbb288e011631a3af32abab73ed5df364d1".hexbytes
    expected_plaintext = "050243df01001536001724020024031d2404031818290324ff0c18".hexbytes
    encrypted_payload.size.should eq(expected_plaintext.size + Matter::Session::SecureMessage::MIC_LENGTH)

    security_flags = 0x00_u8

    packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
      session_id: session_id,
      session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
      message_id: message_counter,
      privacy_enhancements: false,
      control_message: false,
      message_extensions: false,
    )

    # We are the responder
    context = Matter::Session::SecureContext.new(
      session_id: session_id,
      peer_session_id: peer_session_id,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: encryption_key,
      decryption_key: decryption_key,
      initiator: false
    )

    # Nonce construction with the PASE temporary initiator node ID
    pase_initiator_node_id = 0xFFFFFFFB00000001_u64
    nonce = Matter::Session::SecureMessage.build_nonce(pase_initiator_node_id, message_counter, security_flags)
    nonce.hexstring.should eq("005155bb0a01000000fbffffff")

    # AAD is the encoded (unencrypted) packet header
    aad_io = IO::Memory.new
    Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, aad_io)
    aad_io.to_slice.hexstring.should eq("00018a005155bb0a")

    packet = Matter::Codec::MessageCodec::Packet.new(packet_header, encrypted_payload, aad_io.to_slice)
    message = Matter::Session::SecureMessage.decode(context, packet, crypto)
    decrypted = Matter::Codec::MessageCodec::Base.encode_payload(message).payload

    decrypted.should eq(expected_plaintext)
  end
end
