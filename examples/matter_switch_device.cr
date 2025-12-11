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

# Matter Switch Device Example
#
# This is a complete Matter device implementation that:
# - Presents as an On/Off Light Switch
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

  # Main device class
  class Device
    STATE_FILE  = "matter_switch_state.json"
    FABRIC_FILE = "matter_switch_fabrics.json"

    property state : DeviceState
    property switch : Matter::Cluster::OnOffCluster
    property identify : Matter::Cluster::IdentifyCluster
    property groups : Matter::Cluster::GroupsCluster
    property scenes : Matter::Cluster::ScenesCluster
    property basic_info : Matter::Cluster::BasicInformationCluster
    property general_commissioning : Matter::Cluster::GeneralCommissioningCluster
    property operational_credentials : Matter::Cluster::OperationalCredentialsCluster
    property access_control : Matter::Cluster::AccessControlCluster
    property responder : Matter::MDNS::Responder
    property fabric_storage : FabricStorage
    property fabric_table : Matter::FabricTable
    property hostname : String
    property ip_addresses : Array(Socket::IPAddress)
    property port : Int32
    property transport : Matter::Transport::UDPTransport
    property message_handler : Matter::Protocol::MessageHandler

    def initialize(@hostname = "matter-switch.local", @port = 5540)
      @state = DeviceState.load(STATE_FILE)
      @ip_addresses = get_local_ips
      @fabric_storage = FabricStorage.load(FABRIC_FILE)

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
        unique_id: @state.unique_id
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
      # LIGHTING feature is MANDATORY for On/Off Light device type per Matter spec
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
      @identify = Matter::Cluster::IdentifyCluster.new(endpoint)

      # Groups cluster - MANDATORY for On/Off Light device type
      @groups = Matter::Cluster::GroupsCluster.new(endpoint)

      # Scenes cluster - MANDATORY for On/Off Light device type
      @scenes = Matter::Cluster::ScenesCluster.new(endpoint)

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
      # Endpoint 1 clusters (On/Off Light device)
      @message_handler.clusters[{1_u16, Matter::Cluster::OnOffCluster::CLUSTER_ID}] = @switch
      @message_handler.clusters[{1_u16, Matter::Cluster::IdentifyCluster::CLUSTER_ID}] = @identify
      @message_handler.clusters[{1_u16, Matter::Cluster::GroupsCluster::CLUSTER_ID}] = @groups
      @message_handler.clusters[{1_u16, Matter::Cluster::ScenesCluster::CLUSTER_ID}] = @scenes

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
        # Add server clusters for endpoint 0
        descriptor_0.server_list << Matter::Cluster::BasicInformationCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::AccessControlCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::GeneralCommissioningCluster::CLUSTER_ID
        descriptor_0.server_list << Matter::Cluster::OperationalCredentialsCluster::CLUSTER_ID
      end

      # Create Descriptor cluster for endpoint 1 (On/Off Light)
      # HomeKit requires this to identify the device type
      descriptor_1 = Matter::Cluster::DescriptorCluster.new(endpoint)
      # On/Off Light device type
      descriptor_1.device_type_list << Matter::Cluster::DescriptorCluster::DeviceTypeStruct.new(
        device_type: Matter::DeviceTypes::ON_OFF_LIGHT.to_u32,
        revision: 2_u16
      )
      # Add all mandatory server clusters for On/Off Light device type
      descriptor_1.server_list << Matter::Cluster::IdentifyCluster::CLUSTER_ID # 0x0003 - Mandatory
      descriptor_1.server_list << Matter::Cluster::GroupsCluster::CLUSTER_ID   # 0x0004 - Mandatory
      descriptor_1.server_list << Matter::Cluster::ScenesCluster::CLUSTER_ID   # 0x0005 - Mandatory
      descriptor_1.server_list << Matter::Cluster::OnOffCluster::CLUSTER_ID    # 0x0006 - Mandatory
      @message_handler.clusters[{1_u16, Matter::Cluster::DescriptorCluster::CLUSTER_ID}] = descriptor_1

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
      puts "  Device Type: On/Off Light Switch"
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
      @fabric_storage.fabrics.each do |fabric|
        @fabric_table.add_fabric(fabric) unless @fabric_table.find_by_fabric_id(fabric.fabric_id)
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
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: @state.device_name,
        vendor_id: @state.vendor_id,
        product_id: @state.product_id,
        discriminator: @state.discriminator,
        device_type: Matter::DeviceTypes::ON_OFF_LIGHT_SWITCH,
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
          session_idle_interval: 500_u32,
          session_active_interval: 300_u32,
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
        session_idle_interval: 500_u32,
        session_active_interval: 300_u32,
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
