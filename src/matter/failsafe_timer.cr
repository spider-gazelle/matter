require "log"

module Matter
  # FailsafeTimer manages dual timers for commissioning safety
  #
  # The failsafe mechanism uses two timers:
  # 1. Primary timer: Can be re-armed/extended on subsequent ArmFailSafe calls
  # 2. Cumulative timer: Started once, never extended, provides hard limit
  #
  # Either timer expiring triggers the expiry callback, which performs rollback.
  #
  # Matter Core Spec §11.10.7.2 - ArmFailSafe Command & Fail Safe Context
  class FailsafeTimer
    Log = ::Log.for("matter.failsafe_timer")

    property associated_fabric_index : UInt8?

    @completed : Bool
    @primary_channel : Channel(Nil)?
    @cumulative_channel : Channel(Nil)?
    @expiry_callback : Proc(Nil)
    @start_time : Time
    @primary_expiry : Time::Span
    @cumulative_expiry : Time::Span

    # Create a new failsafe timer with dual timer architecture
    #
    # @param fabric_index Fabric index associated with this failsafe context (or nil for PASE)
    # @param expiry_length Primary timer duration in seconds
    # @param max_cumulative Maximum cumulative duration in seconds
    # @param expiry_callback Callback invoked when either timer expires
    def initialize(
      fabric_index : UInt8?,
      expiry_length : UInt16,
      max_cumulative : UInt16,
      @expiry_callback : Proc(Nil),
    )
      @associated_fabric_index = fabric_index
      @completed = false
      @start_time = Time.utc
      @primary_expiry = expiry_length.seconds
      @cumulative_expiry = max_cumulative.seconds

      # Start both timers
      @primary_channel = Channel(Nil).new
      @cumulative_channel = Channel(Nil).new
      start_primary_timer(expiry_length.seconds)
      start_cumulative_timer(max_cumulative.seconds)

      Log.info { "Failsafe armed: primary=#{expiry_length}s, cumulative=#{max_cumulative}s, fabric=#{fabric_index || "PASE"}" }
    end

    # Re-arm the primary timer with a new expiry duration
    #
    # The cumulative timer is NOT extended - it continues counting from the original start.
    # This prevents unbounded commissioning by repeated re-arming.
    #
    # @param fabric_index Must match the associated fabric (or both nil)
    # @param expiry_length New primary timer duration (0 = immediate expiration)
    def re_arm(fabric_index : UInt8?, expiry_length : UInt16) : Nil
      # Validation: can't re-arm if already expired/completed
      if @completed
        raise ArgumentError.new("Cannot re-arm completed failsafe")
      end

      # Validation: fabric must match
      if @associated_fabric_index != fabric_index
        raise ArgumentError.new("Fabric mismatch: expected #{@associated_fabric_index}, got #{fabric_index}")
      end

      # Handle immediate expiration (expiry_length = 0)
      if expiry_length == 0
        Log.info { "Failsafe immediate expiration requested" }
        expire
        return
      end

      # Stop old primary timer
      if channel = @primary_channel
        signal_cancel(channel)
      end

      # Start new primary timer
      @primary_channel = Channel(Nil).new
      start_primary_timer(expiry_length.seconds)

      Log.info { "Failsafe re-armed: primary=#{expiry_length}s, cumulative continues" }
    end

    # Mark the failsafe as completed successfully
    #
    # Stops both timers and prevents expiration callback from firing.
    # Called when CommissioningComplete succeeds.
    def complete : Nil
      return if @completed

      @completed = true

      # Stop both timers (spawn to avoid deadlock if called from timer fiber)
      spawn do
        if channel = @primary_channel
          signal_cancel(channel)
        end
        if channel = @cumulative_channel
          signal_cancel(channel)
        end
      end

      Log.info { "Failsafe completed successfully" }
    end

    # Trigger failsafe expiration and invoke rollback callback
    #
    # Called automatically when either timer expires, or manually via re_arm(0).
    def expire : Nil
      return if @completed

      complete # Stop timers

      Log.warn { "Failsafe expired - triggering rollback" }

      # Invoke expiry callback in a new fiber to avoid scheduling issues
      # This ensures the callback can properly interact with other fibers (like tests)
      spawn do
        @expiry_callback.call
      rescue ex
        Log.error(exception: ex) { "Error in failsafe expiry callback (primary_expiry=#{@primary_expiry} cumulative_expiry=#{@cumulative_expiry})" }
      end

      # Yield to let the callback fiber run
      Fiber.yield
    end

    # Check if failsafe is still running (not completed or expired)
    def running? : Bool
      !@completed
    end

    # Get time remaining on primary timer (nil if expired)
    def primary_time_remaining : Time::Span?
      return if @completed

      elapsed = Time.utc - @start_time
      remaining = @primary_expiry - elapsed
      remaining > Time::Span.zero ? remaining : nil
    end

    # Get time remaining on cumulative timer (nil if expired)
    def cumulative_time_remaining : Time::Span?
      return if @completed

      elapsed = Time.utc - @start_time
      remaining = @cumulative_expiry - elapsed
      remaining > Time::Span.zero ? remaining : nil
    end

    # Start the primary failsafe timer
    #
    # Can be stopped and restarted on re-arm.
    private def start_primary_timer(duration : Time::Span) : Nil
      channel = @primary_channel
      return unless channel

      spawn(name: "Failsafe Primary Timer") do
        select
        when timeout(duration)
          unless @completed
            Log.warn { "Primary failsafe timer expired after #{duration}" }
            expire
          end
        when channel.receive
          # Timer cancelled
        end
      end
    end

    # Start the cumulative failsafe timer
    #
    # Never stopped or restarted - provides hard upper bound on total commissioning time.
    private def start_cumulative_timer(duration : Time::Span) : Nil
      channel = @cumulative_channel
      return unless channel

      spawn(name: "Failsafe Cumulative Timer") do
        select
        when timeout(duration)
          unless @completed
            Log.warn { "Cumulative failsafe timer expired after #{duration}" }
            expire
          end
        when channel.receive
          # Timer cancelled
        end
      end
    end

    # Close and cleanup the failsafe timer
    #
    # Should be called when the context is destroyed to ensure clean shutdown.
    def close : Nil
      return if @completed

      @completed = true

      if channel = @primary_channel
        signal_cancel(channel)
      end
      if channel = @cumulative_channel
        signal_cancel(channel)
      end
    end

    # Signal a timer fiber to stop; a timer that already finished has closed
    # its channel and needs no signal.
    private def signal_cancel(channel : Channel(Nil)) : Nil
      channel.send(nil)
    rescue Channel::ClosedError
    end
  end
end
