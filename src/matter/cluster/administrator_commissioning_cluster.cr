require "log"
require "./cluster"
require "./definitions/administrator_commissioning"
require "../mdns"

module Matter
  module Cluster
    # Administrator Commissioning Cluster (0x003C)
    #
    # Provides commands to open and close commissioning windows for device onboarding.
    # Administrators can open enhanced windows (with custom PAKE verifier) or basic
    # windows (with default passcode) to allow new commissioners to join the fabric.
    #
    # This cluster provides functionality for opening commissioning windows to allow
    # new administrators to commission the device. Supports both enhanced commissioning
    # (with custom PAKE verifier) and basic commissioning (with default passcode).
    #
    # Matter Core Spec §11.19 - Administrator Commissioning Cluster
    class AdministratorCommissioningCluster < Base
      Log = ::Log.for("matter.cluster.administrator_commissioning")

      CLUSTER_ID = 0x003C_u32

      # ========================================================================
      # Enums
      # ========================================================================

      # Commissioning Window Status
      enum CommissioningWindowStatus : UInt8
        WindowNotOpen      = 0 # No commissioning window open
        EnhancedWindowOpen = 1 # Enhanced commissioning window open (PAKE)
        BasicWindowOpen    = 2 # Basic commissioning window open
      end

      # Status Codes
      enum StatusCode : UInt8
        Busy               = 2 # Commissioning window already open
        PAKEParameterError = 3 # Invalid PAKE parameters
        WindowNotOpen      = 4 # No window open for revocation
      end

      # ========================================================================
      # PAKE Constants
      # ========================================================================

      CRYPTO_GROUP_SIZE_BYTES       =      32 # w0 size
      CRYPTO_PUBLIC_KEY_SIZE_BYTES  =      65 # L size (point on curve)
      PAKE_PASSCODE_VERIFIER_LENGTH =      97 # w0 (32) + L (65)
      PBKDF2_MIN_ITERATIONS         =    1000
      PBKDF2_MAX_ITERATIONS         = 100_000
      PAKE_SALT_MIN_LENGTH          =      16
      PAKE_SALT_MAX_LENGTH          =      32

      # ========================================================================
      # Timeout Constants (in seconds)
      # ========================================================================

      MINIMUM_COMMISSIONING_TIMEOUT  =   180_u16 # 3 minutes
      STANDARD_COMMISSIONING_TIMEOUT =   900_u16 # 15 minutes (default max)
      MAXIMUM_COMMISSIONING_TIMEOUT  = 65535_u16 # ~18 hours (UInt16 max, extended commissioning)

      # ========================================================================
      # Attribute IDs
      # ========================================================================

      ATTR_WINDOW_STATUS      = 0x0000_u32
      ATTR_ADMIN_FABRIC_INDEX = 0x0001_u32
      ATTR_ADMIN_VENDOR_ID    = 0x0002_u32

      # ========================================================================
      # Command IDs
      # ========================================================================

      CMD_OPEN_COMMISSIONING_WINDOW       = 0x00_u32
      CMD_OPEN_BASIC_COMMISSIONING_WINDOW = 0x01_u32
      CMD_REVOKE_COMMISSIONING            = 0x02_u32

      # ========================================================================
      # Use definitions for command structs (they have TLV::Serializable)
      alias OpenCommissioningWindowRequest = Definitions::AdministratorCommissioning::OpenCommissioningWindowRequest
      alias OpenBasicCommissioningWindowRequest = Definitions::AdministratorCommissioning::OpenBasicCommissioningWindowRequest

      # ========================================================================
      # Attributes
      # ========================================================================

      # WindowStatus attribute (0x0000) - current commissioning window state
      property window_status : CommissioningWindowStatus

      # AdminFabricIndex attribute (0x0001) - fabric that opened the window
      property admin_fabric_index : UInt8?

      # AdminVendorId attribute (0x0002) - vendor ID of opening administrator
      property admin_vendor_id : UInt16?

      # ========================================================================
      # Device Information (for DNS-SD advertising)
      # ========================================================================

      property device_name : String = "Matter Device"
      property device_type : UInt32 = 0_u32             # Unknown device type
      property vendor_id : UInt16 = 0xFFF1_u16          # Test vendor ID
      property product_id : UInt16 = 0x8000_u16         # Test product ID
      property addresses : Array(String) = [] of String # IP addresses to advertise

      # ========================================================================
      # Window State (for backward compatibility with cluster/ version)
      # ========================================================================

      property window_timeout : Time?

      # PAKE parameters (for enhanced commissioning)
      property pake_verifier : Bytes?
      property discriminator : UInt16?
      property iterations : UInt32?
      property salt : Bytes?

      # Session context (set by the session before invoking commands)
      property session_fabric_index : UInt8?
      property session_vendor_id : UInt16?

      # ========================================================================
      # Internal State Management
      # ========================================================================

      @commissioning_timeout_fiber : Fiber?
      @commissioning_timeout_channel : Channel(Nil)?
      @minimum_commissioning_timeout : UInt16
      @maximum_commissioning_timeout : UInt16
      @mdns_advertiser : MDNS::Advertiser?
      @window_start_time : Time?
      @window_expiry_time : Time?

      # ========================================================================
      # Callbacks
      # ========================================================================

      # Callbacks for external component integration
      property on_configure_pase_server : Proc(Bytes, UInt32, Bytes, Nil)? # (verifier, iterations, salt) -> nil
      property on_configure_pase_pin : Proc(UInt32, UInt32, Bytes, Nil)?   # (pin, iterations, salt) -> nil
      property on_stop_pase_server : Proc(Nil)?
      property on_close_failsafe : Proc(Nil)?

      # mDNS advertising integration.
      # If set, the cluster will not use the legacy `MDNS::Advertiser` implementation.
      property on_start_commissioning_advertising : Proc(UInt16, MDNS::CommissioningMode, Nil)? # (discriminator, mode) -> nil
      property on_stop_commissioning_advertising : Proc(Nil)?

      # ========================================================================
      # Initialization
      # ========================================================================

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        minimum_timeout : UInt16 = MINIMUM_COMMISSIONING_TIMEOUT,
        maximum_timeout : UInt16 = STANDARD_COMMISSIONING_TIMEOUT,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @window_status = CommissioningWindowStatus::WindowNotOpen
        @admin_fabric_index = nil
        @admin_vendor_id = nil

        @window_timeout = nil
        @pake_verifier = nil
        @discriminator = nil
        @iterations = nil
        @salt = nil

        @session_fabric_index = nil
        @session_vendor_id = nil

        @commissioning_timeout_fiber = nil
        @commissioning_timeout_channel = nil
        @minimum_commissioning_timeout = minimum_timeout
        @maximum_commissioning_timeout = maximum_timeout
        @mdns_advertiser = nil
        @window_start_time = nil
        @window_expiry_time = nil

        @on_configure_pase_server = nil
        @on_configure_pase_pin = nil
        @on_stop_pase_server = nil
        @on_close_failsafe = nil
        @on_start_commissioning_advertising = nil
        @on_stop_commissioning_advertising = nil
      end

      # ========================================================================
      # Base Class Required Methods
      # ========================================================================

      def name : String
        "AdministratorCommissioning"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_WINDOW_STATUS),
            "WindowStatus",
            :enum8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ADMIN_FABRIC_INDEX),
            "AdminFabricIndex",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ADMIN_VENDOR_ID),
            "AdminVendorId",
            :uint16,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_OPEN_COMMISSIONING_WINDOW),
            "OpenCommissioningWindow"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_OPEN_BASIC_COMMISSIONING_WINDOW),
            "OpenBasicCommissioningWindow"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_REVOKE_COMMISSIONING),
            "RevokeCommissioning"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_WINDOW_STATUS
          @window_status.value.to_tlv
        when ATTR_ADMIN_FABRIC_INDEX
          if index = @admin_fabric_index
            index.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_ADMIN_VENDOR_ID
          if vendor = @admin_vendor_id
            vendor.to_tlv
          else
            nil.to_tlv
          end
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only
        super
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_OPEN_COMMISSIONING_WINDOW
          handle_open_commissioning_window(fields)
        when CMD_OPEN_BASIC_COMMISSIONING_WINDOW
          handle_open_basic_commissioning_window(fields)
        when CMD_REVOKE_COMMISSIONING
          handle_revoke_commissioning(fields)
        else
          super
        end
      end

      # ========================================================================
      # Configuration
      # ========================================================================

      # Configure timeout bounds (for testing)
      def configure_timeout_bounds(minimum : UInt16, maximum : UInt16) : Nil
        @minimum_commissioning_timeout = minimum
        @maximum_commissioning_timeout = maximum
      end

      # ========================================================================
      # Public Command Handlers (clusters/ version style)
      # ========================================================================

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
        if @window_status != CommissioningWindowStatus::WindowNotOpen
          raise BusyError.new("A commissioning window is already opened")
        end

        # Initialize commissioning window
        initialize_commissioning_window(
          timeout: request.commissioning_timeout,
          status: CommissioningWindowStatus::EnhancedWindowOpen,
          admin_fabric_index: session_fabric_index,
          admin_vendor_id: session_vendor_id,
          discriminator: request.discriminator
        )

        # Store PAKE parameters
        @pake_verifier = request.pake_passcode_verifier
        @iterations = request.iterations
        @salt = request.salt
        @discriminator = request.discriminator

        # Configure PASE server with verifier (if callback provided)
        if callback = @on_configure_pase_server
          callback.call(
            request.pake_passcode_verifier,
            request.iterations,
            request.salt
          )
          Log.debug { "Configured PASE server with custom verifier" }
        end

        Log.info { "Enhanced commissioning window opened for #{request.commissioning_timeout}s" }
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
        if @window_status != CommissioningWindowStatus::WindowNotOpen
          raise BusyError.new("A commissioning window is already opened")
        end

        # Initialize commissioning window
        # Note: Basic commissioning doesn't include discriminator in request, use default
        initialize_commissioning_window(
          timeout: request.commissioning_timeout,
          status: CommissioningWindowStatus::BasicWindowOpen,
          admin_fabric_index: session_fabric_index,
          admin_vendor_id: session_vendor_id,
          discriminator: 0_u16
        )

        # Configure PASE server with default PIN (if callback provided)
        if callback = @on_configure_pase_pin
          # Use standard parameters for basic commissioning
          iterations = 1000_u32
          salt = Random::Secure.random_bytes(32)
          default_pin = 20202021_u32 # Standard test PIN

          callback.call(default_pin, iterations, salt)
          Log.debug { "Configured PASE server with default PIN" }
        end

        Log.info { "Basic commissioning window opened for #{request.commissioning_timeout}s" }
      end

      # Handle RevokeCommissioning command
      #
      # Closes any open commissioning window and stops accepting new PASE sessions.
      #
      # @return nil on success, raises exception if no window open
      def revoke_commissioning : Nil
        Log.info { "RevokeCommissioning" }

        # Check if window currently open
        if @window_status == CommissioningWindowStatus::WindowNotOpen
          raise WindowNotOpenError.new("No commissioning window is opened that could be revoked")
        end

        # Close commissioning window
        close_commissioning_window

        Log.info { "Commissioning window revoked" }
      end

      # ========================================================================
      # Internal Command Handlers (cluster/ version style)
      # ========================================================================

      private def handle_open_commissioning_window(fields : Bytes) : InteractionModel::Status
        # Parse TLV-encoded command using the TLV library

        request = OpenCommissioningWindowRequest.from_slice(fields)

        fabric_index = @session_fabric_index
        vendor_id = @session_vendor_id

        begin
          open_commissioning_window(request, fabric_index, vendor_id)
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        rescue ex : BusyError
          InteractionModel::Status.new(InteractionModel::StatusCode::Busy)
        rescue ex : PAKEParameterError
          InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
        rescue ex
          InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
        end
      rescue ex
        Log.error(exception: ex) { "OpenCommissioningWindow: failed to parse request (bytes=#{fields.hexstring})" }
        InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
      end

      private def handle_open_basic_commissioning_window(fields : Bytes) : InteractionModel::Status
        # Parse TLV-encoded command using the TLV library

        request = OpenBasicCommissioningWindowRequest.from_slice(fields)

        fabric_index = @session_fabric_index
        vendor_id = @session_vendor_id

        begin
          open_basic_commissioning_window(request, fabric_index, vendor_id)
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        rescue ex : BusyError
          InteractionModel::Status.new(InteractionModel::StatusCode::Busy)
        rescue ex
          InteractionModel::Status.new(InteractionModel::StatusCode::Busy)
        end
      rescue ex
        Log.error(exception: ex) { "OpenBasicCommissioningWindow: failed to parse request (bytes=#{fields.hexstring})" }
        InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
      end

      private def handle_revoke_commissioning(fields : Bytes) : InteractionModel::Status
        # RevokeCommissioning command has no parameters

        revoke_commissioning
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      rescue ex : WindowNotOpenError
        InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
      rescue ex
        InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
      end

      # ========================================================================
      # Window Management Methods
      # ========================================================================

      # Open enhanced commissioning window (with PAKE)
      def open_enhanced_window(timeout_seconds : UInt16, fabric_index : UInt8, vendor_id : UInt16) : Nil
        @window_status = CommissioningWindowStatus::EnhancedWindowOpen
        @admin_fabric_index = fabric_index
        @admin_vendor_id = vendor_id
        @window_timeout = Time.utc + timeout_seconds.seconds
        increment_version
      end

      # Open basic commissioning window
      def open_basic_window(timeout_seconds : UInt16, fabric_index : UInt8, vendor_id : UInt16) : Nil
        @window_status = CommissioningWindowStatus::BasicWindowOpen
        @admin_fabric_index = fabric_index
        @admin_vendor_id = vendor_id
        @window_timeout = Time.utc + timeout_seconds.seconds
        increment_version
      end

      # Close commissioning window (backward compatibility)
      def close_window : Nil
        close_commissioning_window
      end

      # Check if window is expired
      def window_expired? : Bool
        return false unless timeout = @window_timeout
        Time.utc >= timeout
      end

      # Check if any commissioning window is open
      def window_open? : Bool
        !@window_status.window_not_open?
      end

      # ========================================================================
      # Public Query Methods
      # ========================================================================

      # Check if commissioning window is open
      def window_open? : Bool
        @window_status != CommissioningWindowStatus::WindowNotOpen
      end

      # Check if enhanced window is open
      def enhanced_window_open? : Bool
        @window_status == CommissioningWindowStatus::EnhancedWindowOpen
      end

      # Check if basic window is open
      def basic_window_open? : Bool
        @window_status == CommissioningWindowStatus::BasicWindowOpen
      end

      # Get time remaining on commissioning window (for testing)
      def time_remaining : Time::Span?
        return nil unless window_open?
        return nil unless expiry = @window_expiry_time

        remaining = expiry - Time.utc
        remaining > Time::Span.zero ? remaining : Time::Span.zero
      end

      # Close and cleanup (for testing/shutdown)
      def close : Nil
        if window_open?
          close_commissioning_window
        end

        # Cleanup advertiser
        if advertiser = @mdns_advertiser
          advertiser.close
          @mdns_advertiser = nil
        end
      end

      # ========================================================================
      # Private Helper Methods
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
        status : CommissioningWindowStatus,
        admin_fabric_index : UInt8?,
        admin_vendor_id : UInt16?,
        discriminator : UInt16 = 0_u16,
      ) : Nil
        # Set attributes
        @window_status = status
        @admin_fabric_index = admin_fabric_index
        @admin_vendor_id = admin_vendor_id

        # Track window timing
        @window_start_time = Time.utc
        @window_expiry_time = Time.utc + timeout.seconds
        @window_timeout = @window_expiry_time

        # Start DNS-SD advertising
        start_mdns_advertising(discriminator)

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
            unless @window_status == CommissioningWindowStatus::WindowNotOpen
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

      # Start mDNS advertising for commissioning window
      private def start_mdns_advertising(discriminator : UInt16) : Nil
        # Determine commissioning mode
        mode = case @window_status
               when CommissioningWindowStatus::BasicWindowOpen
                 MDNS::CommissioningMode::Basic
               when CommissioningWindowStatus::EnhancedWindowOpen
                 MDNS::CommissioningMode::Enhanced
               else
                 MDNS::CommissioningMode::Disabled
               end

        if callback = @on_start_commissioning_advertising
          callback.call(discriminator, mode)
          Log.info { "Requested commissioning mDNS advertising via callback (discriminator=#{discriminator} mode=#{mode})" }
          return
        end

        return if @addresses.empty?

        begin
          # Create service description
          description = MDNS::CommissionableServiceDescription.new(
            name: @device_name,
            device_type: @device_type,
            vendor_id: @vendor_id,
            product_id: @product_id,
            discriminator: discriminator,
            mode: mode
          )

          # Create advertisement
          advertisement = MDNS::CommissionableAdvertisement.new(description, @addresses)

          # Create and start advertiser if needed
          mdns_advertiser = @mdns_advertiser ||= MDNS::Advertiser.new(Socket::Family::INET)
          mdns_advertiser.start_advertising(advertisement)

          Log.info { "Started mDNS advertising: discriminator=#{discriminator}, mode=#{mode}" }
        rescue ex
          Log.error(exception: ex) { "Failed to start mDNS advertising (discriminator=#{discriminator} mode=#{mode} addresses=#{@addresses.map(&.to_s).join(",")})" }
        end
      end

      # Stop mDNS advertising
      private def stop_mdns_advertising : Nil
        if callback = @on_stop_commissioning_advertising
          callback.call
          Log.info { "Requested commissioning mDNS stop via callback" }
          return
        end

        if advertiser = @mdns_advertiser
          advertiser.stop_advertising
          Log.info { "Stopped mDNS advertising" }
        end
      end

      # Close commissioning window and reset state
      private def close_commissioning_window : Nil
        # Stop DNS-SD advertising
        stop_mdns_advertising

        # Stop timer
        stop_commissioning_timeout

        # Reset attributes
        @window_status = CommissioningWindowStatus::WindowNotOpen
        @admin_fabric_index = nil
        @admin_vendor_id = nil

        # Reset timing
        @window_start_time = nil
        @window_expiry_time = nil
        @window_timeout = nil

        # Clear PAKE parameters
        @pake_verifier = nil
        @discriminator = nil
        @iterations = nil
        @salt = nil

        # Stop PASE server (if callback provided)
        if callback = @on_stop_pase_server
          callback.call
          Log.debug { "Stopped PASE server" }
        end

        # Close failsafe if armed (if callback provided)
        if callback = @on_close_failsafe
          callback.call
          Log.debug { "Requested failsafe closure" }
        end

        # Increment data version
        increment_version

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
