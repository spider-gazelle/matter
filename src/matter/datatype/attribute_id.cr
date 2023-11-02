module Matter
  module DataType
    class AttributeId
      include TLV::Serializable

      getter brand : String = "AttributeId"

      @[TLV::Field(tag: nil)]
      property id : UInt32

      def initialize(@id : UInt32)
      end
    end
  end
end
