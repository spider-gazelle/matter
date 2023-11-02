module Matter
  module DataType
    class CommandId
      include TLV::Serializable

      getter brand : String = "CommandId"

      @[TLV::Field(tag: nil)]
      property id : UInt32

      def initialize(@id : UInt32)
      end
    end
  end
end
