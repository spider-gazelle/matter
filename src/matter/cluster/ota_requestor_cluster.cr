require "./cluster"
require "log"

module Matter
  module Cluster
    # OTA Software Update Requestor Cluster (0x002A)
    #
    # Minimal implementation for devices that don't support OTA updates.
    # This cluster is required by some controllers (e.g., Apple Home) to be present
    # even if the device doesn't actually support OTA updates.
    #
    # This implementation returns sensible defaults:
    # - UpdatePossible: true (device can be updated, but no updates available)
    # - UpdateState: Idle (1) - no update in progress
    # - UpdateStateProgress: null - no progress to report
    # - DefaultOTAProviders: empty list
    #
    # Matter Specification: Core 1.4 § 11.20.7 - OTA Software Update Requestor Cluster
    class OtaRequestorCluster < Base
      Log = ::Log.for("matter.cluster.ota_requestor")

      CLUSTER_ID = 0x002A_u32

      # Attribute IDs
      ATTR_DEFAULT_OTA_PROVIDERS = 0x0000_u32 # List of default OTA provider locations
      ATTR_UPDATE_POSSIBLE       = 0x0001_u32 # Whether update is currently possible
      ATTR_UPDATE_STATE          = 0x0002_u32 # Current update state
      ATTR_UPDATE_STATE_PROGRESS = 0x0003_u32 # Progress percentage (nullable)

      # Global attributes
      ATTR_CLUSTER_REVISION = 0xFFFD_u32
      ATTR_FEATURE_MAP      = 0xFFFC_u32
      ATTR_ATTRIBUTE_LIST   = 0xFFFB_u32

      # UpdateState enum values
      enum UpdateState : UInt8
        Unknown              = 0
        Idle                 = 1
        Querying             = 2
        DelayedOnQuery       = 3
        Downloading          = 4
        Applying             = 5
        DelayedOnApply       = 6
        RollingBack          = 7
        DelayedOnUserConsent = 8
      end

      # Command IDs (optional - not implemented for minimal version)
      CMD_ANNOUNCE_OTA_PROVIDER = 0x00_u32

      # Instance variables
      property update_possible : Bool
      property update_state : UpdateState
      property update_state_progress : UInt8?

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        @update_possible : Bool = true,
        @update_state : UpdateState = UpdateState::Idle,
        @update_state_progress : UInt8? = nil,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      def name : String
        "OtaSoftwareUpdateRequestor"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_DEFAULT_OTA_PROVIDERS),
            "DefaultOTAProviders",
            :array,
            writable: true # Fabric-scoped, writable by admins
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_UPDATE_POSSIBLE),
            "UpdatePossible",
            :bool,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_UPDATE_STATE),
            "UpdateState",
            :enum8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_UPDATE_STATE_PROGRESS),
            "UpdateStateProgress",
            :uint8, # nullable
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        # AnnounceOTAProvider is optional, not implemented for minimal version
        [] of CommandMetadata
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_DEFAULT_OTA_PROVIDERS
          # Return empty list - no default OTA providers configured
          encode_empty_array
        when ATTR_UPDATE_POSSIBLE
          encode_bool(@update_possible)
        when ATTR_UPDATE_STATE
          encode_uint8(@update_state.value)
        when ATTR_UPDATE_STATE_PROGRESS
          encode_nullable_uint8(@update_state_progress)
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
        case attribute_id
        when ATTR_DEFAULT_OTA_PROVIDERS
          # Accept writes but don't actually store them for minimal implementation
          # In a real implementation, this would update the provider list
          Log.debug { "Received write to DefaultOTAProviders (ignoring for minimal implementation)" }
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_ANNOUNCE_OTA_PROVIDER
          # AnnounceOTAProvider is optional
          # For minimal implementation, just acknowledge receipt
          Log.debug { "Received AnnounceOTAProvider (ignoring for minimal implementation)" }
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # Helper to encode empty array
      private def encode_empty_array : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put(nil, [] of TLV::Value)
        io.to_slice
      end

      # Helper to encode nullable uint8
      private def encode_nullable_uint8(value : UInt8?) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        if value
          writer.put(nil, value)
        else
          writer.put_null(nil)
        end
        io.to_slice
      end

      # Helper to encode attribute list
      private def encode_attribute_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        attr_ids = [
          ATTR_DEFAULT_OTA_PROVIDERS,
          ATTR_UPDATE_POSSIBLE,
          ATTR_UPDATE_STATE,
          ATTR_UPDATE_STATE_PROGRESS,
          ATTR_CLUSTER_REVISION,
          ATTR_FEATURE_MAP,
          ATTR_ATTRIBUTE_LIST,
        ]

        attr_array = attr_ids.map { |id| id.as(TLV::Value) }
        writer.put(nil, attr_array)

        io.to_slice
      end
    end

    # Alias for consistency
    alias OtaRequestor = OtaRequestorCluster
    alias OtaSoftwareUpdateRequestor = OtaRequestorCluster
  end
end
