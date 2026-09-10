require "../spec_helper"
require "../../src/matter/session/context"
require "../../src/matter/session/secure_message"
require "../../src/matter/crypto/crypto"

describe Matter::Session do
  describe "SecureContext" do
    it "creates a secure session context" do
      encryption_key = Bytes.new(16, 1_u8)
      decryption_key = Bytes.new(16, 2_u8)

      context = Matter::Session::SecureContext.new(
        session_id: 1000_u16,
        peer_session_id: 2000_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: encryption_key,
        decryption_key: decryption_key,
        initiator: true
      )

      context.session_id.should eq(1000_u16)
      context.peer_session_id.should eq(2000_u16)
      context.session_type.should eq(Matter::Session::SessionType::Unicast)
      context.initiator?.should be_true
      # Counter should be initialized to a random value (not 0)
      context.local_message_counter.should be_a(UInt32)
      context.peer_message_counter.should be_nil
    end

    it "increments message counter" do
      context = Matter::Session::SecureContext.new(
        session_id: 1_u16,
        peer_session_id: 2_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: Bytes.new(16),
        decryption_key: Bytes.new(16)
      )

      counter1 = context.next_message_counter
      counter2 = context.next_message_counter
      counter3 = context.next_message_counter

      # Counter should increment by 1 each time (starts at random value)
      counter2.should eq(counter1 + 1)
      counter3.should eq(counter2 + 1)
      context.local_message_counter.should eq(counter3)
    end

    it "validates message counters for replay protection" do
      context = Matter::Session::SecureContext.new(
        session_id: 1_u16,
        peer_session_id: 2_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: Bytes.new(16),
        decryption_key: Bytes.new(16)
      )

      # First message
      context.check_peer_message_counter(100_u32).accept?.should be_true
      context.accept_peer_message_counter(100_u32)
      context.peer_message_counter.should eq(100_u32)

      # Second message with higher counter (valid)
      context.check_peer_message_counter(101_u32).accept?.should be_true
      context.accept_peer_message_counter(101_u32)
      context.peer_message_counter.should eq(101_u32)

      # Replay attempt with same counter (invalid)
      context.check_peer_message_counter(101_u32).duplicate?.should be_true

      # Reordered datagram within the receive window
      context.check_peer_message_counter(50_u32).accept?.should be_true
      context.accept_peer_message_counter(50_u32)

      # Valid next message
      context.check_peer_message_counter(200_u32).accept?.should be_true
      context.accept_peer_message_counter(200_u32)
      context.peer_message_counter.should eq(200_u32)
    end

    it "detects session expiration" do
      context = Matter::Session::SecureContext.new(
        session_id: 1_u16,
        peer_session_id: 2_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: Bytes.new(16),
        decryption_key: Bytes.new(16)
      )

      # Fresh session should not be expired
      context.expired?(5.minutes).should be_false

      # Simulate old session by setting last_activity_time
      context.last_activity_time = Time.utc - 10.minutes
      context.expired?(5.minutes).should be_true
    end
  end
end
