module Matter
  module Cluster
    module Definitions
      module NetworkCommissioning
        enum StatusCode : UInt8
          # OK, no error
          Success = 0

          # Value Outside Range
          OutOfRange = 1

          # A collection would exceed its size limit
          BoundsExceeded = 2

          # The NetworkID is not among the collection of added networks
          NetworkIdNotFound = 3

          # The NetworkID is already among the collection of added networks
          DuplicateNetworkId = 4

          # Cannot find AP: SSID Not found
          NetworkNotFound = 5

          # Cannot find AP: Mismatch on band/channels/regulatory domain / 2.4GHz vs 5GHz
          RegulatoryError = 6

          # Cannot associate due to authentication failure
          AuthFailure = 7

          # Cannot associate due to unsupported security mode
          UnsupportedSecurity = 8

          # Other association failure
          OtherConnectionFailure = 9

          # Failure to generate an IPv6 address
          Ipv6Failed = 10

          # Failure to bind Wi-Fi <-> IP interfaces
          IpBindFailed = 11

          # Unknown error
          UnknownError = 12
        end

        enum Band : UInt8
          # 2.4GHz - 2.401GHz to2.495GHz(802.11b/g/n/ax)
          B2G4 = 0

          # 3.65GHz - 3.655GHz to3.695GHz (802.11y)
          B3G65 = 1

          # 5GHz - 5.150GHz to5.895GHz(802.11a/n/ac/ax)
          B5G = 2

          # 6GHz - 5.925GHz to7.125GHz (802.11ax / WiFi 6E)
          B6G = 3

          # 60GHz - 57.24GHz to70.20GHz (802.11ad/ay)
          B60G = 4
        end

        struct NetworkInformation
          include TLV::Serializable

          # Every network is uniquely identified (for purposes of commissioning) by a NetworkID mapping to the following
          # technology-specific properties:
          #
          #   • SSID for Wi-Fi
          #
          #   • Extended PAN ID for Thread
          #
          #   • Network interface instance name at operating system (or equivalent unique name) for Ethernet.
          #
          # The semantics of the NetworkID field therefore varies between network types accordingly. It contains SSID
          # for Wi-Fi networks, Extended PAN ID (XPAN ID) for Thread networks and netif name for Ethernet networks.
          #
          # NOTE
          #
          # SSID in Wi-Fi is a collection of 1-32 bytes, the text encoding of which is not specified. Implementations
          # must be careful to support reporting byte strings without requiring a particular encoding for transfer. Only
          # the commissioner should try to potentially decode the bytes. The most common encoding is UTF-8, however this
          # is just a convention. Some configurations may use Latin-1 or other character sets. A commissioner may decode
          # using UTF-8, replacing encoding errors with "?" at the application level while retaining the underlying
          # representation.
          #
          # XPAN ID is a big-endian 64-bit unsigned number, represented on the first 8 octets of the octet string.
          @[TLV::Field(tag: 0)]
          property network_id : Slice(UInt8)

          # This field shall indicate the connected status of the associated network, where "connected" means currently
          # linked to the network technology (e.g. Associated for a Wi-Fi network, media connected for an Ethernet
          # network).
          @[TLV::Field(tag: 1)]
          property connected : Bool
        end

        # Input to the NetworkCommissioning scanNetworks command
        struct ScanAvailableNetworksRequest
          include TLV::Serializable

          # This field, if present, shall contain the SSID for a directed scan of that particular Wi-Fi SSID. Otherwise,
          # if the field is absent, or it is null, this shall indicate scanning of all BSSID in range. This field shall
          # be ignored for ScanNetworks invocations on non-Wi-Fi server instances.
          @[TLV::Field(tag: 0)]
          property ssid : Slice(UInt8)?

          # The Breadcrumb field, if present, shall be used to atomically set the Breadcrumb attribute in the General
          # Commissioning cluster on success of the associated command. If the command fails, the Breadcrumb attribute
          # in the General Commissioning cluster shall be left unchanged.
          @[TLV::Field(tag: 1)]
          property breadcrumb : UInt64?
        end

        # WiFiInterfaceScanResultStruct represents a single Wi-Fi network scan result.
        struct WiFiInterfaceScanResult
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property security : UInt8

          @[TLV::Field(tag: 1)]
          property ssid : Slice(UInt8)

          @[TLV::Field(tag: 2)]
          property bssid : Slice(UInt8)

          @[TLV::Field(tag: 3)]
          property channel : UInt16

          # This field, if present, may be used to differentiate overlapping channel number values across different
          # Wi-Fi frequency bands.
          @[TLV::Field(tag: 4)]
          property band : Band?

          # This field, if present, shall denote the signal strength in dBm of the associated scan result.
          @[TLV::Field(tag: 5)]
          property rssi : UInt8?
        end

        # ThreadInterfaceScanResultStruct represents a single Thread network scan result.
        struct ThreadInterfaceScanResult
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property pan_id : UInt16?

          @[TLV::Field(tag: 1)]
          property extended_pan_id : UInt64?

          @[TLV::Field(tag: 2)]
          property network_name : String?

          @[TLV::Field(tag: 3)]
          property channel : UInt16?

          @[TLV::Field(tag: 4)]
          property version : UInt8?

          # ExtendedAddress stands for an IEEE 802.15.4 Extended Address.
          @[TLV::Field(tag: 5)]
          property extended_address : Slice(UInt8)?

          @[TLV::Field(tag: 6)]
          property rssi : UInt8?

          @[TLV::Field(tag: 7)]
          property lqi : UInt8?
        end

        # This command shall contain the status of the last ScanNetworks command, and the associated scan results if the
        # operation was successful.
        #
        # Results are valid only if NetworkingStatus is Success.
        #
        # Before generating a ScanNetworksResponse, the server shall set the LastNetworkingStatus attribute value to the
        # NetworkingStatus matching the response.
        struct ScanNetworksResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property debug_text : String?

          @[TLV::Field(tag: 2)]
          property wifi_scan_results : Array(WiFiInterfaceScanResult)?

          @[TLV::Field(tag: 3)]
          property thread_scan_results : Array(ThreadInterfaceScanResult)?
        end

        # Input to the NetworkCommissioning removeNetwork command
        struct RemoveNetworkRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property network_id : Slice(UInt8)

          @[TLV::Field(tag: 1)]
          property breadcrumb : UInt64?
        end

        # This response command relates status information for some commands which require it as their response command.
        # See each individual cluster server command for the situations that may cause a NetworkingStatus different than
        # Success.
        #
        # Before generating a NetworkConfigResponse, the server shall set the LastNetworkingStatus attribute value to the
        # NetworkingStatus matching the response.
        #
        # Before generating a NetworkConfigResponse, the server shall set the LastNetworkID attribute value to the
        # NetworkID that was used in the command for which an invocation caused the response to be generated.
        #
        # The NetworkingStatus field shall indicate the status of the last operation attempting to modify the Networks
        # attribute configuration, taking one of these values:
        #
        #   • Success: Operation succeeded.
        #
        #   • OutOfRange: Network identifier was invalid (e.g. empty, too long, etc).
        #
        #   • BoundsExceeded: Adding this network configuration would exceed the limit defined by Section 11.8.6.1,
        #     “MaxNetworks Attribute”.
        #
        #   • NetworkIdNotFound: The network identifier was expected to be found, but was not found among the added
        #     network configurations in Networks attribute.
        #
        #   • UnknownError: An internal error occurred during the operation.
        #
        # See Section 11.8.7.2.2, “DebugText Field” for usage.
        struct NetworkConfigurationResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property debug_text : String

          # When the NetworkingStatus is Success, this field shall be present. It shall contain the 0-based index of the
          # entry in the Networks attribute that was last added, updated or removed successfully by the associated
          # request command.
          @[TLV::Field(tag: 2)]
          property networkIndex : UInt8
        end

        # Input to the NetworkCommissioning connectNetwork command
        struct ConnectNetworkRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property network_id : Slice(UInt8)

          @[TLV::Field(tag: 1)]
          property breadcrumb : UInt64?
        end

        # Before generating a ConnectNetworkResponse, the server shall:
        #
        #   • Set the LastNetworkingStatus attribute value to the NetworkingStatus matching the response.
        #
        #   • Set the LastNetworkID attribute value to the NetworkID that was used in the ConnectNetwork command which
        #     caused the response to be generated.
        #
        #   • Set the LastConnectErrorValue attribute value to the ErrorValue matching the response, including setting it
        #     to null if the ErrorValue is not applicable.
        #
        # The NetworkingStatus field shall indicate the status of the last connection attempt, taking one of these values:
        #
        #   • Success: Connection succeeded.
        #
        #   • NetworkNotFound: No instance of an explicitly-provided network identifier was found during the attempt to
        #     join the network.
        #
        #   • OutOfRange: Network identifier was invalid (e.g. empty, too long, etc).
        #
        #   • NetworkIdNotFound: The network identifier was not found among the added network configurations in Networks
        #     attribute.
        #
        #   • RegulatoryError: Could not connect to a network due to lack of regulatory configuration.
        #
        #   • UnknownError: An internal error occurred during the operation.
        #
        #   • Association errors (see also description of errors in Section 11.8.5.3, “NetworkCommissioningStatusEnum”):
        #     AuthFailure, UnsupportedSecurity, OtherConnectionFailure, IPV6Failed, IPBindFailed
        #
        # See Section 11.8.7.2.2, “DebugText Field” for usage.
        struct ConnectNetworkResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property debug_text : String

          #   • ErrorValue interpretation for Wi-Fi association errors:
          #
          #     ◦ On any association failure during enabling of a network, the ErrorValue field shall be set to the
          #       Status Code value that was present in the last frame related to association where Status Code was not
          #       equal to zero and which caused the failure of a final retry attempt, if this final failure was due to
          #       one of the following Management frames:
          #
          #       ▪ Association Response (Type 0, Subtype 1)
          #
          #       ▪ Reassociation Response (Type 0, Subtype 3)
          #
          #       ▪ Authentication (Type 0, Subtype 11)
          #
          #     ◦ Table 9-50 "Status Codes" in IEEE 802.11-2020 contains a description of all values possible, which can
          #       unambiguously be used to determine the cause, such as an invalid security type, unsupported rate, etc.
          #
          #   • Otherwise, the ErrorValue field shall contain an implementation-dependent value which may be used by a
          #     reader of the structure to record, report or diagnose the failure.
          @[TLV::Field(tag: 2)]
          property error_value : Int32?
        end

        # Input to the NetworkCommissioning reorderNetwork command
        struct ReorderNetworkRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property network_id : Slice(UInt8)

          @[TLV::Field(tag: 1)]
          property networkIndex : UInt8

          @[TLV::Field(tag: 2)]
          property breadcrumb : UInt64
        end

        struct AddOrUpdateWiFiNetworkRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property ssid : Slice(UInt8)

          # Credentials is the passphrase or PSK for the network (if any is needed).
          #
          # Security type, cipher and credential format (passphrase or PSK) shall be contextually auto- selected during
          # execution of the ConnectNetwork Command and during subsequent operational state network connections, based
          # on the most secure Wi-Fi security type available within beacons and probe responses for the set of all
          # discovered BSSIDs for the configured SSID. The type of PSK or passphrase used shall be inferred based on the
          # length and contents of the Credentials field provided, matching the security type chosen.
          #
          # Valid Credentials length are:
          #
          #   • 0 bytes: Unsecured (open) connection
          #
          #   • 5 bytes: WEP-64 passphrase
          #
          #   • 10 hexadecimal ASCII characters: WEP-64 40-bit hex raw PSK
          #
          #   • 13 bytes: WEP-128 passphrase
          #
          #   • 26 hexadecimal ASCII characters: WEP-128 104-bit hex raw PSK
          #
          #   • 8..63 bytes: WPA/WPA2/WPA3 passphrase
          #
          #   • 64 bytes: WPA/WPA2/WPA3 raw hex PSK
          #
          # These lengths shall be contextually interpreted based on the security type of the BSSID where connection
          # will occur.
          #
          # When the length of Credentials and available set of BSSID admits more than one option, such as the presence
          # of both WPA2 and WPA security type within the result set, WPA2 shall be considered more secure.
          #
          # Note that it may occur that a station cannot connect to a particular access point with higher security and
          # selects a lower security connectivity type if the link quality is deemed to be too low to achieve successful
          # operation, or if all retry attempts fail.
          #
          # See Section 11.8.7.1.2, “Breadcrumb Field” for usage.
          @[TLV::Field(tag: 1)]
          property credentials : Slice(UInt8)

          @[TLV::Field(tag: 2)]
          property breadcrumb : UInt64
        end

        struct AddOrUpdateThreadNetworkRequest
          include TLV::Serializable

          # The OperationalDataset field shall contain the Thread Network Parameters, including channel, PAN ID, and
          # Extended PAN ID.
          #
          # The encoding for the OperationalDataset field is defined in the Thread specification. The client shall pass
          # the OperationalDataset as an opaque octet string.
          #
          # See Section 11.8.7.1.2, “Breadcrumb Field” for usage.
          @[TLV::Field(tag: 0)]
          property operational_dataset : Slice(UInt8)

          @[TLV::Field(tag: 1)]
          property breadcrumb : UInt64
        end
      end
    end
  end
end
