module Matter
  module DataType
    class FabricIndex
      getter brand : String = "FabricIndex"

      # If nil then OMIT_FABRIC and if 0 then NO_FABRIC
      property index : UInt8? = nil

      def initialize(@index : UInt8?)
      end

      # Serialize to TLV bytes (anonymous UInt8)
      def to_slice : Bytes
        if idx = @index
          TLV::Any.new(idx, nil).to_slice
        else
          Bytes.empty
        end
      end

      # Deserialize from TLV bytes
      def self.from_slice(bytes : Bytes) : FabricIndex
        return FabricIndex.new(nil) if bytes.empty?
        parsed = TLV::Any.from_slice(bytes)
        case v = parsed.value
        when Int
          FabricIndex.new(v.to_u8)
        else
          FabricIndex.new(nil)
        end
      end
    end
  end
end
