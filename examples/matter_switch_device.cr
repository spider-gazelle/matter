require "json"
require "file_utils"
require "goban"
require "../src/matter/mdns/responder"
require "../src/matter/mdns/service_type"
require "../src/matter/mdns/service_description"
require "../src/matter/constants/device_types"
require "../src/matter/fabric"
require "../src/matter/setup_payload"
require "../src/matter"
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

    def initialize(
      @device_name = "Matter Switch",
      @on_off = false,
      @data_version = 0_u32,
      @commissioned = false,
      @discriminator = DeviceState.generate_random_discriminator,
      @vendor_id = 0xFFF1_u16,
      @product_id = 0x8004_u16,
      @setup_pin = DeviceState.generate_random_pin,
    )
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
    property basic_info : Matter::Cluster::BasicInformationCluster
    property responder : Matter::MDNS::Responder
    property fabric_storage : FabricStorage
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
      root_endpoint = Matter::DataType::EndpointNumber.new(0_u16)
      @basic_info = Matter::Cluster::BasicInformationCluster.new(
        root_endpoint,
        data_model_revision: 1_u16,
        vendor_name: "Spider-Gazelle",
        vendor_id: @state.vendor_id,
        product_name: "Matter Switch 2",
        product_id: @state.product_id,
        node_label: @state.device_name, # This is the device name shown in iOS
        hardware_version: 1_u16,
        hardware_version_string: "1.1",
        software_version: 1_u32,
        software_version_string: "1.0.1"
      )

      # Create the switch cluster on endpoint 1
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      @switch = Matter::Cluster::OnOffCluster.new(endpoint, on_off: @state.on_off)

      # Setup state change callback
      @switch.on_state_changed do |new_state|
        handle_state_change(new_state)
      end

      # Create UDP transport
      @transport = Matter::Transport::UDPTransport.new(port: @port)

      # Create protocol message handler (this handles PASE, IM, etc.)
      @message_handler = Matter::Protocol::MessageHandler.new(
        transport: @transport,
        setup_pin: @state.setup_pin,
        discriminator: @state.discriminator
      )

      # Wire up clusters to message handler
      @message_handler.clusters[{0_u16, 0x0028_u32}] = @basic_info # BasicInformation on endpoint 0
      @message_handler.clusters[{1_u16, 0x0006_u32}] = @switch     # OnOff on endpoint 1

      # Create mDNS responder
      @responder = Matter::MDNS::Responder.new(
        hostname: @hostname,
        ip_addresses: @ip_addresses
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

      # Interactive loop
      run_interactive_loop
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
          fabric_id: fabric.fabric_id,
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
Log.setup(:info)

device = MatterSwitch::Device.new

# Trap Ctrl+C for clean shutdown
Process.on_terminate do
  puts "\n\n🛑 Received interrupt signal"
  device.shutdown
  exit(0)
end

device.start
