module Matter
  module MDNS
    # Commissioning Mode for mDNS advertisement
    enum CommissioningMode : UInt8
      Disabled = 0 # Not accepting commissioning
      Basic    = 1 # Basic commissioning window (default passcode)
      Enhanced = 2 # Enhanced commissioning window (custom verifier)
    end

    # Pairing Hint Bitmap (20 bits total)
    #
    # RFC: Matter Core Spec §4.3.1 - Commissioning Discovery
    @[Flags]
    enum PairingHint : UInt32
      PowerCycle         = 0x0001 # Pair by power cycling the device
      DeviceManual       = 0x0002 # See device manual for pairing instructions
      DeviceManufacturer = 0x0004 # See manufacturer website
      NFC                = 0x0008 # Use NFC
      QRCode             = 0x0010 # Scan QR code
      Bluetooth          = 0x0020 # Use Bluetooth
      ThirdPartyApp      = 0x0040 # Use third-party app
      # Bits 7-19 reserved
    end

    # Service description for a commissionable Matter device
    #
    # Contains all information needed to advertise the device via mDNS
    struct CommissionableServiceDescription
      # Device name (DN field)
      property name : String

      # Device type (DT field) - e.g., 1 for Light, 2 for Switch
      property device_type : UInt32

      # Vendor ID (part of VP field)
      property vendor_id : UInt16

      # Product ID (part of VP field)
      property product_id : UInt16

      # Discriminator (D field) - 12-bit value (0-4095)
      property discriminator : UInt16

      # Commissioning mode (CM field)
      property mode : CommissioningMode

      # Pairing hint (PH field) - optional
      property pairing_hint : PairingHint?

      # Pairing instructions (PI field) - optional, required if PH has certain bits
      property pairing_instructions : String?

      # Session Idle Interval in milliseconds (SII field) - optional
      property session_idle_interval_ms : UInt32?

      # Session Active Interval in milliseconds (SAI field) - optional
      property session_active_interval_ms : UInt32?

      # Session Active Threshold in milliseconds (SAT field) - optional
      property session_active_threshold_ms : UInt16?

      # TCP support (T field) - optional
      property? tcp_supported : Bool = false

      # ICD (Intermittently Connected Device) operating mode - optional
      property icd_operating_mode : UInt8?

      def initialize(
        @name,
        @device_type,
        @vendor_id,
        @product_id,
        @discriminator,
        @mode,
        @pairing_hint = nil,
        @pairing_instructions = nil,
        @session_idle_interval_ms = nil,
        @session_active_interval_ms = nil,
        @session_active_threshold_ms = nil,
        @tcp_supported = false,
        @icd_operating_mode = nil,
      )
        # Validate discriminator is 12-bit
        raise ArgumentError.new("Discriminator must be 0-4095 (12-bit)") if @discriminator > 4095
      end

      # Get short discriminator (upper 4 bits of 12-bit discriminator)
      def short_discriminator : UInt8
        ((@discriminator >> 8) & 0x0F).to_u8
      end

      # Get long discriminator (full 12-bit value)
      def long_discriminator : UInt16
        @discriminator & 0x0FFF
      end

      # Generate VP field value (vendor+product ID)
      def vendor_product : String
        "#{@vendor_id}+#{@product_id}"
      end
    end

    # Service description for an operational Matter device
    #
    # Used after commissioning is complete
    struct OperationalServiceDescription
      # Fabric index
      property fabric_index : UInt8

      # Node ID within the fabric
      property node_id : UInt64

      # Compressed fabric ID (8-byte HKDF-derived value)
      # This is used for mDNS service discovery sub-types
      property compressed_fabric_id : Bytes

      def initialize(@fabric_index, @node_id, @compressed_fabric_id)
      end

      # Operational ID for sub-type browsing
      # Returns the compressed fabric ID as an uppercase hex string (16 characters)
      #
      # Format: XXXXXXXXXXXXXXXX (16 hex digits representing 8 bytes)
      # Example: "1234567890ABCDEF"
      #
      # This is used as the sub-type in mDNS operational discovery:
      # _<compressed-fabric-id>-<node-id>._sub._matter._tcp.local
      def operational_id : String
        @compressed_fabric_id.hexstring.upcase
      end
    end
  end
end
