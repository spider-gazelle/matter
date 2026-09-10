require "./cluster"
require "tlv"

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

      CLUSTER_REVISION = 2_u16

      # Device Type Structure
      # IMPORTANT: Device type values MUST be encoded with correct widths per Matter spec:
      # - deviceType (tag 0): UInt32
      # - revision (tag 1): UInt16
      # iOS is strict about this - using wrong widths causes "Not Supported"
      struct DeviceTypeStruct
        include TLV::Serializable

        @[TLV::Field(tag: 0, fixed_size: true)]
        property device_type : UInt32 # Device type ID

        @[TLV::Field(tag: 1, fixed_size: true)]
        property revision : UInt16 # Device type revision

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

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_DEVICE_TYPE_LIST
          encode_device_type_list
        when ATTR_SERVER_LIST
          encode_cluster_list(@server_list)
        when ATTR_CLIENT_LIST
          encode_cluster_list(@client_list)
        when ATTR_PARTS_LIST
          encode_parts_list
        when GLOBAL_FEATURE_MAP
          0_u32.to_tlv # No features for Descriptor cluster
        when GLOBAL_ATTRIBUTE_LIST
          encode_attribute_list
        else
          super
        end
      end

      # Encode the list of supported attributes as TLV array
      private def encode_attribute_list : Bytes
        # All supported attribute IDs including global attributes
        # Order: cluster-specific first, then global attributes
        [
          ATTR_DEVICE_TYPE_LIST,
          ATTR_SERVER_LIST,
          ATTR_CLIENT_LIST,
          ATTR_PARTS_LIST,
          # Global attributes (required on all clusters)
          GLOBAL_GENERATED_COMMAND_LIST,
          GLOBAL_ACCEPTED_COMMAND_LIST,
          GLOBAL_ATTRIBUTE_LIST,
          GLOBAL_FEATURE_MAP,
          GLOBAL_CLUSTER_REVISION,
        ].to_tlv
      end

      protected def handle_write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only
        super
      end

      # Helper: Check if a cluster is in the server list
      def has_server_cluster?(cluster_id : UInt32) : Bool
        @server_list.includes?(cluster_id)
      end

      # Helper: Check if a cluster is in the server list (by class)
      def has_server_cluster?(cluster_class : Base.class) : Bool
        has_server_cluster?(cluster_class.cluster_id)
      end

      # Helper: Check if a cluster is in the client list
      def has_client_cluster?(cluster_id : UInt32) : Bool
        @client_list.includes?(cluster_id)
      end

      # Helper: Check if a cluster is in the client list (by class)
      def has_client_cluster?(cluster_class : Base.class) : Bool
        has_client_cluster?(cluster_class.cluster_id)
      end

      # Helper: Check if an endpoint is in the parts list
      def has_part?(endpoint_id : UInt16) : Bool
        @parts_list.includes?(endpoint_id)
      end

      # Helper: Get primary device type
      def primary_device_type : DeviceTypeStruct?
        @device_type_list.first?
      end

      # Add a server cluster by class
      #
      # @param cluster_class The cluster class (e.g., OnOffCluster)
      # @return self for chaining
      #
      # Example:
      #   descriptor.add_server(OnOffCluster)
      #             .add_server(LevelControlCluster)
      def add_server(cluster_class : Base.class)
        cluster_id = cluster_class.cluster_id
        @server_list << cluster_id unless @server_list.includes?(cluster_id)
        self
      end

      # Add a client cluster by class
      #
      # @param cluster_class The cluster class (e.g., OnOffCluster)
      # @return self for chaining
      #
      # Example:
      #   descriptor.add_client(OnOffCluster)
      #             .add_client(LevelControlCluster)
      def add_client(cluster_class : Base.class)
        cluster_id = cluster_class.cluster_id
        @client_list << cluster_id unless @client_list.includes?(cluster_id)
        self
      end

      # Add a child endpoint to the parts list
      #
      # @param endpoint_id The endpoint ID
      # @return self for chaining
      #
      # Example:
      #   descriptor.add_part(1_u16)
      #             .add_part(2_u16)
      def add_part(endpoint_id : UInt16)
        @parts_list << endpoint_id unless @parts_list.includes?(endpoint_id)
        self
      end

      # Encode device type list as TLV array
      # DeviceTypeStruct uses fixed_size: true for proper Matter spec encoding
      private def encode_device_type_list : Bytes
        @device_type_list.to_tlv
      end

      # Encode cluster list (server or client) as TLV array
      # Cluster IDs are encoded as UInt32 per Matter spec
      private def encode_cluster_list(list : Array(UInt32)) : Bytes
        list.to_tlv
      end

      # Encode parts list as TLV array
      # Endpoint IDs are encoded as UInt16 per Matter spec
      private def encode_parts_list : Bytes
        @parts_list.to_tlv
      end
    end
  end
end
