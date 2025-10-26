require "../fabric_table"
require "log"
require "base64"
require "json"

module Matter
  module Clusters
    # Network Commissioning Cluster (0x0031)
    #
    # This cluster is used to configure network interfaces on Matter devices.
    # It supports WiFi, Thread, and Ethernet network management.
    #
    # Matter Specification: Core 1.4 § 11.8 - Network Commissioning Cluster
    #
    # Commands:
    # - ScanNetworks (0x00): Scan for available networks
    # - AddOrUpdateWiFiNetwork (0x02): Add or update WiFi network configuration
    # - AddOrUpdateThreadNetwork (0x03): Add or update Thread network configuration
    # - RemoveNetwork (0x04): Remove a network from the Networks list
    # - ConnectNetwork (0x06): Connect to a configured network
    # - ReorderNetwork (0x08): Reorder network priority
    #
    # Attributes:
    # - MaxNetworks (0x00): Maximum number of networks
    # - Networks (0x01): List of configured networks
    # - ScanMaxTimeSeconds (0x02): Maximum scan time
    # - ConnectMaxTimeSeconds (0x03): Maximum connect time
    # - InterfaceEnabled (0x04): Network interface enabled status
    # - LastNetworkingStatus (0x05): Status of last operation
    # - LastNetworkID (0x06): Network ID of last operation
    # - LastConnectErrorValue (0x07): Error value from last connect
    class NetworkCommissioning
      CLUSTER_ID = 0x0031_u16

      # Feature flags
      enum Feature : UInt32
        WiFiNetworkInterface     = 0x01 # Bit 0 - WiFi support
        ThreadNetworkInterface   = 0x02 # Bit 1 - Thread support
        EthernetNetworkInterface = 0x04 # Bit 2 - Ethernet support
      end

      # NetworkCommissioningStatus Enum
      # Status codes returned by network commissioning commands
      enum NetworkCommissioningStatus : UInt8
        Success                =  0 # Operation successful
        OutOfRange             =  1 # Invalid network ID (empty, too long, invalid format)
        BoundsExceeded         =  2 # Would exceed MaxNetworks limit
        NetworkIdNotFound      =  3 # Network ID not found in Networks
        DuplicateNetworkId     =  4 # Network ID already exists
        NetworkNotFound        =  5 # Network not found during scan/connection
        RegulatoryError        =  6 # Regulatory domain/band mismatch
        AuthFailure            =  7 # Authentication failure (WiFi)
        UnsupportedSecurity    =  8 # Unsupported security mode
        OtherConnectionFailure =  9 # Other WiFi association failure
        Ipv6Failed             = 10 # IPv6 address generation failed
        IpBindFailed           = 11 # WiFi-IP interface binding failed
        UnknownError           = 12 # Unknown internal error
      end

      # WiFiSecurityBitmap
      # Bitmask of supported WiFi security types
      @[Flags]
      enum WiFiSecurityBitmap : UInt8
        Unencrypted  = 0x01 # Bit 0 - Open network
        WEP          = 0x02 # Bit 1 - WEP security
        WPAPersonal  = 0x04 # Bit 2 - WPA-Personal
        WPA2Personal = 0x08 # Bit 3 - WPA2-Personal
        WPA3Personal = 0x10 # Bit 4 - WPA3-Personal
      end

      # WiFiBandEnum
      # Supported WiFi frequency bands
      enum WiFiBandEnum : UInt8
        Band2G4  = 0 # 2.4GHz 802.11b/g/n/ax
        Band3G65 = 1 # 3.65GHz 802.11y
        Band5G   = 2 # 5GHz 802.11a/n/ac/ax
        Band6G   = 3 # 6GHz 802.11ax (WiFi 6E)
        Band60G  = 4 # 60GHz 802.11ad/ay
        Band1G   = 5 # Sub-1GHz 802.11ah
      end

      # ThreadCapabilitiesBitmap
      # Bitmask of Thread device capabilities
      @[Flags]
      enum ThreadCapabilitiesBitmap : UInt16
        IsBorderRouterCapable                = 0x01 # Bit 0
        IsRouterCapable                      = 0x02 # Bit 1
        IsSleepyEndDeviceCapable             = 0x04 # Bit 2
        IsFullThreadDevice                   = 0x08 # Bit 3
        IsSynchronizedSleepyEndDeviceCapable = 0x10 # Bit 4
      end

      # NetworkInfoStruct - Represents a configured network
      struct NetworkInfo
        property network_id : Bytes # 1-32 bytes (SSID or XPAN ID)
        property connected : Bool   # Current connection status

        def initialize(@network_id : Bytes, @connected : Bool)
          raise ArgumentError.new("network_id must be 1-32 bytes") unless network_id.size.in?(1..32)
        end
      end

      # WiFiInterfaceScanResult - Result from WiFi network scan
      struct WiFiInterfaceScanResult
        property security : WiFiSecurityBitmap?
        property ssid : Bytes?  # Max 32 bytes
        property bssid : Bytes? # Exactly 6 bytes (MAC address)
        property channel : UInt16?
        property wifi_band : WiFiBandEnum?
        property rssi : Int8? # dBm

        def initialize(
          @security : WiFiSecurityBitmap? = nil,
          @ssid : Bytes? = nil,
          @bssid : Bytes? = nil,
          @channel : UInt16? = nil,
          @wifi_band : WiFiBandEnum? = nil,
          @rssi : Int8? = nil,
        )
          raise ArgumentError.new("ssid must be max 32 bytes") if ssid && ssid.size > 32
          raise ArgumentError.new("bssid must be exactly 6 bytes") if bssid && bssid.size != 6
        end
      end

      # ThreadInterfaceScanResult - Result from Thread network scan
      struct ThreadInterfaceScanResult
        property pan_id : UInt16?          # Max 65534
        property extended_pan_id : UInt64? # XPAN ID
        property network_name : String?    # 1-16 chars
        property channel : UInt16?
        property version : UInt8?          # Thread version
        property extended_address : Bytes? # IEEE 802.15.4
        property rssi : Int8?              # dBm
        property lqi : UInt8?              # Link Quality Indicator

        def initialize(
          @pan_id : UInt16? = nil,
          @extended_pan_id : UInt64? = nil,
          @network_name : String? = nil,
          @channel : UInt16? = nil,
          @version : UInt8? = nil,
          @extended_address : Bytes? = nil,
          @rssi : Int8? = nil,
          @lqi : UInt8? = nil,
        )
          raise ArgumentError.new("network_name must be 1-16 chars") if network_name && !network_name.size.in?(1..16)
          raise ArgumentError.new("pan_id must be max 65534") if pan_id && pan_id > 65534
        end
      end

      # ScanNetworks command (0x00)
      struct ScanNetworksRequest
        property ssid : Bytes? # 1-32 bytes, optional directed scan
        property breadcrumb : UInt64?

        def initialize(@ssid : Bytes? = nil, @breadcrumb : UInt64? = nil)
          raise ArgumentError.new("ssid must be 1-32 bytes") if ssid && !ssid.size.in?(1..32)
        end
      end

      struct ScanNetworksResponse
        property networking_status : NetworkCommissioningStatus
        property debug_text : String? # 0-512 chars
        property wifi_scan_results : Array(WiFiInterfaceScanResult)?
        property thread_scan_results : Array(ThreadInterfaceScanResult)?

        def initialize(
          @networking_status : NetworkCommissioningStatus,
          @debug_text : String? = nil,
          @wifi_scan_results : Array(WiFiInterfaceScanResult)? = nil,
          @thread_scan_results : Array(ThreadInterfaceScanResult)? = nil,
        )
          raise ArgumentError.new("debug_text must be max 512 chars") if debug_text && debug_text.size > 512
        end
      end

      # AddOrUpdateWiFiNetwork command (0x02)
      struct AddOrUpdateWiFiNetworkRequest
        property ssid : Bytes        # Max 32 bytes
        property credentials : Bytes # Max 64 bytes
        property breadcrumb : UInt64?

        def initialize(@ssid : Bytes, @credentials : Bytes, @breadcrumb : UInt64? = nil)
          raise ArgumentError.new("ssid must be max 32 bytes") if ssid.size > 32
          raise ArgumentError.new("credentials must be max 64 bytes") if credentials.size > 64
        end
      end

      # AddOrUpdateThreadNetwork command (0x03)
      struct AddOrUpdateThreadNetworkRequest
        property operational_dataset : Bytes # Max 254 bytes
        property breadcrumb : UInt64?

        def initialize(@operational_dataset : Bytes, @breadcrumb : UInt64? = nil)
          raise ArgumentError.new("operational_dataset must be max 254 bytes") if operational_dataset.size > 254
        end
      end

      # NetworkConfigResponse - Generic response for Add/Update/Remove/Reorder
      struct NetworkConfigResponse
        property networking_status : NetworkCommissioningStatus
        property debug_text : String? # 0-512 chars
        property network_index : UInt8?

        def initialize(
          @networking_status : NetworkCommissioningStatus,
          @debug_text : String? = nil,
          @network_index : UInt8? = nil,
        )
          raise ArgumentError.new("debug_text must be max 512 chars") if debug_text && debug_text.size > 512
        end
      end

      # RemoveNetwork command (0x04)
      struct RemoveNetworkRequest
        property network_id : Bytes # 1-32 bytes
        property breadcrumb : UInt64?

        def initialize(@network_id : Bytes, @breadcrumb : UInt64? = nil)
          raise ArgumentError.new("network_id must be 1-32 bytes") unless network_id.size.in?(1..32)
        end
      end

      # ConnectNetwork command (0x06)
      struct ConnectNetworkRequest
        property network_id : Bytes # 1-32 bytes
        property breadcrumb : UInt64?

        def initialize(@network_id : Bytes, @breadcrumb : UInt64? = nil)
          raise ArgumentError.new("network_id must be 1-32 bytes") unless network_id.size.in?(1..32)
        end
      end

      struct ConnectNetworkResponse
        property networking_status : NetworkCommissioningStatus
        property debug_text : String? # 0-512 chars
        property error_value : Int32? # WiFi 802.11 Status Code or platform-specific

        def initialize(
          @networking_status : NetworkCommissioningStatus,
          @debug_text : String? = nil,
          @error_value : Int32? = nil,
        )
          raise ArgumentError.new("debug_text must be max 512 chars") if debug_text && debug_text.size > 512
        end
      end

      # ReorderNetwork command (0x08)
      struct ReorderNetworkRequest
        property network_id : Bytes    # 1-32 bytes
        property network_index : UInt8 # Desired position (0-based)
        property breadcrumb : UInt64?

        def initialize(@network_id : Bytes, @network_index : UInt8, @breadcrumb : UInt64? = nil)
          raise ArgumentError.new("network_id must be 1-32 bytes") unless network_id.size.in?(1..32)
        end
      end

      # The Network Commissioning cluster server
      @max_networks : UInt8
      @networks : Array(NetworkInfo)
      @interface_enabled : Bool
      @last_networking_status : NetworkCommissioningStatus?
      @last_network_id : Bytes?
      @last_connect_error_value : Int32?
      @features : Feature
      @scan_max_time_seconds : UInt8
      @connect_max_time_seconds : UInt8

      # WiFi-specific
      @supported_wifi_bands : Array(WiFiBandEnum)?

      # Thread-specific
      @supported_thread_features : ThreadCapabilitiesBitmap?
      @thread_version : UInt16?

      # Breadcrumb callback to update GeneralCommissioning cluster
      @breadcrumb_callback : Proc(UInt64, Nil)?

      def initialize(
        @max_networks : UInt8 = 4_u8,
        @features : Feature = Feature::WiFiNetworkInterface,
        @scan_max_time_seconds : UInt8 = 30_u8,
        @connect_max_time_seconds : UInt8 = 60_u8,
      )
        raise ArgumentError.new("max_networks must be >= 1") if @max_networks < 1

        @networks = [] of NetworkInfo
        @interface_enabled = true
        @last_networking_status = nil
        @last_network_id = nil
        @last_connect_error_value = nil

        # Initialize WiFi-specific attributes if WiFi feature enabled
        if @features.includes?(Feature::WiFiNetworkInterface)
          @supported_wifi_bands = [WiFiBandEnum::Band2G4, WiFiBandEnum::Band5G]
        end

        # Initialize Thread-specific attributes if Thread feature enabled
        if @features.includes?(Feature::ThreadNetworkInterface)
          @supported_thread_features = ThreadCapabilitiesBitmap::IsRouterCapable | ThreadCapabilitiesBitmap::IsFullThreadDevice
          @thread_version = 4_u16 # Thread 1.3
        end
      end

      # Set breadcrumb callback for GeneralCommissioning integration
      def breadcrumb_callback=(callback : Proc(UInt64, Nil)?)
        @breadcrumb_callback = callback
      end

      # Attributes

      def max_networks : UInt8
        @max_networks
      end

      def networks : Array(NetworkInfo)
        @networks
      end

      def scan_max_time_seconds : UInt8
        @scan_max_time_seconds
      end

      def connect_max_time_seconds : UInt8
        @connect_max_time_seconds
      end

      def interface_enabled : Bool
        @interface_enabled
      end

      def interface_enabled=(value : Bool)
        @interface_enabled = value
      end

      def last_networking_status : NetworkCommissioningStatus?
        @last_networking_status
      end

      def last_network_id : Bytes?
        @last_network_id
      end

      def last_connect_error_value : Int32?
        @last_connect_error_value
      end

      def supported_wifi_bands : Array(WiFiBandEnum)?
        @supported_wifi_bands
      end

      def supported_thread_features : ThreadCapabilitiesBitmap?
        @supported_thread_features
      end

      def thread_version : UInt16?
        @thread_version
      end

      # Commands

      # ScanNetworks command (0x00)
      def handle_scan_networks(
        cmd : ScanNetworksRequest,
        failsafe_armed : Bool,
      ) : ScanNetworksResponse
        # Validate fail-safe is armed
        unless failsafe_armed
          return ScanNetworksResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "Fail-safe not armed"
          )
        end

        # Update breadcrumb if provided
        update_breadcrumb(cmd.breadcrumb)

        # Perform scan based on enabled features
        wifi_results = nil
        thread_results = nil

        if @features.includes?(Feature::WiFiNetworkInterface)
          wifi_results = perform_wifi_scan(cmd.ssid)
        end

        if @features.includes?(Feature::ThreadNetworkInterface)
          thread_results = perform_thread_scan
        end

        # Update state
        @last_networking_status = NetworkCommissioningStatus::Success
        @last_network_id = cmd.ssid

        ScanNetworksResponse.new(
          networking_status: NetworkCommissioningStatus::Success,
          wifi_scan_results: wifi_results,
          thread_scan_results: thread_results
        )
      end

      # AddOrUpdateWiFiNetwork command (0x02)
      def handle_add_or_update_wifi_network(
        cmd : AddOrUpdateWiFiNetworkRequest,
        failsafe_armed : Bool,
      ) : NetworkConfigResponse
        # Validate fail-safe is armed
        unless failsafe_armed
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "Fail-safe not armed"
          )
        end

        # Validate WiFi feature is supported
        unless @features.includes?(Feature::WiFiNetworkInterface)
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "WiFi not supported"
          )
        end

        # Validate network ID
        if cmd.ssid.empty?
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::OutOfRange,
            debug_text: "SSID cannot be empty"
          )
        end

        # Check if network already exists (update) or new (add)
        existing_index = @networks.index { |n| n.network_id == cmd.ssid }

        if existing_index
          # Update existing network
          @networks[existing_index] = NetworkInfo.new(cmd.ssid, @networks[existing_index].connected)
          network_index = existing_index.to_u8
        else
          # Add new network
          if @networks.size >= @max_networks
            return NetworkConfigResponse.new(
              networking_status: NetworkCommissioningStatus::BoundsExceeded,
              debug_text: "Max networks limit reached"
            )
          end

          @networks << NetworkInfo.new(cmd.ssid, false)
          network_index = (@networks.size - 1).to_u8
        end

        # Update state
        @last_networking_status = NetworkCommissioningStatus::Success
        @last_network_id = cmd.ssid
        update_breadcrumb(cmd.breadcrumb)

        NetworkConfigResponse.new(
          networking_status: NetworkCommissioningStatus::Success,
          network_index: network_index
        )
      end

      # AddOrUpdateThreadNetwork command (0x03)
      def handle_add_or_update_thread_network(
        cmd : AddOrUpdateThreadNetworkRequest,
        failsafe_armed : Bool,
      ) : NetworkConfigResponse
        # Validate fail-safe is armed
        unless failsafe_armed
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "Fail-safe not armed"
          )
        end

        # Validate Thread feature is supported
        unless @features.includes?(Feature::ThreadNetworkInterface)
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "Thread not supported"
          )
        end

        # Extract XPAN ID from operational dataset (simplified - real implementation would parse TLV)
        # For now, use first 8 bytes as network ID
        network_id = cmd.operational_dataset.size >= 8 ? cmd.operational_dataset[0, 8] : cmd.operational_dataset

        # Check if network already exists
        existing_index = @networks.index { |n| n.network_id == network_id }

        if existing_index
          # Update existing network
          @networks[existing_index] = NetworkInfo.new(network_id, @networks[existing_index].connected)
          network_index = existing_index.to_u8
        else
          # Add new network
          if @networks.size >= @max_networks
            return NetworkConfigResponse.new(
              networking_status: NetworkCommissioningStatus::BoundsExceeded,
              debug_text: "Max networks limit reached"
            )
          end

          @networks << NetworkInfo.new(network_id, false)
          network_index = (@networks.size - 1).to_u8
        end

        # Update state
        @last_networking_status = NetworkCommissioningStatus::Success
        @last_network_id = network_id
        update_breadcrumb(cmd.breadcrumb)

        NetworkConfigResponse.new(
          networking_status: NetworkCommissioningStatus::Success,
          network_index: network_index
        )
      end

      # RemoveNetwork command (0x04)
      def handle_remove_network(
        cmd : RemoveNetworkRequest,
        failsafe_armed : Bool,
      ) : NetworkConfigResponse
        # Validate fail-safe is armed
        unless failsafe_armed
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "Fail-safe not armed"
          )
        end

        # Find network by ID
        index = @networks.index { |n| n.network_id == cmd.network_id }

        unless index
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::NetworkIdNotFound,
            debug_text: "Network not found"
          )
        end

        # Remove network (maintains relative order of remaining entries)
        @networks.delete_at(index)

        # Update state
        @last_networking_status = NetworkCommissioningStatus::Success
        @last_network_id = cmd.network_id
        update_breadcrumb(cmd.breadcrumb)

        NetworkConfigResponse.new(
          networking_status: NetworkCommissioningStatus::Success,
          network_index: index.to_u8
        )
      end

      # ConnectNetwork command (0x06)
      def handle_connect_network(
        cmd : ConnectNetworkRequest,
        failsafe_armed : Bool,
      ) : ConnectNetworkResponse
        # Validate fail-safe is armed
        unless failsafe_armed
          return ConnectNetworkResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "Fail-safe not armed"
          )
        end

        # Find network by ID
        index = @networks.index { |n| n.network_id == cmd.network_id }

        unless index
          return ConnectNetworkResponse.new(
            networking_status: NetworkCommissioningStatus::NetworkIdNotFound,
            debug_text: "Network not found"
          )
        end

        # Simulate connection (real implementation would actually connect)
        # Set target network as connected, others as disconnected
        @networks = @networks.map_with_index do |network, i|
          NetworkInfo.new(network.network_id, i == index)
        end

        # Update state
        @last_networking_status = NetworkCommissioningStatus::Success
        @last_network_id = cmd.network_id
        @last_connect_error_value = nil
        update_breadcrumb(cmd.breadcrumb)

        ConnectNetworkResponse.new(
          networking_status: NetworkCommissioningStatus::Success,
          error_value: nil
        )
      end

      # ReorderNetwork command (0x08)
      def handle_reorder_network(
        cmd : ReorderNetworkRequest,
        failsafe_armed : Bool,
      ) : NetworkConfigResponse
        # Validate fail-safe is armed
        unless failsafe_armed
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::UnknownError,
            debug_text: "Fail-safe not armed"
          )
        end

        # Find network by ID
        current_index = @networks.index { |n| n.network_id == cmd.network_id }

        unless current_index
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::NetworkIdNotFound,
            debug_text: "Network not found"
          )
        end

        # Validate new index is in range
        if cmd.network_index >= @networks.size
          return NetworkConfigResponse.new(
            networking_status: NetworkCommissioningStatus::OutOfRange,
            debug_text: "Network index out of range"
          )
        end

        # Reorder network (move from current_index to network_index)
        network = @networks.delete_at(current_index)
        @networks.insert(cmd.network_index, network)

        # Update state
        @last_networking_status = NetworkCommissioningStatus::Success
        @last_network_id = cmd.network_id
        update_breadcrumb(cmd.breadcrumb)

        NetworkConfigResponse.new(
          networking_status: NetworkCommissioningStatus::Success,
          network_index: cmd.network_index
        )
      end

      # Restore network state from snapshot (used during failsafe rollback)
      #
      # This method restores the network configuration to a previously captured state.
      # It's called during failsafe rollback to undo any network configuration changes
      # made during a failed commissioning session.
      #
      # @param state Snapshot of network state (key-value pairs)
      def restore_network_state(state : Hash(String, String)) : Nil
        Log.info { "Restoring network state from snapshot" }

        # Restore networks list
        if networks_json = state["networks"]?
          begin
            network_data = Array(Hash(String, JSON::Any)).from_json(networks_json)
            @networks.clear

            network_data.each do |net|
              network_id = Base64.decode(net["network_id"].as_s)
              connected = net["connected"].as_bool
              @networks << NetworkInfo.new(network_id, connected)
            end

            Log.debug { "Restored #{@networks.size} network(s)" }
          rescue ex
            Log.error(exception: ex) { "Failed to restore networks from snapshot" }
          end
        end

        # Restore interface enabled state
        if interface_enabled_str = state["interface_enabled"]?
          @interface_enabled = interface_enabled_str == "true"
          Log.debug { "Restored interface_enabled: #{@interface_enabled}" }
        end

        # Restore last networking status
        if last_status_str = state["last_networking_status"]?
          @last_networking_status = NetworkCommissioningStatus.from_value(last_status_str.to_u8)
          Log.debug { "Restored last_networking_status: #{@last_networking_status}" }
        end

        # Restore last network ID
        if last_network_id_str = state["last_network_id"]?
          @last_network_id = Base64.decode(last_network_id_str) unless last_network_id_str.empty?
          Log.debug { "Restored last_network_id" }
        end

        # Restore last connect error value
        if last_error_str = state["last_connect_error_value"]?
          @last_connect_error_value = last_error_str.to_i32? unless last_error_str.empty?
          Log.debug { "Restored last_connect_error_value: #{@last_connect_error_value}" }
        end

        Log.info { "Network state restored successfully" }
      end

      # Helper methods

      private def update_breadcrumb(breadcrumb : UInt64?)
        return unless breadcrumb
        @breadcrumb_callback.try &.call(breadcrumb)
      end

      private def perform_wifi_scan(ssid : Bytes?) : Array(WiFiInterfaceScanResult)
        # Simplified WiFi scan simulation
        # Real implementation would use platform WiFi APIs
        results = [] of WiFiInterfaceScanResult

        # Simulate finding networks
        if ssid
          # Directed scan - return single result if found
          results << WiFiInterfaceScanResult.new(
            security: WiFiSecurityBitmap::WPA2Personal,
            ssid: ssid,
            bssid: Bytes[0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
            channel: 6_u16,
            wifi_band: WiFiBandEnum::Band2G4,
            rssi: -50_i8
          )
        else
          # Full scan - return multiple results
          results << WiFiInterfaceScanResult.new(
            security: WiFiSecurityBitmap::WPA2Personal | WiFiSecurityBitmap::WPA3Personal,
            ssid: "TestNetwork1".to_slice,
            bssid: Bytes[0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
            channel: 6_u16,
            wifi_band: WiFiBandEnum::Band2G4,
            rssi: -45_i8
          )

          results << WiFiInterfaceScanResult.new(
            security: WiFiSecurityBitmap::WPA2Personal,
            ssid: "TestNetwork2".to_slice,
            bssid: Bytes[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
            channel: 11_u16,
            wifi_band: WiFiBandEnum::Band2G4,
            rssi: -60_i8
          )
        end

        # Sort by RSSI (strongest first)
        results.sort_by! { |r| -(r.rssi || -100) }
        results
      end

      private def perform_thread_scan : Array(ThreadInterfaceScanResult)
        # Simplified Thread scan simulation
        # Real implementation would use platform Thread APIs
        results = [] of ThreadInterfaceScanResult

        results << ThreadInterfaceScanResult.new(
          pan_id: 0x1234_u16,
          extended_pan_id: 0x1122334455667788_u64,
          network_name: "TestThread1",
          channel: 15_u16,
          version: 4_u8,
          rssi: -50_i8,
          lqi: 200_u8
        )

        results << ThreadInterfaceScanResult.new(
          pan_id: 0x5678_u16,
          extended_pan_id: 0x8877665544332211_u64,
          network_name: "TestThread2",
          channel: 20_u16,
          version: 4_u8,
          rssi: -65_i8,
          lqi: 150_u8
        )

        # Sort by LQI (highest first) - convert to Int32 for negation
        results.sort_by! { |r| -(r.lqi || 0_u8).to_i32 }
        results
      end
    end
  end
end
