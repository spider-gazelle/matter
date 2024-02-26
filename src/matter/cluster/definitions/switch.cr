module Matter
  module Cluster
    module Definitions
      module Switch
        module Events
          # Body of the Switch multiPressOngoing event
          struct MultiPressOngoingEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property new_position : UInt8

            @[TLV::Field(tag: 1)]
            property current_number_of_presses_counted : UInt8
          end

          # Body of the Switch multiPressComplete event
          struct MultiPressCompleteEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property previous_position : UInt8

            @[TLV::Field(tag: 1)]
            property current_number_of_presses_counted : UInt8
          end

          # Body of the Switch switchLatched event
          struct SwitchLatchedEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property new_position : UInt8
          end

          # Body of the Switch initialPress event
          struct InitialPressEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property new_position : UInt8
          end

          # Body of the Switch longPress event
          struct LongPressEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property new_position : UInt8
          end

          # Body of the Switch longRelease event
          struct LongReleaseEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property previous_position : UInt8
          end

          # Body of the Switch shortRelease event
          struct ShortReleaseEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property previous_position : UInt8
          end
        end
      end
    end
  end
end
