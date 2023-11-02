module Matter
  module DataType
    class NodeId
      include TLV::Serializable

      OPERATIONAL_MINIMUM = BigInt.new("0000000000000001", base: 16)
      OPERATIONAL_MAXIMUM = BigInt.new("FFFFFFEFFFFFFFFF", base: 16)

      getter brand : String = "NodeId"

      @[TLV::Field(tag: nil)]
      property id : UInt64

      def initialize(@id : UInt64)
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

        writer.write(nil, id)

        io.rewind.to_slice.hexstring.upcase
      end
    end
  end
end
