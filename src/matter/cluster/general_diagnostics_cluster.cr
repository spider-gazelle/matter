require "./cluster"
require "./definitions/general_diagnostics"
require "log"

module Matter
  module Cluster
    # General Diagnostics Cluster (0x0033)
    #
    # Provides general diagnostic information about the device.
    # Required on endpoint 0 for Root Node device type.
    #
    # Matter Specification: Core 1.4 § 11.11 - General Diagnostics Cluster
    class GeneralDiagnosticsCluster < Base
      Log = ::Log.for("matter.cluster.general_diagnostics")

      cluster 0x0033, revision: 2

      # Use definitions from the definitions module
      alias InterfaceType = Definitions::GeneralDiagnostics::InterfaceType
      alias BootReason = Definitions::GeneralDiagnostics::BootReason
      alias HardwareFault = Definitions::GeneralDiagnostics::HardwareFault
      alias RadioFault = Definitions::GeneralDiagnostics::RadioFault
      alias NetworkFault = Definitions::GeneralDiagnostics::NetworkFault

      # Network interface information
      struct NetworkInterfaceInfo
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property name : String

        @[TLV::Field(tag: 1)]
        property? is_operational : Bool

        @[TLV::Field(tag: 2)]
        property off_premise_services_reachable_ipv4 : Bool?

        @[TLV::Field(tag: 3)]
        property off_premise_services_reachable_ipv6 : Bool?

        @[TLV::Field(tag: 4)]
        property hardware_address : Bytes

        @[TLV::Field(tag: 5)]
        property ipv4_addresses : Array(Bytes)

        @[TLV::Field(tag: 6)]
        property ipv6_addresses : Array(Bytes)

        @[TLV::Field(tag: 7)]
        property type : UInt8 # InterfaceType enum value

        def initialize(
          @name : String,
          @is_operational : Bool,
          @hardware_address : Bytes,
          interface_type : InterfaceType,
          @ipv4_addresses : Array(Bytes) = [] of Bytes,
          @ipv6_addresses : Array(Bytes) = [] of Bytes,
          @off_premise_services_reachable_ipv4 : Bool? = nil,
          @off_premise_services_reachable_ipv6 : Bool? = nil,
        )
          @type = interface_type.value
        end

        # Getter to convert back to InterfaceType enum
        def interface_type : InterfaceType
          InterfaceType.from_value(@type)
        end
      end

      # TestEventTrigger request: the 16 byte enable key and the trigger id.
      struct TestEventTriggerRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property enable_key : Bytes

        @[TLV::Field(tag: 1)]
        property event_trigger : UInt64

        def initialize(@enable_key : Bytes, @event_trigger : UInt64)
        end
      end

      # UpTime and TotalOperationalHours are computed on read from the time
      # the cluster was created; the stored TotalOperationalHours is the
      # count carried over from earlier runs.
      attribute 0x0000, :network_interfaces, Array(NetworkInterfaceInfo), default: [] of NetworkInterfaceInfo
      attribute 0x0001, :reboot_count, UInt16, default: 0_u16
      attribute 0x0002, :up_time, UInt64, default: 0_u64, omit_changes: true
      attribute 0x0003, :total_operational_hours, UInt32, default: 0_u32, omit_changes: true, optional: true
      attribute 0x0004, :boot_reason, BootReason, default: BootReason::PowerOnReboot, optional: true
      attribute 0x0005, :active_hardware_faults, Array(HardwareFault), default: [] of HardwareFault, optional: true
      attribute 0x0006, :active_radio_faults, Array(RadioFault), default: [] of RadioFault, optional: true
      attribute 0x0007, :active_network_faults, Array(NetworkFault), default: [] of NetworkFault, optional: true
      attribute 0x0008, :test_event_triggers_enabled, Bool, default: false

      command 0x00, :test_event_trigger, request: TestEventTriggerRequest, access: :manage

      @start_time : Time

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        @reboot_count : UInt16 = 0_u16,
        @boot_reason : BootReason = BootReason::PowerOnReboot,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @start_time = Time.utc
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | TLV::Any
        case attribute_id
        when ATTR_UP_TIME
          tlv(elapsed.total_seconds.to_u64)
        when ATTR_TOTAL_OPERATIONAL_HOURS
          tlv(@total_operational_hours + elapsed.total_hours.to_u32)
        else
          super
        end
      end

      private def elapsed : Time::Span
        Time.utc - @start_time
      end

      # Test event triggers are never enabled on a production device, so no
      # enable key matches.
      def test_event_trigger(request : TestEventTriggerRequest) : InteractionModel::Status
        InteractionModel::Status.constraint_error
      end

      # Add a network interface
      def add_network_interface(interface : NetworkInterfaceInfo) : Nil
        @network_interfaces << interface
        increment_version_and_notify(ATTR_NETWORK_INTERFACES)
      end
    end
  end
end
