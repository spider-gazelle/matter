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
      property? initiator : Bool

      # Session type and fabric association
      # case_session: true for CASE sessions, false for PASE sessions
      # fabric_index: the fabric index for CASE sessions (nil for PASE)
      property? case_session : Bool
      property fabric_index : UInt8?

      def initialize(
        @session_id : UInt16,
        @peer_session_id : UInt16,
        @session_type : SessionType,
        @encryption_key : Bytes,
        @decryption_key : Bytes,
        @initiator : Bool = true,
        @peer_node_id : DataType::NodeId? = nil,
        @local_node_id : DataType::NodeId? = nil,
        @attestation_challenge : Bytes? = nil,
        @case_session : Bool = false,
        @fabric_index : UInt8? = nil,
      )
        # Matter spec requires message counter to start at a random value
        # to prevent replay attacks across session resumptions
        @local_message_counter = Random::Secure.rand(UInt32)
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

      # Check if a message counter would be accepted (without updating state)
      # Used for pre-checking duplicates before attempting decryption
      def would_accept_message_counter?(received_counter : UInt32) : Bool
        last_counter = @peer_message_counter

        # First message: accept any counter
        return true if last_counter.nil?

        # Subsequent messages: must be greater than last received
        received_counter > last_counter
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
      def last_activity_time=(time : Time)
        @last_activity_time = time
      end

      # Check if session is expired based on idle time
      def expired?(idle_timeout : Time::Span = 5.minutes) : Bool
        Time.utc - @last_activity_time > idle_timeout
      end

      # Serialize session to a hash for JSON persistence
      def to_h : Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
        h = {} of String => (String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
        h["session_id"] = @session_id
        h["peer_session_id"] = @peer_session_id
        h["session_type"] = @session_type.value.to_i64
        h["encryption_key"] = @encryption_key.hexstring
        h["decryption_key"] = @decryption_key.hexstring
        h["is_initiator"] = @initiator
        h["is_case"] = @case_session
        h["local_message_counter"] = @local_message_counter
        h["peer_message_counter"] = @peer_message_counter.try(&.to_i64) || 0_i64
        h["has_peer_message_counter"] = !@peer_message_counter.nil?
        h["creation_time"] = @creation_time.to_unix
        h["last_activity_time"] = @last_activity_time.to_unix

        if node_id = @peer_node_id
          h["peer_node_id"] = node_id.id
        end
        if node_id = @local_node_id
          h["local_node_id"] = node_id.id
        end
        if challenge = @attestation_challenge
          h["attestation_challenge"] = challenge.hexstring
        end
        if fabric_idx = @fabric_index
          h["fabric_index"] = fabric_idx
        end

        h
      end

      # Deserialize session from a hash
      def self.from_h(h : Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)) : SecureContext
        session_id = h["session_id"].as(Int).to_u16
        peer_session_id = h["peer_session_id"].as(Int).to_u16
        session_type_value = h["session_type"].as(Int).to_i32
        session_type = SessionType.new(session_type_value)
        encryption_key = h["encryption_key"].as(String).hexbytes
        decryption_key = h["decryption_key"].as(String).hexbytes
        is_initiator = h["is_initiator"].as(Bool)
        is_case = h["is_case"].as(Bool)

        peer_node_id = if node_id = h["peer_node_id"]?
                         DataType::NodeId.new(node_id.as(Int).to_u64)
                       end
        local_node_id = if node_id = h["local_node_id"]?
                          DataType::NodeId.new(node_id.as(Int).to_u64)
                        end
        attestation_challenge = if challenge = h["attestation_challenge"]?
                                  challenge.as(String).hexbytes
                                end
        fabric_index = if idx = h["fabric_index"]?
                         idx.as(Int).to_u8
                       end

        # Restore message counters
        local_msg_counter = h["local_message_counter"].as(Int).to_u32
        peer_msg_counter = if h["has_peer_message_counter"]?.try(&.as(Bool))
                             h["peer_message_counter"].as(Int).to_u32
                           end

        # Restore timestamps
        creation = Time.unix(h["creation_time"].as(Int).to_i64)
        last_activity = Time.unix(h["last_activity_time"].as(Int).to_i64)

        ctx = new(
          session_id: session_id,
          peer_session_id: peer_session_id,
          session_type: session_type,
          encryption_key: encryption_key,
          decryption_key: decryption_key,
          initiator: is_initiator,
          peer_node_id: peer_node_id,
          local_node_id: local_node_id,
          attestation_challenge: attestation_challenge,
          case_session: is_case,
          fabric_index: fabric_index
        )

        # Set restored values using setters
        ctx.local_message_counter = local_msg_counter
        ctx.peer_message_counter = peer_msg_counter
        ctx.creation_time = creation
        ctx.last_activity_time = last_activity

        ctx
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
