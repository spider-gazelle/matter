require "../spec_helper"
require "../../src/matter/transport/udp_transport"

describe Matter::Transport::UDPTransport do
  describe "#initialize" do
    it "creates transport on default port" do
      transport = Matter::Transport::UDPTransport.new
      transport.port.should eq(Matter::Transport::UDPTransport::MATTER_PORT)
      transport.close
    end

    it "creates transport on custom port" do
      transport = Matter::Transport::UDPTransport.new(port: 15540)
      transport.port.should eq(15540)
      transport.close
    end

    it "initializes message counter" do
      transport = Matter::Transport::UDPTransport.new(port: 15541)
      transport.message_counter.should_not be_nil
      transport.close
    end

    it "initializes exchange manager" do
      transport = Matter::Transport::UDPTransport.new(port: 15542)
      transport.exchange_manager.should_not be_nil
      transport.close
    end
  end

  describe "message counter integration" do
    it "assigns message IDs automatically" do
      transport = Matter::Transport::UDPTransport.new(port: 15543)

      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 100_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 0_u32, # Zero - should be assigned
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        security_flags: 0_u8
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

      peer_address = Socket::IPAddress.new("127.0.0.1", 5540)

      # Message counter should start at 0
      initial_counter = transport.message_counter.counter

      transport.send_message(message, peer_address, nil)

      # Counter should have incremented
      transport.message_counter.counter.should eq(initial_counter + 1)

      transport.close
    end

    it "increments counter for each message sent" do
      transport = Matter::Transport::UDPTransport.new(port: 15544)
      peer_address = Socket::IPAddress.new("127.0.0.1", 5540)

      initial_counter = transport.message_counter.counter

      # Send 3 messages
      3.times do |i|
        packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
          session_id: 100_u16,
          session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
          message_id: 0_u32,
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          security_flags: 0_u8
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
          payload: Bytes[i.to_u8]
        )

        transport.send_message(message, peer_address, nil)
      end

      transport.message_counter.counter.should eq(initial_counter + 3)

      transport.close
    end
  end

  describe "#send_request" do
    it "creates new exchange and sends message" do
      transport = Matter::Transport::UDPTransport.new(port: 15545)
      peer_address = Socket::IPAddress.new("127.0.0.1", 5540)

      exchange = transport.send_request(
        protocol_id: 0_u16,
        message_type: 1_u8,
        payload: Bytes[0x01, 0x02],
        session_id: 100_u16,
        peer_address: peer_address,
        requires_ack: false
      )

      exchange.should_not be_nil
      exchange.initiator?.should be_true
      exchange.protocol_id.should eq(0_u16)
      exchange.peer_address.should eq(peer_address)

      transport.close
    end

    it "increments message counter" do
      transport = Matter::Transport::UDPTransport.new(port: 15546)
      peer_address = Socket::IPAddress.new("127.0.0.1", 5540)

      initial_counter = transport.message_counter.counter

      transport.send_request(
        protocol_id: 0_u16,
        message_type: 1_u8,
        payload: Bytes[0x01],
        session_id: 100_u16,
        peer_address: peer_address,
        requires_ack: false
      )

      transport.message_counter.counter.should eq(initial_counter + 1)

      transport.close
    end
  end

  describe "exchange management" do
    it "creates exchanges for requests" do
      transport = Matter::Transport::UDPTransport.new(port: 15547)
      peer_address = Socket::IPAddress.new("127.0.0.1", 5540)

      initial_count = transport.exchange_manager.active_count

      exchange = transport.send_request(
        protocol_id: 0_u16,
        message_type: 1_u8,
        payload: Bytes[0x01],
        session_id: 100_u16,
        peer_address: peer_address,
        requires_ack: false
      )

      transport.exchange_manager.active_count.should eq(initial_count + 1)

      transport.close
    end

    it "stores pending messages for retransmission" do
      transport = Matter::Transport::UDPTransport.new(port: 15548)
      peer_address = Socket::IPAddress.new("127.0.0.1", 5540)

      exchange = transport.send_request(
        protocol_id: 0_u16,
        message_type: 1_u8,
        payload: Bytes[0x01],
        session_id: 100_u16,
        peer_address: peer_address,
        requires_ack: true # Requires ACK - will be stored for retransmission
      )

      exchange.should_not be_nil

      transport.close
    end
  end

  describe "#send_raw" do
    it "sends raw bytes" do
      transport = Matter::Transport::UDPTransport.new(port: 15549)
      peer_address = Socket::IPAddress.new("127.0.0.1", 5540)

      data = Bytes[0x01, 0x02, 0x03, 0x04]

      # Should not raise
      transport.send_raw(data, peer_address)

      transport.close
    end
  end

  describe "#close" do
    it "closes both sockets" do
      transport = Matter::Transport::UDPTransport.new(port: 15550)

      transport.close

      transport.socket_ipv4.closed?.should be_true
      transport.socket_ipv6.closed?.should be_true
    end

    it "can be called multiple times safely" do
      transport = Matter::Transport::UDPTransport.new(port: 15551)

      transport.close
      transport.close # Should not raise

      transport.socket_ipv4.closed?.should be_true
      transport.socket_ipv6.closed?.should be_true
    end
  end
end
