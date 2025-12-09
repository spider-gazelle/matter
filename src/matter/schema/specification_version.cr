# Specification Version Schema for Matter protocol
# Encodes/decodes Matter specification version numbers
#
# Ported from matter.js SpecificationVersionSchema.ts

module Matter
  module Schema
    # Represents a Matter specification version with major, minor, patch components
    struct SpecificationVersionData
      property major : UInt8
      property minor : UInt8
      property patch : UInt8
      property reserved : UInt8

      def initialize(@major : UInt8, @minor : UInt8, @patch : UInt8, @reserved : UInt8 = 0_u8)
      end
    end

    # Schema for encoding/decoding specification versions
    # Format: 0xMMmmPPrr where MM=major, mm=minor, PP=patch, rr=reserved
    module SpecificationVersion
      # Current Matter specification version (1.4.2)
      SPECIFICATION_VERSION = 0x01040200_u32

      # Encode a version struct to a 32-bit integer
      def self.encode(version : SpecificationVersionData) : UInt32
        (version.major.to_u32 << 24) |
          (version.minor.to_u32 << 16) |
          (version.patch.to_u32 << 8) |
          version.reserved.to_u32
      end

      # Encode a version from components to a 32-bit integer
      def self.encode(major : UInt8, minor : UInt8, patch : UInt8, reserved : UInt8 = 0_u8) : UInt32
        encode(SpecificationVersionData.new(major, minor, patch, reserved))
      end

      # Decode a 32-bit integer to a version struct
      def self.decode(encoded : UInt32) : SpecificationVersionData
        SpecificationVersionData.new(
          major: ((encoded >> 24) & 0xFF).to_u8,
          minor: ((encoded >> 16) & 0xFF).to_u8,
          patch: ((encoded >> 8) & 0xFF).to_u8,
          reserved: (encoded & 0xFF).to_u8
        )
      end

      # Get the current specification version as a struct
      def self.current : SpecificationVersionData
        decode(SPECIFICATION_VERSION)
      end

      # Format a version as a string (e.g., "1.4.2")
      def self.to_s(version : SpecificationVersionData) : String
        "#{version.major}.#{version.minor}.#{version.patch}"
      end

      def self.to_s(encoded : UInt32) : String
        to_s(decode(encoded))
      end
    end
  end
end
