module Matter
  module Cluster
    module Definitions
      module BarrierControl
        # Input to the BarrierControl barrierControlGoToPercent command
        struct GoToPercentRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property percent_open : UInt8
        end
      end
    end
  end
end
