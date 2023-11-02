module Matter
  module DataType
    class EndpointNumber
      include TLV::Serializable

      getter brand : String = "EndpointNumber"

      @[TLV::Field(tag: nil)]
      property number : UInt16

      def initialize(@number : UInt16)
      end
    end
  end
end
