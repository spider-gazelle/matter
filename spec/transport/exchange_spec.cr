require "../spec_helper"
require "../../src/matter/transport/exchange"

describe Matter::Transport::Exchange do
  describe "#initialize" do
    it "creates active exchange" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      exchange.exchange_id.should eq(1_u16)
      exchange.protocol_id.should eq(0_u16)
      exchange.session_id.should eq(100_u16)
      exchange.initiator?.should be_true
      exchange.state.should eq(Matter::Transport::Exchange::State::Active)
    end

    it "stores peer information" do
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)
      peer_node_id = Matter::DataType::NodeId.new(12345_u64)

      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: false,
        peer_address: peer_address,
        peer_node_id: peer_node_id
      )

      exchange.peer_address.should eq(peer_address)
      exchange.peer_node_id.should eq(peer_node_id)
      exchange.initiator?.should be_false
    end
  end

  describe "#close" do
    it "marks exchange as closed" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      exchange.close

      exchange.state.should eq(Matter::Transport::Exchange::State::Closed)
    end

    it "clears pending message" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      # Create a mock message
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 100_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false
      )
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        message_type: 1_u8,
        initiator_message: true,
        requires_acknowledge: true
      )
      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: Bytes.new(0)
      )

      exchange.set_pending_message(message)
      exchange.close

      exchange.needs_retransmit?.should be_nil
    end
  end

  describe "#fail" do
    it "marks exchange as failed" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      exchange.fail

      exchange.state.should eq(Matter::Transport::Exchange::State::Failed)
    end
  end

  describe "retransmission logic" do
    it "does not retransmit immediately" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      # Create and set pending message
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 100_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false
      )
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        message_type: 1_u8,
        initiator_message: true,
        requires_acknowledge: true
      )
      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: Bytes.new(0)
      )

      exchange.set_pending_message(message)

      # Should not need retransmit immediately
      exchange.needs_retransmit?.should be_nil
    end

    it "retransmits after timeout" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      # Create and set pending message
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 100_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false
      )
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        message_type: 1_u8,
        initiator_message: true,
        requires_acknowledge: true
      )
      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: Bytes.new(0)
      )

      exchange.set_pending_message(message)

      # Wait for timeout (200ms base timeout)
      sleep 250.milliseconds

      # Should need retransmit now
      retransmit_msg = exchange.needs_retransmit?
      retransmit_msg.should_not be_nil
      retransmit_msg.not_nil!.packet_header.message_id.should eq(1_u32)
    end

    it "clears pending message on acknowledgment" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      # Create and set pending message
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 100_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false
      )
      payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        message_type: 1_u8,
        initiator_message: true,
        requires_acknowledge: true
      )
      message = Matter::Codec::MessageCodec::Message.new(
        packet_header: packet_header,
        payload_header: payload_header,
        payload: Bytes.new(0)
      )

      exchange.set_pending_message(message)
      exchange.clear_pending_message

      # Even after timeout, should not retransmit
      sleep 250.milliseconds
      exchange.needs_retransmit?.should be_nil
    end
  end

  describe "#touch" do
    it "updates activity timestamp" do
      exchange = Matter::Transport::Exchange.new(
        exchange_id: 1_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        initiator: true
      )

      sleep 10.milliseconds
      exchange.touch

      # Activity is recent, so not timed out
      exchange.timed_out?.should be_false
    end
  end
end

describe Matter::Transport::ExchangeManager do
  describe "#create_exchange" do
    it "creates new exchange as initiator" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      exchange = manager.create_exchange(
        protocol_id: 0_u16,
        session_id: 100_u16,
        peer_address: peer_address
      )

      exchange.should_not be_nil
      exchange.initiator?.should be_true
      exchange.protocol_id.should eq(0_u16)
      exchange.session_id.should eq(100_u16)
      exchange.peer_address.should eq(peer_address)
    end

    it "generates unique exchange IDs" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      exchange1 = manager.create_exchange(0_u16, 100_u16, peer_address)
      exchange2 = manager.create_exchange(0_u16, 100_u16, peer_address)
      exchange3 = manager.create_exchange(0_u16, 100_u16, peer_address)

      exchange1.exchange_id.should_not eq(exchange2.exchange_id)
      exchange2.exchange_id.should_not eq(exchange3.exchange_id)
      exchange1.exchange_id.should_not eq(exchange3.exchange_id)
    end
  end

  describe "#get_or_create_exchange" do
    it "creates new exchange if not exists" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      exchange = manager.get_or_create_exchange(
        exchange_id: 42_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        peer_address: peer_address,
        initiator: false
      )

      exchange.exchange_id.should eq(42_u16)
      exchange.initiator?.should be_false
    end

    it "returns existing exchange if found" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      exchange1 = manager.get_or_create_exchange(
        exchange_id: 42_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        peer_address: peer_address
      )

      exchange2 = manager.get_or_create_exchange(
        exchange_id: 42_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        peer_address: peer_address
      )

      exchange1.should be(exchange2) # Same object
    end

    it "updates activity on existing exchange" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      exchange = manager.get_or_create_exchange(
        exchange_id: 42_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        peer_address: peer_address
      )

      sleep 10.milliseconds

      # Get again - should touch the exchange
      manager.get_or_create_exchange(
        exchange_id: 42_u16,
        protocol_id: 0_u16,
        session_id: 100_u16,
        peer_address: peer_address
      )

      exchange.timed_out?.should be_false
    end
  end

  describe "#get_exchange" do
    it "returns exchange if exists" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      created = manager.create_exchange(0_u16, 100_u16, peer_address)
      found = manager.get_exchange(created.exchange_id)

      found.should eq(created)
    end

    it "returns nil if not exists" do
      manager = Matter::Transport::ExchangeManager.new

      found = manager.get_exchange(999_u16)

      found.should be_nil
    end
  end

  describe "#close_exchange" do
    it "closes and removes exchange" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      exchange = manager.create_exchange(0_u16, 100_u16, peer_address)
      manager.close_exchange(exchange.exchange_id)

      manager.get_exchange(exchange.exchange_id).should be_nil
      exchange.state.should eq(Matter::Transport::Exchange::State::Closed)
    end

    it "handles closing non-existent exchange" do
      manager = Matter::Transport::ExchangeManager.new

      # Should not raise
      manager.close_exchange(999_u16)
    end
  end

  describe "#active_count" do
    it "counts active exchanges" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      manager.active_count.should eq(0)

      ex1 = manager.create_exchange(0_u16, 100_u16, peer_address)
      manager.active_count.should eq(1)

      ex2 = manager.create_exchange(0_u16, 100_u16, peer_address)
      manager.active_count.should eq(2)

      ex1.close
      manager.active_count.should eq(1)

      ex2.fail
      manager.active_count.should eq(0)
    end
  end

  describe "#cleanup_stale_exchanges" do
    it "removes timed out exchanges" do
      manager = Matter::Transport::ExchangeManager.new
      peer_address = Socket::IPAddress.new("192.168.1.100", 5540)

      exchange = manager.create_exchange(0_u16, 100_u16, peer_address)
      exchange_id = exchange.exchange_id

      # Mark as failed (stale)
      exchange.fail

      manager.cleanup_stale_exchanges

      manager.get_exchange(exchange_id).should be_nil
    end
  end
end
