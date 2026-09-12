require "../spec_helper"
require "../../src/matter/commissioning/failsafe_timer"

module Matter::Commissioning
  describe FailsafeTimer do
    describe "initialization" do
      it "creates timer with primary and cumulative durations" do
        expired = false
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 5_u16,
          max_cumulative: 10_u16,
          expiry_callback: -> { expired = true }
        )

        timer.running?.should be_true
        timer.associated_fabric_index.should be_nil
        expired.should be_false

        timer.close
      end

      it "associates with fabric index" do
        timer = FailsafeTimer.new(
          fabric_index: 1_u8,
          expiry_length: 5_u16,
          max_cumulative: 10_u16,
          expiry_callback: -> { }
        )

        timer.associated_fabric_index.should eq(1_u8)
        timer.close
      end
    end

    describe "primary timer expiration" do
      it "invokes expiry callback when primary timer expires" do
        expired = Channel(Bool).new(1) # Buffered channel
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 1_u16, # 1 second
          max_cumulative: 10_u16,
          expiry_callback: -> { expired.send(true) }
        )

        # Wait for expiration with timeout
        select
        when result = expired.receive
          result.should be_true
        when timeout(2.seconds)
          fail "Expiry callback was not invoked"
        end

        timer.running?.should be_false
      end
    end

    describe "cumulative timer expiration" do
      it "invokes expiry callback when cumulative timer expires" do
        expired = Channel(Bool).new(1) # Buffered channel
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 10_u16, # Primary: 10 seconds
          max_cumulative: 1_u16, # Cumulative: 1 second (shorter)
          expiry_callback: -> { expired.send(true) }
        )

        # Wait for expiration with timeout
        select
        when result = expired.receive
          result.should be_true
        when timeout(2.seconds)
          fail "Cumulative expiry callback was not invoked"
        end

        timer.running?.should be_false
      end
    end

    describe "re_arm" do
      it "extends primary timer without extending cumulative timer" do
        expired = Channel(Bool).new(1) # Buffered channel
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 1_u16,  # Initial: 1 second
          max_cumulative: 3_u16, # Cumulative: 3 seconds
          expiry_callback: -> { expired.send(true) }
        )

        sleep 0.5.seconds # Half of initial timeout

        # Re-arm with 1 more second
        timer.re_arm(nil, 1_u16)

        # Wait for expiration after re-arm
        select
        when result = expired.receive
          result.should be_true
        when timeout(2.seconds)
          fail "Expiry callback was not invoked after re-arm"
        end

        timer.running?.should be_false
      end

      it "triggers immediate expiration on re_arm with 0" do
        expired = false
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 10_u16, # Would take 10 seconds
          max_cumulative: 20_u16,
          expiry_callback: -> { expired = true }
        )

        sleep 0.1.seconds
        expired.should be_false

        # Re-arm with 0 = immediate expiration
        timer.re_arm(nil, 0_u16)
        expired.should be_true
        timer.running?.should be_false
      end

      it "validates fabric index match on re_arm" do
        timer = FailsafeTimer.new(
          fabric_index: 1_u8,
          expiry_length: 10_u16,
          max_cumulative: 20_u16,
          expiry_callback: -> { }
        )

        # Should succeed with matching fabric
        timer.re_arm(1_u8, 5_u16)

        # Should fail with different fabric
        expect_raises(ArgumentError, /Fabric mismatch/) do
          timer.re_arm(2_u8, 5_u16)
        end

        timer.close
      end

      it "rejects re_arm after completion" do
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 10_u16,
          max_cumulative: 20_u16,
          expiry_callback: -> { }
        )

        timer.complete

        expect_raises(ArgumentError, /Cannot re-arm completed failsafe/) do
          timer.re_arm(nil, 5_u16)
        end
      end
    end

    describe "complete" do
      it "stops timers and prevents expiry callback" do
        expired = false
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 1_u16,
          max_cumulative: 2_u16,
          expiry_callback: -> { expired = true }
        )

        sleep 500.milliseconds
        expired.should be_false

        # Mark as completed
        timer.complete
        timer.running?.should be_false

        # Wait for what would have been expiration
        sleep 1.0.seconds
        expired.should be_false # Should NOT fire
      end
    end

    describe "time remaining" do
      it "reports primary time remaining" do
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 5_u16,
          max_cumulative: 10_u16,
          expiry_callback: -> { }
        )

        sleep 0.1.seconds

        remaining = timer.primary_time_remaining
        remaining.should_not be_nil
        remaining.as(Time::Span).total_seconds.should be_close(5.0, 0.5)

        timer.close
      end

      it "reports cumulative time remaining" do
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 5_u16,
          max_cumulative: 10_u16,
          expiry_callback: -> { }
        )

        sleep 0.1.seconds

        remaining = timer.cumulative_time_remaining
        remaining.should_not be_nil
        remaining.as(Time::Span).total_seconds.should be_close(10.0, 0.5)

        timer.close
      end

      it "returns nil when completed" do
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 5_u16,
          max_cumulative: 10_u16,
          expiry_callback: -> { }
        )

        timer.complete

        timer.primary_time_remaining.should be_nil
        timer.cumulative_time_remaining.should be_nil
      end
    end

    describe "close" do
      it "stops timers without invoking expiry callback" do
        expired = false
        timer = FailsafeTimer.new(
          fabric_index: nil,
          expiry_length: 1_u16,
          max_cumulative: 2_u16,
          expiry_callback: -> { expired = true }
        )

        sleep 0.1.seconds
        timer.close

        sleep 1.5.seconds       # Wait past expiration
        expired.should be_false # Should NOT fire
      end
    end
  end
end
