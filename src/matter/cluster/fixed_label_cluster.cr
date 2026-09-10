require "./cluster"
require "./definitions/label_struct"

module Matter
  module Cluster
    # Fixed Label Cluster (0x0040)
    #
    # Provides fixed (non-writable) labels for an endpoint.
    class FixedLabelCluster < Base
      cluster 0x0040, revision: 1

      attribute 0x0000, :label_list, Array(LabelStruct), default: [] of LabelStruct, fixed: true

      def initialize(endpoint_id : DataType::EndpointNumber, @label_list : Array(LabelStruct))
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end
    end
  end
end
