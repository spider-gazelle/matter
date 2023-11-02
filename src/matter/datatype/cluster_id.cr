module Matter
  module DataType
    class ClusterId
      include TLV::Serializable

      getter brand : String = "ClusterId"

      @[TLV::Field(tag: nil)]
      property id : UInt32

      def initialize(@id : UInt32)
      end
    end
  end
end
