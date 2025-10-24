require "./cluster"

module Matter
  module Cluster
    # Descriptor Cluster (0x001D)
    #
    # Provides device composition information including device types,
    # server/client clusters, and endpoint hierarchy.
    #
    # Required on all endpoints.
    #
    # Matter Spec: Core 9.5
    class DescriptorCluster < Base
      CLUSTER_ID = 0x001D_u32

      # Attributes
      ATTR_DEVICE_TYPE_LIST = 0x0000_u32
      ATTR_SERVER_LIST      = 0x0001_u32
      ATTR_CLIENT_LIST      = 0x0002_u32
      ATTR_PARTS_LIST       = 0x0003_u32

      # Device Type Structure
      struct DeviceTypeStruct
        property device_type : UInt32 # Device type ID
        property revision : UInt16    # Device type revision

        def initialize(@device_type : UInt32, @revision : UInt16)
        end
      end

      # Attribute storage
      property device_type_list : Array(DeviceTypeStruct)
      property server_list : Array(UInt32)
      property client_list : Array(UInt32)
      property parts_list : Array(UInt16)

      def initialize(endpoint_id : DataType::EndpointNumber)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @device_type_list = [] of DeviceTypeStruct
        @server_list = [] of UInt32
        @client_list = [] of UInt32
        @parts_list = [] of UInt16

        # Descriptor cluster is always a server on every endpoint
        @server_list << CLUSTER_ID
      end

      def name : String
        "Descriptor"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_DEVICE_TYPE_LIST),
            "DeviceTypeList",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SERVER_LIST),
            "ServerList",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CLIENT_LIST),
            "ClientList",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PARTS_LIST),
            "PartsList",
            :list,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        # No commands defined for Descriptor cluster
        [] of CommandMetadata
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_DEVICE_TYPE_LIST
          # TODO: Encode device type list as TLV
          Bytes.new(0)
        when ATTR_SERVER_LIST
          # TODO: Encode server list as TLV
          Bytes.new(0)
        when ATTR_CLIENT_LIST
          # TODO: Encode client list as TLV
          Bytes.new(0)
        when ATTR_PARTS_LIST
          # TODO: Encode parts list as TLV
          Bytes.new(0)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only
        super
      end

      # Helper: Check if a cluster is in the server list
      def has_server_cluster?(cluster_id : UInt32) : Bool
        @server_list.includes?(cluster_id)
      end

      # Helper: Check if a cluster is in the client list
      def has_client_cluster?(cluster_id : UInt32) : Bool
        @client_list.includes?(cluster_id)
      end

      # Helper: Check if an endpoint is in the parts list
      def has_part?(endpoint_id : UInt16) : Bool
        @parts_list.includes?(endpoint_id)
      end

      # Helper: Get primary device type
      def primary_device_type : DeviceTypeStruct?
        @device_type_list.first?
      end
    end
  end
end
