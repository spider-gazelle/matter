require "json"
require "tlv"

module Matter
  module Cluster
    # Shared struct for FixedLabel (0x0040) and UserLabel (0x0041) clusters.
    struct LabelStruct
      include TLV::Serializable
      include JSON::Serializable

      @[TLV::Field(tag: 0)]
      property label : String

      @[TLV::Field(tag: 1)]
      property value : String

      def initialize(@label : String, @value : String)
      end
    end
  end
end
