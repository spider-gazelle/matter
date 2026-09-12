module Matter
  # Coalesces bursts of `trigger` calls into a single run of the action.
  #
  # The first `trigger` arms one fiber that sleeps for *delay* and then runs
  # the action; triggers arriving while the fiber is armed are absorbed.
  # `flush` runs the action immediately when a run is pending and `cancel`
  # drops it. Runs are never overlapped: a trigger during a run arms a new
  # fiber once the run completes.
  class Debouncer
    Log = ::Log.for("matter.debouncer")

    getter delay : Time::Span

    @action : Proc(Nil)
    @pending : Bool = false
    @armed : Bool = false

    def initialize(@delay : Time::Span, &@action : -> Nil)
    end

    # True when a run has been requested and has not happened yet.
    def pending? : Bool
      @pending
    end

    # Requests a run after `delay`.
    def trigger : Nil
      @pending = true
      return if @armed

      @armed = true
      spawn(name: "debouncer") do
        sleep @delay
        @armed = false
        run if @pending
      end
    end

    # Runs the action now if a run is pending. Any armed fiber wakes up to
    # find nothing pending and exits.
    def flush : Nil
      run if @pending
    end

    # Drops a pending run without executing it.
    def cancel : Nil
      @pending = false
    end

    private def run : Nil
      @pending = false
      @action.call
    rescue ex
      Log.error(exception: ex) { "debounced action failed" }
    end
  end
end
