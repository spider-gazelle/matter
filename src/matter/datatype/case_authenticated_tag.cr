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
    struct CaseAuthenticatedTag
      # The identity value occupies the bits above the version
      IDENTITY_SHIFT =         16
      VERSION_MASK   = 0xFFFF_u32
      MAX_VERSION    =     0xFFFF

      # Width of the big-endian byte form
      BYTE_SIZE = 4

      getter value : UInt32

      def initialize(@value : UInt32)
        validate!
      end

      # Create from bytes (big-endian)
      def initialize(slice : Bytes)
        if slice.size < BYTE_SIZE
          raise Matter::CodecError.new("CaseAuthenticatedTag slice must be at least #{BYTE_SIZE} bytes")
        end
        @value = IO::ByteFormat::BigEndian.decode(UInt32, slice)
        validate!
      end

      # Create a tag from identity and version
      def self.create(identity : UInt16, version : UInt16) : CaseAuthenticatedTag
        if version == 0
          raise ArgumentError.new("CaseAuthenticatedTag version number must not be 0.")
        end
        new((identity.to_u32 << IDENTITY_SHIFT) | version.to_u32)
      end

      # Validate the tag value
      private def validate!
        if version == 0
          raise ArgumentError.new("CaseAuthenticatedTag version number must not be 0.")
        end
      end

      # Get the identity value (upper 16 bits)
      def identity_value : UInt16
        (value >> IDENTITY_SHIFT).to_u16
      end

      # Get the version (lower 16 bits)
      def version : UInt16
        (value & VERSION_MASK).to_u16
      end

      # Increase the version by 1
      # Raises if version would exceed MAX_VERSION
      def increase_version : CaseAuthenticatedTag
        current_version = version
        if current_version >= MAX_VERSION
          raise ArgumentError.new("CaseAuthenticatedTag version number must not exceed 0xffff.")
        end

        CaseAuthenticatedTag.create(identity_value, (current_version + 1).to_u16)
      end

      def_equals_and_hash value

      def ==(other : UInt32) : Bool
        value == other
      end

      # To integer for comparison
      def to_u32 : UInt32
        value
      end

      # Serialize to bytes (big-endian)
      def to_slice : Bytes
        bytes = Bytes.new(BYTE_SIZE)
        IO::ByteFormat::BigEndian.encode(@value, bytes)
        bytes
      end

      def to_s(io : IO) : Nil
        io << Hex.u32(@value)
      end

      def inspect(io : IO) : Nil
        io << "CaseAuthenticatedTag("
        to_s(io)
        io << ')'
      end
    end
  end
end
