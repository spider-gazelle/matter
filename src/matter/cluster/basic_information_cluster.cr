require "./cluster"

module Matter
  module Cluster
    # Basic Information Cluster Implementation (0x0028)
    # Provides attributes about the device hardware, software, and configuration
    #
    # Required on endpoint 0 (root node).
    #
    # Matter Spec: Core 11.1
    class BasicInformationCluster < Base
      CLUSTER_ID = 0x0028_u32

      # Attribute IDs (using ATTR_ prefix for consistency)
      ATTR_DATA_MODEL_REVISION     = 0x0000_u32
      ATTR_VENDOR_NAME             = 0x0001_u32
      ATTR_VENDOR_ID               = 0x0002_u32
      ATTR_PRODUCT_NAME            = 0x0003_u32
      ATTR_PRODUCT_ID              = 0x0004_u32
      ATTR_NODE_LABEL              = 0x0005_u32
      ATTR_LOCATION                = 0x0006_u32
      ATTR_HARDWARE_VERSION        = 0x0007_u32
      ATTR_HARDWARE_VERSION_STRING = 0x0008_u32
      ATTR_SOFTWARE_VERSION        = 0x0009_u32
      ATTR_SOFTWARE_VERSION_STRING = 0x000A_u32
      ATTR_MANUFACTURING_DATE      = 0x000B_u32
      ATTR_PART_NUMBER             = 0x000C_u32
      ATTR_PRODUCT_URL             = 0x000D_u32
      ATTR_PRODUCT_LABEL           = 0x000E_u32
      ATTR_SERIAL_NUMBER           = 0x000F_u32
      ATTR_LOCAL_CONFIG_DISABLED   = 0x0010_u32
      ATTR_REACHABLE               = 0x0011_u32
      ATTR_UNIQUE_ID               = 0x0012_u32
      ATTR_CAPABILITY_MINIMA       = 0x0013_u32
      ATTR_PRODUCT_APPEARANCE      = 0x0014_u32

      # Events
      EVENT_START_UP          = 0x00_u32
      EVENT_SHUT_DOWN         = 0x01_u32
      EVENT_LEAVE             = 0x02_u32
      EVENT_REACHABLE_CHANGED = 0x03_u32

      # Product Finish enum
      enum ProductFinish : UInt8
        Other    = 0
        Matte    = 1
        Satin    = 2
        Polished = 3
        Rugged   = 4
        Fabric   = 5
      end

      # Color enum
      enum Color : UInt8
        Black   =  0
        Navy    =  1
        Green   =  2
        Teal    =  3
        Maroon  =  4
        Purple  =  5
        Olive   =  6
        Gray    =  7
        Blue    =  8
        Lime    =  9
        Aqua    = 10
        Red     = 11
        Fuchsia = 12
        Yellow  = 13
        White   = 14
        Nickel  = 15
        Chrome  = 16
        Brass   = 17
        Copper  = 18
        Silver  = 19
        Gold    = 20
      end

      # Product Appearance Structure
      struct ProductAppearanceStruct
        property finish : ProductFinish
        property primary_color : Color?

        def initialize(@finish : ProductFinish, @primary_color : Color? = nil)
        end
      end

      # Capability Minima Structure
      struct CapabilityMinimaStruct
        property case_sessions_per_fabric : UInt16
        property subscriptions_per_fabric : UInt16

        def initialize(@case_sessions_per_fabric : UInt16 = 3_u16,
                       @subscriptions_per_fabric : UInt16 = 3_u16)
        end
      end

      # Attribute storage - Required
      property data_model_revision : UInt16
      property vendor_name : String
      property vendor_id : UInt16
      property product_name : String
      property product_id : UInt16
      property node_label : String
      property location : String # ISO 3166-1 alpha-2
      property hardware_version : UInt16
      property hardware_version_string : String
      property software_version : UInt32
      property software_version_string : String

      # Attribute storage - Optional
      property manufacturing_date : String
      property part_number : String
      property product_url : String
      property product_label : String
      property serial_number : String
      property local_config_disabled : Bool
      property reachable : Bool
      property unique_id : String
      property capability_minima : CapabilityMinimaStruct
      property product_appearance : ProductAppearanceStruct?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @data_model_revision : UInt16 = 1_u16,
                     @vendor_name : String = "",
                     @vendor_id : UInt16 = 0_u16,
                     @product_name : String = "",
                     @product_id : UInt16 = 0_u16,
                     @node_label : String = "",
                     @location : String = "XX",
                     @hardware_version : UInt16 = 0_u16,
                     @hardware_version_string : String = "1.0",
                     @software_version : UInt32 = 0_u32,
                     @software_version_string : String = "1.0.0",
                     @manufacturing_date : String = "",
                     @part_number : String = "",
                     @product_url : String = "",
                     @product_label : String = "",
                     @serial_number : String = "",
                     @local_config_disabled : Bool = false,
                     @reachable : Bool = true,
                     @unique_id : String = "",
                     @capability_minima : CapabilityMinimaStruct = CapabilityMinimaStruct.new,
                     @product_appearance : ProductAppearanceStruct? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      def name : String
        "BasicInformation"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_DATA_MODEL_REVISION),
            "DataModelRevision",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_VENDOR_NAME),
            "VendorName",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_VENDOR_ID),
            "VendorID",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_NAME),
            "ProductName",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_ID),
            "ProductID",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_NODE_LABEL),
            "NodeLabel",
            :string,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_LOCATION),
            "Location",
            :string,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_HARDWARE_VERSION),
            "HardwareVersion",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_HARDWARE_VERSION_STRING),
            "HardwareVersionString",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SOFTWARE_VERSION),
            "SoftwareVersion",
            :uint32,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SOFTWARE_VERSION_STRING),
            "SoftwareVersionString",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MANUFACTURING_DATE),
            "ManufacturingDate",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PART_NUMBER),
            "PartNumber",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_URL),
            "ProductURL",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_LABEL),
            "ProductLabel",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SERIAL_NUMBER),
            "SerialNumber",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_LOCAL_CONFIG_DISABLED),
            "LocalConfigDisabled",
            :bool,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_REACHABLE),
            "Reachable",
            :bool,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_UNIQUE_ID),
            "UniqueID",
            :string,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CAPABILITY_MINIMA),
            "CapabilityMinima",
            :struct,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_APPEARANCE),
            "ProductAppearance",
            :struct,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        # No commands defined for Basic Information cluster
        [] of CommandMetadata
      end

      def events : Array(EventMetadata)
        [
          EventMetadata.new(
            DataType::EventId.new(EVENT_START_UP),
            "StartUp",
            InteractionModel::EventPriority::Critical
          ),
          EventMetadata.new(
            DataType::EventId.new(EVENT_SHUT_DOWN),
            "ShutDown",
            InteractionModel::EventPriority::Critical
          ),
          EventMetadata.new(
            DataType::EventId.new(EVENT_LEAVE),
            "Leave",
            InteractionModel::EventPriority::Info
          ),
          EventMetadata.new(
            DataType::EventId.new(EVENT_REACHABLE_CHANGED),
            "ReachableChanged",
            InteractionModel::EventPriority::Info
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_DATA_MODEL_REVISION
          encode_uint16(@data_model_revision)
        when ATTR_VENDOR_NAME
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_VENDOR_ID
          encode_uint16(@vendor_id)
        when ATTR_PRODUCT_NAME
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_PRODUCT_ID
          encode_uint16(@product_id)
        when ATTR_NODE_LABEL
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_LOCATION
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_HARDWARE_VERSION
          encode_uint16(@hardware_version)
        when ATTR_HARDWARE_VERSION_STRING
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_SOFTWARE_VERSION
          encode_uint32(@software_version)
        when ATTR_SOFTWARE_VERSION_STRING
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_MANUFACTURING_DATE
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_PART_NUMBER
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_PRODUCT_URL
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_PRODUCT_LABEL
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_SERIAL_NUMBER
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_LOCAL_CONFIG_DISABLED
          encode_bool(@local_config_disabled)
        when ATTR_REACHABLE
          encode_bool(@reachable)
        when ATTR_UNIQUE_ID
          # TODO: Encode string as TLV
          Bytes.new(0)
        when ATTR_CAPABILITY_MINIMA
          # TODO: Encode CapabilityMinimaStruct as TLV
          Bytes.new(0)
        when ATTR_PRODUCT_APPEARANCE
          # TODO: Encode ProductAppearanceStruct as TLV
          Bytes.new(0)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_NODE_LABEL
          # TODO: Decode TLV string
          # @node_label = decode_string(value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_LOCATION
          # TODO: Decode TLV string and validate ISO 3166-1 alpha-2
          # @location = decode_string(value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_LOCAL_CONFIG_DISABLED
          # TODO: Decode TLV bool
          # @local_config_disabled = decode_bool(value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # Helper: Trigger StartUp event (call when node boots)
      def emit_start_up_event(software_version : UInt32)
        # TODO: Implement event emission
      end

      # Helper: Trigger ShutDown event (call when node shuts down)
      def emit_shut_down_event
        # TODO: Implement event emission
      end

      # Helper: Trigger Leave event (call when leaving fabric)
      def emit_leave_event(fabric_index : UInt8)
        # TODO: Implement event emission
      end

      # Helper: Trigger ReachableChanged event (call when reachability changes)
      def emit_reachable_changed_event(reachable_new_value : Bool)
        @reachable = reachable_new_value
        # TODO: Implement event emission
      end
    end
  end
end
