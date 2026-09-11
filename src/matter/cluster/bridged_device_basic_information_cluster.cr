require "./cluster"
require "./basic_information_cluster"
require "tlv"

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
      cluster 0x0039, revision: 5

      NODE_LABEL_MAX_LENGTH = 32

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

      # The optional attributes are present exactly when the bridge supplied
      # a value (see `attribute_present?`).
      attribute 0x0001, :vendor_name, String, nullable: true, fixed: true, optional: true
      attribute 0x0002, :vendor_id, UInt16, nullable: true, fixed: true, optional: true
      attribute 0x0003, :product_name, String, nullable: true, fixed: true, optional: true
      attribute 0x0004, :product_id, UInt16, nullable: true, fixed: true, optional: true
      attribute 0x0005, :node_label, String, default: "", writable: true, write_access: :manage, max_length: NODE_LABEL_MAX_LENGTH
      attribute 0x0007, :hardware_version, UInt16, nullable: true, fixed: true, optional: true
      attribute 0x0008, :hardware_version_string, String, nullable: true, fixed: true, optional: true
      attribute 0x0009, :software_version, UInt32, nullable: true, fixed: true, optional: true
      attribute 0x000A, :software_version_string, String, nullable: true, fixed: true, optional: true
      attribute 0x000B, :manufacturing_date, String, nullable: true, fixed: true, optional: true
      attribute 0x000C, :part_number, String, nullable: true, fixed: true, optional: true
      attribute 0x000D, :product_url, String, nullable: true, fixed: true, optional: true
      attribute 0x000E, :product_label, String, nullable: true, fixed: true, optional: true
      attribute 0x000F, :serial_number, String, nullable: true, fixed: true, optional: true
      attribute 0x0011, :reachable, Bool, default: true, persist: true, callback: :new_only
      attribute 0x0012, :unique_id, String, nullable: true, fixed: true, optional: true
      attribute 0x0014, :product_appearance, ProductAppearanceStruct, nullable: true, fixed: true, optional: true

      event 0x00, :start_up, priority: :critical
      event 0x01, :shut_down, priority: :critical
      event 0x02, :leave, priority: :info
      event 0x03, :reachable_changed, priority: :info

      # The DSL gates attributes on features only; this hook runs after the
      # DSL's own `finished` hook and narrows the generated tables to the
      # attributes that have a value.
      macro finished
        protected def dsl_attribute_supported?(attribute_id : UInt32) : Bool
          previous_def && attribute_present?(attribute_id)
        end

        def attributes : Array(AttributeMetadata)
          ATTRIBUTES.select { |attribute| dsl_attribute_supported?(attribute.id.id) }
        end
      end

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @reachable : Bool = true,
        @vendor_name : String? = nil,
        @vendor_id : UInt16? = nil,
        @product_name : String? = nil,
        @product_id : UInt16? = nil,
        node_label : String? = nil,
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
        @node_label = node_label || ""
      end

      # An optional attribute is absent while its value is nil.
      private def attribute_present?(attribute_id : UInt32) : Bool
        case attribute_id
        when ATTR_VENDOR_NAME             then !@vendor_name.nil?
        when ATTR_VENDOR_ID               then !@vendor_id.nil?
        when ATTR_PRODUCT_NAME            then !@product_name.nil?
        when ATTR_PRODUCT_ID              then !@product_id.nil?
        when ATTR_HARDWARE_VERSION        then !@hardware_version.nil?
        when ATTR_HARDWARE_VERSION_STRING then !@hardware_version_string.nil?
        when ATTR_SOFTWARE_VERSION        then !@software_version.nil?
        when ATTR_SOFTWARE_VERSION_STRING then !@software_version_string.nil?
        when ATTR_MANUFACTURING_DATE      then !@manufacturing_date.nil?
        when ATTR_PART_NUMBER             then !@part_number.nil?
        when ATTR_PRODUCT_URL             then !@product_url.nil?
        when ATTR_PRODUCT_LABEL           then !@product_label.nil?
        when ATTR_SERIAL_NUMBER           then !@serial_number.nil?
        when ATTR_UNIQUE_ID               then !@unique_id.nil?
        when ATTR_PRODUCT_APPEARANCE      then !@product_appearance.nil?
        else                                   true
        end
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | TLV::Any
        return InteractionModel::Status.unsupported_attribute unless attribute_present?(attribute_id)
        super
      end

      protected def handle_write_attribute(attribute_id : UInt32, value : TLV::Any) : InteractionModel::Status
        return InteractionModel::Status.unsupported_attribute unless attribute_present?(attribute_id)
        super
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
    end
  end
end
