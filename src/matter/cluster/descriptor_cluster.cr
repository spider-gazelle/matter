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
      cluster 0x001D, revision: 3

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

      # The lists are built by the device while it composes its endpoints
      # (`add_server`, `add_part`, ...); they are fixed once commissioned.
      attribute 0x0000, :device_type_list, Array(DeviceTypeStruct), default: [] of DeviceTypeStruct, fixed: true
      attribute 0x0001, :server_list, Array(UInt32), default: [] of UInt32, fixed: true
      attribute 0x0002, :client_list, Array(UInt32), default: [] of UInt32, fixed: true
      attribute 0x0003, :parts_list, Array(UInt16), default: [] of UInt16, fixed: true

      def initialize(endpoint_id : DataType::EndpointNumber)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Descriptor cluster is always a server on every endpoint
        @server_list << CLUSTER_ID
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
    end
  end
end
