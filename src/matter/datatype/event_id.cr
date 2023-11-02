module Matter
  module DataType
    class EventId
      include TLV::Serializable

      getter brand : String = "EventId"

      @[TLV::Field(tag: nil)]
      property id : UInt32

      def initialize(@id : UInt32)
      end
    end
  end
end
