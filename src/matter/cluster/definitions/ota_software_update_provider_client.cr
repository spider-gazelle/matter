module Matter
  module Cluster
    module Definitions
      module OtaSoftwareUpdateProviderClient
        # Note that only HTTP over TLS (HTTPS) is supported (see RFC 7230). Using HTTP without TLS shall
        # NOT be supported, as there is no way to authenticate the involved participants.
        enum DownloadProtocol : UInt8
          # Indicates support for synchronous BDX.
          BdxSynchronous = 0

          # Indicates support for asynchronous BDX.
          BdxAsynchronous = 1

          # Indicates support for HTTPS.
          Https = 2

          # Indicates support for vendor specific protocol.
          VendorSpecific = 3
        end

        # See Section 11.19.3.2, “Querying the OTA Provider” for the semantics of these values.
        enum Status : UInt8
          # Indicates that the OTA Provider has an update available.
          UpdateAvailable = 0

          # Indicates OTA Provider may have an update, but it is not ready yet.
          Busy = 1

          # Indicates that there is definitely no update currently available from the OTA Provider.
          NotAvailable = 2

          # Indicates that the requested download protocol is not supported by the OTA Provider.
          DownloadProtocolNotSupported = 3
        end

        # See Section 11.19.3.6, “Applying a software update” for the semantics of the values. This enumeration is used in
        # the Action field of the ApplyUpdateResponse command. See (Section 11.19.6.5.4.1, “Action Field”).
        enum ApplyUpdateAction : UInt8
          # Apply the update.
          Proceed = 0

          # Wait at least the given delay time.
          AwaitNextAction = 1

          # The OTA Provider is conveying a desire to rescind a previously provided Software Image.
          Discontinue = 2
        end

        # Input to the OtaSoftwareUpdateProvider queryImage command
        struct QueryImageRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property vendor_id : DataType::VendorId

          @[TLV::Field(tag: 1)]
          property product_id : UInt16

          @[TLV::Field(tag: 2)]
          property software_version : UInt32

          @[TLV::Field(tag: 3)]
          property protocols_supported : Array(DownloadProtocol)?

          @[TLV::Field(tag: 4)]
          property hardware_version : UInt16?

          @[TLV::Field(tag: 5)]
          property location : String?

          @[TLV::Field(tag: 6)]
          property requestor_can_consent : Bool?

          @[TLV::Field(tag: 7)]
          property metadata_for_provider : Slice(UInt8)?
        end

        struct QueryImageResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status : Status

          @[TLV::Field(tag: 1)]
          property delayed_action_time : UInt32?

          @[TLV::Field(tag: 2)]
          property image_uri : String?

          @[TLV::Field(tag: 3)]
          property software_version : UInt32?

          @[TLV::Field(tag: 4)]
          property software_version_string : String?

          @[TLV::Field(tag: 5)]
          property update_token : Slice(UInt8)?

          @[TLV::Field(tag: 6)]
          property user_consent_needed : Bool?

          @[TLV::Field(tag: 7)]
          property metadata_for_requestor : Slice(UInt8)?
        end

        # Input to the OtaSoftwareUpdateProvider applyUpdateRequest command
        struct ApplyUpdateRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property update_token : Slice(UInt8)

          @[TLV::Field(tag: 0)]
          property new_version : UInt32
        end

        struct ApplyUpdateResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action : ApplyUpdateAction

          @[TLV::Field(tag: 1)]
          property delayed_action_time : UInt32
        end

        # Input to the OtaSoftwareUpdateProvider notifyUpdateApplied command
        struct NotifyUpdateAppliedRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property update_Token : Slice(UInt8)

          @[TLV::Field(tag: 1)]
          property software_version : UInt32
        end
      end
    end
  end
end
