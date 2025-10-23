require "./cluster"
require "./definitions/basic_information"

module Matter
  module Cluster
    # Basic Information Cluster Implementation (0x0028)
    # Provides attributes about the device hardware, software, and configuration
    class BasicInformationCluster < Base
      CLUSTER_ID = 0x0028_u32

      # Attribute IDs
      DATA_MODEL_REVISION     = 0x0000_u32
      VENDOR_NAME             = 0x0001_u32
      VENDOR_ID               = 0x0002_u32
      PRODUCT_NAME            = 0x0003_u32
      PRODUCT_ID              = 0x0004_u32
      NODE_LABEL              = 0x0005_u32
      LOCATION                = 0x0006_u32
      HARDWARE_VERSION        = 0x0007_u32
      HARDWARE_VERSION_STRING = 0x0008_u32
      SOFTWARE_VERSION        = 0x0009_u32
      SOFTWARE_VERSION_STRING = 0x000A_u32
      MANUFACTURING_DATE      = 0x000B_u32
      PART_NUMBER             = 0x000C_u32
      PRODUCT_URL             = 0x000D_u32
      PRODUCT_LABEL           = 0x000E_u32
      SERIAL_NUMBER           = 0x000F_u32
      LOCAL_CONFIG_DISABLED   = 0x0010_u32
      REACHABLE               = 0x0011_u32
      UNIQUE_ID               = 0x0012_u32
      CAPABILITY_MINIMA       = 0x0013_u32
      PRODUCT_APPEARANCE      = 0x0014_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      property data_model_revision : UInt16
      property vendor_name : String
      property vendor_id : DataType::VendorId
      property product_name : String
      property product_id : UInt16
      property node_label : String
      property location : String
      property hardware_version : UInt16
      property hardware_version_string : String
      property software_version : UInt32
      property software_version_string : String
      property serial_number : String?
      property reachable : Bool

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @data_model_revision : UInt16 = 1_u16,
        @vendor_name : String = "Test Vendor",
        vendor_id : UInt16 = 0xFFF1_u16,
        @product_name : String = "Test Product",
        @product_id : UInt16 = 0x8000_u16,
        @node_label : String = "",
        @location : String = "XX",
        @hardware_version : UInt16 = 0_u16,
        @hardware_version_string : String = "v1.0",
        @software_version : UInt32 = 1_u32,
        @software_version_string : String = "1.0.0",
        @serial_number : String? = nil,
        @reachable : Bool = true,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @vendor_id = DataType::VendorId.new(vendor_id)

        # Initialize attribute storage
        @attribute_values[DATA_MODEL_REVISION] = encode_uint16(@data_model_revision)
        @attribute_values[VENDOR_NAME] = @vendor_name.to_slice
        @attribute_values[VENDOR_ID] = encode_uint16(@vendor_id.id)
        @attribute_values[PRODUCT_NAME] = @product_name.to_slice
        @attribute_values[PRODUCT_ID] = encode_uint16(@product_id)
        @attribute_values[NODE_LABEL] = @node_label.to_slice
        @attribute_values[LOCATION] = @location.to_slice
        @attribute_values[HARDWARE_VERSION] = encode_uint16(@hardware_version)
        @attribute_values[HARDWARE_VERSION_STRING] = @hardware_version_string.to_slice
        @attribute_values[SOFTWARE_VERSION] = encode_uint32(@software_version)
        @attribute_values[SOFTWARE_VERSION_STRING] = @software_version_string.to_slice
        @attribute_values[REACHABLE] = encode_bool(@reachable)
      end

      def name : String
        "BasicInformation"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(DATA_MODEL_REVISION),
            name: "DataModelRevision",
            type: :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(VENDOR_NAME),
            name: "VendorName",
            type: :string,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(VENDOR_ID),
            name: "VendorID",
            type: :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(PRODUCT_NAME),
            name: "ProductName",
            type: :string,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(PRODUCT_ID),
            name: "ProductID",
            type: :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(NODE_LABEL),
            name: "NodeLabel",
            type: :string,
            writable: true,
            default: "".to_slice
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(LOCATION),
            name: "Location",
            type: :string,
            writable: true,
            default: "XX".to_slice
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(HARDWARE_VERSION),
            name: "HardwareVersion",
            type: :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(HARDWARE_VERSION_STRING),
            name: "HardwareVersionString",
            type: :string,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(SOFTWARE_VERSION),
            name: "SoftwareVersion",
            type: :uint32,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(SOFTWARE_VERSION_STRING),
            name: "SoftwareVersionString",
            type: :string,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(SERIAL_NUMBER),
            name: "SerialNumber",
            type: :string,
            writable: false
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(REACHABLE),
            name: "Reachable",
            type: :bool,
            writable: false,
            default: encode_bool(true)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLUSTER_REVISION),
            name: "ClusterRevision",
            type: :uint16,
            writable: false,
            default: encode_uint16(2_u16)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(FEATURE_MAP),
            name: "FeatureMap",
            type: :uint32,
            writable: false,
            default: encode_uint32(0_u32)
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when DATA_MODEL_REVISION
          encode_uint16(@data_model_revision)
        when VENDOR_NAME
          @vendor_name.to_slice
        when VENDOR_ID
          encode_uint16(@vendor_id.id)
        when PRODUCT_NAME
          @product_name.to_slice
        when PRODUCT_ID
          encode_uint16(@product_id)
        when NODE_LABEL
          @node_label.to_slice
        when LOCATION
          @location.to_slice
        when HARDWARE_VERSION
          encode_uint16(@hardware_version)
        when HARDWARE_VERSION_STRING
          @hardware_version_string.to_slice
        when SOFTWARE_VERSION
          encode_uint32(@software_version)
        when SOFTWARE_VERSION_STRING
          @software_version_string.to_slice
        when SERIAL_NUMBER
          if sn = @serial_number
            sn.to_slice
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
          end
        when REACHABLE
          encode_bool(@reachable)
        else
          super(attribute_id)
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when NODE_LABEL
          # Convert bytes to string
          @node_label = String.new(value)
          @attribute_values[NODE_LABEL] = value
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when LOCATION
          # Validate location code (should be 2-character ISO 3166-1 alpha-2)
          location_str = String.new(value)
          if location_str.size == 2
            @location = location_str.upcase
            @attribute_values[LOCATION] = @location.to_slice
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end
        else
          super(attribute_id, value)
        end
      end
    end
  end
end
