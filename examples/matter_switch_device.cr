require "json"
require "file_utils"
require "goban"
require "../src/matter"
require "../src/matter/mdns/responder"
require "../src/matter/mdns/service_type"
require "../src/matter/mdns/service_description"
require "../src/matter/constants/device_types"
require "../src/matter/fabric"
require "../src/matter/fabric_table"
require "../src/matter/storage/memory_backend"
require "../src/matter/setup_payload"
require "../src/matter/transport/udp_transport"
require "../src/matter/codec/message_codec"
require "../src/matter/protocol/message_handler"
require "../src/matter/cluster/administrator_commissioning_cluster"
require "../src/matter/cluster/general_diagnostics_cluster"
require "../src/matter/cluster/network_commissioning_cluster"
require "../src/matter/cluster/group_key_management_cluster"
require "../src/matter/cluster/ota_requestor_cluster"
require "../src/matter/cluster/diagnostic_logs_cluster"
require "../src/matter/cluster/ethernet_network_diagnostics_cluster"
require "../src/matter/cluster/scenes_management_cluster"

# Matter Switch Device Example
#
# This is a complete Matter device implementation that:
# - Presents as an On/Off Light (controllable light device)
# - Persists state to JSON files
# - Supports commissioning and operational modes
# - Can reconnect after restart without recommissioning
# - Uses terminal UI for interaction
# - Actually works with real Matter controllers (iPhone, chip-tool, etc.)

module MatterSwitch
  # Device state manager - handles JSON persistence
  class DeviceState
    include JSON::Serializable

    property device_name : String
    property on_off : Bool
    property data_version : UInt32
    property commissioned : Bool
    property discriminator : UInt16
    property vendor_id : UInt16
    property product_id : UInt16
    property setup_pin : UInt32
    property unique_id : String
    property serial_number : String

    def initialize(
      @device_name = "Crystal Switch",
      @on_off = false,
      @data_version = 0_u32,
      @commissioned = false,
      @discriminator = DeviceState.generate_random_discriminator,
      @vendor_id = 0xFFF1_u16,
      @product_id = 0x8004_u16,
      @setup_pin = DeviceState.generate_random_pin,
      @unique_id = DeviceState.generate_unique_id,
      @serial_number = DeviceState.generate_serial_number,
    )
    end

    # Generate a unique ID (UUID-like format)
    def self.generate_unique_id : String
      bytes = Random::Secure.random_bytes(16)
      bytes.hexstring.upcase
    end

    # Generate a serial number
    def self.generate_serial_number : String
      "CS-#{Random::Secure.rand(100000..999999)}"
    end

    # Generate a random discriminator (12-bit value, 0-4095)
    # Each device instance should have a unique discriminator
    def self.generate_random_discriminator : UInt16
      Random::Secure.rand(4096).to_u16
    end

    # Generate a random valid PIN that meets Matter requirements
    # - Must be 1-99999998
    # - Cannot be all same digit (11111111, etc.)
    # - Cannot be 12345678 or 87654321
    def self.generate_random_pin : UInt32
      loop do
        pin = Random::Secure.rand(1_u32..99999998_u32)
        pin_str = pin.to_s.rjust(8, '0')

        # Check if all digits are the same
        next if pin_str.chars.uniq.size == 1

        # Check blacklisted PINs
        next if pin == 12345678 || pin == 87654321

        return pin
      end
    end

    def self.load(path : String) : DeviceState
      if File.exists?(path)
        from_json(File.read(path))
      else
        new
      end
    rescue ex
      puts "⚠️  Failed to load state: #{ex.message}"
      new
    end

    def save(path : String)
      File.write(path, to_pretty_json)
    end
  end

  # Simple fabric storage for the example
  # In a production device, use FabricTable with persistent Storage::Base
  class FabricStorage
    property fabrics : Array(Matter::Fabric)

    def initialize
      @fabrics = [] of Matter::Fabric
    end

    def self.load(path : String) : FabricStorage
      storage = new
      if File.exists?(path)
        json = File.read(path)
        data = Hash(String, Hash(String, String | Int64)).from_json(json)
        data.each do |_, fabric_data|
          # Convert to proper hash types for Fabric.from_h
          fabric_hash = {} of String => (String | UInt64 | UInt16 | UInt8 | Int64)
          fabric_data.each do |key, value|
            fabric_hash[key] = value
          end
          storage.fabrics << Matter::Fabric.from_h(fabric_hash)
        end
      end
      storage
    rescue ex
      puts "⚠️  Failed to load fabrics: #{ex.message}"
      new
    end

    def save(path : String)
      data = {} of String => Hash(String, String | UInt64 | UInt16 | UInt8 | Int64)
      @fabrics.each_with_index do |fabric, index|
        data[index.to_s] = fabric.to_h
      end
      File.write(path, data.to_pretty_json)
    end

    def add_fabric(fabric : Matter::Fabric)
      @fabrics << fabric
    end

    def empty?
      @fabrics.empty?
    end

    def size
      @fabrics.size
    end
  end

  # Session storage for persisting CASE sessions across restarts
  # This allows controllers to reconnect without re-establishing CASE
  class SessionStorage
    property sessions : Hash(UInt16, Matter::Session::SecureContext)

    def initialize
      @sessions = {} of UInt16 => Matter::Session::SecureContext
    end

    def self.load(path : String) : SessionStorage
      storage = new
      if File.exists?(path)
        json = File.read(path)
        data = Hash(String, Hash(String, String | Int64 | Bool)).from_json(json)
        data.each do |session_id_str, session_data|
          # Convert to proper hash types for SecureContext.from_h
          session_hash = {} of String => (String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
          session_data.each do |key, value|
            session_hash[key] = value
          end
          session = Matter::Session::SecureContext.from_h(session_hash)
          # Only restore CASE sessions (skip PASE sessions which are ephemeral)
          if session.is_case
            storage.sessions[session.session_id] = session
            puts "   📡 Restored session #{session.session_id} (peer: #{session.peer_session_id})"
          end
        end
      end
      storage
    rescue ex
      puts "⚠️  Failed to load sessions: #{ex.message}"
      new
    end

    def save(path : String)
      # Only save CASE sessions (PASE sessions are ephemeral)
      data = {} of String => Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
      @sessions.each do |session_id, session|
        next unless session.is_case
        data[session_id.to_s] = session.to_h
      end
      File.write(path, data.to_pretty_json)
    end

    def add_session(session : Matter::Session::SecureContext)
      @sessions[session.session_id] = session
    end

    def get(session_id : UInt16) : Matter::Session::SecureContext?
      @sessions[session_id]?
    end

    def empty?
      @sessions.empty?
    end

    def size
      @sessions.size
    end

    def each(&)
      @sessions.each { |k, v| yield k, v }
    end
  end

  # Main device class
  class Device
    STATE_FILE   = "matter_switch_state.json"
    FABRIC_FILE  = "matter_switch_fabrics.json"
    SESSION_FILE = "matter_switch_sessions.json"

    property state : DeviceState
    property switch : Matter::Cluster::OnOffCluster
    property identify : Matter::Cluster::IdentifyCluster
    property groups : Matter::Cluster::GroupsCluster
    property basic_info : Matter::Cluster::BasicInformationCluster
    property general_commissioning : Matter::Cluster::GeneralCommissioningCluster
    property operational_credentials : Matter::Cluster::OperationalCredentialsCluster
    property access_control : Matter::Cluster::AccessControlCluster
    property administrator_commissioning : Matter::Cluster::AdministratorCommissioningCluster
    property general_diagnostics : Matter::Cluster::GeneralDiagnosticsCluster
    property network_commissioning : Matter::Cluster::NetworkCommissioningCluster
    property group_key_management : Matter::Cluster::GroupKeyManagementCluster
    property ota_requestor : Matter::Cluster::OtaRequestorCluster
    property diagnostic_logs : Matter::Cluster::DiagnosticLogsCluster
    property ethernet_diagnostics : Matter::Cluster::EthernetNetworkDiagnosticsCluster
    property scenes_management : Matter::Cluster::ScenesManagementCluster
    property responder : Matter::MDNS::Responder
    property fabric_storage : FabricStorage
    property session_storage : SessionStorage
    property fabric_table : Matter::FabricTable
    property hostname : String
    property ip_addresses : Array(Socket::IPAddress)
    property port : Int32
    property transport : Matter::Transport::UDPTransport
    property message_handler : Matter::Protocol::MessageHandler
    property on_commissioned : Proc(Matter::Fabric, Nil)?

    def initialize(@hostname = "matter-switch.local", @port = 5540)
      @on_commissioned = nil
      @state = DeviceState.load(STATE_FILE)
      @ip_addresses = get_local_ips
      @fabric_storage = FabricStorage.load(FABRIC_FILE)
      @session_storage = SessionStorage.load(SESSION_FILE)

      # Create Basic Information cluster on endpoint 0 (required for root node)
      # NOTE: nodeLabel and productLabel are what iOS Home app reads for device name
      root_endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      @basic_info = Matter::Cluster::BasicInformationCluster.new(
        root_endpoint,
        data_model_revision: 1_u16,
        vendor_name: "Spider-Gazelle",
        vendor_id: @state.vendor_id,
        product_name: @state.device_name, # Product name
        product_id: @state.product_id,
        node_label: @state.device_name,    # User-facing device name (writable)
        product_label: @state.device_name, # Product label (fixed)
        hardware_version: 1_u16,
        hardware_version_string: "1.0",
        software_version: 1_u32,
        software_version_string: "1.0.0",
        serial_number: @state.serial_number,
        unique_id: @state.unique_id,
        product_appearance: Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
          Matter::Cluster::BasicInformationCluster::ProductFinish::Satin
        )
      )

      # Create General Commissioning cluster on endpoint 0 (required for commissioning)
      @general_commissioning = Matter::Cluster::GeneralCommissioningCluster.new(root_endpoint)

      # Create UDP transport
      @transport = Matter::Transport::UDPTransport.new(port: @port)

      # Create fabric table with in-memory storage
      storage = Matter::Storage::MemoryBackend.new
      @fabric_table = Matter::FabricTable.new(storage)

      # Create Access Control cluster on endpoint 0 (required for ACL management)
      @access_control = Matter::Cluster::AccessControlCluster.new(root_endpoint)

      # Create Administrator Commissioning cluster on endpoint 0 (required for Root Node)
      # Handles commissioning window management (open/close/revoke)
      @administrator_commissioning = Matter::Cluster::AdministratorCommissioningCluster.new(root_endpoint)

      # Create General Diagnostics cluster on endpoint 0 (required for Root Node)
      # Provides device health and network interface information
      @general_diagnostics = Matter::Cluster::GeneralDiagnosticsCluster.new(root_endpoint)

      # Create Network Commissioning cluster on endpoint 0 (required for Root Node)
      # For Ethernet devices, advertise Ethernet interface feature
      @network_commissioning = Matter::Cluster::NetworkCommissioningCluster.new(
        root_endpoint,
        network_type: Matter::Cluster::NetworkCommissioningCluster::NetworkType::Ethernet,
        feature_map: Matter::Cluster::NetworkCommissioningCluster::Feature::EthernetNetworkInterface
      )

      # Create Group Key Management cluster on endpoint 0 (MANDATORY for Root Node)
      # Manages group keys for secure group communication
      @group_key_management = Matter::Cluster::GroupKeyManagementCluster.new(root_endpoint)

      # Create OTA Requestor cluster on endpoint 0 (required for Apple Home compatibility)
      # This is a minimal implementation that returns sensible defaults
      # indicating no OTA update is in progress
      @ota_requestor = Matter::Cluster::OtaRequestorCluster.new(root_endpoint)

      # Diagnostic Logs cluster - required by Apple Home for accessory compatibility
      @diagnostic_logs = Matter::Cluster::DiagnosticLogsCluster.new(root_endpoint)

      # Ethernet Network Diagnostics cluster - required by Apple Home for Ethernet devices
      @ethernet_diagnostics = Matter::Cluster::EthernetNetworkDiagnosticsCluster.new(root_endpoint)

      # Create Operational Credentials cluster on endpoint 0 (required for commissioning)
      # Pass the general_commissioning reference so AddNOC can update the failsafe context
      @operational_credentials = Matter::Cluster::OperationalCredentialsCluster.new(
        @fabric_table,
        root_endpoint,
        access_control_cluster: @access_control,
        general_commissioning_cluster: @general_commissioning
      )

      # Set up test attestation credentials (DAC, PAI, and attestation key)
      setup_attestation_credentials

      # Create clusters for endpoint 1 (the actual device)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      # OnOff cluster - the main functionality
      # Per Matter spec, On/Off Light device type REQUIRES the Lighting (LT) feature
      # This adds attributes like GlobalSceneControl, OnTime, OffWaitTime, StartUpOnOff
      @switch = Matter::Cluster::OnOffCluster.new(
        endpoint,
        on_off: @state.on_off,
        feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting
      )

      # Setup state change callback
      @switch.on_state_changed do |new_state|
        handle_state_change(new_state)
      end

      # Identify cluster - MANDATORY for On/Off Light device type
      # Use VisibleLight identify type since this is a light device
      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )

      # Groups cluster - MANDATORY for On/Off Light device type
      @groups = Matter::Cluster::GroupsCluster.new(endpoint)

      # ScenesManagement cluster - MANDATORY for On/Off Light device type
      @scenes_management = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      # Create protocol message handler (this handles PASE, IM, etc.)
      @message_handler = Matter::Protocol::MessageHandler.new(
        transport: @transport,
        setup_pin: @state.setup_pin,
        discriminator: @state.discriminator,
        fabric_table: @fabric_table,
        vendor_id: @state.vendor_id,
        product_id: @state.product_id
      )

      # Wire up clusters to message handler
      # Endpoint 0 clusters
      @message_handler.clusters[{0_u16, Matter::Cluster::BasicInformationCluster::CLUSTER_ID}] = @basic_info
      @message_handler.clusters[{0_u16, Matter::Cluster::AccessControlCluster::CLUSTER_ID}] = @access_control
      @message_handler.clusters[{0_u16, Matter::Cluster::GeneralCommissioningCluster::CLUSTER_ID}] = @general_commissioning
      @message_handler.clusters[{0_u16, Matter::Cluster::OperationalCredentialsCluster::CLUSTER_ID}] = @operational_credentials
      @message_handler.clusters[{0_u16, Matter::Cluster::AdministratorCommissioningCluster::CLUSTER_ID}] = @administrator_commissioning
      @message_handler.clusters[{0_u16, Matter::Cluster::GeneralDiagnosticsCluster::CLUSTER_ID}] = @general_diagnostics
      @message_handler.clusters[{0_u16, Matter::Cluster::NetworkCommissioningCluster::CLUSTER_ID}] = @network_commissioning
      @message_handler.clusters[{0_u16, Matter::Cluster::GroupKeyManagementCluster::CLUSTER_ID}] = @group_key_management
      @message_handler.clusters[{0_u16, Matter::Cluster::OtaRequestorCluster::CLUSTER_ID}] = @ota_requestor
      @message_handler.clusters[{0_u16, Matter::Cluster::DiagnosticLogsCluster::CLUSTER_ID}] = @diagnostic_logs
      @message_handler.clusters[{0_u16, Matter::Cluster::EthernetNetworkDiagnosticsCluster::CLUSTER_ID}] = @ethernet_diagnostics
      # Endpoint 1 clusters (On/Off Light device)
      @message_handler.clusters[{1_u16, Matter::Cluster::OnOffCluster::CLUSTER_ID}] = @switch
      @message_handler.clusters[{1_u16, Matter::Cluster::IdentifyCluster::CLUSTER_ID}] = @identify
      @message_handler.clusters[{1_u16, Matter::Cluster::GroupsCluster::CLUSTER_ID}] = @groups
      @message_handler.clusters[{1_u16, Matter::Cluster::ScenesManagementCluster::CLUSTER_ID}] = @scenes_management

      # CRITICAL: Set up session_lookup callback on OperationalCredentials cluster
      # This allows the cluster to get the attestation challenge from PASE sessions
      # Without this, attestation signatures will fail because attestation_challenge is nil
      sessions = @message_handler.sessions
      @operational_credentials.session_lookup = ->(session_id : UInt64) : Bytes? do
        session = sessions[session_id.to_u16]?
        if session
          puts "session_lookup: Found session #{session_id}, returning attestation_challenge"
          session.attestation_challenge
        else
          puts "session_lookup: Session #{session_id} not found in #{sessions.keys.inspect}"
          nil
        end
      end

      # Restore persisted sessions to the message handler
      # This allows controllers to reconnect after device restart without CASE re-establishment
      if !@session_storage.empty?
        puts "📡 Restoring #{@session_storage.size} CASE session(s)..."
        @session_storage.each do |session_id, session|
          @message_handler.sessions[session_id] = session
        end
      end

      # Set up callback to save sessions when new CASE sessions are established
      session_storage = @session_storage
      @message_handler.on_session_established = ->(session : Matter::Session::SecureContext) do
        if session.is_case
          puts "💾 Saving new CASE session #{session.session_id}"
          session_storage.add_session(session)
          session_storage.save(SESSION_FILE)
        end
      end

      # Set up on_fabric_added callback to switch to operational mode after commissioning
      puts "DEBUG: Setting up on_fabric_added callback on @operational_credentials"
      @operational_credentials.on_fabric_added = ->(fabric : Matter::Fabric) do
        puts "✅ Fabric added! Switching to operational mode..."
        puts "   Fabric ID: #{fabric.fabric_id}"
        puts "   Node ID: #{fabric.node_id}"
        puts "   Compressed Fabric ID: #{fabric.compressed_fabric_id.hexstring.upcase}"
        # Trigger operational mDNS advertisement
        if commissioned_callback = @on_commissioned
          commissioned_callback.call(fabric)
        end
      end
      puts "DEBUG: on_fabric_added callback set: #{@operational_credentials.on_fabric_added.nil? ? "nil" : "set"}"

      # Configure Descriptor cluster for endpoint 0 (Root Node)
      # This tells controllers about the device structure
      if descriptor_0 = @message_handler.clusters[{0_u16, Matter::Cluster::DescriptorCluster::CLUSTER_ID}]?.as?(Matter::Cluster::DescriptorCluster)
        # Root Node device type
        descriptor_0.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
          device_type: Matter::DeviceTypes::ROOT_NODE.to_u32,
          revision: 1_u16
        )
        # Add endpoint 1 to parts list (child endpoints)
        descriptor_0.add_part(1_u16)
        # Add server clusters for endpoint 0 (Root Node required clusters)
        # NOTE: Descriptor cluster already adds itself to server_list in initialize()
        descriptor_0.server_list << Matter::Cluster::BasicInformationCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::AccessControlCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::GeneralCommissioningCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::OperationalCredentialsCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::AdministratorCommissioningCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::GeneralDiagnosticsCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::NetworkCommissioningCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::GroupKeyManagementCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::OtaRequestorCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::DiagnosticLogsCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::EthernetNetworkDiagnosticsCluster::CLUSTER_ID
      end

      # Create Descriptor cluster for endpoint 1 (On/Off Light)
      # HomeKit requires this to identify the device type
      descriptor_1 = Matter::Cluster::DescriptorCluster.new(endpoint)
      # On/Off Light device type
      descriptor_1.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: Matter::DeviceTypes::ON_OFF_LIGHT.to_u32,
        revision: 1_u16 # On/Off Light device type revision 1
      )
      # Add all mandatory server clusters for On/Off Light device type
      # NOTE: Descriptor cluster already adds itself to server_list in initialize()
      descriptor_1.server_list << Matter::Cluster::IdentifyCluster::CLUSTER_ID         # 0x0003 - Mandatory
      descriptor_1.server_list << Matter::Cluster::GroupsCluster::CLUSTER_ID           # 0x0004 - Mandatory
      descriptor_1.server_list << Matter::Cluster::OnOffCluster::CLUSTER_ID            # 0x0006 - Mandatory
      descriptor_1.server_list << Matter::Cluster::ScenesManagementCluster::CLUSTER_ID # 0x0062 - Mandatory
      @message_handler.clusters[{1_u16, Matter::Cluster::DescriptorCluster::CLUSTER_ID}] = descriptor_1

      # Log final cluster count for debugging
      puts "📊 Final cluster configuration:"
      puts "   Endpoint 0: #{@message_handler.clusters.count { |k, _| k[0] == 0_u16 }} clusters"
      puts "   Endpoint 1: #{@message_handler.clusters.count { |k, _| k[0] == 1_u16 }} clusters"
      puts "   Total: #{@message_handler.clusters.size} clusters"

      # Configure session lookup callback for attestation signature generation
      # This allows the OperationalCredentials cluster to access the session's attestation_challenge
      @operational_credentials.session_lookup = ->(session_id : UInt64) {
        puts "DEBUG: session_lookup called with session_id=#{session_id}"
        puts "DEBUG: Available sessions: #{@message_handler.sessions.keys.inspect}"
        if session = @message_handler.sessions[session_id.to_u16]?
          challenge = session.attestation_challenge
          puts "DEBUG: Found session, attestation_challenge=#{challenge ? challenge.hexstring : "nil"}"
          challenge
        else
          puts "DEBUG: Session not found!"
          nil
        end
      }

      # Configure fabric access callback for CASE session establishment
      # This allows the message handler to access the fabric data for CASE responder
      @message_handler.on_get_fabric = -> : Matter::Fabric? {
        @fabric_storage.fabrics.first?
      }

      # Configure fabric added callback for operational advertisement
      # When a fabric is successfully added during commissioning, we need to:
      # 1. Save the fabric to persistent storage
      # 2. Advertise the operational service for the new fabric
      # 3. Mark the device as commissioned
      # NOTE: The failsafe context is automatically updated by the library when
      #       general_commissioning_cluster is passed to OperationalCredentialsCluster
      @operational_credentials.on_fabric_added = ->(fabric : Matter::Fabric) {
        handle_fabric_added(fabric)
      }

      # Configure failsafe armed callback to reset OperationalCredentials state
      # When a new failsafe is armed (new commissioning session), we need to reset
      # OperationalCredentials failsafe context to avoid "Cannot generate CSR after AddNOC"
      @general_commissioning.on_failsafe_armed = -> {
        @operational_credentials.on_failsafe_armed
      }

      # Create mDNS responder
      @responder = Matter::MDNS::Responder.new(
        hostname: @hostname,
        ip_addresses: @ip_addresses
      )
    end

    # Generate test attestation credentials (DAC, PAI, attestation key)
    # In production, these would be pre-installed during manufacturing
    def setup_attestation_credentials
      # Use the AttestationCertificateManager helper to generate proper certificates
      @operational_credentials.set_attestation_from_manager(
        vendor_id: @state.vendor_id,
        product_id: @state.product_id
      )
    end

    def get_local_ips : Array(Socket::IPAddress)
      ips = [] of Socket::IPAddress

      # Get IPv6 address
      begin
        socket = UDPSocket.new(:inet6)
        socket.connect("2606:4700:4700::1111", 53)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
        # IPv6 not available
      end

      # Get IPv4 address
      begin
        socket = UDPSocket.new(:inet)
        socket.connect("8.8.8.8", 80)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
        # IPv4 not available
      end

      # Fallback to localhost if nothing worked
      ips << Socket::IPAddress.new("127.0.0.1", 0) if ips.empty?
      ips
    end

    def handle_state_change(new_state : Bool)
      @state.on_off = new_state
      @state.data_version += 1
      @state.save(STATE_FILE)

      puts "\n  💡 Switch is now: #{new_state ? "🟢 ON" : "⚫ OFF"}"
      puts "  📊 Data version: #{@state.data_version}"
      print "> "
    end

    def start
      print_header
      load_state

      if @state.commissioned
        start_operational_mode
      else
        start_commissioning_mode
      end

      # Start mDNS responder
      @responder.start

      # Start UDP transport (handles incoming Matter messages)
      puts "🔌 Starting UDP transport..."
      @transport.start
      puts "   ✅ Listening on all interfaces, port #{@port}"
      puts ""

      # Interactive loop (unless --no-interactive flag)
      interactive = !ARGV.includes?("--no-interactive")
      if interactive
        run_interactive_loop
      else
        puts "⏸️  Running in non-interactive mode (--no-interactive)"
        puts "   Press Ctrl+C to stop"
        puts ""
        # Just sleep forever
        loop do
          sleep 1.second
        end
      end
    end

    def print_header
      puts "\n" + "=" * 70
      puts "  Matter Switch Device"
      puts "  Device Type: On/Off Light"
      puts "=" * 70
      puts ""
    end

    def load_state
      puts "📁 Loading device state..."
      puts "   Name: #{@state.device_name}"
      puts "   Switch: #{@state.on_off ? "🟢 ON" : "⚫ OFF"}"
      puts "   Data Version: #{@state.data_version}"
      puts "   Commissioned: #{@state.commissioned ? "✅ Yes" : "❌ No"}"
      puts "   Fabrics: #{@fabric_storage.size}"
      puts "   Discriminator: #{@state.discriminator}"
      puts "   Setup PIN: #{@state.setup_pin}"
      puts "   Serial Number: #{@state.serial_number}"
      puts "   Unique ID: #{@state.unique_id}"

      # Sync fabrics from FabricStorage to FabricTable for CASE destination_id matching
      # Also restore root certificates to OperationalCredentials cluster
      @fabric_storage.fabrics.each do |fabric|
        @fabric_table.add_fabric(fabric) unless @fabric_table.find_by_fabric_id(fabric.fabric_id)
        # Restore root cert to OperationalCredentials if present
        if root_cert = fabric.root_cert
          @operational_credentials.restore_root_cert(root_cert)
        end
      end
      puts ""
      @ip_addresses.each do |ip|
        puts "   IP: #{ip.address} (#{ip.family == Socket::Family::INET ? "IPv4" : "IPv6"})"
      end
      puts ""
    end

    def start_commissioning_mode
      puts "🔓 Starting in Commissioning Mode"
      puts "   The device is ready to be paired with a Matter controller"
      puts ""

      # Advertise commissioning service
      # Device type in mDNS MUST match the primary device type in descriptor
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: @state.device_name,
        vendor_id: @state.vendor_id,
        product_id: @state.product_id,
        discriminator: @state.discriminator,
        device_type: Matter::DeviceTypes::ON_OFF_LIGHT,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      @responder.advertise_commissioning(info, port: @port)

      puts "📡 mDNS Advertisement Active:"
      puts "   Service: _matterc._udp.local"
      puts "   Instance: #{@state.device_name}._matterc._udp.local"
      puts "   Hostname: #{@hostname}"
      puts "   Port: #{@port}"
      puts "   Discriminator: #{@state.discriminator}"
      puts ""

      # Display QR code
      print_qr_code

      manual_code = generate_setup_code
      puts "💡 To pair this device:"
      puts "   1. Open your Matter controller app (iPhone Home app, chip-tool, etc.)"
      puts "   2. Select 'Add Device' or 'Commission Device'"
      puts "   3. Scan the QR code above, or use:"
      puts ""
      puts "      Manual Code: #{manual_code}"
      puts ""
      puts "   With chip-tool:"
      puts "      chip-tool pairing code 1 #{manual_code}"
      puts ""
    end

    def start_operational_mode
      puts "🔒 Starting in Operational Mode"
      puts "   The device is already commissioned and ready for use"
      puts ""

      # Advertise operational service for each fabric
      @fabric_storage.fabrics.each do |fabric|
        info = Matter::MDNS::OperationalInfo.new(
          compressed_fabric_id: fabric.compressed_fabric_id,
          node_id: fabric.node_id,
          # Don't set session intervals - this is an always-on device, not ICD
          tcp_supported: false
        )

        @responder.advertise_operational(info, port: @port)

        puts "📡 Operational Advertisement (Fabric #{fabric.fabric_index}):"
        puts "   Service: _matter._tcp.local"
        puts "   Fabric ID: 0x#{fabric.fabric_id.to_s(16).upcase}"
        puts "   Node ID: 0x#{fabric.node_id.to_s(16).upcase}"
        puts ""
      end

      puts "✅ Device is ready to receive commands from your controller!"
      puts ""
    end

    # Handle fabric added during commissioning
    # This is called by the OperationalCredentials cluster when AddNOC succeeds
    def handle_fabric_added(fabric : Matter::Fabric)
      puts ""
      puts "🎉 Fabric Successfully Added!"
      puts "   Fabric ID: 0x#{fabric.fabric_id.to_s(16).upcase}"
      puts "   Node ID: 0x#{fabric.node_id.to_s(16).upcase}"
      puts "   Fabric Index: #{fabric.fabric_index}"
      puts ""

      # 1. Save fabric to storage (both FabricStorage for persistence and FabricTable for CASE matching)
      @fabric_storage.add_fabric(fabric)
      @fabric_storage.save(FABRIC_FILE)
      @fabric_table.add_fabric(fabric) # Add to fabric_table so CASE destination_id matching works
      puts "💾 Fabric saved to #{FABRIC_FILE}"

      # 2. Mark device as commissioned
      @state.commissioned = true
      @state.save(STATE_FILE)
      puts "💾 Device state saved to #{STATE_FILE}"

      # 3. Advertise operational service for the new fabric
      info = Matter::MDNS::OperationalInfo.new(
        compressed_fabric_id: fabric.compressed_fabric_id,
        node_id: fabric.node_id,
        # Don't set session intervals - this is an always-on device, not ICD
        tcp_supported: false
      )

      @responder.advertise_operational(info, port: @port)

      puts "📡 Operational Advertisement Started:"
      puts "   Service: _matter._tcp.local"
      puts "   Compressed Fabric ID: #{fabric.compressed_fabric_id.hexstring.upcase}"
      puts "   Node ID: 0x#{fabric.node_id.to_s(16).upcase.rjust(16, '0')}"
      puts ""
      puts "✅ Commissioning Complete! Device is now operational."
      puts ""
    end

    def generate_setup_code : String
      Matter::SetupPayload.generate_manual_code(@state.discriminator, @state.setup_pin)
    end

    def generate_qr_code : String
      Matter::SetupPayload::QRCode.generate_qr_code(
        discriminator: @state.discriminator,
        pin: @state.setup_pin,
        vendor_id: @state.vendor_id,
        product_id: @state.product_id,
        flow: Matter::SetupPayload::QRCode::CommissionFlow::Standard,
        capabilities: Matter::SetupPayload::QRCode::DiscoveryCapability::BLE
      )
    end

    def print_qr_code
      qr_payload = generate_qr_code
      begin
        qr = Goban::QR.encode_string(qr_payload, Goban::ECC::Level::Low)
        puts ""
        puts "📱 Scan this QR code with your Matter controller app:"
        puts ""
        qr.print_to_console
        puts ""
      rescue ex
        puts "⚠️  Failed to generate QR code: #{ex.message}"
      end
    end

    def run_interactive_loop
      puts "⌨️  Interactive Commands:"
      puts "   toggle  - Toggle the switch on/off"
      puts "   on      - Turn the switch on"
      puts "   off     - Turn the switch off"
      puts "   status  - Show current status"
      puts "   reset   - Reset to factory defaults"
      puts "   quit    - Exit the application"
      puts ""

      loop do
        print "> "
        input = gets
        break unless input

        handle_command(input.strip.downcase)
      end

      shutdown
    end

    def handle_command(command : String)
      case command
      when "toggle"
        @switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      when "on"
        @switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
      when "off"
        @switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
      when "status"
        show_status
      when "reset"
        factory_reset
      when "quit", "exit", "q"
        puts "👋 Shutting down..."
        shutdown
        exit(0)
      when "help", "?"
        show_help
      when ""
        # Ignore empty input
      else
        puts "❌ Unknown command: #{command}"
        puts "   Type 'help' for available commands"
      end
    end

    def show_status
      puts ""
      puts "📊 Device Status:"
      puts "   Name: #{@state.device_name}"
      puts "   Switch State: #{@state.on_off ? "🟢 ON" : "⚫ OFF"}"
      puts "   Data Version: #{@state.data_version}"
      puts "   Commissioned: #{@state.commissioned ? "✅ Yes" : "❌ No"}"
      puts "   Fabrics: #{@fabric_storage.size}"
      puts "   Sessions: #{@message_handler.sessions.size}"

      unless @fabric_storage.fabrics.empty?
        puts ""
        puts "   Connected Fabrics:"
        @fabric_storage.fabrics.each do |fabric|
          puts "     • Fabric #{fabric.fabric_index}: #{fabric.label}"
          puts "       ID: 0x#{fabric.fabric_id.to_s(16).upcase}"
          puts "       Node: 0x#{fabric.node_id.to_s(16).upcase}"
        end
      end
      puts ""
    end

    def show_help
      puts ""
      puts "Available Commands:"
      puts "   toggle  - Toggle the switch between on and off"
      puts "   on      - Turn the switch on"
      puts "   off     - Turn the switch off"
      puts "   status  - Show detailed device status"
      puts "   reset   - Reset device to factory defaults"
      puts "   quit    - Shut down the device and exit"
      puts ""
    end

    def factory_reset
      print "⚠️  Are you sure you want to reset to factory defaults? (yes/no): "
      confirmation = gets

      if confirmation && confirmation.strip.downcase == "yes"
        puts "🔄 Performing factory reset..."

        # Delete state files
        File.delete(STATE_FILE) if File.exists?(STATE_FILE)
        File.delete(FABRIC_FILE) if File.exists?(FABRIC_FILE)
        File.delete(SESSION_FILE) if File.exists?(SESSION_FILE)

        puts "✅ Factory reset complete"
        puts "🔄 Please restart the application"

        shutdown
        exit(0)
      else
        puts "❌ Factory reset cancelled"
      end
    end

    def shutdown
      puts ""
      puts "📁 Saving state..."
      @state.save(STATE_FILE)
      @fabric_storage.save(FABRIC_FILE)

      # Save all current CASE sessions for reconnection after restart
      @message_handler.sessions.each do |session_id, session|
        if session.is_case
          @session_storage.add_session(session)
        end
      end
      @session_storage.save(SESSION_FILE)
      puts "   💾 Saved #{@session_storage.size} session(s)"

      puts "🛑 Stopping transport..."
      @transport.close

      puts "🛑 Stopping mDNS responder..."
      @responder.stop

      puts "✅ Shutdown complete"
    end
  end
end

# Main entry point
puts "Starting Matter Switch Device..."
puts ""

# Enable logging for Matter protocol messages
Log.setup(:debug)

device = MatterSwitch::Device.new

# Trap Ctrl+C for clean shutdown
Process.on_terminate do
  puts "\n\n🛑 Received interrupt signal"
  device.shutdown
  exit(0)
end

device.start
