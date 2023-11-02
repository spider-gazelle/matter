module Matter
  module DataType
    class DeviceTypeId
      include TLV::Serializable

      getter brand : String = "DeviceTypeId"

      @[TLV::Field(tag: nil)]
      property id : UInt32

      def initialize(@id : UInt32)
      end
    end
  end
end
