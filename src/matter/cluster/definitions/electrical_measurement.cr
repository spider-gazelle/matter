module Matter
  module Cluster
    module Definitions
      module ElectricalMeasurement
        # Input to the ElectricalMeasurement getMeasurementProfileCommand command
        struct GetMeasurementProfileCommandRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property attribute_id : UInt16

          @[TLV::Field(tag: 1)]
          property start_time : UInt32

          @[TLV::Field(tag: 2)]
          property number_of_intervals : UInt8
        end
      end
    end
  end
end
