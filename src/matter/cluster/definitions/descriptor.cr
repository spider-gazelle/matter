module Matter
  module Cluster
    module Definitions
      module Descriptor
        # The device type and revision define endpoint conformance to a release of a device type definition. See the Data
        # Model specification for more information.
        struct DeviceType
          include TLV::Serializable

          # This shall indicate the device type definition. The endpoint shall conform to the device type definition and
          # cluster specifications required by the device type.
          @[TLV::Field(tag: 0)]
          property device_type : DataType::DeviceTypeId

          # This is the implemented revision of the device type definition. The endpoint shall conform to this revision
          # of the device type.
          @[TLV::Field(tag: 1)]
          property revision : UInt16
        end
      end
    end
  end
end
