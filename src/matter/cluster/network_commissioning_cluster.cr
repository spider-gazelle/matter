require "./cluster"

module Matter
  module Cluster
    # Network Commissioning Cluster (0x0031)
    #
    # Functionality to configure a network interface on a Matter device.
    # Supports WiFi, Thread, and Ethernet network types.
    #
    # Matter Spec: Core 11.8
    class NetworkCommissioningCluster < Base
      CLUSTER_ID = 0x0031_u32

      # Network commissioning features
      @[Flags]
      enum Feature : UInt32
        WiFiNetworkInterface     = 0x01 # Supports WiFi
        ThreadNetworkInterface   = 0x02 # Supports Thread
        EthernetNetworkInterface = 0x04 # Supports Ethernet
      end

      # Network Types
      enum NetworkType : UInt8
        WiFi     = 0x00
        Thread   = 0x01
        Ethernet = 0x02
      end

      # WiFi Security Types
      enum WiFiSecurityType : UInt8
        Unencrypted = 0x00 # Open network
        WEP         = 0x01 # WEP security (deprecated)
        WPA         = 0x02 # WPA-Personal
        WPA2        = 0x03 # WPA2-Personal
        WPA3        = 0x04 # WPA3-Personal
      end

      # Network Commissioning Status Codes
      enum NetworkCommissioningStatus : UInt8
        Success                = 0x00
        OutOfRange             = 0x01
        BoundsExceeded         = 0x02
        NetworkIDNotFound      = 0x03
        DuplicateNetworkID     = 0x04
        NetworkNotFound        = 0x05
        RegulatoryError        = 0x06
        AuthFailure            = 0x07
        UnsupportedSecurity    = 0x08
        OtherConnectionFailure = 0x09
        IPV6Failed             = 0x0A
        IPBindFailed           = 0x0B
        UnknownError           = 0x0C
      end

      # Attributes
      ATTR_MAX_NETWORKS              = 0x0000_u32
      ATTR_NETWORKS                  = 0x0001_u32
      ATTR_SCAN_MAX_TIME_SECONDS     = 0x0002_u32
      ATTR_CONNECT_MAX_TIME_SECONDS  = 0x0003_u32
      ATTR_INTERFACE_ENABLED         = 0x0004_u32
      ATTR_LAST_NETWORKING_STATUS    = 0x0005_u32
      ATTR_LAST_NETWORK_ID           = 0x0006_u32
      ATTR_LAST_CONNECT_ERROR_VALUE  = 0x0007_u32
      ATTR_SUPPORTED_WIFI_BANDS      = 0x0008_u32
      ATTR_SUPPORTED_THREAD_FEATURES = 0x0009_u32

      # Commands
      CMD_SCAN_NETWORKS                = 0x00_u32
      CMD_SCAN_NETWORKS_RESPONSE       = 0x01_u32
      CMD_ADD_OR_UPDATE_WIFI_NETWORK   = 0x02_u32
      CMD_ADD_OR_UPDATE_THREAD_NETWORK = 0x03_u32
      CMD_REMOVE_NETWORK               = 0x04_u32
      CMD_NETWORK_CONFIG_RESPONSE      = 0x05_u32
      CMD_CONNECT_NETWORK              = 0x06_u32
      CMD_CONNECT_NETWORK_RESPONSE     = 0x07_u32
      CMD_REORDER_NETWORK              = 0x08_u32

      # Network Configuration
      struct NetworkInfo
        property network_id : Bytes # Network identifier (SSID for WiFi, Extended PAN ID for Thread)
        property connected : Bool   # Whether currently connected

        def initialize(@network_id : Bytes, @connected : Bool)
        end
      end

      # WiFi Network Scan Result
      struct WiFiInterfaceScanResult
        property security : WiFiSecurityType
        property ssid : Bytes      # Network SSID
        property bssid : Bytes     # MAC address (6 bytes)
        property channel : UInt16  # WiFi channel
        property wifi_band : UInt8 # WiFi band (2.4GHz, 5GHz, etc.)
        property rssi : Int8       # Signal strength

        def initialize(@security : WiFiSecurityType, @ssid : Bytes, @bssid : Bytes,
                       @channel : UInt16, @wifi_band : UInt8, @rssi : Int8)
        end
      end

      # Thread Network Scan Result
      struct ThreadInterfaceScanResult
        property pan_id : UInt16          # PAN ID
        property extended_pan_id : Bytes  # Extended PAN ID (8 bytes)
        property network_name : String    # Network name
        property channel : UInt16         # Thread channel
        property version : UInt8          # Thread version
        property extended_address : Bytes # Extended address (8 bytes)
        property rssi : Int8              # Signal strength
        property lqi : UInt8              # Link Quality Indicator

        def initialize(@pan_id : UInt16, @extended_pan_id : Bytes, @network_name : String,
                       @channel : UInt16, @version : UInt8, @extended_address : Bytes,
                       @rssi : Int8, @lqi : UInt8)
        end
      end

      property network_type : NetworkType
      property feature_map : Feature

      # Attribute storage
      property max_networks : UInt8
      property networks : Array(NetworkInfo)
      property scan_max_time_seconds : UInt8
      property connect_max_time_seconds : UInt8
      property interface_enabled : Bool
      property last_networking_status : NetworkCommissioningStatus?
      property last_network_id : Bytes?
      property last_connect_error_value : Int32?

      # WiFi-specific
      property wifi_credentials : Hash(Bytes, Bytes) # SSID -> password
      property supported_wifi_bands : Array(UInt8)

      # Thread-specific
      property thread_credentials : Hash(Bytes, Bytes) # Extended PAN ID -> credentials
      property supported_thread_features : UInt16

      # Callbacks
      property on_scan_networks : Proc(NetworkType, Bytes?, Array(WiFiInterfaceScanResult | ThreadInterfaceScanResult))?
      property on_add_network : Proc(Bytes, Bytes, NetworkCommissioningStatus)?
      property on_remove_network : Proc(Bytes, NetworkCommissioningStatus)?
      property on_connect_network : Proc(Bytes, Tuple(NetworkCommissioningStatus, Int32?))?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @network_type : NetworkType,
        @feature_map : Feature = Feature::None,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @max_networks = 1_u8
        @networks = [] of NetworkInfo
        @scan_max_time_seconds = 30_u8
        @connect_max_time_seconds = 60_u8
        @interface_enabled = true
        @last_networking_status = nil
        @last_network_id = nil
        @last_connect_error_value = nil

        @wifi_credentials = {} of Bytes => Bytes
        @supported_wifi_bands = [] of UInt8

        @thread_credentials = {} of Bytes => Bytes
        @supported_thread_features = 0_u16

        @on_scan_networks = nil
        @on_add_network = nil
        @on_remove_network = nil
        @on_connect_network = nil
      end

      def name : String
        "NetworkCommissioning"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MAX_NETWORKS),
            "MaxNetworks",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SCAN_MAX_TIME_SECONDS),
            "ScanMaxTimeSeconds",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CONNECT_MAX_TIME_SECONDS),
            "ConnectMaxTimeSeconds",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_INTERFACE_ENABLED),
            "InterfaceEnabled",
            :bool,
            writable: true
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_SCAN_NETWORKS),
            "ScanNetworks"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_ADD_OR_UPDATE_WIFI_NETWORK),
            "AddOrUpdateWiFiNetwork"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_ADD_OR_UPDATE_THREAD_NETWORK),
            "AddOrUpdateThreadNetwork"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_REMOVE_NETWORK),
            "RemoveNetwork"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_CONNECT_NETWORK),
            "ConnectNetwork"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_REORDER_NETWORK),
            "ReorderNetwork"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_MAX_NETWORKS
          encode_uint8(@max_networks)
        when ATTR_SCAN_MAX_TIME_SECONDS
          encode_uint8(@scan_max_time_seconds)
        when ATTR_CONNECT_MAX_TIME_SECONDS
          encode_uint8(@connect_max_time_seconds)
        when ATTR_INTERFACE_ENABLED
          encode_bool(@interface_enabled)
        when ATTR_LAST_NETWORKING_STATUS
          if status = @last_networking_status
            encode_uint8(status.value)
          else
            Bytes.new(0) # Null
          end
        when ATTR_LAST_NETWORK_ID
          @last_network_id || Bytes.new(0) # Null
        when ATTR_LAST_CONNECT_ERROR_VALUE
          if error = @last_connect_error_value
            encode_uint32(error.to_u32)
          else
            Bytes.new(0) # Null
          end
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_INTERFACE_ENABLED
          if value.size > 0
            @interface_enabled = (value[0] != 0)
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        case command_id
        when CMD_SCAN_NETWORKS
          handle_scan_networks(fields)
        when CMD_ADD_OR_UPDATE_WIFI_NETWORK
          handle_add_or_update_wifi_network(fields)
        when CMD_ADD_OR_UPDATE_THREAD_NETWORK
          handle_add_or_update_thread_network(fields)
        when CMD_REMOVE_NETWORK
          handle_remove_network(fields)
        when CMD_CONNECT_NETWORK
          handle_connect_network(fields)
        when CMD_REORDER_NETWORK
          handle_reorder_network(fields)
        else
          super
        end
      end

      private def handle_scan_networks(fields : Bytes) : Bytes
        # Simplified implementation - return empty response
        Bytes.new(0)
      end

      private def handle_add_or_update_wifi_network(fields : Bytes) : Bytes
        # Simplified implementation
        Bytes.new(0)
      end

      private def handle_add_or_update_thread_network(fields : Bytes) : Bytes
        # Simplified implementation
        Bytes.new(0)
      end

      private def handle_remove_network(fields : Bytes) : Bytes
        # Simplified implementation
        Bytes.new(0)
      end

      private def handle_connect_network(fields : Bytes) : Bytes
        # Simplified implementation
        Bytes.new(0)
      end

      private def handle_reorder_network(fields : Bytes) : Bytes
        # Simplified implementation
        Bytes.new(0)
      end

      # Helper: Get current connected network
      def connected_network : NetworkInfo?
        @networks.find(&.connected)
      end

      # Helper: Check if network exists
      def has_network?(network_id : Bytes) : Bool
        @networks.any? { |n| n.network_id == network_id }
      end
    end
  end
end
