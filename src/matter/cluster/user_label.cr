require "./cluster"
require "./label_struct"

module Matter
  module Cluster
    # User Label Cluster (0x0041)
    #
    # Provides writable labels for an endpoint.
    class UserLabel < Base
      cluster 0x0041, revision: 1

      # Longest label and value a LabelStruct entry may carry.
      LABEL_MAX_LENGTH = 16

      attribute 0x0000, :label_list, Array(LabelStruct), default: [] of LabelStruct, writable: true, write_access: :manage

      # Entries are bounded per field; the DSL has no per-element constraint.
      before_write :label_list do |labels|
        too_long = labels.any? { |entry| entry.label.bytesize > LABEL_MAX_LENGTH || entry.value.bytesize > LABEL_MAX_LENGTH }
        InteractionModel::Status.constraint_error if too_long
      end

      def initialize(endpoint_id : DataType::EndpointNumber, @label_list : Array(LabelStruct) = [] of LabelStruct)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end
    end
  end
end
