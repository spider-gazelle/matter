require "./cluster"
require "tlv"

module Matter
  module Cluster
    # Basic Information Cluster Implementation (0x0028)
    # Provides attributes about the device hardware, software, and configuration
    #
    # Required on endpoint 0 (root node).
    #
    # Matter Spec: Core 11.1
    class BasicInformationCluster < Base
      cluster 0x0028, revision: 5

      # NodeLabel is at most 32 bytes; Location is an ISO 3166-1 alpha-2 code
      # (two ASCII letters, or "XX" for an unknown region).
      NODE_LABEL_MAX_LENGTH = 32
      LOCATION_LENGTH       =  2
      LOCATION_UNKNOWN      = "XX"

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
        property? reachable_new_value : Bool

        def initialize(@reachable_new_value : Bool)
        end
      end

      attribute 0x0000, :data_model_revision, UInt16, default: 1_u16, fixed: true
      attribute 0x0001, :vendor_name, String, default: "", fixed: true
      attribute 0x0002, :vendor_id, UInt16, default: 0_u16, fixed: true
      attribute 0x0003, :product_name, String, default: "", fixed: true
      attribute 0x0004, :product_id, UInt16, default: 0_u16, fixed: true
      attribute 0x0005, :node_label, String, default: "", writable: true, write_access: :manage, max_length: NODE_LABEL_MAX_LENGTH
      attribute 0x0006, :location, String, default: LOCATION_UNKNOWN, writable: true, write_access: :administer
      attribute 0x0007, :hardware_version, UInt16, default: 0_u16, fixed: true
      attribute 0x0008, :hardware_version_string, String, default: "1.0", fixed: true
      attribute 0x0009, :software_version, UInt32, default: 0_u32, fixed: true
      attribute 0x000A, :software_version_string, String, default: "1.0.0", fixed: true
      attribute 0x000B, :manufacturing_date, String, default: "", fixed: true, optional: true
      attribute 0x000C, :part_number, String, default: "", fixed: true, optional: true
      attribute 0x000D, :product_url, String, default: "", fixed: true, optional: true
      attribute 0x000E, :product_label, String, default: "", fixed: true, optional: true
      attribute 0x000F, :serial_number, String, default: "", fixed: true, optional: true
      attribute 0x0010, :local_config_disabled, Bool, default: false, writable: true, write_access: :manage, optional: true
      attribute 0x0011, :reachable, Bool, default: true, optional: true
      attribute 0x0012, :unique_id, String, default: "", fixed: true
      attribute 0x0013, :capability_minima, CapabilityMinimaStruct, default: CapabilityMinimaStruct.new, fixed: true
      attribute 0x0014, :product_appearance, ProductAppearanceStruct, nullable: true, fixed: true, optional: true, present_if: :product_appearance

      # Location is validated as a country code and stored upper case.
      before_write :location do |code|
        valid_location?(code) ? code.upcase : InteractionModel::Status.constraint_error
      end

      event 0x00, :start_up, priority: :critical
      event 0x01, :shut_down, priority: :critical
      event 0x02, :leave, priority: :info
      event 0x03, :reachable_changed, priority: :info

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @data_model_revision : UInt16 = 1_u16,
                     @vendor_name : String = "",
                     @vendor_id : UInt16 = 0_u16,
                     @product_name : String = "",
                     @product_id : UInt16 = 0_u16,
                     node_label : String? = nil,
                     @location : String = LOCATION_UNKNOWN,
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

      private def valid_location?(code : String) : Bool
        code.size == LOCATION_LENGTH && (code == LOCATION_UNKNOWN || code.chars.all?(&.ascii_letter?))
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
        self.reachable = reachable_new_value

        # NOTE: Event emission would be handled by the event management system
        ReachableChangedEvent.new(reachable_new_value).to_slice
      end
    end
  end
end
