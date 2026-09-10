require "../spec_helper"
require "../../src/matter/controller/client"

class ReplaySpecClient < Matter::Controller::Client
  def receive_for_spec(message : Matter::Codec::MessageCodec::Message, peer : Socket::IPAddress)
    handle_transport_message(message, peer)
  end
end

describe Matter::Controller::Client do
  it "resends the same encrypted ACK for duplicate messages without advancing its outgoing counter" do
    require_udp_sockets!
    client = ReplaySpecClient.new
    peer = UDPSocket.new(Socket::Family::INET6)
    peer.bind("::1", 0)
    peer.read_timeout = 1.second
    session = Matter::Session::SecureContext.new(
      session_id: 1_u16, peer_session_id: 1_u16,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: Bytes.new(16, 1_u8), decryption_key: Bytes.new(16, 1_u8)
    )
    client.register_session(session)
    header = Matter::Codec::MessageCodec::PayloadHeader.new(
      exchange_id: 1_u16, protocol_id: 1_u16, message_type: 1_u8,
      initiator_message: false, requires_acknowledge: true
    )
    bytes, _ = Matter::Session::SecureMessage.encode(session, header, Bytes[1], message_counter: 1_u32)
    packet = Matter::Codec::MessageCodec::Base.decode_packet(bytes)
    message = Matter::Codec::MessageCodec::Message.new(packet.header, header, packet.payload, packet.header_bytes)
    client.receive_for_spec(message, peer.local_address)
    received = client.wait_for(1_u16, 1_u16, 1_u8, 1.second)
    received.should_not be_nil
    first_ack, _ = peer.receive
    counter = session.local_message_counter

    client.receive_for_spec(message, peer.local_address)
    repeated_ack, _ = peer.receive
    repeated_ack.should eq(first_ack)
    session.local_message_counter.should eq(counter)
    client.wait_for(1_u16, 1_u16, 1_u8, 1.millisecond).should be_nil
  ensure
    client.try(&.close)
    peer.try(&.close)
  end
end
