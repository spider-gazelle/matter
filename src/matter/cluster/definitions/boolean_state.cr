module Matter
  module Cluster
    module Definitions
      module BooleanState
        module Events
          # Body of the BooleanState stateChange event
          struct StateChange
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property value : Bool
          end
        end
      end
    end
  end
end
