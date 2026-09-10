require "json"
require "./cluster"
require "./definitions/label_struct"

module Matter
  module Cluster
    # User Label Cluster (0x0041)
    #
    # Provides writable labels for an endpoint.
    class UserLabelCluster < Base
      CLUSTER_ID = 0x0041_u32

      ATTR_LABEL_LIST = 0x0000_u32

      property label_list : Array(LabelStruct)

      def initialize(endpoint_id : DataType::EndpointNumber, @label_list : Array(LabelStruct) = [] of LabelStruct)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @attribute_values[ATTR_LABEL_LIST] = @label_list.to_tlv
      end

      def name : String
        "UserLabel"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_LABEL_LIST),
            name: "LabelList",
            type: :list,
            writable: true
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

      protected def handle_write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_LABEL_LIST
          begin
            list = TLV::Any.from_slice(value).as_list
            @label_list = list.map { |entry| LabelStruct.from_tlv(entry) }
            @attribute_values[ATTR_LABEL_LIST] = @label_list.to_tlv
            increment_version_and_notify(ATTR_LABEL_LIST)
            InteractionModel::Status.success
          rescue ex
            Log.warn(exception: ex) { "UserLabel: rejected LabelList write (bytes=#{value.hexstring})" }
            InteractionModel::Status.invalid_data_type
          end
        else
          super
        end
      end

      def save_state : String?
        @label_list.to_json
      end

      def restore_state(json : String) : Nil
        @label_list = Array(LabelStruct).from_json(json)
        @attribute_values[ATTR_LABEL_LIST] = @label_list.to_tlv
      rescue ex
        Log.warn(exception: ex) { "UserLabel restore_state failed; starting fresh" }
      end
    end
  end
end
