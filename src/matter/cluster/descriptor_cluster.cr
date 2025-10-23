require "./cluster"
require "./definitions/descriptor"

module Matter
  module Cluster
    # Descriptor Cluster Implementation (0x001D)
    # Required on all endpoints to describe the endpoint's configuration
    class DescriptorCluster < Base
      CLUSTER_ID = 0x001D_u32

      # Attribute IDs
      DEVICE_TYPE_LIST = 0x0000_u32
      SERVER_LIST      = 0x0001_u32
      CLIENT_LIST      = 0x0002_u32
      PARTS_LIST       = 0x0003_u32
      TAG_LIST         = 0x0004_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32
      ATTRIBUTE_LIST   = 0xFFFB_u32

      # Store device types as raw data
      struct DeviceTypeInfo
        property device_type_id : UInt32
        property revision : UInt16

        def initialize(@device_type_id : UInt32, @revision : UInt16)
        end
      end

      property device_types : Array(DeviceTypeInfo)
      property server_clusters : Array(UInt32)
      property client_clusters : Array(UInt32)
      property parts : Array(UInt16)

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @device_types : Array(DeviceTypeInfo) = [] of DeviceTypeInfo,
        @server_clusters : Array(UInt32) = [] of UInt32,
        @client_clusters : Array(UInt32) = [] of UInt32,
        @parts : Array(UInt16) = [] of UInt16,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      def name : String
        "Descriptor"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(DEVICE_TYPE_LIST),
            name: "DeviceTypeList",
            type: :array,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(SERVER_LIST),
            name: "ServerList",
            type: :array,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLIENT_LIST),
            name: "ClientList",
            type: :array,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(PARTS_LIST),
            name: "PartsList",
            type: :array,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(TAG_LIST),
            name: "TagList",
            type: :array,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLUSTER_REVISION),
            name: "ClusterRevision",
            type: :uint16,
            writable: false,
            default: encode_uint16(1_u16)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(FEATURE_MAP),
            name: "FeatureMap",
            type: :uint32,
            writable: false,
            default: encode_uint32(0_u32)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTRIBUTE_LIST),
            name: "AttributeList",
            type: :array,
            writable: false
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when DEVICE_TYPE_LIST
          encode_device_type_list
        when SERVER_LIST
          encode_cluster_list(@server_clusters)
        when CLIENT_LIST
          encode_cluster_list(@client_clusters)
        when PARTS_LIST
          encode_parts_list
        when TAG_LIST
          Bytes.new(0) # Empty list for now
        when ATTRIBUTE_LIST
          encode_attribute_list
        else
          super(attribute_id)
        end
      end

      private def encode_device_type_list : Bytes
        # Simplified encoding - real implementation would use TLV
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(@device_types.size.to_u16, io)
        @device_types.each do |dt|
          IO::ByteFormat::LittleEndian.encode(dt.device_type_id, io)
          IO::ByteFormat::LittleEndian.encode(dt.revision, io)
        end
        io.to_slice
      end

      private def encode_cluster_list(clusters : Array(UInt32)) : Bytes
        # Simplified encoding - real implementation would use TLV
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(clusters.size.to_u16, io)
        clusters.each do |cluster_id|
          IO::ByteFormat::LittleEndian.encode(cluster_id, io)
        end
        io.to_slice
      end

      private def encode_parts_list : Bytes
        # Simplified encoding - real implementation would use TLV
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(@parts.size.to_u16, io)
        @parts.each do |part|
          IO::ByteFormat::LittleEndian.encode(part, io)
        end
        io.to_slice
      end

      private def encode_attribute_list : Bytes
        # List all attribute IDs
        ids = attributes.map(&.id.id)
        io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(ids.size.to_u16, io)
        ids.each do |id|
          IO::ByteFormat::LittleEndian.encode(id, io)
        end
        io.to_slice
      end
    end
  end
end
