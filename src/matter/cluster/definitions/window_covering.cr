require "tlv"

module Matter
  module Cluster
    module Definitions
      module WindowCovering
        struct GoToLiftPercentageRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property lift_percent100ths_value : UInt16

          def initialize(@lift_percent100ths_value : UInt16)
          end
        end

        struct GoToTiltPercentageRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property tilt_percent100ths_value : UInt16

          def initialize(@tilt_percent100ths_value : UInt16)
          end
        end
      end
    end
  end
end
