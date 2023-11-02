module Matter
  module DataType
    class FabricIndex
      include TLV::Serializable

      getter brand : String = "FabricIndex"

      @[TLV::Field(tag: nil)]
      # If nil then OMIT_FABRIC and if 0 then NO_FABRIC
      property index : UInt8? = nil

      def initialize(@index : UInt8?)
      end
    end
  end
end
