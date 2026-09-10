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

      CLUSTER_ID = 0x0033_u32

      # Attribute IDs
      ATTR_NETWORK_INTERFACES          = 0x0000_u32
      ATTR_REBOOT_COUNT                = 0x0001_u32
      ATTR_UP_TIME                     = 0x0002_u32
      ATTR_TOTAL_OPERATIONAL_HOURS     = 0x0003_u32
      ATTR_BOOT_REASON                 = 0x0004_u32
      ATTR_ACTIVE_HARDWARE_FAULTS      = 0x0005_u32
      ATTR_ACTIVE_RADIO_FAULTS         = 0x0006_u32
      ATTR_ACTIVE_NETWORK_FAULTS       = 0x0007_u32
      ATTR_TEST_EVENT_TRIGGERS_ENABLED = 0x0008_u32

      # Command IDs
      CMD_TEST_EVENT_TRIGGER = 0x00_u32

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

      # Instance variables
      property network_interfaces : Array(NetworkInterfaceInfo)
      property reboot_count : UInt16
      property up_time : UInt64
      property total_operational_hours : UInt32
      property boot_reason : BootReason
      property active_hardware_faults : Array(HardwareFault)
      property active_radio_faults : Array(RadioFault)
      property active_network_faults : Array(NetworkFault)
      property? test_event_triggers_enabled : Bool

      @start_time : Time

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        @reboot_count : UInt16 = 0_u16,
        @boot_reason : BootReason = BootReason::PowerOnReboot,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @network_interfaces = [] of NetworkInterfaceInfo
        @up_time = 0_u64
        @total_operational_hours = 0_u32
        @active_hardware_faults = [] of HardwareFault
        @active_radio_faults = [] of RadioFault
        @active_network_faults = [] of NetworkFault
        @test_event_triggers_enabled = false
        @start_time = Time.utc
      end

      def name : String
        "GeneralDiagnostics"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_NETWORK_INTERFACES),
            "NetworkInterfaces",
            :array,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_REBOOT_COUNT),
            "RebootCount",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_UP_TIME),
            "UpTime",
            :uint64,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_TOTAL_OPERATIONAL_HOURS),
            "TotalOperationalHours",
            :uint32,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BOOT_REASON),
            "BootReason",
            :enum8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACTIVE_HARDWARE_FAULTS),
            "ActiveHardwareFaults",
            :array,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACTIVE_RADIO_FAULTS),
            "ActiveRadioFaults",
            :array,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACTIVE_NETWORK_FAULTS),
            "ActiveNetworkFaults",
            :array,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_TEST_EVENT_TRIGGERS_ENABLED),
            "TestEventTriggersEnabled",
            :bool,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_TEST_EVENT_TRIGGER),
            "TestEventTrigger"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_NETWORK_INTERFACES
          @network_interfaces.to_tlv
        when ATTR_REBOOT_COUNT
          @reboot_count.to_tlv
        when ATTR_UP_TIME
          # Calculate uptime in seconds since start
          (Time.utc - @start_time).total_seconds.to_u64.to_tlv
        when ATTR_TOTAL_OPERATIONAL_HOURS
          # Calculate hours from uptime
          uptime_hours = ((Time.utc - @start_time).total_hours).to_u32
          (@total_operational_hours + uptime_hours).to_tlv
        when ATTR_BOOT_REASON
          @boot_reason.value.to_tlv
        when ATTR_ACTIVE_HARDWARE_FAULTS
          @active_hardware_faults.map(&.value).to_tlv
        when ATTR_ACTIVE_RADIO_FAULTS
          @active_radio_faults.map(&.value).to_tlv
        when ATTR_ACTIVE_NETWORK_FAULTS
          @active_network_faults.map(&.value).to_tlv
        when ATTR_TEST_EVENT_TRIGGERS_ENABLED
          @test_event_triggers_enabled.to_tlv
        when GLOBAL_FEATURE_MAP
          0_u32.to_tlv # No features
        when GLOBAL_ATTRIBUTE_LIST
          encode_attribute_list
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only
        super
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_TEST_EVENT_TRIGGER
          # TestEventTrigger requires test mode to be enabled
          # For production devices, always return constraint error
          InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
        else
          super
        end
      end

      # Add a network interface
      def add_network_interface(interface : NetworkInterfaceInfo) : Nil
        @network_interfaces << interface
        increment_version
      end

      # Helper to encode attribute list
      private def encode_attribute_list : Bytes
        [
          ATTR_NETWORK_INTERFACES,
          ATTR_REBOOT_COUNT,
          ATTR_UP_TIME,
          ATTR_TOTAL_OPERATIONAL_HOURS,
          ATTR_BOOT_REASON,
          ATTR_ACTIVE_HARDWARE_FAULTS,
          ATTR_ACTIVE_RADIO_FAULTS,
          ATTR_ACTIVE_NETWORK_FAULTS,
          ATTR_TEST_EVENT_TRIGGERS_ENABLED,
          GLOBAL_CLUSTER_REVISION,
          GLOBAL_FEATURE_MAP,
          GLOBAL_ATTRIBUTE_LIST,
        ].to_tlv
      end
    end
  end
end
