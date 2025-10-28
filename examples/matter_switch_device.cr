require "json"
require "file_utils"
require "../src/matter/mdns/responder"
require "../src/matter/mdns/service_type"
require "../src/matter/mdns/service_description"
require "../src/matter/constants/device_types"
require "../src/matter/fabric"
require "../src/matter" # This includes all the required modules including TLV

# Matter Switch Device Example
#
# This is a complete Matter device implementation that:
# - Presents as an On/Off Light Switch
# - Persists state to JSON files
# - Supports commissioning and operational modes
# - Can reconnect after restart without recommissioning
# - Uses terminal UI for interaction

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

    def initialize(
      @device_name = "Matter Switch",
      @on_off = false,
      @data_version = 0_u32,
      @commissioned = false,
      @discriminator = 3840_u16,
      @vendor_id = 0xFFF1_u16,
      @product_id = 0x8001_u16,
    )
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
    property responder : Matter::MDNS::Responder
    property fabric_storage : FabricStorage
    property hostname : String
    property ip_address : Socket::IPAddress
    property port : Int32

    def initialize(@hostname = "matter-switch.local", @port = 5540)
      @state = DeviceState.load(STATE_FILE)
      @ip_address = get_local_ip

      # Create the switch cluster
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      @switch = Matter::Cluster::OnOffCluster.new(endpoint, on_off: @state.on_off)

      # Setup state change callback
      @switch.on_state_changed do |new_state|
        handle_state_change(new_state)
      end

      # Create fabric storage
      @fabric_storage = FabricStorage.load(FABRIC_FILE)

      # Create mDNS responder
      @responder = Matter::MDNS::Responder.new(
        hostname: @hostname,
        ip_addresses: [@ip_address]
      )
    end

    def get_local_ip : Socket::IPAddress
      # Try to get actual local IP, fallback to localhost
      begin
        # Create a UDP socket to determine local IP
        socket = UDPSocket.new
        socket.connect("8.8.8.8", 80)
        addr = socket.local_address
        socket.close
        Socket::IPAddress.new(addr.address, 0)
      rescue
        Socket::IPAddress.new("127.0.0.1", 0)
      end
    end

    def handle_state_change(new_state : Bool)
      @state.on_off = new_state
      @state.data_version += 1
      @state.save(STATE_FILE)

      puts "  💡 Switch is now: #{new_state ? "ON" : "OFF"}"
      puts "  📊 Data version: #{@state.data_version}"
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
      puts "   Switch: #{@state.on_off ? "ON" : "OFF"}"
      puts "   Data Version: #{@state.data_version}"
      puts "   Commissioned: #{@state.commissioned ? "Yes" : "No"}"
      puts "   Fabrics: #{@fabric_storage.size}"
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
      puts "   IP: #{@ip_address.address}"
      puts "   Port: #{@port}"
      puts "   Discriminator: #{@state.discriminator}"
      puts ""
      puts "💡 To pair this device:"
      puts "   1. Open your Matter controller app"
      puts "   2. Select 'Add Device' or 'Commission Device'"
      puts "   3. Use setup code: #{generate_setup_code}"
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
    end

    def generate_setup_code : String
      # Generate a simple setup code for demo purposes
      # In a real device, this would be QR code compatible
      "#{@state.vendor_id.to_s.rjust(4, '0')}-#{@state.product_id.to_s.rjust(4, '0')}-#{@state.discriminator.to_s.rjust(4, '0')}"
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

        # Reset state
        @state = DeviceState.new
        @fabric_storage = FabricStorage.new

        # Reset switch state
        endpoint = Matter::DataType::EndpointNumber.new(1_u16)
        @switch = Matter::Cluster::OnOffCluster.new(endpoint, on_off: false)
        @switch.on_state_changed do |new_state|
          handle_state_change(new_state)
        end

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

      puts "🛑 Stopping mDNS responder..."
      @responder.stop

      puts "✅ Shutdown complete"
    end

    # Mock commissioning method (for testing without full protocol)
    def mock_commission(fabric_id : UInt64, node_id : UInt64, label : String = "Test Fabric")
      puts ""
      puts "🔐 Mock Commissioning (for testing)..."

      # Create a mock fabric
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)
      root_pub_key = key.public_key

      fabric = Matter::Fabric.new(
        fabric_id: fabric_id,
        fabric_index: 1_u8,
        node_id: node_id,
        root_public_key: root_pub_key,
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        vendor_id: @state.vendor_id,
        label: label
      )

      @fabric_storage.add_fabric(fabric)
      @state.commissioned = true
      @state.save(STATE_FILE)
      @fabric_storage.save(FABRIC_FILE)

      puts "✅ Device commissioned successfully!"
      puts "   Fabric: #{label}"
      puts "   Fabric ID: 0x#{fabric_id.to_s(16).upcase}"
      puts "   Node ID: 0x#{node_id.to_s(16).upcase}"
      puts ""
      puts "🔄 Restart the device to enter operational mode"
    end
  end
end

# Main entry point
puts "Starting Matter Switch Device..."
puts ""

device = MatterSwitch::Device.new

# Trap Ctrl+C for clean shutdown
Signal::INT.trap do
  puts "\n\n🛑 Received interrupt signal"
  device.shutdown
  exit(0)
end

# For demo purposes, allow mock commissioning via environment variable
if ENV["MOCK_COMMISSION"]? == "true"
  device.mock_commission(
    fabric_id: 0x1234567890ABCDEF_u64,
    node_id: 0x0000000000000001_u64,
    label: "Demo Controller"
  )
end

device.start
