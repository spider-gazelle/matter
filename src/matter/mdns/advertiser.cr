require "log"
require "./server"
require "./commissionable_advertisement"

module Matter
  module MDNS
    # Advertiser manages the lifecycle of mDNS advertisements
    #
    # Handles:
    # - Broadcasting announcements with exponential backoff
    # - Sending goodbye packets on close
    # - Integration with commissioning window lifecycle
    #
    # RFC 6762 §8.3: Announcing records
    class Advertiser
      Log = ::Log.for("matter.mdns.advertiser")

      property server : Server
      @advertisement : RecordGenerator?
      @broadcast_fiber : Fiber?
      @broadcast_channel : Channel(Nil)?
      @broadcasting : Bool = false

      # Broadcasting schedule (exponential backoff with jitter)
      INITIAL_INTERVAL   = 1.seconds
      MAX_INTERVAL       = 90.seconds
      JITTER_PERCENT     = 0.25_f64 # ±25% jitter
      MAX_BROADCAST_TIME = 15.minutes

      def initialize(@server : Server)
        Log.debug { "Advertiser initialized" }
      end

      # Convenience constructor that creates server and socket
      def self.new(family : Socket::Family = Socket::Family::INET)
        server = Server.new(family)
        new(server)
      end

      # Start advertising a service
      #
      # @param advertisement The advertisement to broadcast
      def start_advertising(advertisement : RecordGenerator) : Nil
        stop_advertising if @advertisement

        @advertisement = advertisement
        @server.register(advertisement)

        # Start broadcasting fiber
        start_broadcasting

        Log.info { "Started advertising #{advertisement.instance_name}" }
      end

      # Stop advertising and send goodbye packets
      def stop_advertising : Nil
        ad = @advertisement
        return unless ad

        # Stop broadcasting
        stop_broadcasting

        # Send goodbye packets (TTL=0)
        @server.send_goodbye

        # Unregister from server
        @server.unregister(ad)

        @advertisement = nil
        Log.info { "Stopped advertising #{ad.instance_name}" }
      end

      # Check if currently advertising
      def advertising? : Bool
        !@advertisement.nil?
      end

      # Start the broadcasting fiber with exponential backoff
      private def start_broadcasting : Nil
        # Stop any existing broadcast first
        if @broadcasting
          Log.debug { "Stopping existing broadcast before starting new one" }
          stop_broadcasting_internal
        end

        @broadcasting = true
        @broadcast_channel = Channel(Nil).new(1) # Buffered channel

        @broadcast_fiber = spawn(name: "mDNS Broadcaster") do
          run_broadcast_schedule
        end

        # Start server if not running
        @server.start unless @server.running?

        Log.debug { "Broadcasting started" }
      end

      # Stop the broadcasting fiber
      private def stop_broadcasting : Nil
        return unless @broadcasting
        stop_broadcasting_internal
      end

      # Internal method to stop broadcasting without checking @broadcasting flag
      private def stop_broadcasting_internal : Nil
        @broadcasting = false

        # Signal the broadcast fiber to stop
        if channel = @broadcast_channel
          # Use non-blocking send since channel is buffered
          select
          when channel.send(nil)
            Log.trace { "Sent cancellation signal to broadcast fiber" }
          else
            # Channel full or closed, fiber probably already exited
            Log.trace { "Could not send cancellation signal" }
          end
        end

        # Give the fiber a moment to exit gracefully
        3.times { Fiber.yield }

        @broadcast_channel = nil
        @broadcast_fiber = nil
        Log.debug { "Broadcasting stopped" }
      end

      # Run the broadcast schedule with exponential backoff
      #
      # RFC 6762 §8.3:
      # - Initial announcement at 1s
      # - Subsequent announcements double interval: 2s, 4s, 8s, etc.
      # - Maximum interval of 90s
      # - Continue for up to 15 minutes
      # - Apply ±25% jitter to avoid collisions
      private def run_broadcast_schedule : Nil
        interval = INITIAL_INTERVAL
        announcement_count = 0

        channel = @broadcast_channel
        return unless channel

        start_time = Time.monotonic

        while @broadcasting
          # Check if we've exceeded max broadcast time
          elapsed = Time.monotonic - start_time
          if elapsed >= MAX_BROADCAST_TIME
            Log.debug { "Max broadcast time (#{MAX_BROADCAST_TIME.total_minutes.to_i}m) reached, stopping announcements" }
            break
          end

          # Send announcement
          @server.announce
          announcement_count += 1
          Log.debug { "Sent announcement ##{announcement_count} (interval: #{interval.total_seconds}s)" }

          # Apply jitter: ±25%
          jittered_interval = apply_jitter(interval)

          # Wait for next interval or cancellation
          select
          when timeout(jittered_interval)
            # Continue to next announcement
          when channel.receive
            # Cancelled
            Log.debug { "Broadcast schedule cancelled" }
            break
          end

          # Double interval for next time (up to max)
          interval = {interval * 2, MAX_INTERVAL}.min
        end

        Log.debug { "Broadcast schedule completed: #{announcement_count} announcements in #{(Time.monotonic - start_time).total_minutes.round(1)}m" }
      rescue ex
        elapsed = start_time ? (Time.monotonic - start_time) : Time::Span.zero
        interval_seconds = interval.try(&.total_seconds.round(3))
        Log.error(exception: ex) do
          "Error in broadcast schedule (broadcasting=#{@broadcasting} announcements=#{announcement_count} elapsed=#{elapsed.total_seconds.round(3)}s interval=#{interval_seconds}s)"
        end
      end

      # Apply ±25% random jitter to an interval
      private def apply_jitter(interval : Time::Span) : Time::Span
        jitter_range = interval.total_seconds * JITTER_PERCENT
        jitter = rand(-jitter_range..jitter_range)
        interval + jitter.seconds
      end

      # Close the advertiser and cleanup
      def close : Nil
        stop_advertising
        @server.close
        Log.debug { "Advertiser closed" }
      end
    end
  end
end
