require "./case_authenticated_tag"

module Matter
  module DataType
    class NodeId
      include TLV::Serializable

      OPERATIONAL_MINIMUM = BigInt.new("0000000000000001", base: 16)
      OPERATIONAL_MAXIMUM = BigInt.new("FFFFFFEFFFFFFFFF", base: 16)

      # CAT NodeId prefix: 0xFFFFFFFD followed by 32-bit CAT value
      CAT_PREFIX = 0xFFFFFFFD00000000_u64

      getter brand : String = "NodeId"

      @[TLV::Field(tag: nil)]
      property id : UInt64

      def initialize(@id : UInt64)
      end

      # Create NodeId from a CaseAuthenticatedTag
      # Format: 0xFFFFFFFD + 32-bit CAT value
      def self.from_case_authenticated_tag(cat : CaseAuthenticatedTag) : NodeId
        NodeId.new(CAT_PREFIX | cat.value.to_u64)
      end

      # Check if this NodeId encodes a CaseAuthenticatedTag
      def is_case_authenticated_tag? : Bool
        (id >> 32) == 0xFFFFFFFD_u64
      end

      # Extract the CaseAuthenticatedTag from this NodeId
      # Raises if this NodeId is not a CAT-encoded NodeId
      def extract_as_case_authenticated_tag : CaseAuthenticatedTag
        unless is_case_authenticated_tag?
          raise ArgumentError.new("NodeId does not encode a CaseAuthenticatedTag")
        end
        CaseAuthenticatedTag.new((id & 0xFFFFFFFF).to_u32)
      end

      def get_random_operational_node_id : NodeId
        while true
          random_id = BigInt.new(Random::Secure.hex(8), base: 16)

          if random_id >= OPERATIONAL_MINIMUM || random_id <= OPERATIONAL_MAXIMUM
            return NodeId.new(random_id.to_u64)
          end
        end
      end

      def get_group_node_id(group_id : UInt16)
        io = IO::Memory.new
        byte_format = IO::ByteFormat::LittleEndian

        byte_format.encode(group_id, io)

        NodeId.new(BigInt.new("FFFFFFFFFFFF" + io.rewind.to_slice.hexstring, base: 16).to_u64)
      end

      def hexstring : String
        io = IO::Memory.new
        writer = TLV::Writer.new(io, IO::ByteFormat::BigEndian)

        writer.put(nil, id)

        io.rewind.to_slice.hexstring.upcase
      end
    end
  end
end
