# CaseAuthenticatedTag datatype for Matter protocol
#
# A CaseAuthenticatedTag is a 32-bit value used to identify and version
# CASE (Certificate Authenticated Session Establishment) tags.
#
# Format: 0xIIIIVVVV
# - Upper 16 bits (IIII): Identity Value - identifies the tag
# - Lower 16 bits (VVVV): Version - must be non-zero, incremented on changes
#
# Ported from matter.js CaseAuthenticatedTag.ts

module Matter
  module DataType
    class CaseAuthenticatedTag
      getter brand : String = "CaseAuthenticatedTag"
      property value : UInt32

      def initialize(@value : UInt32)
        validate!
      end

      # Create from raw value with validation
      def self.new(value : UInt32) : CaseAuthenticatedTag
        instance = allocate
        instance.initialize(value)
        instance
      end

      # Validate the tag value
      private def validate!
        ver = version
        if ver == 0
          raise ArgumentError.new("CaseAuthenticatedTag version number must not be 0.")
        end
      end

      # Get the identity value (upper 16 bits)
      def identity_value : UInt16
        ((value >> 16) & 0xFFFF).to_u16
      end

      # Get the version (lower 16 bits)
      def version : UInt16
        (value & 0xFFFF).to_u16
      end

      # Increase the version by 1
      # Raises if version would exceed 0xFFFF
      def increase_version : CaseAuthenticatedTag
        current_version = version
        if current_version >= 0xFFFF
          raise ArgumentError.new("CaseAuthenticatedTag version number must not exceed 0xffff.")
        end

        identity = identity_value.to_u32
        new_version = (current_version + 1).to_u32
        CaseAuthenticatedTag.new((identity << 16) | new_version)
      end

      # Class methods that mirror matter.js static methods
      def self.identity_value(tag : CaseAuthenticatedTag) : UInt16
        tag.identity_value
      end

      def self.version(tag : CaseAuthenticatedTag) : UInt16
        tag.version
      end

      def self.increase_version(tag : CaseAuthenticatedTag) : CaseAuthenticatedTag
        tag.increase_version
      end

      # Create a tag from identity and version
      def self.create(identity : UInt16, version : UInt16) : CaseAuthenticatedTag
        if version == 0
          raise ArgumentError.new("CaseAuthenticatedTag version number must not be 0.")
        end
        new((identity.to_u32 << 16) | version.to_u32)
      end

      # Equality comparison
      def ==(other : CaseAuthenticatedTag) : Bool
        value == other.value
      end

      def ==(other : UInt32) : Bool
        value == other
      end

      # To integer for comparison
      def to_u32 : UInt32
        value
      end

      # Serialize to bytes (big-endian)
      def to_slice : Bytes
        io = IO::Memory.new
        IO::ByteFormat::BigEndian.encode(@value, io)
        io.to_slice
      end

      # Create from bytes (big-endian)
      def initialize(slice : Bytes)
        if slice.size < 4
          raise ArgumentError.new("CaseAuthenticatedTag slice must be at least 4 bytes")
        end
        @value = IO::ByteFormat::BigEndian.decode(UInt32, slice)
        validate!
      end
    end
  end
end
