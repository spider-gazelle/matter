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
        @attribute_values[ATTR_LABEL_LIST] = tlv(@label_list)
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

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | TLV::Any
        case attribute_id
        when ATTR_LABEL_LIST
          tlv(@label_list)
        else
          super
        end
      end

      protected def handle_write_attribute(attribute_id : UInt32, value : TLV::Any) : InteractionModel::Status
        case attribute_id
        when ATTR_LABEL_LIST
          begin
            list = value.as_list
            @label_list = list.map { |entry| LabelStruct.from_tlv(entry) }
            @attribute_values[ATTR_LABEL_LIST] = tlv(@label_list)
            increment_version_and_notify(ATTR_LABEL_LIST)
            InteractionModel::Status.success
          rescue ex
            Log.warn(exception: ex) { "UserLabel: rejected LabelList write (bytes=#{value.inspect})" }
            InteractionModel::Status.invalid_data_type
          end
        else
          super
        end
      end

      private struct PersistedState
        include Storage::Record

        getter labels : Array(LabelStruct)
        getter data_version : UInt32

        def initialize(@labels : Array(LabelStruct), @data_version : UInt32)
        end
      end

      def save_state : Storage::Document?
        PersistedState.new(@label_list, @data_version).to_document
      end

      def restore_state(document : Storage::Document) : Nil
        state = PersistedState.from_document(document)
        @label_list = state.labels
        @attribute_values[ATTR_LABEL_LIST] = tlv(@label_list)
        @data_version = state.data_version
      rescue ex
        Log.warn(exception: ex) { "UserLabel restore_state failed; starting fresh" }
      end
    end
  end
end
