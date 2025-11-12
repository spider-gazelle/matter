module Matter
  # SetupPayload handles encoding and decoding of Matter onboarding payloads
  #
  # Matter devices use two types of setup codes:
  # 1. Manual Pairing Code: 11-digit decimal code (formatted as xxxx-xxx-xxxx)
  # 2. QR Code: Longer base38-encoded string with additional device information
  #
  # Manual Pairing Code Format (Matter Core Spec § 5.1.4.1):
  # - Bits 0-26: Setup PIN Code (27 bits)
  # - Bits 27-38: Discriminator (12 bits)
  # - Bit 39: Check digit (4 bits, Verhoeff algorithm)
  #
  # The 11-digit code is computed as: (discriminator << 27) | PIN
  # Then the Verhoeff check digit is appended.
  module SetupPayload
    # Verhoeff check digit algorithm
    # Used by Matter for manual pairing code validation
    module Verhoeff
      # Multiplication table
      D = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
        [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
        [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
        [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
        [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
        [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
        [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
        [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
        [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
      ]

      # Permutation table
      P = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
        [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
        [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
        [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
        [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
        [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
        [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
      ]

      # Inverse table
      INV = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9]

      # Compute Verhoeff check digit for a number string
      def self.compute(num : String) : Int32
        c = 0
        num.reverse.chars.each_with_index do |char, i|
          digit = char.to_i
          c = D[c][P[(i + 1) % 8][digit]]
        end
        INV[c]
      end

      # Validate a number string with Verhoeff check digit
      def self.validate(num_with_check : String) : Bool
        c = 0
        num_with_check.reverse.chars.each_with_index do |char, i|
          digit = char.to_i
          c = D[c][P[i % 8][digit]]
        end
        c == 0
      end
    end

    # Generate a manual pairing code from discriminator and PIN
    #
    # @param discriminator Device discriminator (12-bit value, 0-4095)
    # @param pin Setup PIN code (27-bit value, 1-99999998, excluding invalid PINs)
    # @param validate Whether to validate PIN security requirements (default: true)
    # @return 11-digit manual pairing code string (formatted as xxxx-xxx-xxxx)
    #
    # Algorithm from matter.js PairingCodeSchema.ts (Matter Core Spec § 5.1.4.1)
    def self.generate_manual_code(discriminator : UInt16, pin : UInt32, validate : Bool = true) : String
      # Validate discriminator (12 bits = 0-4095)
      raise ArgumentError.new("Discriminator must be 0-4095") if discriminator > 4095

      if validate
        # Validate PIN (27 bits, but Matter has specific restrictions)
        # PIN must be 1-99999998 and cannot be:
        # - 00000000, 11111111, 22222222, ..., 99999999
        # - 12345678, 87654321
        raise ArgumentError.new("PIN must be 1-99999998") if pin < 1 || pin > 99999998

        # Check for invalid repeating digit PINs
        pin_str = pin.to_s.rjust(8, '0')
        if pin_str.chars.uniq.size == 1
          raise ArgumentError.new("PIN cannot be all the same digit")
        end

        # Check for specific invalid PINs
        if pin == 12345678 || pin == 87654321
          raise ArgumentError.new("PIN cannot be 12345678 or 87654321")
        end
      else
        # Minimal validation even when validate=false
        raise ArgumentError.new("PIN must be 1-99999998") if pin < 1 || pin > 99999998
      end

      # Encode using matter.js algorithm (matches Matter Core Spec § 5.1.4.1)
      # This encodes 10 digits before the check digit:
      # - Digit 1: Top 2 bits of discriminator (bits 10-11)
      # - Digits 2-6: Mixed discriminator (bits 8-9) and passcode (bits 0-13)
      # - Digits 7-10: Top bits of passcode (bits 14-27)

      result = ""

      # Digit 1: Top 2 bits of discriminator
      result += (discriminator >> 10).to_s

      # Digits 2-6: ((discriminator & 0x300) << 6) | (passcode & 0x3fff)
      # - discriminator & 0x300 isolates bits 8-9 of discriminator
      # - << 6 shifts left by 6 positions
      # - passcode & 0x3fff gets bottom 14 bits of passcode
      part2 = ((discriminator & 0x300) << 6) | (pin & 0x3fff)
      result += part2.to_s.rjust(5, '0')

      # Digits 7-10: Top bits of passcode (passcode >> 14)
      part3 = pin >> 14
      result += part3.to_s.rjust(4, '0')

      # Compute Verhoeff check digit
      check_digit = Verhoeff.compute(result)

      # Append check digit to get 11-digit code
      full_code = result + check_digit.to_s

      # Format as xxxx-xxx-xxxx
      format_manual_code(full_code)
    end

    # Format an 11-digit code as xxxx-xxx-xxxx
    def self.format_manual_code(code : String) : String
      raise ArgumentError.new("Code must be 11 digits") if code.size != 11
      "#{code[0..3]}-#{code[4..6]}-#{code[7..10]}"
    end

    # Parse a formatted manual code back to discriminator and PIN
    #
    # @param formatted_code Manual code in xxxx-xxx-xxxx format (or with spaces/dashes stripped)
    # @return Tuple of {discriminator, pin}
    #
    # Note: Manual pairing codes only encode the SHORT discriminator (top 4 bits of the full 12-bit discriminator).
    # This function reconstructs the full discriminator from those 4 bits by assuming the lower 8 bits are zero.
    # Algorithm from matter.js PairingCodeSchema.ts
    def self.parse_manual_code(formatted_code : String) : {UInt16, UInt32}
      # Remove non-digit characters (dashes, spaces)
      code = formatted_code.gsub(/\D/, "")
      raise ArgumentError.new("Code must be 11 digits") if code.size != 11

      # Validate check digit
      unless Verhoeff.validate(code)
        raise ArgumentError.new("Invalid check digit")
      end

      # Decode using matter.js algorithm (reverse of encoding)
      # Digit 1: Contains top 2 bits of short discriminator + optional vendor/product flag
      digit1 = code[0].to_i

      # Digits 2-6: Contains bottom 2 bits of short discriminator (in high bits) + bottom 14 bits of passcode
      digits_2_6 = code[1..5].to_i

      # Digits 7-10: Contains top 14 bits of passcode (passcode >> 14)
      digits_7_10 = code[6..9].to_i

      # Extract short discriminator (4 bits)
      # Top 2 bits from digit 1 (bits 0-1, since bit 2 is vendor/product flag)
      # Bottom 2 bits from high bits of digits_2_6
      short_discriminator = ((digit1 & 0x03) << 2) | ((digits_2_6 >> 14) & 0x3)

      # Extract passcode (27 bits)
      # Bottom 14 bits from digits_2_6, top 14 bits from digits_7_10
      passcode = (digits_2_6 & 0x3fff) | (digits_7_10 << 14)

      # Convert short discriminator (4 bits) back to full discriminator (12 bits)
      # The short discriminator is the top 4 bits (bits 8-11) of the full discriminator
      # So shift left by 8 to position them correctly
      discriminator = (short_discriminator << 8).to_u16

      {discriminator, passcode.to_u32}
    end

    # Generate a default PIN for testing/examples
    # Returns a valid PIN that's easy to remember
    def self.default_pin : UInt32
      20202021_u32 # A valid PIN that's not on the blacklist
    end

    # Compute the short discriminator (4 bits: bits 8-11 of the full 12-bit discriminator)
    # This is what gets encoded in manual pairing codes
    def self.short_discriminator(discriminator : UInt16) : UInt16
      (discriminator >> 8).to_u16
    end

    # QR Code payload generation for Matter onboarding
    #
    # Matter QR codes encode more information than manual codes:
    # - Vendor ID and Product ID
    # - Flow type and discovery capabilities
    # - Discriminator and setup PIN
    #
    # The payload uses TLV encoding and base-38 representation with "MT:" prefix
    #
    # Matter Core Spec § 5.1.4.2 - QR Code Format
    module QRCode
      # Commission flow types
      enum CommissionFlow : UInt8
        Standard         = 0 # Device not on IP network, needs commissioning
        UserActionNeeded = 1 # Device requires user action (e.g., press button)
        Custom           = 2 # Custom commissioning flow
        AlreadyOnNetwork = 3 # Device already on IP network
      end

      # Discovery capability flags
      @[Flags]
      enum DiscoveryCapability : UInt8
        None      = 0x00
        SoftAP    = 0x01 # WiFi soft access point
        BLE       = 0x02 # Bluetooth Low Energy
        OnNetwork = 0x04 # Already on IP network
      end

      # Base-38 alphabet for Matter QR codes
      BASE38_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-."

      # Generate Matter QR code payload string
      #
      # @param discriminator Device discriminator (12-bit)
      # @param pin Setup PIN code (27-bit)
      # @param vendor_id Vendor ID (16-bit)
      # @param product_id Product ID (16-bit)
      # @param flow Commission flow type
      # @param capabilities Discovery capabilities
      # @return QR code string with "MT:" prefix
      def self.generate_qr_code(
        discriminator : UInt16,
        pin : UInt32,
        vendor_id : UInt16,
        product_id : UInt16,
        flow : CommissionFlow = CommissionFlow::Standard,
        capabilities : DiscoveryCapability = DiscoveryCapability::BLE,
      ) : String
        # Validate inputs
        raise ArgumentError.new("Discriminator must be 0-4095") if discriminator > 4095
        raise ArgumentError.new("PIN must be 1-99999998") if pin < 1 || pin > 99999998

        # Encode payload as bit-packed integer
        # Matter spec defines specific bit layout:
        # Bits 0-2: Version (3 bits) = 0
        # Bits 3-18: Vendor ID (16 bits)
        # Bits 19-34: Product ID (16 bits)
        # Bits 35-36: Flow (2 bits)
        # Bits 37-44: Discovery capabilities (8 bits)
        # Bits 45-56: Discriminator (12 bits)
        # Bits 57-83: Setup PIN (27 bits)
        # Total: 84 bits (exceeds 64-bit, need BigInt)

        version = BigInt.new(0)
        payload = version # Start with version

        payload |= (BigInt.new(vendor_id) << 3)
        payload |= (BigInt.new(product_id) << 19)
        payload |= (BigInt.new(flow.value) << 35)
        payload |= (BigInt.new(capabilities.value) << 37)
        payload |= (BigInt.new(discriminator) << 45)
        payload |= (BigInt.new(pin) << 57)

        # Convert to base-38
        encoded = encode_base38(payload)

        # Add "MT:" prefix per Matter spec
        "MT:#{encoded}"
      end

      # Encode an integer as base-38 string
      private def self.encode_base38(value : BigInt) : String
        return "0" if value == 0

        result = ""
        num = value

        while num > 0
          remainder = (num % 38).to_i
          result = BASE38_ALPHABET[remainder] + result
          num //= 38
        end

        result
      end

      # Decode base-38 string to integer
      private def self.decode_base38(encoded : String) : BigInt
        result = BigInt.new(0)

        encoded.each_char do |char|
          index = BASE38_ALPHABET.index(char)
          raise ArgumentError.new("Invalid character in base-38 string: #{char}") unless index
          result = result * 38 + index
        end

        result
      end

      # Parse Matter QR code payload
      #
      # @param qr_code QR code string (with or without "MT:" prefix)
      # @return Hash with decoded values
      def self.parse_qr_code(qr_code : String) : Hash(Symbol, UInt64 | UInt32 | UInt16 | UInt8)
        # Remove "MT:" prefix if present
        code = qr_code.starts_with?("MT:") ? qr_code[3..-1] : qr_code

        # Decode from base-38 (returns BigInt)
        payload = decode_base38(code)

        # Extract fields using bit masks and convert to appropriate types
        version = (payload & BigInt.new(0x7)).to_u8
        vendor_id = ((payload >> 3) & BigInt.new(0xFFFF)).to_u16
        product_id = ((payload >> 19) & BigInt.new(0xFFFF)).to_u16
        flow = ((payload >> 35) & BigInt.new(0x3)).to_u8
        capabilities = ((payload >> 37) & BigInt.new(0xFF)).to_u8
        discriminator = ((payload >> 45) & BigInt.new(0xFFF)).to_u16
        pin = ((payload >> 57) & BigInt.new(0x7FFFFFF)).to_u32

        {
          :version       => version.to_u64,
          :vendor_id     => vendor_id.as(UInt64 | UInt32 | UInt16 | UInt8),
          :product_id    => product_id.as(UInt64 | UInt32 | UInt16 | UInt8),
          :flow          => flow.as(UInt64 | UInt32 | UInt16 | UInt8),
          :capabilities  => capabilities.as(UInt64 | UInt32 | UInt16 | UInt8),
          :discriminator => discriminator.as(UInt64 | UInt32 | UInt16 | UInt8),
          :pin           => pin.as(UInt64 | UInt32 | UInt16 | UInt8),
        }
      end
    end
  end
end
