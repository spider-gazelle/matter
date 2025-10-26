require "log"

module Matter
  module Clusters
    # Administrator Commissioning Cluster (0x003C)
    #
    # Provides commands to open and close commissioning windows for device onboarding.
    # Administrators can open enhanced windows (with custom PAKE verifier) or basic
    # windows (with default passcode) to allow new commissioners to join the fabric.
    #
    # Matter Core Spec §11.19 - Administrator Commissioning Cluster
    class AdministratorCommissioning
      Log = ::Log.for("matter.cluster.administrator_commissioning")

      CLUSTER_ID = 0x003C_u16

      # Commissioning Window Status
      enum WindowStatus : UInt8
        WindowNotOpen      = 0
        EnhancedWindowOpen = 1
        BasicWindowOpen    = 2
      end

      # Commissioning Error Codes
      enum StatusCode : UInt8
        Busy               = 2
        PAKEParameterError = 3
        WindowNotOpen      = 4
      end

      # PAKE Constants
      CRYPTO_GROUP_SIZE_BYTES       =      32 # w0 size
      CRYPTO_PUBLIC_KEY_SIZE_BYTES  =      65 # L size (point on curve)
      PAKE_PASSCODE_VERIFIER_LENGTH =      97 # w0 (32) + L (65)
      PBKDF2_MIN_ITERATIONS         =    1000
      PBKDF2_MAX_ITERATIONS         = 100_000
      PAKE_SALT_MIN_LENGTH          =      16
      PAKE_SALT_MAX_LENGTH          =      32

      # Timeout Constants (in seconds)
      MINIMUM_COMMISSIONING_TIMEOUT  =   180_u16 # 3 minutes
      STANDARD_COMMISSIONING_TIMEOUT =   900_u16 # 15 minutes (default max)
      MAXIMUM_COMMISSIONING_TIMEOUT  = 65535_u16 # ~18 hours (UInt16 max, extended commissioning)

      # ========================================================================
      # Attributes
      # ========================================================================

      # WindowStatus attribute (0x0000) - current commissioning window state
      property window_status : WindowStatus = WindowStatus::WindowNotOpen

      # AdminFabricIndex attribute (0x0001) - fabric that opened the window
      property admin_fabric_index : UInt8?

      # AdminVendorId attribute (0x0002) - vendor ID of opening administrator
      property admin_vendor_id : UInt16?

      # ========================================================================
      # State Management
      # ========================================================================

      @commissioning_timeout_fiber : Fiber?
      @commissioning_timeout_channel : Channel(Nil)?
      @minimum_commissioning_timeout : UInt16 = MINIMUM_COMMISSIONING_TIMEOUT
      @maximum_commissioning_timeout : UInt16 = STANDARD_COMMISSIONING_TIMEOUT

      def initialize
        @commissioning_timeout_fiber = nil
        @commissioning_timeout_channel = nil
      end

      # Configure timeout bounds (for testing)
      def configure_timeout_bounds(minimum : UInt16, maximum : UInt16) : Nil
        @minimum_commissioning_timeout = minimum
        @maximum_commissioning_timeout = maximum
      end

      # ========================================================================
      # OpenCommissioningWindow Command (0x00) - Enhanced
      # ========================================================================

      # OpenCommissioningWindow command request (Enhanced)
      struct OpenCommissioningWindowRequest
        property commissioning_timeout : UInt16
        property pake_passcode_verifier : Bytes
        property discriminator : UInt16
        property iterations : UInt32
        property salt : Bytes

        def initialize(
          @commissioning_timeout,
          @pake_passcode_verifier,
          @discriminator,
          @iterations,
          @salt,
        )
        end
      end

      # Handle OpenCommissioningWindow command (Enhanced)
      #
      # Opens an enhanced commissioning window with custom PAKE verifier.
      # The verifier is pre-computed by the administrator from an ephemeral passcode.
      #
      # @param request OpenCommissioningWindow request
      # @param session_fabric_index Fabric index of requesting session
      # @return nil on success, raises exception on error
      def open_commissioning_window(
        request : OpenCommissioningWindowRequest,
        session_fabric_index : UInt8?,
        session_vendor_id : UInt16?,
      ) : Nil
        Log.info { "OpenCommissioningWindow: timeout=#{request.commissioning_timeout}s, discriminator=#{request.discriminator}" }

        # Validate PAKE parameters
        validate_pake_parameters(
          request.pake_passcode_verifier,
          request.iterations,
          request.salt
        )

        # Validate timeout bounds
        validate_timeout(request.commissioning_timeout)

        # Check if window already open
        if @window_status != WindowStatus::WindowNotOpen
          raise BusyError.new("A commissioning window is already opened")
        end

        # Initialize commissioning window
        initialize_commissioning_window(
          timeout: request.commissioning_timeout,
          status: WindowStatus::EnhancedWindowOpen,
          admin_fabric_index: session_fabric_index,
          admin_vendor_id: session_vendor_id
        )

        # TODO: Configure PASE server with verifier
        # PaseServer.from_verification_value(
        #   verifier: request.pake_passcode_verifier,
        #   iterations: request.iterations,
        #   salt: request.salt
        # )

        Log.info { "Enhanced commissioning window opened for #{request.commissioning_timeout}s" }
      end

      # ========================================================================
      # OpenBasicCommissioningWindow Command (0x01) - Basic
      # ========================================================================

      # OpenBasicCommissioningWindow command request (Basic)
      struct OpenBasicCommissioningWindowRequest
        property commissioning_timeout : UInt16

        def initialize(@commissioning_timeout)
        end
      end

      # Handle OpenBasicCommissioningWindow command (Basic)
      #
      # Opens a basic commissioning window with device's default passcode.
      # PBKDF2 parameters are auto-generated (iterations=1000, salt=random).
      #
      # @param request OpenBasicCommissioningWindow request
      # @param session_fabric_index Fabric index of requesting session
      # @return nil on success, raises exception on error
      def open_basic_commissioning_window(
        request : OpenBasicCommissioningWindowRequest,
        session_fabric_index : UInt8?,
        session_vendor_id : UInt16?,
      ) : Nil
        Log.info { "OpenBasicCommissioningWindow: timeout=#{request.commissioning_timeout}s" }

        # Validate timeout bounds
        validate_timeout(request.commissioning_timeout)

        # Check if window already open
        if @window_status != WindowStatus::WindowNotOpen
          raise BusyError.new("A commissioning window is already opened")
        end

        # Initialize commissioning window
        initialize_commissioning_window(
          timeout: request.commissioning_timeout,
          status: WindowStatus::BasicWindowOpen,
          admin_fabric_index: session_fabric_index,
          admin_vendor_id: session_vendor_id
        )

        # TODO: Configure PASE server with default PIN
        # iterations = 1000_u32
        # salt = Random::Secure.random_bytes(32)
        # PaseServer.from_pin(default_passcode, iterations, salt)

        Log.info { "Basic commissioning window opened for #{request.commissioning_timeout}s" }
      end

      # ========================================================================
      # RevokeCommissioning Command (0x02)
      # ========================================================================

      # Handle RevokeCommissioning command
      #
      # Closes any open commissioning window and stops accepting new PASE sessions.
      #
      # @return nil on success, raises exception if no window open
      def revoke_commissioning : Nil
        Log.info { "RevokeCommissioning" }

        # Check if window currently open
        if @window_status == WindowStatus::WindowNotOpen
          raise WindowNotOpenError.new("No commissioning window is opened that could be revoked")
        end

        # Close commissioning window
        close_commissioning_window

        Log.info { "Commissioning window revoked" }
      end

      # ========================================================================
      # Helper Methods
      # ========================================================================

      # Validate PAKE parameters per Matter spec
      private def validate_pake_parameters(
        verifier : Bytes,
        iterations : UInt32,
        salt : Bytes,
      ) : Nil
        # Validate verifier length
        unless verifier.size == PAKE_PASSCODE_VERIFIER_LENGTH
          raise PAKEParameterError.new(
            "PAKE passcode verifier length is invalid (expected #{PAKE_PASSCODE_VERIFIER_LENGTH}, got #{verifier.size})"
          )
        end

        # Validate iterations range
        unless iterations >= PBKDF2_MIN_ITERATIONS && iterations <= PBKDF2_MAX_ITERATIONS
          raise PAKEParameterError.new(
            "PAKE iterations invalid (must be #{PBKDF2_MIN_ITERATIONS}-#{PBKDF2_MAX_ITERATIONS}, got #{iterations})"
          )
        end

        # Validate salt length
        unless salt.size >= PAKE_SALT_MIN_LENGTH && salt.size <= PAKE_SALT_MAX_LENGTH
          raise PAKEParameterError.new(
            "PAKE salt has invalid length (must be #{PAKE_SALT_MIN_LENGTH}-#{PAKE_SALT_MAX_LENGTH}, got #{salt.size})"
          )
        end
      end

      # Validate commissioning timeout
      private def validate_timeout(timeout : UInt16) : Nil
        if timeout < @minimum_commissioning_timeout
          raise ArgumentError.new(
            "Commissioning timeout must not be lower than #{@minimum_commissioning_timeout} seconds"
          )
        end

        if timeout > @maximum_commissioning_timeout
          raise ArgumentError.new(
            "Commissioning timeout must not exceed #{@maximum_commissioning_timeout} seconds"
          )
        end
      end

      # Initialize commissioning window and start timer
      private def initialize_commissioning_window(
        timeout : UInt16,
        status : WindowStatus,
        admin_fabric_index : UInt8?,
        admin_vendor_id : UInt16?,
      ) : Nil
        # Set attributes
        @window_status = status
        @admin_fabric_index = admin_fabric_index
        @admin_vendor_id = admin_vendor_id

        # Start timeout timer
        start_commissioning_timeout(timeout)

        # Yield to give timeout fiber a chance to start
        Fiber.yield

        Log.debug { "Commissioning window initialized: status=#{status}, admin_fabric=#{admin_fabric_index}" }
      end

      # Start commissioning timeout timer
      private def start_commissioning_timeout(timeout_seconds : UInt16) : Nil
        # Create cancellation channel
        @commissioning_timeout_channel = Channel(Nil).new

        # Start timeout fiber
        @commissioning_timeout_fiber = spawn(name: "Commissioning Timeout") do
          channel = @commissioning_timeout_channel
          next unless channel

          select
          when timeout(timeout_seconds.seconds)
            unless @window_status == WindowStatus::WindowNotOpen
              Log.warn { "Commissioning window timeout after #{timeout_seconds}s" }
              handle_commissioning_timeout
              Fiber.yield # Allow other fibers to see the changes
            end
          when channel.receive
            # Timer cancelled
            Log.debug { "Commissioning timeout cancelled" }
          end
        end
      end

      # Handle commissioning timeout expiry
      private def handle_commissioning_timeout : Nil
        Log.warn { "Commissioning window timed out - closing window" }
        close_commissioning_window
      end

      # Close commissioning window and reset state
      private def close_commissioning_window : Nil
        # Stop timer
        stop_commissioning_timeout

        # Reset attributes
        @window_status = WindowStatus::WindowNotOpen
        @admin_fabric_index = nil
        @admin_vendor_id = nil

        # TODO: Stop PASE server
        # TODO: Stop DNS-SD advertising
        # TODO: Close failsafe if armed

        Log.info { "Commissioning window closed" }
      end

      # Stop commissioning timeout timer
      private def stop_commissioning_timeout : Nil
        # Don't try to send to channel if we're in the timeout fiber
        # (it's already past the select block)
        if channel = @commissioning_timeout_channel
          # Only send if we're not the timeout fiber
          if Fiber.current != @commissioning_timeout_fiber
            channel.send(nil) rescue nil
          end
          @commissioning_timeout_channel = nil
        end
        @commissioning_timeout_fiber = nil
      end

      # Check if commissioning window is open
      def window_open? : Bool
        @window_status != WindowStatus::WindowNotOpen
      end

      # Get time remaining on commissioning window (for testing)
      def time_remaining : Time::Span?
        # TODO: Track start time and calculate remaining time
        nil
      end

      # Close and cleanup (for testing/shutdown)
      def close : Nil
        if window_open?
          close_commissioning_window
        end
      end

      # ========================================================================
      # Exception Classes
      # ========================================================================

      class BusyError < Exception
        def cluster_code : UInt8
          StatusCode::Busy.value
        end
      end

      class PAKEParameterError < Exception
        def cluster_code : UInt8
          StatusCode::PAKEParameterError.value
        end
      end

      class WindowNotOpenError < Exception
        def cluster_code : UInt8
          StatusCode::WindowNotOpen.value
        end
      end
    end
  end
end
