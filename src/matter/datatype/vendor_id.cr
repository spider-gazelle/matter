module Matter
  module DataType
    class VendorId
      include TLV::Serializable

      getter brand : String = "VendorId"

      @[TLV::Field(tag: nil)]
      property id : UInt16

      def initialize(@id : UInt16)
      end
    end
  end
end
