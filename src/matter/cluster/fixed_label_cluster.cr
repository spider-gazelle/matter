require "./cluster"
require "./definitions/label_struct"

module Matter
  module Cluster
    # Fixed Label Cluster (0x0040)
    #
    # Provides fixed (non-writable) labels for an endpoint.
    class FixedLabelCluster < Base
      CLUSTER_ID = 0x0040_u32

      ATTR_LABEL_LIST = 0x0000_u32

      property label_list : Array(LabelStruct)

      def initialize(endpoint_id : DataType::EndpointNumber, @label_list : Array(LabelStruct))
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @attribute_values[ATTR_LABEL_LIST] = @label_list.to_tlv
      end

      def name : String
        "FixedLabel"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_LABEL_LIST),
            name: "LabelList",
            type: :list,
            writable: false
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_LABEL_LIST
          @label_list.to_tlv
        else
          super
        end
      end

      protected def encode_cluster_revision_global : Bytes
        1_u16.to_tlv
      end
    end
  end
end
