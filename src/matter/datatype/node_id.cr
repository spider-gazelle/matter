require "./case_authenticated_tag"
require "tlv"

module Matter
  module DataType
    class NodeId
      # Operational Node ID range (Matter 1.4 § 2.5.5.1)
      OPERATIONAL_MINIMUM = 0x0000_0000_0000_0001_u64
      OPERATIONAL_MAXIMUM = 0xFFFF_FFEF_FFFF_FFFF_u64

      # Group Node ID prefix: 0xFFFFFFFFFFFF followed by the 16-bit group id
      GROUP_NODE_ID_PREFIX = 0xFFFF_FFFF_FFFF_0000_u64

      # CAT NodeId prefix: 0xFFFFFFFD followed by 32-bit CAT value
      CAT_PREFIX = 0xFFFFFFFD00000000_u64

      getter brand : String = "NodeId"
      property id : UInt64

      def initialize(@id : UInt64)
      end

      # Create NodeId from bytes (big-endian)
      def initialize(slice : Bytes)
        if slice.size < 8
          raise ArgumentError.new("NodeId slice must be at least 8 bytes")
        end
        @id = IO::ByteFormat::BigEndian.decode(UInt64, slice)
      end

      # Serialize to bytes (big-endian)
      def to_slice : Bytes
        io = IO::Memory.new
        IO::ByteFormat::BigEndian.encode(@id, io)
        io.to_slice
      end

      # Create NodeId from a CaseAuthenticatedTag
      # Format: 0xFFFFFFFD + 32-bit CAT value
      def self.from_case_authenticated_tag(cat : CaseAuthenticatedTag) : NodeId
        NodeId.new(CAT_PREFIX | cat.value.to_u64)
      end

      # Check if this NodeId encodes a CaseAuthenticatedTag
      def case_authenticated_tag? : Bool
        (id >> 32) == 0xFFFFFFFD_u64
      end

      # Extract the CaseAuthenticatedTag from this NodeId
      # Raises if this NodeId is not a CAT-encoded NodeId
      def extract_as_case_authenticated_tag : CaseAuthenticatedTag
        unless case_authenticated_tag?
          raise ArgumentError.new("NodeId does not encode a CaseAuthenticatedTag")
        end
        CaseAuthenticatedTag.new((id & 0xFFFFFFFF).to_u32)
      end

      # Generate a random NodeId within the operational range
      def self.random_operational : NodeId
        NodeId.new(Random::Secure.rand(OPERATIONAL_MINIMUM..OPERATIONAL_MAXIMUM))
      end

      # Create the Group NodeId for a group id
      # Format: 0xFFFFFFFFFFFF + 16-bit group id
      def self.group(group_id : UInt16) : NodeId
        NodeId.new(GROUP_NODE_ID_PREFIX | group_id.to_u64)
      end

      def hexstring : String
        io = IO::Memory.new
        IO::ByteFormat::BigEndian.encode(@id, io)
        io.to_slice.hexstring.upcase
      end
    end
  end
end
