module Matter
  module DataType
    # Fabric-scoped index of a fabric on a node. The Matter spec reserves two
    # values: `nil` omits the fabric (`FabricIndex.omit`, used where the field
    # is not present) and 0 means "no fabric" (`FabricIndex.no_fabric`).
    struct FabricIndex
      NO_FABRIC = 0_u8

      getter index : UInt8?

      def initialize(@index : UInt8?)
      end

      # The field is absent
      def self.omit : FabricIndex
        new(nil)
      end

      # Explicitly not associated with any fabric
      def self.no_fabric : FabricIndex
        new(NO_FABRIC)
      end

      def omit? : Bool
        @index.nil?
      end

      def no_fabric? : Bool
        @index == NO_FABRIC
      end

      def_equals_and_hash index

      # Serialize to TLV bytes (anonymous UInt8), empty when omitted
      def to_slice : Bytes
        if idx = @index
          TLV::Any.new(idx, nil).to_slice
        else
          Bytes.empty
        end
      end

      # Deserialize from TLV bytes
      def self.from_slice(bytes : Bytes) : FabricIndex
        return omit if bytes.empty?
        parsed = TLV::Any.from_slice(bytes)
        case v = parsed.value
        when Int
          new(v.to_u8)
        else
          omit
        end
      end

      def to_s(io : IO) : Nil
        if idx = @index
          io << idx
        else
          io << "omitted"
        end
      end

      def inspect(io : IO) : Nil
        io << "FabricIndex("
        to_s(io)
        io << ')'
      end
    end
  end
end
