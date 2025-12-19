require "./cluster"
require "tlv"
require "json"

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
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property finish : ProductFinish

        @[TLV::Field(tag: 1)]
        property primary_color : Color?

        def initialize(@finish : ProductFinish, @primary_color : Color? = nil)
        end
      end

      # Capability Minima Structure
      struct CapabilityMinimaStruct
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property case_sessions_per_fabric : UInt16

        @[TLV::Field(tag: 1)]
        property subscriptions_per_fabric : UInt16

        def initialize(@case_sessions_per_fabric : UInt16 = 3_u16,
                       @subscriptions_per_fabric : UInt16 = 3_u16)
        end
      end

      # Event structures
      struct StartUpEvent
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property software_version : UInt32

        def initialize(@software_version : UInt32)
        end
      end

      struct LeaveEvent
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property fabric_index : UInt8

        def initialize(@fabric_index : UInt8)
        end
      end

      struct ShutDownEvent
        include TLV::Serializable

        # ShutDown event has no fields
        def initialize
        end
      end

      struct ReachableChangedEvent
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property reachable_new_value : Bool

        def initialize(@reachable_new_value : Bool)
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
                     node_label : String? = nil,
                     @location : String = "XX",
                     @hardware_version : UInt16 = 0_u16,
                     @hardware_version_string : String = "1.0",
                     @software_version : UInt32 = 0_u32,
                     @software_version_string : String = "1.0.0",
                     @manufacturing_date : String = "",
                     @part_number : String = "",
                     @product_url : String = "",
                     product_label : String? = nil,
                     @serial_number : String = "",
                     @local_config_disabled : Bool = false,
                     @reachable : Bool = true,
                     @unique_id : String = "",
                     @capability_minima : CapabilityMinimaStruct = CapabilityMinimaStruct.new,
                     @product_appearance : ProductAppearanceStruct? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Default node_label to product_name if not explicitly set
        # This ensures iOS/controllers show a meaningful device name
        @node_label = node_label || @product_name

        # Default product_label to product_name if not explicitly set
        @product_label = product_label || @product_name
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

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_DATA_MODEL_REVISION
          encode_tlv_uint16(@data_model_revision)
        when ATTR_VENDOR_NAME
          encode_tlv_string(@vendor_name)
        when ATTR_VENDOR_ID
          encode_tlv_uint16(@vendor_id)
        when ATTR_PRODUCT_NAME
          encode_tlv_string(@product_name)
        when ATTR_PRODUCT_ID
          encode_tlv_uint16(@product_id)
        when ATTR_NODE_LABEL
          encode_tlv_string(@node_label)
        when ATTR_LOCATION
          encode_tlv_string(@location)
        when ATTR_HARDWARE_VERSION
          encode_tlv_uint16(@hardware_version)
        when ATTR_HARDWARE_VERSION_STRING
          encode_tlv_string(@hardware_version_string)
        when ATTR_SOFTWARE_VERSION
          encode_tlv_uint32(@software_version)
        when ATTR_SOFTWARE_VERSION_STRING
          encode_tlv_string(@software_version_string)
        when ATTR_MANUFACTURING_DATE
          encode_tlv_string(@manufacturing_date)
        when ATTR_PART_NUMBER
          encode_tlv_string(@part_number)
        when ATTR_PRODUCT_URL
          encode_tlv_string(@product_url)
        when ATTR_PRODUCT_LABEL
          encode_tlv_string(@product_label)
        when ATTR_SERIAL_NUMBER
          encode_tlv_string(@serial_number)
        when ATTR_LOCAL_CONFIG_DISABLED
          encode_tlv_bool(@local_config_disabled)
        when ATTR_REACHABLE
          encode_tlv_bool(@reachable)
        when ATTR_UNIQUE_ID
          encode_tlv_string(@unique_id)
        when ATTR_CAPABILITY_MINIMA
          encode_capability_minima(@capability_minima)
        when ATTR_PRODUCT_APPEARANCE
          if appearance = @product_appearance
            encode_product_appearance(appearance)
          else
            # Attribute not present
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_NODE_LABEL
          parsed = TLV::Any.from_slice(value)
          str = parsed.value.as?(String)
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) unless str

          # Validate max length (32 chars per Matter spec)
          if str.bytesize > 32
            return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end

          @node_label = str
          increment_version_and_notify(ATTR_NODE_LABEL)
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_LOCATION
          parsed = TLV::Any.from_slice(value)
          str = parsed.value.as?(String)
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) unless str

          # Validate ISO 3166-1 alpha-2 format (must be exactly 2 characters)
          if str.size != 2
            return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end

          # Validate it contains only ASCII letters or is "XX" (region-agnostic)
          unless str == "XX" || str.chars.all? { |c| c.ascii_letter? }
            return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end

          @location = str.upcase
          increment_version_and_notify(ATTR_LOCATION)
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_LOCAL_CONFIG_DISABLED
          parsed = TLV::Any.from_slice(value)
          bool = parsed.value.as?(Bool)
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if bool.nil?

          @local_config_disabled = bool
          increment_version_and_notify(ATTR_LOCAL_CONFIG_DISABLED)
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # ------------------------------------------------------------------------
      # Persistence support
      # ------------------------------------------------------------------------

      private struct PersistedState
        include JSON::Serializable

        property node_label : String
        property location : String
        property local_config_disabled : Bool
        property data_version : UInt32

        def initialize(
          @node_label : String,
          @location : String,
          @local_config_disabled : Bool,
          @data_version : UInt32,
        )
        end
      end

      def save_state : String?
        PersistedState.new(
          node_label: @node_label,
          location: @location,
          local_config_disabled: @local_config_disabled,
          data_version: @data_version
        ).to_json
      end

      def restore_state(json : String) : Nil
        state = PersistedState.from_json(json)
        @node_label = state.node_label
        @location = state.location
        @local_config_disabled = state.local_config_disabled
        @data_version = state.data_version
      rescue ex
        # Start fresh if restore fails
      end

      # Helper: Trigger StartUp event (call when node boots)
      def emit_start_up_event(software_version : UInt32)
        # NOTE: Event emission would be handled by the event management system
        StartUpEvent.new(software_version).to_slice
      end

      # Helper: Trigger ShutDown event (call when node shuts down)
      def emit_shut_down_event
        # NOTE: Event emission would be handled by the event management system
        ShutDownEvent.new.to_slice
      end

      # Helper: Trigger Leave event (call when leaving fabric)
      def emit_leave_event(fabric_index : UInt8)
        # NOTE: Event emission would be handled by the event management system
        LeaveEvent.new(fabric_index).to_slice
      end

      # Helper: Trigger ReachableChanged event (call when reachability changes)
      def emit_reachable_changed_event(reachable_new_value : Bool)
        @reachable = reachable_new_value
        increment_version

        # NOTE: Event emission would be handled by the event management system
        ReachableChangedEvent.new(reachable_new_value).to_slice
      end

      # TLV encoding helpers
      private def encode_tlv_string(value : String) : Bytes
        TLV::Any.new(value, nil).to_slice
      end

      private def encode_tlv_uint16(value : UInt16) : Bytes
        TLV::Any.new(value, nil).to_slice
      end

      private def encode_tlv_uint32(value : UInt32) : Bytes
        TLV::Any.new(value, nil).to_slice
      end

      private def encode_tlv_bool(value : Bool) : Bytes
        TLV::Any.new(value, nil).to_slice
      end

      private def encode_capability_minima(capability : CapabilityMinimaStruct) : Bytes
        capability.to_slice
      end

      private def encode_product_appearance(appearance : ProductAppearanceStruct) : Bytes
        appearance.to_slice
      end
    end
  end
end
