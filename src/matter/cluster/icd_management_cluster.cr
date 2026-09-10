require "./cluster"
require "log"

module Matter
  module Cluster
    # ICD Management Cluster (0x0046)
    #
    # Minimal implementation for always-connected devices.
    # This enables configuration of the ICD's behavior and ensures that listed
    # clients can be notified when an intermittently connected device (ICD)
    # is available for communication.
    #
    # For always-on devices, this cluster returns sane defaults indicating
    # the device is always available (not actually an ICD).
    #
    # Matter Specification: Core 1.4 § 9.16 - ICD Management Cluster
    class IcdManagementCluster < Base
      Log = ::Log.for("matter.cluster.icd_management")

      CLUSTER_ID = 0x0046_u32

      # Attribute IDs (mandatory base attributes)
      ATTR_IDLE_MODE_DURATION    = 0x0000_u32 # Max interval in seconds server can stay in idle mode
      ATTR_ACTIVE_MODE_DURATION  = 0x0001_u32 # Min interval in milliseconds in active mode
      ATTR_ACTIVE_MODE_THRESHOLD = 0x0002_u32 # Min time in ms to stay active after network activity

      # Optional attributes (with CheckInProtocolSupport feature)
      ATTR_REGISTERED_CLIENTS           = 0x0003_u32
      ATTR_ICD_COUNTER                  = 0x0004_u32
      ATTR_CLIENTS_SUPPORTED_PER_FABRIC = 0x0005_u32
      ATTR_MAXIMUM_CHECK_IN_BACKOFF     = 0x0009_u32

      # Optional attributes (with UserActiveModeTrigger feature)
      ATTR_USER_ACTIVE_MODE_TRIGGER_HINT        = 0x0006_u32
      ATTR_USER_ACTIVE_MODE_TRIGGER_INSTRUCTION = 0x0007_u32

      # Optional attributes (with LongIdleTimeSupport feature)
      ATTR_OPERATING_MODE = 0x0008_u32

      CLUSTER_REVISION = 3_u16 # Matter 1.4

      # Feature bits
      FEATURE_CHECK_IN_PROTOCOL_SUPPORT = 0x01_u32
      FEATURE_USER_ACTIVE_MODE_TRIGGER  = 0x02_u32
      FEATURE_LONG_IDLE_TIME_SUPPORT    = 0x04_u32
      FEATURE_DYNAMIC_SIT_LIT_SUPPORT   = 0x08_u32

      # Command IDs (optional - not implemented for minimal version)
      CMD_REGISTER_CLIENT     = 0x00_u32
      CMD_UNREGISTER_CLIENT   = 0x02_u32
      CMD_STAY_ACTIVE_REQUEST = 0x03_u32

      # Instance variables for base attributes
      # For always-on devices, these represent "not really an ICD" defaults
      property idle_mode_duration : UInt32    # Max idle interval (seconds) - 1 = always responsive
      property active_mode_duration : UInt32  # Active mode duration (ms) - 300 = 300ms default
      property active_mode_threshold : UInt16 # Active threshold (ms) - 300 = 300ms default

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        @idle_mode_duration : UInt32 = 1_u32,      # 1 second - device is always responsive
        @active_mode_duration : UInt32 = 300_u32,  # 300ms default
        @active_mode_threshold : UInt16 = 300_u16, # 300ms default
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      def name : String
        "IcdManagement"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_IDLE_MODE_DURATION),
            "IdleModeDuration",
            :uint32,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACTIVE_MODE_DURATION),
            "ActiveModeDuration",
            :uint32,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACTIVE_MODE_THRESHOLD),
            "ActiveModeThreshold",
            :uint16,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        # No commands implemented for minimal version (all are optional)
        [] of CommandMetadata
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_IDLE_MODE_DURATION
          @idle_mode_duration.to_tlv
        when ATTR_ACTIVE_MODE_DURATION
          @active_mode_duration.to_tlv
        when ATTR_ACTIVE_MODE_THRESHOLD
          @active_mode_threshold.to_tlv
        when GLOBAL_FEATURE_MAP
          # No features enabled - this is an always-on device, not a true ICD
          0_u32.to_tlv
        when GLOBAL_ATTRIBUTE_LIST
          [
            ATTR_IDLE_MODE_DURATION,
            ATTR_ACTIVE_MODE_DURATION,
            ATTR_ACTIVE_MODE_THRESHOLD,
            GLOBAL_CLUSTER_REVISION,
            GLOBAL_FEATURE_MAP,
            GLOBAL_ATTRIBUTE_LIST,
          ].to_tlv
        else
          super
        end
      end

      protected def handle_write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only in the base ICD Management cluster
        super
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_STAY_ACTIVE_REQUEST
          # StayActiveRequest is optional and only with LITS feature
          # Return UnsupportedCommand for minimal implementation
          InteractionModel::Status.unsupported_command
        when CMD_REGISTER_CLIENT, CMD_UNREGISTER_CLIENT
          # These require CheckInProtocolSupport feature
          InteractionModel::Status.unsupported_command
        else
          super
        end
      end
    end

    # Alias for consistency
    alias IcdManagement = IcdManagementCluster
  end
end
