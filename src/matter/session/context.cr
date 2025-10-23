require "../crypto/crypto"
require "../datatype/*"

module Matter
  module Session
    # Session types in Matter protocol
    enum SessionType
      # Unsecured session (commissioning only)
      Unsecured
      # Unicast secure session (CASE or PASE)
      Unicast
      # Group secure session (multicast)
      Group
    end

    # Session parameters used during session establishment
    struct SessionParameters
      property session_id : UInt16
      property peer_session_id : UInt16
      property session_timestamp : Time
      property session_idle_interval : UInt32
      property session_active_interval : UInt32
      property session_active_threshold : UInt16

      def initialize(
        @session_id : UInt16,
        @peer_session_id : UInt16,
        @session_timestamp : Time = Time.utc,
        @session_idle_interval : UInt32 = 4000_u32,    # 4 seconds
        @session_active_interval : UInt32 = 500_u32,   # 500ms
        @session_active_threshold : UInt16 = 4000_u16, # 4000 messages
      )
      end
    end

    # Secure session context holding encryption keys and state
    class SecureContext
      property session_id : UInt16
      property peer_session_id : UInt16
      property session_type : SessionType
      property peer_node_id : DataType::NodeId?
      property local_node_id : DataType::NodeId?

      # Encryption keys
      property encryption_key : Bytes # i2r (initiator to responder) or encryption key
      property decryption_key : Bytes # r2i (responder to initiator) or decryption key
      property attestation_challenge : Bytes?

      # Message counters for replay protection
      property local_message_counter : UInt32
      property peer_message_counter : UInt32?
      property max_message_counter : UInt32

      # Session metadata
      property creation_time : Time
      property last_activity_time : Time
      property is_initiator : Bool

      def initialize(
        @session_id : UInt16,
        @peer_session_id : UInt16,
        @session_type : SessionType,
        @encryption_key : Bytes,
        @decryption_key : Bytes,
        @is_initiator : Bool = true,
        @peer_node_id : DataType::NodeId? = nil,
        @local_node_id : DataType::NodeId? = nil,
        @attestation_challenge : Bytes? = nil,
      )
        @local_message_counter = 0_u32
        @peer_message_counter = nil
        @max_message_counter = UInt32::MAX
        @creation_time = Time.utc
        @last_activity_time = Time.utc
      end

      # Get the next message counter and increment
      def next_message_counter : UInt32
        counter = @local_message_counter
        @local_message_counter += 1

        if @local_message_counter > @max_message_counter
          raise "Message counter overflow - session must be renegotiated"
        end

        counter
      end

      # Validate received message counter (prevent replay attacks)
      def validate_message_counter(received_counter : UInt32) : Bool
        # Message counter must be greater than the last received counter
        # This prevents replay attacks
        last_counter = @peer_message_counter

        # First message: accept any counter (including 0)
        if last_counter.nil?
          @peer_message_counter = received_counter
          @last_activity_time = Time.utc
          return true
        end

        # Subsequent messages: must be greater than last received
        if received_counter <= last_counter
          return false
        end

        @peer_message_counter = received_counter
        @last_activity_time = Time.utc
        true
      end

      # Update activity timestamp
      def update_activity
        @last_activity_time = Time.utc
      end

      # Set activity time (for testing)
      def set_last_activity_time(time : Time)
        @last_activity_time = time
      end

      # Check if session is expired based on idle time
      def expired?(idle_timeout : Time::Span = 5.minutes) : Bool
        Time.utc - @last_activity_time > idle_timeout
      end
    end

    # Unsecured session context (used during commissioning)
    class UnsecuredContext
      property session_id : UInt16
      property session_type : SessionType
      property initiator_session_id : UInt16
      property creation_time : Time

      def initialize(@session_id : UInt16, @initiator_session_id : UInt16 = 0_u16)
        @session_type = SessionType::Unsecured
        @creation_time = Time.utc
      end
    end
  end
end
