require "../codec/message_codec"

module Matter
  module Transport
    # Represents a message exchange (request/response pair)
    #
    # In Matter protocol, exchanges are bidirectional conversations
    # identified by an exchange ID. Each exchange tracks:
    # - Exchange ID
    # - Protocol ID
    # - Whether we initiated the exchange
    # - Pending acknowledgments
    # - Retransmission state
    class Exchange
      enum State
        Active
        Closed
        Failed
      end

      getter exchange_id : UInt16
      getter protocol_id : UInt16
      getter? initiator : Bool
      getter state : State
      getter peer_address : Socket::IPAddress?
      getter peer_node_id : DataType::NodeId?
      getter session_id : UInt16

      # Retransmission parameters (from Matter spec)
      MRP_BASE_TIMEOUT      = 200 # milliseconds
      MRP_BACKOFF_BASE      = 1.6 # exponential backoff multiplier
      MRP_MAX_RETRIES       =   5
      MRP_STANDALONE_ACK_MS = 200 # Time to wait before sending standalone ACK

      @pending_message : Codec::MessageCodec::Message?
      @retransmit_count : Int32
      @timeout_ms : Int32
      @last_activity : Time

      def initialize(
        @exchange_id : UInt16,
        @protocol_id : UInt16,
        @session_id : UInt16,
        @initiator : Bool,
        @peer_address : Socket::IPAddress? = nil,
        @peer_node_id : DataType::NodeId? = nil,
      )
        @state = State::Active
        @pending_message = nil
        @retransmit_count = 0
        @timeout_ms = MRP_BASE_TIMEOUT
        @last_activity = Time.utc
      end

      # Mark exchange as closed
      def close : Nil
        @state = State::Closed
        @pending_message = nil
      end

      # Mark exchange as failed
      def fail : Nil
        @state = State::Failed
        @pending_message = nil
      end

      # Store message for retransmission if needed
      def set_pending_message(message : Codec::MessageCodec::Message) : Nil
        @pending_message = message
        @last_activity = Time.utc
      end

      # Clear pending message (successful acknowledgment received)
      def clear_pending_message : Nil
        @pending_message = nil
        @retransmit_count = 0
        @timeout_ms = MRP_BASE_TIMEOUT
      end

      # Check if message needs retransmission
      # Returns the message to retransmit, or nil if none needed
      def needs_retransmit? : Codec::MessageCodec::Message?
        return nil if @pending_message.nil?
        return nil if @state != State::Active

        elapsed_ms = (Time.utc - @last_activity).total_milliseconds.to_i

        if elapsed_ms >= @timeout_ms
          if @retransmit_count >= MRP_MAX_RETRIES
            fail
            return nil
          end

          @retransmit_count += 1
          @timeout_ms = (MRP_BASE_TIMEOUT * (MRP_BACKOFF_BASE ** @retransmit_count)).to_i
          @last_activity = Time.utc
          return @pending_message
        end

        nil
      end

      # Update activity timestamp
      def touch : Nil
        @last_activity = Time.utc
      end

      # Check if exchange has timed out
      def timed_out? : Bool
        return false if @state != State::Active
        elapsed_ms = (Time.utc - @last_activity).total_milliseconds.to_i
        elapsed_ms > (@timeout_ms * 2) # Allow some grace period
      end
    end

    # Manages multiple exchanges
    class ExchangeManager
      @exchanges : Hash(UInt16, Exchange)
      @next_exchange_id : UInt16

      def initialize
        @exchanges = Hash(UInt16, Exchange).new
        @next_exchange_id = Random.rand(UInt16).to_u16
      end

      # Create new exchange as initiator
      def create_exchange(
        protocol_id : UInt16,
        session_id : UInt16,
        peer_address : Socket::IPAddress,
        peer_node_id : DataType::NodeId? = nil,
      ) : Exchange
        exchange_id = @next_exchange_id
        @next_exchange_id = @next_exchange_id &+ 1 # Wrap-around safe

        exchange = Exchange.new(
          exchange_id: exchange_id,
          protocol_id: protocol_id,
          session_id: session_id,
          initiator: true,
          peer_address: peer_address,
          peer_node_id: peer_node_id
        )

        @exchanges[exchange_id] = exchange
        exchange
      end

      # Get or create exchange for received message
      def get_or_create_exchange(
        exchange_id : UInt16,
        protocol_id : UInt16,
        session_id : UInt16,
        peer_address : Socket::IPAddress,
        peer_node_id : DataType::NodeId? = nil,
        initiator : Bool = false,
      ) : Exchange
        if exchange = @exchanges[exchange_id]?
          exchange.touch
          return exchange
        end

        # Create new exchange for incoming message
        exchange = Exchange.new(
          exchange_id: exchange_id,
          protocol_id: protocol_id,
          session_id: session_id,
          initiator: initiator,
          peer_address: peer_address,
          peer_node_id: peer_node_id
        )

        @exchanges[exchange_id] = exchange
        exchange
      end

      # Get exchange by ID
      def get_exchange(exchange_id : UInt16) : Exchange?
        @exchanges[exchange_id]?
      end

      # Close and remove exchange
      def close_exchange(exchange_id : UInt16) : Nil
        if exchange = @exchanges[exchange_id]?
          exchange.close
          @exchanges.delete(exchange_id)
        end
      end

      # Get all exchanges that need retransmission
      def get_retransmit_candidates : Array(Tuple(UInt16, Codec::MessageCodec::Message))
        candidates = [] of Tuple(UInt16, Codec::MessageCodec::Message)

        @exchanges.each do |exchange_id, exchange|
          if message = exchange.needs_retransmit?
            candidates << {exchange_id, message}
          end
        end

        candidates
      end

      # Clean up timed out exchanges
      def cleanup_stale_exchanges : Nil
        @exchanges.reject! do |_exchange_id, exchange|
          exchange.timed_out? || exchange.state != Exchange::State::Active
        end
      end

      # Get count of active exchanges
      def active_count : Int32
        @exchanges.count { |_id, ex| ex.state == Exchange::State::Active }
      end
    end
  end
end
