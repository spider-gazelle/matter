module Matter
  module Cluster
    module Definitions
      module FaultInjection
        enum FaultType : UInt8
          Unspecified = 0
          SystemFault = 1
          InetFault   = 2
          ChipFault   = 3
          CertFault   = 4
        end

        # Input to the FaultInjection failAtFault command
        struct FailAtFaultRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property type : FaultType

          @[TLV::Field(tag: 1)]
          property id : UInt32

          @[TLV::Field(tag: 2)]
          property number_of_calls_to_skip : UInt32

          @[TLV::Field(tag: 3)]
          property number_of_calls_to_fail : UInt32

          @[TLV::Field(tag: 4)]
          property take_mutex : Bool
        end

        # Input to the FaultInjection failRandomlyAtFault command
        struct FailRandomlyAtFaultRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property type : FaultType

          @[TLV::Field(tag: 1)]
          property id : UInt32

          @[TLV::Field(tag: 2)]
          property precentage : UInt8
        end
      end
    end
  end
end
