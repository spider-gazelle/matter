require "goban"
require "../src/matter"

# Matter Switch Device Example
#
# - Presents as an On/Off Light (endpoint 1)
# - Persists state in a single YAML storage file
# - Supports commissioning and operational modes
# - Works with real Matter controllers (iPhone, chip-tool, etc.)

module MatterSwitch
  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Switch"
    STORAGE_FILE = "matter_switch_storage.yml"

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    @switch : Matter::Cluster::OnOffCluster? = nil
    @fixed_label : Matter::Cluster::FixedLabelCluster? = nil
    @identify : Matter::Cluster::IdentifyCluster? = nil
    @groups : Matter::Cluster::GroupsCluster? = nil
    @scenes_management : Matter::Cluster::ScenesManagementCluster? = nil

    def initialize
      super(Matter::Storage::YamlFile.new(STORAGE_FILE), ip_addresses: Matter::Network.local_ip_addresses)
    end

    def device_name : String
      DEVICE_NAME
    end

    def vendor_id : UInt16
      VENDOR_ID
    end

    def product_id : UInt16
      PRODUCT_ID
    end

    def discriminator : UInt16
      DISCRIMINATOR
    end

    def setup_pin : UInt32
      SETUP_PIN_CODE
    end

    def primary_device_type_id : UInt32
      Matter::DeviceType::ON_OFF_LIGHT
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def product_appearance : Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct?
      Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        Matter::Cluster::BasicInformationCluster::ProductFinish::Satin
      )
    end

    def switch : Matter::Cluster::OnOffCluster
      @switch.as(Matter::Cluster::OnOffCluster)
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      @switch = Matter::Cluster::OnOffCluster.new(
        endpoint,
        feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting
      )
      switch.on_state_changed { |new_state| handle_state_change(new_state) }

      # FixedLabel is optional, but can help controllers show a friendly name for this endpoint.
      @fixed_label = Matter::Cluster::FixedLabelCluster.new(
        endpoint,
        [Matter::Cluster::LabelStruct.new("name", "Example Switch")]
      )

      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )

      @groups = Matter::Cluster::GroupsCluster.new(endpoint)
      @scenes_management = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      [
        switch,
        @fixed_label.as(Matter::Cluster::FixedLabelCluster),
        @identify.as(Matter::Cluster::IdentifyCluster),
        @groups.as(Matter::Cluster::GroupsCluster),
        @scenes_management.as(Matter::Cluster::ScenesManagementCluster),
      ] of Matter::Cluster::Base
    end

    protected def before_start : Nil
      print_header
      print_state
    end

    protected def started_commissioning_mode : Nil
      puts "🔓 Starting in Commissioning Mode"
      puts "   The device is ready to be paired with a Matter controller"
      puts ""
      puts "📡 mDNS Advertisement Active:"
      puts "   Service: _matterc._udp.local"
      puts "   Instance: #{responder.commissioning_instance_name || "<pending>"}"
      puts "   Hostname: #{hostname}"
      puts "   Port: #{port}"
      puts "   Discriminator: #{discriminator}"
      puts ""

      print_qr_code

      manual_code = setup_code
      puts "💡 To pair this device:"
      puts "   chip-tool pairing code 1 #{manual_code}"
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
    end

    protected def on_started : Nil
      interactive = !ARGV.includes?("--no-interactive")
      if interactive
        spawn { run_interactive_loop }
      else
        puts "⏸️  Running in non-interactive mode (--no-interactive)"
        puts "   Press Ctrl+C to stop"
        puts ""
      end
    end

    protected def on_shutdown : Nil
      puts "✅ Shutdown complete"
    end

    private def handle_state_change(new_state : Bool) : Nil
      puts "\n  💡 Switch is now: #{new_state ? "🟢 ON" : "⚫ OFF"}"
      puts "  📊 Data version: #{switch.data_version}"
      print "> "
    end

    private def print_header : Nil
      puts "\n" + "=" * 70
      puts "  Matter Switch Device"
      puts "  Device Type: On/Off Light"
      puts "=" * 70
      puts ""
    end

    private def print_state : Nil
      puts "📁 Loading device state..."
      puts "   Name: #{device_name}"
      puts "   Switch: #{switch.on_off? ? "🟢 ON" : "⚫ OFF"}"
      puts "   Data Version: #{switch.data_version}"
      puts "   Commissioned: #{fabric_table.empty? ? "❌ No" : "✅ Yes"}"
      puts "   Fabrics: #{fabric_table.size}"
      puts "   Discriminator: #{discriminator}"
      puts "   Setup PIN: #{setup_pin}"
      puts ""
      ip_addresses.each do |ip|
        puts "   IP: #{ip.address} (#{ip.family == Socket::Family::INET ? "IPv4" : "IPv6"})"
      end
      puts ""
    end

    private def setup_code : String
      Matter::SetupPayload.generate_manual_code(discriminator, setup_pin)
    end

    private def qr_code_payload : String
      Matter::SetupPayload::QRCode.generate_qr_code(
        discriminator: discriminator,
        pin: setup_pin,
        vendor_id: vendor_id,
        product_id: product_id,
        flow: Matter::SetupPayload::QRCode::CommissionFlow::Standard,
        capabilities: Matter::SetupPayload::QRCode::DiscoveryCapability::BLE
      )
    end

    private def print_qr_code : Nil
      payload = qr_code_payload
      qr = Goban::QR.encode_string(payload, Goban::ECC::Level::Low)
      puts "📱 Scan this QR code with your Matter controller app:"
      puts ""
      qr.print_to_console
      puts ""
    rescue ex
      puts "⚠️  Failed to generate QR code: #{ex.message}"
    end

    private def run_interactive_loop : Nil
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
    end

    private def handle_command(command : String) : Nil
      case command
      when "toggle"
        switch.toggle
      when "on"
        switch.on = true
      when "off"
        switch.on = false
      when "status"
        show_status
      when "reset"
        factory_reset
      when "quit", "exit", "q"
        puts "👋 Shutting down..."
        shutdown!
      when "help", "?"
        show_help
      when ""
        # Ignore empty input
      else
        puts "❌ Unknown command: #{command}"
        puts "   Type 'help' for available commands"
      end
    end

    private def show_status : Nil
      puts ""
      puts "📊 Device Status:"
      puts "   Name: #{device_name}"
      puts "   Switch State: #{switch.on_off? ? "🟢 ON" : "⚫ OFF"}"
      puts "   Data Version: #{switch.data_version}"
      puts "   Commissioned: #{fabric_table.empty? ? "❌ No" : "✅ Yes"}"
      puts "   Fabrics: #{fabric_table.size}"
      puts "   Sessions: #{message_handler.sessions.size}"
      puts "   Subscriptions: #{message_handler.active_subscriptions.size}"
      puts ""
    end

    private def show_help : Nil
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

    private def factory_reset : Nil
      print "⚠️  Are you sure you want to reset to factory defaults? (yes/no): "
      confirmation = gets
      return unless confirmation && confirmation.strip.downcase == "yes"

      puts "🔄 Performing factory reset..."
      shutdown!
      persistence.reset!
      puts "✅ Factory reset complete"
      puts "🔄 Please restart the application"
      exit(0)
    end
  end
end

puts "Starting Matter Switch Device..."
puts ""

Log.setup(Log::Severity.parse(ENV["MATTER_LOG"]? || "info"))

device = MatterSwitch::Device.new

Process.on_terminate do
  puts "\n\n🛑 Received interrupt signal"
  device.shutdown!
end

device.start
device.await_shutdown
