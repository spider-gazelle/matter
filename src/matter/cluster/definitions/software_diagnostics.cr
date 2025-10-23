module Matter
  module Cluster
    module Definitions
      module SoftwareDiagnostics
        struct ThreadMetrics
          include TLV::Serializable

          # The Id field shall be a server-assigned per-thread unique ID that is constant for the duration of the
          # thread. Efforts SHOULD be made to avoid reusing ID values when possible.
          @[TLV::Field(tag: 0)]
          property id : UInt64

          # The Name field shall be set to a vendor defined name or prefix of the software thread that is static for the
          # duration of the thread.
          @[TLV::Field(tag: 1)]
          property name : String?

          # The StackFreeCurrent field shall indicate the current amount of stack memory, in bytes, that are not being
          # utilized on the respective thread.
          @[TLV::Field(tag: 2)]
          property stack_free_current : UInt32?

          # The StackFreeMinimum field shall indicate the minimum amount of stack memory, in bytes, that has been
          # available at any point between the current time and this attribute being reset or initialized on the
          # respective thread. This value shall only be reset upon a Node reboot or upon receiving of the
          # ResetWatermarks command.
          @[TLV::Field(tag: 3)]
          property stack_free_minimum : UInt32?

          # The StackSize field shall indicate the amount of stack memory, in bytes, that has been allocated
          #
          # for use by the respective thread.
          @[TLV::Field(tag: 4)]
          property stackSize : UInt32?
        end

        # Body of the SoftwareDiagnostics softwareFault event
        struct SoftwareFaultEvent
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property id : UInt64

          @[TLV::Field(tag: 1)]
          property name : String?

          # The FaultRecording field shall be a manufacturer-specified payload intended to convey information to assist
          # in further diagnosing or debugging a software fault. The FaultRecording field may be used to convey
          # information such as, but not limited to, thread backtraces or register contents.
          @[TLV::Field(tag: 2)]
          property fault_recording : Slice(UInt8)?
        end
      end
    end
  end
end
