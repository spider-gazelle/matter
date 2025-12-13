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

      # Global attributes
      ATTR_CLUSTER_REVISION = 0xFFFD_u32
      ATTR_FEATURE_MAP      = 0xFFFC_u32
      ATTR_ATTRIBUTE_LIST   = 0xFFFB_u32

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
        property name : String
        property is_operational : Bool
        property hardware_address : Bytes
        property type : InterfaceType
        property ipv4_addresses : Array(Bytes)
        property ipv6_addresses : Array(Bytes)

        def initialize(
          @name : String,
          @is_operational : Bool,
          @hardware_address : Bytes,
          @type : InterfaceType,
          @ipv4_addresses : Array(Bytes) = [] of Bytes,
          @ipv6_addresses : Array(Bytes) = [] of Bytes,
        )
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
      property test_event_triggers_enabled : Bool

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
          encode_network_interfaces
        when ATTR_REBOOT_COUNT
          encode_uint16(@reboot_count)
        when ATTR_UP_TIME
          # Calculate uptime in seconds since start
          uptime_seconds = (Time.utc - @start_time).total_seconds.to_u64
          encode_uint64(uptime_seconds)
        when ATTR_TOTAL_OPERATIONAL_HOURS
          # Calculate hours from uptime
          uptime_hours = ((Time.utc - @start_time).total_hours).to_u32
          encode_uint32(@total_operational_hours + uptime_hours)
        when ATTR_BOOT_REASON
          encode_uint8(@boot_reason.value)
        when ATTR_ACTIVE_HARDWARE_FAULTS
          encode_fault_array(@active_hardware_faults.map(&.value))
        when ATTR_ACTIVE_RADIO_FAULTS
          encode_fault_array(@active_radio_faults.map(&.value))
        when ATTR_ACTIVE_NETWORK_FAULTS
          encode_fault_array(@active_network_faults.map(&.value))
        when ATTR_TEST_EVENT_TRIGGERS_ENABLED
          encode_bool(@test_event_triggers_enabled)
        when ATTR_CLUSTER_REVISION
          encode_uint16(1_u16) # Cluster revision 1
        when ATTR_FEATURE_MAP
          encode_uint32(0_u32) # No features
        when ATTR_ATTRIBUTE_LIST
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

      # Helper to encode network interfaces as TLV array
      private def encode_network_interfaces : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        writer.start_array(nil)
        @network_interfaces.each do |iface|
          writer.start_structure(nil)
          writer.put(0_u8, iface.name)             # name
          writer.put(1_u8, iface.is_operational)   # isOperational
          writer.put(2_u8, nil.as(Bool?))          # offPremiseServicesReachableIPv4 (null)
          writer.put(3_u8, nil.as(Bool?))          # offPremiseServicesReachableIPv6 (null)
          writer.put(4_u8, iface.hardware_address) # hardwareAddress
          writer.start_array(5_u8)                 # IPv4Addresses array
          iface.ipv4_addresses.each { |addr| writer.put(nil, addr) }
          writer.end_container
          writer.start_array(6_u8) # IPv6Addresses array
          iface.ipv6_addresses.each { |addr| writer.put(nil, addr) }
          writer.end_container
          writer.put(7_u8, iface.type.value) # type
          writer.end_container
        end
        writer.end_container

        io.to_slice
      end

      # Helper to encode fault array
      private def encode_fault_array(faults : Array(UInt8)) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        fault_array = faults.map { |f| f.as(TLV::Value) }
        writer.put(nil, fault_array)

        io.to_slice
      end

      # Helper to encode attribute list
      private def encode_attribute_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        attr_ids = [
          ATTR_NETWORK_INTERFACES,
          ATTR_REBOOT_COUNT,
          ATTR_UP_TIME,
          ATTR_TOTAL_OPERATIONAL_HOURS,
          ATTR_BOOT_REASON,
          ATTR_ACTIVE_HARDWARE_FAULTS,
          ATTR_ACTIVE_RADIO_FAULTS,
          ATTR_ACTIVE_NETWORK_FAULTS,
          ATTR_TEST_EVENT_TRIGGERS_ENABLED,
          ATTR_CLUSTER_REVISION,
          ATTR_FEATURE_MAP,
          ATTR_ATTRIBUTE_LIST,
        ]

        attr_array = attr_ids.map { |id| id.as(TLV::Value) }
        writer.put(nil, attr_array)

        io.to_slice
      end

      # NOTE: encode_uint16, encode_uint32 inherited from Base class with proper TLV encoding
      # Do NOT override them with raw byte encoding

      # encode_uint64 uses TLV encoding for attribute responses
      private def encode_uint64(value : UInt64) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put(nil, value)
        io.rewind.to_slice
      end
    end

    # Backward compatibility alias
    alias GeneralDiagnostics = GeneralDiagnosticsCluster
  end
end
