require "../spec_helper"
require "../../src/matter/session/secure_message"
require "../../src/matter/codec/message_codec"

# Nonce and AAD vectors captured from iPhone (Apple Home) commissioning logs.
# Raw packet: 00f17f00b3aeaf0b... = flags 0x00, session 0x7FF1, security 0x00,
# counter 0x0BAFAEB3, followed by the encrypted payload.
describe "iPhone PASE nonce and AAD vectors" do
  session_id = 32753_u16
  message_counter = 196062899_u32

  security_flags = 0x00_u8
  pase_initiator_node_id = 0xFFFFFFFB00000001_u64

  it "builds the nonce logged by the iPhone session" do
    nonce = Matter::Session::SecureMessage.build_nonce(pase_initiator_node_id, message_counter, security_flags)
    nonce.hexstring.should eq("00b3aeaf0b01000000fbffffff")
  end

  it "builds the AAD (packet header) logged by the iPhone session" do
    packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
      session_id: session_id,
      session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
      message_id: message_counter,
      privacy_enhancements: false,
      control_message: false,
      message_extensions: false,
    )

    aad_io = IO::Memory.new
    Matter::Codec::MessageCodec::Base.encode_packet_header(packet_header, aad_io)
    aad_io.to_slice.hexstring.should eq("00f17f00b3aeaf0b")
  end
end
