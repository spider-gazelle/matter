require "goban"
require "../src/matter"

module MatterLevelControl
  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Level Control"
    STORAGE_FILE = "matter_level_control_storage.json"

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    @on_off : Matter::Cluster::OnOffCluster? = nil
    @level_control : Matter::Cluster::LevelControlCluster? = nil
    @fixed_label : Matter::Cluster::FixedLabelCluster? = nil
    @identify : Matter::Cluster::IdentifyCluster? = nil
    @groups : Matter::Cluster::GroupsCluster? = nil
    @scenes_management : Matter::Cluster::ScenesManagementCluster? = nil

    def initialize
      super(ip_addresses: local_ips)
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

    def primary_device_type_id : UInt16
      Matter::DeviceTypes::DIMMABLE_LIGHT
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

    def on_off : Matter::Cluster::OnOffCluster
      @on_off.as(Matter::Cluster::OnOffCluster)
    end

    def level_control : Matter::Cluster::LevelControlCluster
      @level_control.as(Matter::Cluster::LevelControlCluster)
    end

    protected def build_storage_manager : Matter::Storage::Manager
      Matter::Storage::Manager.new(Matter::Storage::JsonFileBackend.new(STORAGE_FILE))
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      @on_off = Matter::Cluster::OnOffCluster.new(
        endpoint,
        feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting
      )
      @level_control = Matter::Cluster::LevelControlCluster.new(
        endpoint,
        current_level: 128_u8,
        min_level: 1_u8,
        max_level: 254_u8,
        feature_map: Matter::Cluster::LevelControlCluster::Feature::OnOff |
                     Matter::Cluster::LevelControlCluster::Feature::Lighting
      )
      on_off.on_state_changed { |new_state| handle_on_off_change(new_state) }
      level_control.on_level_changed { |old_level, new_level| handle_level_change(old_level, new_level) }

      # FixedLabel is optional, but can help controllers show a friendly name for this endpoint.
      @fixed_label = Matter::Cluster::FixedLabelCluster.new(
        endpoint,
        [
          Matter::Cluster::LabelStruct.new("name", "Example Level"),
          Matter::Cluster::LabelStruct.new("name", "Example Mute"),
        ]
      )

      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )
      @groups = Matter::Cluster::GroupsCluster.new(endpoint)
      @scenes_management = Matter::Cluster::ScenesManagementCluster.new(endpoint)

      [
        on_off,
        level_control,
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
      puts "Starting in Commissioning Mode"
      puts "The device is ready to be paired with a Matter controller."
      puts ""
      puts "mDNS Advertisement Active:"
      puts "  Service: _matterc._udp.local"
      puts "  Instance: #{responder.commissioning_instance_name || "<pending>"}"
      puts "  Hostname: #{hostname}"
      puts "  Port: #{port}"
      puts "  Discriminator: #{discriminator}"
      puts ""

      print_qr_code

      manual_code = setup_code
      puts "To pair this device:"
      puts "  chip-tool pairing code 1 #{manual_code}"
      puts ""
    end

    protected def started_operational_mode : Nil
      puts "Starting in Operational Mode"
      puts "The device is commissioned and ready for use."
      puts ""

      fabric_table.all_fabrics.each do |fabric|
        puts "Operational Advertisement (Fabric #{fabric.fabric_index}):"
        puts "  Service: _matter._tcp.local"
        puts "  Fabric ID: 0x#{fabric.fabric_id.to_s(16).upcase}"
        puts "  Node ID: 0x#{fabric.node_id.to_s(16).upcase}"
        puts ""
      end
    end

    protected def main_loop : Nil
      interactive = !ARGV.includes?("--no-interactive")
      if interactive
        run_interactive_loop
      else
        puts "Running in non-interactive mode (--no-interactive)"
        puts "Press Ctrl+C to stop."
        puts ""
        loop { sleep 1.second }
      end
    end

    def shutdown : Nil
      puts ""
      stop
      puts "Shutdown complete"
    end

    private def handle_on_off_change(new_state : Bool) : Nil
      puts ""
      puts "Light state: #{new_state ? "ON" : "OFF"}"
      puts "Level: #{level_control.current_level} (#{level_percent(level_control.current_level)}%)"
      puts "Data version: #{on_off.data_version}"
      print "> "
    end

    private def handle_level_change(old_level : UInt8, new_level : UInt8) : Nil
      # Apple Home treats `currentLevel == minLevel` as OFF for dimmable lights.
      # Align the OnOff state so controllers don't interpret a "minimum on" level as 100%.
      if new_level <= level_control.min_level
        on_off.on = false if on_off.on?
      elsif on_off.off?
        on_off.on = true
      end

      puts ""
      puts "Level changed: #{old_level} -> #{new_level} (#{level_percent(new_level)}%)"
      puts "Data version: #{level_control.data_version}"
      print "> "
    end

    private def level_percent(level : UInt8) : Int32
      (level.to_i * 100) // 254
    end

    private def print_header : Nil
      puts "\n" + "=" * 70
      puts "  Matter Level Control Device"
      puts "  Device Type: Dimmable Light"
      puts "=" * 70
      puts ""
    end

    private def print_state : Nil
      puts "Loading device state..."
      puts "  Name: #{device_name}"
      puts "  Light: #{on_off.on_off? ? "ON" : "OFF"}"
      puts "  Level: #{level_control.current_level} (#{level_percent(level_control.current_level)}%)"
      puts "  Data Version: #{level_control.data_version}"
      puts "  Commissioned: #{fabric_table.empty? ? "No" : "Yes"}"
      puts "  Fabrics: #{fabric_table.size}"
      puts "  Discriminator: #{discriminator}"
      puts "  Setup PIN: #{setup_pin}"
      puts ""
      ip_addresses.each do |ip|
        puts "  IP: #{ip.address} (#{ip.family == Socket::Family::INET ? "IPv4" : "IPv6"})"
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
      puts "Scan this QR code with your Matter controller app:"
      puts ""
      qr.print_to_console
      puts ""
    rescue ex
      puts "Failed to generate QR code: #{ex.message}"
    end

    private def run_interactive_loop : Nil
      puts "Interactive Commands:"
      puts "  toggle           - Toggle the light on/off"
      puts "  on               - Turn the light on"
      puts "  off              - Turn the light off"
      puts "  level <0-100>    - Set the brightness level %"
      puts "  status           - Show current status"
      puts "  reset            - Reset to factory defaults"
      puts "  quit             - Exit the application"
      puts ""

      loop do
        print "> "
        input = gets
        break unless input
        handle_command(input.strip)
      end

      shutdown
    end

    private def handle_command(command : String) : Nil
      parts = command.strip.split
      return if parts.empty?

      case parts[0].downcase
      when "toggle"
        on_off.toggle
      when "on"
        on_off.on = true
      when "off"
        on_off.on = false
      when "level", "brightness"
        set_level_from_command(parts)
      when "status"
        show_status
      when "reset"
        factory_reset
      when "quit", "exit", "q"
        puts "Shutting down..."
        shutdown
        exit(0)
      when "help", "?"
        show_help
      else
        puts "Unknown command: #{command}"
        puts "Type 'help' for available commands."
      end
    end

    private def set_level_from_command(parts : Array(String)) : Nil
      if parts.size < 2
        puts "Usage: level <0-100>"
        return
      end

      value = parts[1].to_f?
      unless value
        puts "Invalid level: #{parts[1]}"
        return
      end

      # cluster performs clamping and value checks
      level_control.level = value
    end

    private def show_status : Nil
      puts ""
      puts "Device Status:"
      puts "  Name: #{device_name}"
      puts "  Light State: #{on_off.on_off? ? "ON" : "OFF"}"
      puts "  Level: #{level_control.current_level} (#{level_percent(level_control.current_level)}%)"
      puts "  Data Version: #{level_control.data_version}"
      puts "  Commissioned: #{fabric_table.empty? ? "No" : "Yes"}"
      puts "  Fabrics: #{fabric_table.size}"
      puts "  Sessions: #{message_handler.sessions.size}"
      puts "  Subscriptions: #{message_handler.active_subscriptions.size}"
      puts ""
    end

    private def show_help : Nil
      puts ""
      puts "Available Commands:"
      puts "  toggle        - Toggle the light between on and off"
      puts "  on            - Turn the light on"
      puts "  off           - Turn the light off"
      puts "  level <0-100> - Set the brightness level %"
      puts "  status        - Show detailed device status"
      puts "  reset         - Reset device to factory defaults"
      puts "  quit          - Shut down the device and exit"
      puts ""
    end

    private def factory_reset : Nil
      print "Are you sure you want to reset to factory defaults? (yes/no): "
      confirmation = gets
      return unless confirmation && confirmation.strip.downcase == "yes"

      puts "Performing factory reset..."
      stop
      File.delete(STORAGE_FILE) if File.exists?(STORAGE_FILE)
      puts "Factory reset complete."
      puts "Please restart the application."
      exit(0)
    end

    private def local_ips : Array(Socket::IPAddress)
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
  end
end

puts "Starting Matter Level Control Device..."
puts ""

Log.setup(:debug)

device = MatterLevelControl::Device.new

Process.on_terminate do
  puts "\n\nReceived interrupt signal"
  device.shutdown
  exit(0)
end

device.start
