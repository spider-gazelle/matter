module Matter
  module Transport
    # Manages message IDs and deduplication
    #
    # Matter protocol uses 32-bit message counters for:
    # - Ensuring message ordering
    # - Detecting duplicate messages
    # - Replay attack protection
    class MessageCounter
      # Rolling window size for duplicate detection (spec recommends at least 32)
      WINDOW_SIZE = 64

      enum CheckResult
        Accept
        Duplicate
        Stale
      end

      getter counter : UInt32
      @received_window : Set(UInt32)
      @max_received : UInt32

      def initialize(@counter : UInt32 = 0_u32)
        @received_window = Set(UInt32).new
        @max_received = 0_u32
      end

      # Get next message ID to send
      def next : UInt32
        @counter = @counter &+ 1 # Wrapping addition
        @counter
      end

      # Check if a received message ID is valid (not a duplicate or replay)
      # Returns true if message should be accepted
      def valid?(message_id : UInt32) : Bool
        check(message_id) == CheckResult::Accept
      end

      # Check whether a received message ID is accepted, a duplicate, or stale.
      #
      # This allows reliability layers to treat duplicates as valid retransmissions
      # (e.g. re-send a cached response) while still rejecting stale replays.
      def check(message_id : UInt32) : CheckResult
        # First message is always valid
        if @max_received == 0
          @max_received = message_id
          @received_window.add(message_id)
          return CheckResult::Accept
        end

        # Message is in the future - always accept
        if message_id > @max_received
          # Clean old entries from window
          cutoff = message_id > WINDOW_SIZE ? message_id &- WINDOW_SIZE : 0_u32
          @received_window = @received_window.select { |id| id >= cutoff }.to_set

          @received_window.add(message_id)
          @max_received = message_id
          return CheckResult::Accept
        end

        # Message is within window - check if we've seen it
        window_start = @max_received > WINDOW_SIZE ? @max_received &- WINDOW_SIZE : 0_u32
        if message_id >= window_start
          if @received_window.includes?(message_id)
            return CheckResult::Duplicate
          else
            @received_window.add(message_id)
            return CheckResult::Accept
          end
        end

        # Message is too old - reject (potential replay attack)
        CheckResult::Stale
      end

      # Mark a message ID as received (for testing/manual tracking)
      def mark_received(message_id : UInt32) : Nil
        valid?(message_id)
      end

      # Reset counter (used when establishing new session)
      def reset(value : UInt32 = 0_u32) : Nil
        @counter = value
        @received_window.clear
        @max_received = 0_u32
      end
    end
  end
end
