require "./cluster"
require "tlv"
require "json"

module Matter
  module Cluster
    # Bridged Device Basic Information Cluster Implementation (0x0039)
    # Provides information about a bridged device from another ecosystem.
    #
    # Required on each bridged endpoint in a bridge device.
    # The bridge populates this with information from the original device.
    #
    # Matter Spec: Core 9.13
    class BridgedDeviceBasicInformationCluster < Base
      CLUSTER_ID = 0x0039_u32

      # Attribute IDs
      ATTR_VENDOR_NAME             = 0x0001_u32
      ATTR_VENDOR_ID               = 0x0002_u32
      ATTR_PRODUCT_NAME            = 0x0003_u32
      ATTR_PRODUCT_ID              = 0x0004_u32 # Added in revision 4
      ATTR_NODE_LABEL              = 0x0005_u32
      ATTR_HARDWARE_VERSION        = 0x0007_u32
      ATTR_HARDWARE_VERSION_STRING = 0x0008_u32
      ATTR_SOFTWARE_VERSION        = 0x0009_u32
      ATTR_SOFTWARE_VERSION_STRING = 0x000A_u32
      ATTR_MANUFACTURING_DATE      = 0x000B_u32
      ATTR_PART_NUMBER             = 0x000C_u32
      ATTR_PRODUCT_URL             = 0x000D_u32
      ATTR_PRODUCT_LABEL           = 0x000E_u32
      ATTR_SERIAL_NUMBER           = 0x000F_u32
      ATTR_REACHABLE               = 0x0011_u32 # Required
      ATTR_UNIQUE_ID               = 0x0012_u32
      ATTR_PRODUCT_APPEARANCE      = 0x0014_u32

      # Events
      EVENT_START_UP          = 0x00_u32
      EVENT_SHUT_DOWN         = 0x01_u32
      EVENT_LEAVE             = 0x02_u32
      EVENT_REACHABLE_CHANGED = 0x03_u32

      # Reuse enums and structs from BasicInformationCluster
      alias ProductFinish = BasicInformationCluster::ProductFinish
      alias Color = BasicInformationCluster::Color
      alias ProductAppearanceStruct = BasicInformationCluster::ProductAppearanceStruct

      # Event structures
      struct StartUpEvent
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property software_version : UInt32

        def initialize(@software_version : UInt32)
        end
      end

      struct ShutDownEvent
        include TLV::Serializable

        def initialize
        end
      end

      struct LeaveEvent
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property fabric_index : UInt8

        def initialize(@fabric_index : UInt8)
        end
      end

      struct ReachableChangedEvent
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property? reachable_new_value : Bool

        def initialize(@reachable_new_value : Bool)
        end
      end

      # Attribute storage - Required
      property? reachable : Bool

      # Attribute storage - Optional (all optional for bridged devices)
      property vendor_name : String?
      property vendor_id : UInt16?
      property product_name : String?
      property product_id : UInt16?
      property node_label : String?
      property hardware_version : UInt16?
      property hardware_version_string : String?
      property software_version : UInt32?
      property software_version_string : String?
      property manufacturing_date : String?
      property part_number : String?
      property product_url : String?
      property product_label : String?
      property serial_number : String?
      property unique_id : String?
      property product_appearance : ProductAppearanceStruct?

      # Callback for reachability changes
      property on_reachable_changed : Proc(Bool, Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @reachable : Bool = true,
        @vendor_name : String? = nil,
        @vendor_id : UInt16? = nil,
        @product_name : String? = nil,
        @product_id : UInt16? = nil,
        @node_label : String? = nil,
        @hardware_version : UInt16? = nil,
        @hardware_version_string : String? = nil,
        @software_version : UInt32? = nil,
        @software_version_string : String? = nil,
        @manufacturing_date : String? = nil,
        @part_number : String? = nil,
        @product_url : String? = nil,
        @product_label : String? = nil,
        @serial_number : String? = nil,
        @unique_id : String? = nil,
        @product_appearance : ProductAppearanceStruct? = nil,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      def name : String
        "BridgedDeviceBasicInformation"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_REACHABLE),
            "Reachable",
            :bool,
            writable: false
          ),
        ]

        # Add optional attributes only if they have values
        if @vendor_name
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_VENDOR_NAME),
            "VendorName",
            :string,
            writable: false
          )
        end

        if @vendor_id
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_VENDOR_ID),
            "VendorID",
            :uint16,
            writable: false
          )
        end

        if @product_name
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_NAME),
            "ProductName",
            :string,
            writable: false
          )
        end

        if @product_id
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_ID),
            "ProductID",
            :uint16,
            writable: false
          )
        end

        # NodeLabel is always present and writable
        attrs << AttributeMetadata.new(
          DataType::AttributeId.new(ATTR_NODE_LABEL),
          "NodeLabel",
          :string,
          writable: true
        )

        if @hardware_version
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_HARDWARE_VERSION),
            "HardwareVersion",
            :uint16,
            writable: false
          )
        end

        if @hardware_version_string
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_HARDWARE_VERSION_STRING),
            "HardwareVersionString",
            :string,
            writable: false
          )
        end

        if @software_version
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SOFTWARE_VERSION),
            "SoftwareVersion",
            :uint32,
            writable: false
          )
        end

        if @software_version_string
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SOFTWARE_VERSION_STRING),
            "SoftwareVersionString",
            :string,
            writable: false
          )
        end

        if @manufacturing_date
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MANUFACTURING_DATE),
            "ManufacturingDate",
            :string,
            writable: false
          )
        end

        if @part_number
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PART_NUMBER),
            "PartNumber",
            :string,
            writable: false
          )
        end

        if @product_url
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_URL),
            "ProductURL",
            :string,
            writable: false
          )
        end

        if @product_label
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_LABEL),
            "ProductLabel",
            :string,
            writable: false
          )
        end

        if @serial_number
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SERIAL_NUMBER),
            "SerialNumber",
            :string,
            writable: false
          )
        end

        if @unique_id
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_UNIQUE_ID),
            "UniqueID",
            :string,
            writable: false
          )
        end

        if @product_appearance
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PRODUCT_APPEARANCE),
            "ProductAppearance",
            :struct,
            writable: false
          )
        end

        attrs
      end

      def commands : Array(CommandMetadata)
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
        when ATTR_REACHABLE
          encode_tlv_bool(@reachable)
        when ATTR_VENDOR_NAME
          if value = @vendor_name
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_VENDOR_ID
          if value = @vendor_id
            encode_tlv_uint16(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PRODUCT_NAME
          if value = @product_name
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PRODUCT_ID
          if value = @product_id
            encode_tlv_uint16(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_NODE_LABEL
          encode_tlv_string(@node_label || "")
        when ATTR_HARDWARE_VERSION
          if value = @hardware_version
            encode_tlv_uint16(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_HARDWARE_VERSION_STRING
          if value = @hardware_version_string
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_SOFTWARE_VERSION
          if value = @software_version
            encode_tlv_uint32(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_SOFTWARE_VERSION_STRING
          if value = @software_version_string
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_MANUFACTURING_DATE
          if value = @manufacturing_date
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PART_NUMBER
          if value = @part_number
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PRODUCT_URL
          if value = @product_url
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PRODUCT_LABEL
          if value = @product_label
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_SERIAL_NUMBER
          if value = @serial_number
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_UNIQUE_ID
          if value = @unique_id
            encode_tlv_string(value)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PRODUCT_APPEARANCE
          if value = @product_appearance
            value.to_slice
          else
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
        else
          super
        end
      end

      # Set reachability and emit event
      def reachable=(value : Bool) : Nil
        return if @reachable == value

        @reachable = value
        increment_version_and_notify(ATTR_REACHABLE)

        # Call the reachability callback if set
        @on_reachable_changed.try(&.call(value))

        # Generate event data (for future event system)
        emit_reachable_changed_event(value)
      end

      # Helper: Trigger StartUp event
      def emit_start_up_event(software_version : UInt32) : Bytes
        StartUpEvent.new(software_version).to_slice
      end

      # Helper: Trigger ShutDown event
      def emit_shut_down_event : Bytes
        ShutDownEvent.new.to_slice
      end

      # Helper: Trigger Leave event
      def emit_leave_event(fabric_index : UInt8) : Bytes
        LeaveEvent.new(fabric_index).to_slice
      end

      # Helper: Trigger ReachableChanged event
      def emit_reachable_changed_event(reachable_new_value : Bool) : Bytes
        ReachableChangedEvent.new(reachable_new_value).to_slice
      end

      # ------------------------------------------------------------------------
      # Persistence support
      # ------------------------------------------------------------------------

      private struct PersistedState
        include JSON::Serializable

        property node_label : String?
        property? reachable : Bool
        property data_version : UInt32

        def initialize(
          @node_label : String?,
          @reachable : Bool,
          @data_version : UInt32,
        )
        end
      end

      def save_state : String?
        PersistedState.new(
          node_label: @node_label,
          reachable: @reachable,
          data_version: @data_version
        ).to_json
      end

      def restore_state(json : String) : Nil
        state = PersistedState.from_json(json)
        @node_label = state.node_label
        @reachable = state.reachable?
        @data_version = state.data_version
      rescue ex
        # Start fresh if restore fails
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
    end
  end
end
