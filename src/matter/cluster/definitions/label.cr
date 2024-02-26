module Matter
  module Cluster
    module Definitions
      module Label
        # This is a string tuple with strings that are user defined.
        struct Base
          include TLV::Serializable

          # The Label or Value semantic is not defined here. Label examples: "room", "zone", "group", "direction".
          @[TLV::Field(tag: 0)]
          property label : String

          # The Label or Value semantic is not defined here. The Value is a discriminator for a Label that may have
          # multiple instances. Label:Value examples: "room":"bedroom 2", "orientation":"North", "floor":"2",
          # "direction":"up"
          @[TLV::Field(tag: 1)]
          property value : String
        end
      end
    end
  end
end
