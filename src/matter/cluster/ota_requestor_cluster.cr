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

      cluster 0x002A, revision: 1

      # The spec cluster name; the class name is shortened.
      def name : String
        "OtaSoftwareUpdateRequestor"
      end

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

      # An OTA provider on a fabric (DefaultOTAProviders entries)
      struct ProviderLocation
        include TLV::Serializable

        @[TLV::Field(tag: 1)]
        property provider_node_id : UInt64

        @[TLV::Field(tag: 2)]
        property endpoint : UInt16

        @[TLV::Field(tag: 254)]
        property fabric_index : UInt8

        def initialize(@provider_node_id : UInt64, @endpoint : UInt16, @fabric_index : UInt8)
        end
      end

      attribute 0x0000, :default_ota_providers, Array(ProviderLocation), default: [] of ProviderLocation, writable: true, persist: false, write_access: :administer, fabric_scoped: true
      attribute 0x0001, :update_possible, Bool, default: true
      attribute 0x0002, :update_state, UpdateState, default: UpdateState::Idle
      attribute 0x0003, :update_state_progress, UInt8, nullable: true

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        @update_possible : Bool = true,
        @update_state : UpdateState = UpdateState::Idle,
        @update_state_progress : UInt8? = nil,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      # No OTA provider is ever used, so a DefaultOTAProviders write is
      # accepted and discarded rather than stored per fabric.
      protected def handle_write_attribute(attribute_id : UInt32, value : TLV::Any) : InteractionModel::Status
        return super unless attribute_id == ATTR_DEFAULT_OTA_PROVIDERS

        Log.debug { "Received write to DefaultOTAProviders (ignoring for minimal implementation)" }
        InteractionModel::Status.success
      end
    end
  end
end
