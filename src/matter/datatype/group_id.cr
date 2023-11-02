module Matter
  module DataType
    class GroupId
      include TLV::Serializable

      getter brand : String = "GroupId"

      @[TLV::Field(tag: nil)]
      property id : UInt16

      def initialize(@id : UInt16)
      end
    end
  end
end
