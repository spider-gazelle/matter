module Matter
  module DataType
    class FabricId
      include TLV::Serializable

      getter brand : String = "FabricId"

      @[TLV::Field(tag: nil)]
      property id : UInt64

      def initialize(@id : UInt64)
      end
    end
  end
end
