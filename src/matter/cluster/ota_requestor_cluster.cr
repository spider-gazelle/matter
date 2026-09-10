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
      property? update_possible : Bool
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
          ([] of UInt8).to_tlv
        when ATTR_UPDATE_POSSIBLE
          @update_possible.to_tlv
        when ATTR_UPDATE_STATE
          @update_state.value.to_tlv
        when ATTR_UPDATE_STATE_PROGRESS
          @update_state_progress.to_tlv
        when GLOBAL_FEATURE_MAP
          0_u32.to_tlv # No features
        when GLOBAL_ATTRIBUTE_LIST
          [
            ATTR_DEFAULT_OTA_PROVIDERS,
            ATTR_UPDATE_POSSIBLE,
            ATTR_UPDATE_STATE,
            ATTR_UPDATE_STATE_PROGRESS,
            GLOBAL_CLUSTER_REVISION,
            GLOBAL_FEATURE_MAP,
            GLOBAL_ATTRIBUTE_LIST,
          ].to_tlv
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
          InteractionModel::Status.success
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
          InteractionModel::Status.success
        else
          super
        end
      end
    end
  end
end
