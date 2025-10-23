module Matter
  module Cluster
    module Definitions
      module OtaSoftwareUpdateRequestor
        enum UpdateState : UInt8
          # Current state is not yet determined.
          Unknown = 0

          # Indicate a Node not yet in the process of software update.
          Idle = 1

          # Indicate a Node in the process of querying an OTA Provider.
          Querying = 2

          # Indicate a Node waiting after a Busy response.
          DelayedOnQuery = 3

          # Indicate a Node currently in the process of downloading a software update.
          Downloading = 4

          # Indicate a Node currently in the process of verifying and applying a software update.
          Applying = 5

          # Indicate a Node waiting caused by AwaitNextAction response.
          DelayedOnApply = 6

          # Indicate a Node in the process of recovering to a previous version.
          RollingBack = 7

          # Indicate a Node is capable of user consent.
          DelayedOnUserConsent = 8
        end

        # This value shall indicate that the reason for a state change is unknown.
        enum ChangeReason : UInt8
          # The reason for a state change is unknown.
          Unknown = 0

          # The reason for a state change is the success of a prior operation.
          Success = 1

          # The reason for a state change is the failure of a prior operation.
          Failure = 2

          # The reason for a state change is a time-out.
          TimeOut = 3

          # The reason for a state change is a request by the OTA Provider to wait.
          DelayByProvider = 4
        end

        enum AnnouncementReason : UInt8
          # An OTA Provider is announcing its presence.
          SimpleAnnouncement = 0

          # An OTA Provider is announcing, either to a single Node or to a group of Nodes, that a new Software Image MAY
          # be available.
          UpdateAvailable = 1

          # An OTA Provider is announcing, either to a single Node or to a group of Nodes, that a new Software Image MAY
          # be available, which contains an update that needs to be applied urgently.
          UrgentUpdateAvailable = 2
        end

        # This structure encodes a fabric-scoped location of an OTA provider on a given fabric.
        struct TlvProviderLocation
          include TLV::Serializable
          @[TLV::Field(tag: 1)]
          property provider_node_id : DataType::NodeId

          @[TLV::Field(tag: 2)]
          property endpoint : DataType::EndpointNumber

          @[TLV::Field(tag: 254)]
          property fabric_index : DataType::FabricIndex
        end

        # Input to the OtaSoftwareUpdateRequestor announceOtaProvider command
        struct TlvAnnounceOtaProviderRequest
          include TLV::Serializable
          @[TLV::Field(tag: 0)]
          property provider_node_id : DataType::NodeId

          @[TLV::Field(tag: 1)]
          property vendor_id : DataType::VendorId

          @[TLV::Field(tag: 2)]
          property announcement_Reason : AnnouncementReason

          @[TLV::Field(tag: 3)]
          property metadata_for_node : Slice(UInt8)?

          @[TLV::Field(tag: 4)]
          property endpoint : DataType::EndpointNumber

          @[TLV::Field(tag: 254)]
          property fabric_index : DataType::FabricIndex
        end

        module Events
          # Body of the OtaSoftwareUpdateRequestor stateTransition event
          struct TlvStateTransitionEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property previous_state : UpdateState

            @[TLV::Field(tag: 1)]
            property new_state : UpdateState

            @[TLV::Field(tag: 2)]
            property reason : ChangeReason

            @[TLV::Field(tag: 3)]
            property target_software_version : UInt32
          end

          # Body of the OtaSoftwareUpdateRequestor versionApplied event
          struct TlvVersionAppliedEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property software_version : UInt32

            @[TLV::Field(tag: 1)]
            property product_id : UInt16
          end

          # Body of the OtaSoftwareUpdateRequestor downloadError event
          struct TlvDownloadErrorEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property software_version : UInt32

            @[TLV::Field(tag: 1)]
            property bytes_downloaded : UInt64

            @[TLV::Field(tag: 2)]
            property progress_percent : UInt8?

            @[TLV::Field(tag: 3)]
            property platform_code : UInt64?
          end
        end
      end
    end
  end
end
