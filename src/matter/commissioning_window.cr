require "log"

module Matter
  # CommissioningWindow manages the state of the commissioning window
  #
  # The commissioning window is a time-limited period during which a device
  # accepts incoming PASE (Password-Authenticated Session Establishment) sessions
  # for onboarding new administrators or updating credentials.
  #
  # There are two types of commissioning windows:
  # - Basic: Uses the device's default setup PIN
  # - Enhanced: Uses a dynamically-generated PAKE verifier
  #
  # Matter Core Spec §5.5 - Commissioning Flows
  # Matter Core Spec §11.19 - Administrator Commissioning Cluster
  class CommissioningWindow
    Log = ::Log.for("matter.commissioning_window")

    # Window status
    enum Status
      Closed   = 0
      Basic    = 1
      Enhanced = 2
    end

    # Current window status
    property status : Status

    # Fabric index of the administrator who opened the window
    property admin_fabric_index : UInt8?

    # Vendor ID of the administrator who opened the window
    property admin_vendor_id : UInt16?

    # Discriminator used for discovery (12-bit value)
    property discriminator : UInt16?

    # Timeout expiry time
    property expires_at : Time?

    # Callback invoked when window times out
    @timeout_callback : Proc(Nil)?

    def initialize
      @status = Status::Closed
      @admin_fabric_index = nil
      @admin_vendor_id = nil
      @discriminator = nil
      @expires_at = nil
      @timeout_callback = nil
      Log.debug { "CommissioningWindow initialized (closed)" }
    end

    # Open a commissioning window
    #
    # @param status Window status (Basic or Enhanced)
    # @param admin_fabric_index Fabric index of administrator opening window
    # @param admin_vendor_id Vendor ID of administrator
    # @param discriminator Discriminator for DNS-SD advertising
    # @param timeout_seconds Window timeout in seconds
    # @param timeout_callback Callback invoked when window times out
    def open(
      status : Status,
      admin_fabric_index : UInt8?,
      admin_vendor_id : UInt16?,
      discriminator : UInt16,
      timeout_seconds : UInt16,
      timeout_callback : Proc(Nil)? = nil,
    ) : Nil
      raise ArgumentError.new("Cannot open commissioning window: status must be Basic or Enhanced") if status == Status::Closed

      @status = status
      @admin_fabric_index = admin_fabric_index
      @admin_vendor_id = admin_vendor_id
      @discriminator = discriminator
      @expires_at = Time.utc + timeout_seconds.seconds
      @timeout_callback = timeout_callback

      Log.info { "Commissioning window opened: status=#{status}, discriminator=#{discriminator}, timeout=#{timeout_seconds}s, admin_fabric=#{admin_fabric_index}" }
    end

    # Close the commissioning window
    #
    # This method is called:
    # - When commissioning completes successfully
    # - When RevokeCommissioning command is received
    # - During failsafe rollback
    # - When the window times out
    def close : Nil
      return if @status == Status::Closed

      previous_status = @status

      @status = Status::Closed
      @admin_fabric_index = nil
      @admin_vendor_id = nil
      @discriminator = nil
      @expires_at = nil
      @timeout_callback = nil

      Log.info { "Commissioning window closed (was: #{previous_status})" }
    end

    # Check if window is open
    def open? : Bool
      @status != Status::Closed
    end

    # Check if window is closed
    def closed? : Bool
      @status == Status::Closed
    end

    # Check if window has expired
    def expired? : Bool
      if expires_at = @expires_at
        Time.utc >= expires_at
      else
        false
      end
    end

    # Get time remaining on window
    def time_remaining : Time::Span?
      if expires_at = @expires_at
        remaining = expires_at - Time.utc
        remaining > Time::Span.zero ? remaining : Time::Span.zero
      end
    end

    # Handle window timeout
    #
    # This should be called periodically by a timer or when checking window status.
    # If the window has expired, it closes the window and invokes the timeout callback.
    def check_timeout : Nil
      return unless open?

      if expired?
        Log.warn { "Commissioning window timeout" }
        callback = @timeout_callback
        close
        callback.try &.call
      end
    end

    # Get window statistics
    def statistics : Hash(String, String | Bool | Int32 | UInt8 | UInt16?)
      {
        "status"             => @status.to_s,
        "open"               => open?,
        "admin_fabric_index" => @admin_fabric_index,
        "admin_vendor_id"    => @admin_vendor_id ? @admin_vendor_id.to_s(16) : nil,
        "discriminator"      => @discriminator,
        "expires_at"         => @expires_at ? @expires_at.to_s : nil,
        "time_remaining_sec" => time_remaining ? time_remaining.total_seconds.to_i : nil,
        "expired"            => expired?,
      }
    end
  end
end
