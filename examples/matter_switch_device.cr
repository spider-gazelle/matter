require "json"
require "goban"
require "../src/matter"

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

  # Main device class
  class Device < Matter::Device::Base
    STATE_FILE   = "matter_switch_state.json"
    STORAGE_FILE = "matter_switch_storage.json"

    getter state : DeviceState

    @switch : Matter::Cluster::OnOffCluster? = nil
    @identify : Matter::Cluster::IdentifyCluster? = nil
    @groups : Matter::Cluster::GroupsCluster? = nil
    @scenes_management : Matter::Cluster::ScenesManagementCluster? = nil

    def initialize(hostname = "matter-switch.local", port = 5540)
      @state = DeviceState.load(STATE_FILE)
      super(hostname, port, get_local_ips)
    end

    def device_name : String
      @state.device_name
    end

    def vendor_id : UInt16
      @state.vendor_id
    end

    def product_id : UInt16
      @state.product_id
    end

    def discriminator : UInt16
      @state.discriminator
    end

    def setup_pin : UInt32
      @state.setup_pin
    end

    def primary_device_type_id : UInt16
      Matter::DeviceTypes::ON_OFF_LIGHT
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      @state.device_name
    end

    def serial_number : String?
      @state.serial_number
    end

    def unique_id : String?
      @state.unique_id
    end

    def product_appearance : Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct?
      Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        Matter::Cluster::BasicInformationCluster::ProductFinish::Satin
      )
    end

    def switch : Matter::Cluster::OnOffCluster
      @switch.not_nil!
    end

    def identify : Matter::Cluster::IdentifyCluster
      @identify.not_nil!
    end

    def groups : Matter::Cluster::GroupsCluster
      @groups.not_nil!
    end

    def scenes_management : Matter::Cluster::ScenesManagementCluster
      @scenes_management.not_nil!
    end

    protected def build_storage_manager : Matter::Persistence::StorageManager
      Matter::Persistence::JsonStorage.new(STORAGE_FILE)
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      @switch = Matter::Cluster::OnOffCluster.new(
        endpoint,
        on_off: @state.on_off,
        feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting
      )
      switch.on_state_changed { |new_state| handle_state_change(new_state) }

      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )

      @groups = Matter::Cluster::GroupsCluster.new(endpoint)
      @scenes_management = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      [
        switch,
        identify,
        groups,
        scenes_management,
      ] of Matter::Cluster::Base
    end

    protected def before_start : Nil
      print_header
      load_state
    end

    protected def started_commissioning_mode : Nil
      puts "🔓 Starting in Commissioning Mode"
      puts "   The device is ready to be paired with a Matter controller"
      puts ""

      puts "📡 mDNS Advertisement Active:"
      puts "   Service: _matterc._udp.local"
      puts "   Instance: #{@state.device_name}._matterc._udp.local"
      puts "   Hostname: #{hostname}"
      puts "   Port: #{port}"
      puts "   Discriminator: #{@state.discriminator}"
      puts ""

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

    protected def started_operational_mode : Nil
      puts "🔒 Starting in Operational Mode"
      puts "   The device is already commissioned and ready for use"
      puts ""

      fabric_table.all_fabrics.each do |fabric|
        puts "📡 Operational Advertisement (Fabric #{fabric.fabric_index}):"
        puts "   Service: _matter._tcp.local"
        puts "   Fabric ID: 0x#{fabric.fabric_id.to_s(16).upcase}"
        puts "   Node ID: 0x#{fabric.node_id.to_s(16).upcase}"
        puts ""
      end

      puts "✅ Device is ready to receive commands from your controller!"
      puts ""
    end

    protected def commissioned(fabric : Matter::Fabric) : Nil
      @state.commissioned = true
      @state.save(STATE_FILE)
    end

    protected def decommissioned : Nil
      @state.commissioned = false
      @state.save(STATE_FILE)
    end

    protected def main_loop : Nil
      interactive = !ARGV.includes?("--no-interactive")
      if interactive
        run_interactive_loop
      else
        puts "⏸️  Running in non-interactive mode (--no-interactive)"
        puts "   Press Ctrl+C to stop"
        puts ""
        loop { sleep 1.second }
      end
    end

    def get_local_ips : Array(Socket::IPAddress)
      ips = [] of Socket::IPAddress

      begin
        socket = UDPSocket.new(:inet6)
        socket.connect("2606:4700:4700::1111", 53)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
      end

      begin
        socket = UDPSocket.new(:inet)
        socket.connect("8.8.8.8", 80)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
      end

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

      actual_commissioned = !fabric_table.empty?
      if @state.commissioned != actual_commissioned
        puts "   ⚠️  Correcting commissioned state: #{@state.commissioned} -> #{actual_commissioned}"
        @state.commissioned = actual_commissioned
        @state.save(STATE_FILE)
      end

      puts "   Commissioned: #{@state.commissioned ? "✅ Yes" : "❌ No"}"
      puts "   Fabrics: #{fabric_table.size}"
      puts "   Discriminator: #{@state.discriminator}"
      puts "   Setup PIN: #{@state.setup_pin}"
      puts "   Serial Number: #{@state.serial_number}"
      puts "   Unique ID: #{@state.unique_id}"
      puts ""
      ip_addresses.each do |ip|
        puts "   IP: #{ip.address} (#{ip.family == Socket::Family::INET ? "IPv4" : "IPv6"})"
      end
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
        switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_TOGGLE, Bytes.new(0))
      when "on"
        switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_ON, Bytes.new(0))
      when "off"
        switch.invoke_command(Matter::Cluster::OnOffCluster::CMD_OFF, Bytes.new(0))
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
      puts "   Fabrics: #{@fabric_table.size}"
      puts "   Sessions: #{@message_handler.sessions.size}"
      puts "   Subscriptions: #{@message_handler.active_subscriptions.size}"

      unless @fabric_table.empty?
        puts ""
        puts "   Connected Fabrics:"
        @fabric_table.all_fabrics.each do |fabric|
          puts "     • Fabric #{fabric.fabric_index}: #{fabric.label}"
          puts "       ID: 0x#{fabric.fabric_id.to_s(16).upcase}"
          puts "       Node: 0x#{fabric.node_id.to_s(16).upcase}"
        end
      end

      unless @message_handler.active_subscriptions.empty?
        puts ""
        puts "   Active Subscriptions:"
        @message_handler.active_subscriptions.each do |sub_id, sub|
          puts "     • Subscription #{sub_id}:"
          puts "       Peer: #{sub.peer}"
          puts "       Interval: #{sub.min_interval}s - #{sub.max_interval}s"
          puts "       Paths: #{sub.attribute_paths.size}"
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

        # Delete local state and persistence file
        File.delete(STATE_FILE) if File.exists?(STATE_FILE)
        File.delete(STORAGE_FILE) if File.exists?(STORAGE_FILE)

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
      stop

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
