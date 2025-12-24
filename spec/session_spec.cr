require "./spec_helper"
require "../src/matter/session/context"
require "../src/matter/session/secure_message"
require "../src/matter/crypto/crypto"

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
      context.local_message_counter.should eq(counter3 + 1)
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
      context.validate_message_counter(100_u32).should be_true
      context.peer_message_counter.should eq(100_u32)

      # Second message with higher counter (valid)
      context.validate_message_counter(101_u32).should be_true
      context.peer_message_counter.should eq(101_u32)

      # Replay attempt with same counter (invalid)
      context.validate_message_counter(101_u32).should be_false

      # Replay attempt with lower counter (invalid)
      context.validate_message_counter(50_u32).should be_false

      # Valid next message
      context.validate_message_counter(200_u32).should be_true
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

  describe "SecureMessage" do
    crypto = Matter::Crypto::StandardCrypto.new

    it "builds nonce correctly" do
      source_node_id = 0x1234567890ABCDEF_u64
      message_counter = 0x87654321_u32
      security_flags = 0xA5_u8

      nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

      nonce.size.should eq(13)

      # Matter spec format: security_flags (1) | message_counter (4) | source_node_id (8)
      # Verify security flags
      nonce[0].should eq(security_flags)

      # Verify message counter (little-endian)
      IO::ByteFormat::LittleEndian.decode(UInt32, nonce[1, 4]).should eq(message_counter)

      # Verify source node ID (little-endian)
      IO::ByteFormat::LittleEndian.decode(UInt64, nonce[5, 8]).should eq(source_node_id)
    end

    it "encrypts and decrypts messages" do
      key = "abcdef0123456789abcdef0123456789".hexbytes
      payload = "Hello, Matter Protocol!".to_slice
      source_node_id = 0x1122334455667788_u64
      message_counter = 42_u32
      session_id = 100_u16

      # Encrypt
      encrypted = Matter::Session::SecureMessage.encrypt_with_params(
        key,
        payload,
        source_node_id,
        message_counter,
        session_id,
        crypto: crypto
      )

      # Encrypted should be longer (includes MIC/tag)
      encrypted.size.should eq(payload.size + 16)

      # Decrypt
      decrypted = Matter::Session::SecureMessage.decrypt_with_params(
        key,
        encrypted,
        source_node_id,
        message_counter,
        session_id,
        crypto: crypto
      )

      decrypted.should eq(payload)
      String.new(decrypted).should eq("Hello, Matter Protocol!")
    end

    it "fails decryption with wrong key" do
      key1 = "abcdef0123456789abcdef0123456789".hexbytes
      key2 = "fedcba9876543210fedcba9876543210".hexbytes
      payload = "Secret message".to_slice
      source_node_id = 0x1122334455667788_u64
      message_counter = 10_u32
      session_id = 50_u16

      encrypted = Matter::Session::SecureMessage.encrypt_with_params(
        key1,
        payload,
        source_node_id,
        message_counter,
        session_id,
        crypto: crypto
      )

      expect_raises(Exception, /authentication failed|MIC mismatch/) do
        Matter::Session::SecureMessage.decrypt_with_params(
          key2, # Wrong key
          encrypted,
          source_node_id,
          message_counter,
          session_id,
          crypto: crypto
        )
      end
    end

    it "fails decryption with wrong message counter" do
      key = "abcdef0123456789abcdef0123456789".hexbytes
      payload = "Test payload".to_slice
      source_node_id = 0xAABBCCDDEEFF0011_u64
      message_counter_encrypt = 100_u32
      message_counter_decrypt = 101_u32 # Different
      session_id = 25_u16

      encrypted = Matter::Session::SecureMessage.encrypt_with_params(
        key,
        payload,
        source_node_id,
        message_counter_encrypt,
        session_id,
        crypto: crypto
      )

      expect_raises(Exception, /authentication failed|MIC mismatch/) do
        Matter::Session::SecureMessage.decrypt_with_params(
          key,
          encrypted,
          source_node_id,
          message_counter_decrypt, # Wrong counter
          session_id,
          crypto: crypto
        )
      end
    end

    it "encrypts and decrypts using session context" do
      crypto = Matter::Crypto::StandardCrypto.new

      # Create matching keys for both sides
      i2r_key = "11111111111111111111111111111111".hexbytes # Initiator to responder
      r2i_key = "22222222222222222222222222222222".hexbytes # Responder to initiator

      # Initiator context
      initiator_context = Matter::Session::SecureContext.new(
        session_id: 1000_u16,
        peer_session_id: 2000_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: i2r_key,
        decryption_key: r2i_key,
        initiator: true,
        local_node_id: Matter::DataType::NodeId.new(0x1111111111111111_u64),
        peer_node_id: Matter::DataType::NodeId.new(0x2222222222222222_u64)
      )

      # Responder context (keys swapped)
      responder_context = Matter::Session::SecureContext.new(
        session_id: 2000_u16,
        peer_session_id: 1000_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: r2i_key,
        decryption_key: i2r_key,
        initiator: false,
        local_node_id: Matter::DataType::NodeId.new(0x2222222222222222_u64),
        peer_node_id: Matter::DataType::NodeId.new(0x1111111111111111_u64)
      )

      # Create packet header
      # No source or destination node IDs, so flags is just version bits
      flags = 0_u8
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 1000_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: flags,
        security_flags: 0_u8
      )

      payload = "Matter secure message".to_slice

      # Encrypt from initiator
      # Capture the counter before encryption
      counter_before = initiator_context.local_message_counter
      encrypted = Matter::Session::SecureMessage.encrypt(
        initiator_context,
        payload,
        packet_header,
        crypto
      )

      encrypted.size.should eq(payload.size + 16) # Payload + MIC

      # Decrypt at responder using the actual counter that was used
      message_counter = counter_before # The counter used for encryption
      decrypted = Matter::Session::SecureMessage.decrypt(
        responder_context,
        encrypted,
        message_counter,
        packet_header,
        crypto
      )

      decrypted.should eq(payload)
      String.new(decrypted).should eq("Matter secure message")
    end

    it "prevents replay attacks in session context" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = "33333333333333333333333333333333".hexbytes

      context = Matter::Session::SecureContext.new(
        session_id: 500_u16,
        peer_session_id: 600_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: key,
        decryption_key: key,
        peer_node_id: Matter::DataType::NodeId.new(0xABCDEF0123456789_u64)
      )

      # No source or destination node IDs, so flags is just version bits
      flags = 0_u8
      packet_header = Matter::Codec::MessageCodec::PacketHeader.new(
        session_id: 500_u16,
        session_type: Matter::Codec::MessageCodec::SessionType::Unicast,
        message_id: 1_u32,
        privacy_enhancements: false,
        control_message: false,
        message_extensions: false,
        flags: flags,
        security_flags: 0_u8
      )

      payload = "Test message".to_slice

      # Encrypt a message with counter 10
      source_node_id = 0xABCDEF0123456789_u64
      message_counter = 10_u32
      encrypted = Matter::Session::SecureMessage.encrypt_with_params(
        key,
        payload,
        source_node_id,
        message_counter,
        500_u16,
        crypto: crypto
      )

      # First decrypt should succeed
      decrypted = Matter::Session::SecureMessage.decrypt(
        context,
        encrypted,
        message_counter,
        packet_header,
        crypto
      )
      decrypted.should eq(payload)

      # Replay attempt should fail
      expect_raises(Exception, /Invalid message counter|replay attack/) do
        Matter::Session::SecureMessage.decrypt(
          context,
          encrypted,
          message_counter, # Same counter
          packet_header,
          crypto
        )
      end
    end
  end

  describe "UnsecuredContext" do
    it "creates an unsecured session context" do
      context = Matter::Session::UnsecuredContext.new(
        session_id: 0_u16,
        initiator_session_id: 100_u16
      )

      context.session_id.should eq(0_u16)
      context.initiator_session_id.should eq(100_u16)
      context.session_type.should eq(Matter::Session::SessionType::Unsecured)
    end
  end
end
