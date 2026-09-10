require "goban"
require "../src/matter"
require "../src/matter/cluster/bridged_device_basic_information_cluster"
require "../src/matter/cluster/on_off_cluster"
require "../src/matter/cluster/identify_cluster"

# Matter Bridge Device Example
#
# - Acts as a bridge aggregating multiple non-Matter devices
# - Presents as a Matter Bridge (Root Node with Aggregator device type)
# - Dynamically bridges On/Off devices on endpoints 1, 2, 3, etc.
# - Supports adding/removing bridged devices at runtime via stdin
# - Each bridged device has BridgedDeviceBasicInformation + OnOff clusters
#
# Commands:
#   add          - Add a new bridged device
#   remove <n>   - Remove bridged device on endpoint n
#   list         - List all bridged devices
#   toggle <n>   - Toggle device on endpoint n
#   on <n>       - Turn on device on endpoint n
#   off <n>      - Turn off device on endpoint n
#   status       - Show bridge status
#   reset        - Factory reset
#   quit         - Exit

module MatterBridge
  # Persisted state for a bridged device
  struct BridgedDeviceConfig
    include JSON::Serializable

    property endpoint_id : UInt16
    property name : String
    property unique_id : String

    def initialize(@endpoint_id : UInt16, @name : String, @unique_id : String)
    end
  end

  # Persisted state for all bridged devices
  struct BridgedDevicesState
    include JSON::Serializable

    property devices : Array(BridgedDeviceConfig)
    property device_counter : Int32

    def initialize(@devices : Array(BridgedDeviceConfig) = [] of BridgedDeviceConfig, @device_counter : Int32 = 0)
    end
  end

  # Represents a bridged device (non-Matter device exposed through the bridge)
  class BridgedDevice
    getter endpoint_id : UInt16
    getter name : String
    getter unique_id : String
    property? reachable : Bool = true

    @on_off_cluster : Matter::Cluster::OnOffCluster
    @bridged_info_cluster : Matter::Cluster::BridgedDeviceBasicInformationCluster
    @identify_cluster : Matter::Cluster::IdentifyCluster

    def initialize(@endpoint_id : UInt16, @name : String, @unique_id : String)
      endpoint = Matter::DataType::EndpointNumber.new(@endpoint_id)

      @on_off_cluster = Matter::Cluster::OnOffCluster.new(
        endpoint,
        feature_map: Matter::Cluster::OnOffCluster::Feature::None
      )

      @bridged_info_cluster = Matter::Cluster::BridgedDeviceBasicInformationCluster.new(
        endpoint,
        reachable: @reachable,
        vendor_name: "Bridged Vendor",
        product_name: @name,
        node_label: @name,
        unique_id: @unique_id,
        hardware_version: 1_u16,
        hardware_version_string: "1.0",
        software_version: 1_u32,
        software_version_string: "1.0.0"
      )

      @identify_cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )

      # Wire reachability callback
      @bridged_info_cluster.on_reachable_changed = ->(new_state : Bool) {
        @reachable = new_state
        nil
      }
    end

    def clusters : Array(Matter::Cluster::Base)
      [
        @on_off_cluster.as(Matter::Cluster::Base),
        @bridged_info_cluster.as(Matter::Cluster::Base),
        @identify_cluster.as(Matter::Cluster::Base),
      ]
    end

    def on_off_cluster : Matter::Cluster::OnOffCluster
      @on_off_cluster
    end

    def bridged_info_cluster : Matter::Cluster::BridgedDeviceBasicInformationCluster
      @bridged_info_cluster
    end

    def on? : Bool
      @on_off_cluster.on_off?
    end

    def on=(value : Bool)
      @on_off_cluster.on = value
    end

    def toggle
      @on_off_cluster.toggle
    end

    def reachable=(value : Bool)
      @reachable = value
      @bridged_info_cluster.reachable = value
    end
  end

  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Bridge"
    STORAGE_FILE = "matter_bridge_storage.json"

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    # Storage keys for bridged devices
    BRIDGED_DEVICES_CONTEXT = ["bridge"] of String
    BRIDGED_DEVICES_KEY     = "bridged_devices"

    # Track bridged devices by endpoint ID
    @bridged_devices : Hash(UInt16, BridgedDevice) = {} of UInt16 => BridgedDevice
    @device_counter : Int32 = 0

    def initialize
      super(ip_addresses: local_ips)
    end

    # Save bridged devices configuration to storage
    private def save_bridged_devices : Nil
      configs = @bridged_devices.values.map do |device|
        BridgedDeviceConfig.new(
          endpoint_id: device.endpoint_id,
          name: device.name,
          unique_id: device.unique_id
        )
      end

      state = BridgedDevicesState.new(
        devices: configs,
        device_counter: @device_counter
      )

      storage_manager.storage.set(BRIDGED_DEVICES_CONTEXT, BRIDGED_DEVICES_KEY, state.to_json)
    rescue ex
      puts "Warning: Failed to save bridged devices: #{ex.message}"
    end

    # Restore bridged devices from storage
    # Returns true if devices were restored, false if none were stored
    private def restore_bridged_devices : Bool
      json = storage_manager.storage.get(BRIDGED_DEVICES_CONTEXT, BRIDGED_DEVICES_KEY)
      return false unless json.is_a?(String)
      return false if json.empty?

      state = BridgedDevicesState.from_json(json)
      @device_counter = state.device_counter

      return false if state.devices.empty?

      puts "Restoring #{state.devices.size} bridged device(s) from storage..."

      state.devices.each do |config|
        restore_bridged_device(config)
      end

      # Restore cluster states (OnOff state, etc.) after devices are created
      restore_cluster_states

      true
    rescue ex
      puts "Warning: Failed to restore bridged devices: #{ex.message}"
      false
    end

    # Restore a single bridged device from config
    private def restore_bridged_device(config : BridgedDeviceConfig) : BridgedDevice?
      device = BridgedDevice.new(config.endpoint_id, config.name, config.unique_id)

      # Don't send subscription notifications when restoring - the controller
      # already knows about these devices from before the restart
      success = add_endpoint(
        endpoint_id: config.endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: device.clusters,
        notify_subscribers: false
      )

      unless success
        puts "  Warning: Failed to restore endpoint #{config.endpoint_id}"
        return
      end

      @bridged_devices[config.endpoint_id] = device

      # Wire up state change callback
      device.on_off_cluster.on_state_changed do |new_state|
        puts "\n  [Endpoint #{config.endpoint_id}] #{device.name} is now: #{new_state ? "ON" : "OFF"}"
        print "> "
      end

      puts "  Restored: Endpoint #{config.endpoint_id} - #{config.name}"
      device
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

    # Bridge is a Root Node device type
    def primary_device_type_id : UInt32
      Matter::DeviceType::ROOT_NODE
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def product_appearance : Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct?
      Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        Matter::Cluster::BasicInformationCluster::ProductFinish::Matte
      )
    end

    protected def build_storage_manager : Matter::Storage::Manager
      Matter::Storage::Manager.new(Matter::Storage::JsonFileBackend.new(STORAGE_FILE))
    end

    # Bridge doesn't have static device endpoints - we use dynamic endpoints
    protected def device_clusters : Array(Matter::Cluster::Base)
      [] of Matter::Cluster::Base
    end

    # Override endpoint_device_types to return empty since we add devices dynamically
    protected def endpoint_device_types : Hash(UInt16, UInt32)
      {} of UInt16 => UInt32
    end

    protected def before_start : Nil
      print_header

      # Try to restore bridged devices from storage first
      if restore_bridged_devices
        puts ""
      else
        # No stored devices - create random initial devices
        initial_count = rand(1..2)
        puts "Creating #{initial_count} initial bridged device(s)..."
        initial_count.times do
          add_bridged_device
        end
        puts ""
      end

      print_state
    end

    protected def started_commissioning_mode : Nil
      puts "Starting in Commissioning Mode"
      puts "   The bridge is ready to be paired with a Matter controller"
      puts ""
      puts "mDNS Advertisement Active:"
      puts "   Service: _matterc._udp.local"
      puts "   Instance: #{responder.commissioning_instance_name || "<pending>"}"
      puts "   Hostname: #{hostname}"
      puts "   Port: #{port}"
      puts "   Discriminator: #{discriminator}"
      puts ""

      print_qr_code

      manual_code = setup_code
      puts "To pair this bridge:"
      puts "   chip-tool pairing code 1 #{manual_code}"
      puts ""
    end

    protected def started_operational_mode : Nil
      puts "Starting in Operational Mode"
      puts "   The bridge is commissioned and ready for use"
      puts ""

      fabric_table.all_fabrics.each do |fabric|
        puts "Operational Advertisement (Fabric #{fabric.fabric_index}):"
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
        puts "Running in non-interactive mode (--no-interactive)"
        puts "   Press Ctrl+C to stop"
        puts ""
      end
    end

    protected def on_shutdown : Nil
      puts "Shutdown complete"
    end

    # Add a new bridged device
    def add_bridged_device : BridgedDevice?
      endpoint_id = next_endpoint_id
      @device_counter += 1

      name = "Bridged Light #{@device_counter}"
      unique_id = "bridged-#{@device_counter}-#{Random::Secure.hex(4)}"

      device = BridgedDevice.new(endpoint_id, name, unique_id)

      # Register with the bridge using dynamic endpoint management
      success = add_endpoint(
        endpoint_id: endpoint_id,
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        clusters: device.clusters
      )

      unless success
        puts "Failed to add endpoint #{endpoint_id}"
        return
      end

      @bridged_devices[endpoint_id] = device

      # Wire up state change callback
      device.on_off_cluster.on_state_changed do |new_state|
        puts "\n  [Endpoint #{endpoint_id}] #{device.name} is now: #{new_state ? "ON" : "OFF"}"
        print "> "
      end

      puts "  Added: Endpoint #{endpoint_id} - #{name}"

      # Persist the updated device list
      save_bridged_devices

      device
    end

    # Remove a bridged device
    def remove_bridged_device(endpoint_id : UInt16) : Bool
      return false unless @bridged_devices.has_key?(endpoint_id)

      device = @bridged_devices.delete(endpoint_id)
      remove_endpoint(endpoint_id)

      if device
        puts "  Removed: Endpoint #{endpoint_id} - #{device.name}"

        # Persist the updated device list
        save_bridged_devices

        true
      else
        false
      end
    end

    private def print_header : Nil
      puts "\n" + "=" * 70
      puts "  Matter Bridge Device"
      puts "  Bridges non-Matter On/Off devices to Matter"
      puts "=" * 70
      puts ""
    end

    private def print_state : Nil
      puts "Bridge Status:"
      puts "   Name: #{device_name}"
      puts "   Bridged Devices: #{@bridged_devices.size}"
      puts "   Commissioned: #{fabric_table.empty? ? "No" : "Yes"}"
      puts "   Fabrics: #{fabric_table.size}"
      puts "   Discriminator: #{discriminator}"
      puts "   Setup PIN: #{setup_pin}"
      puts ""
      ip_addresses.each do |ip|
        puts "   IP: #{ip.address} (#{ip.family == Socket::Family::INET ? "IPv4" : "IPv6"})"
      end
      puts ""

      unless @bridged_devices.empty?
        puts "Bridged Devices:"
        @bridged_devices.each do |endpoint_id, device|
          state = device.on? ? "ON" : "OFF"
          reachable = device.reachable? ? "" : " [UNREACHABLE]"
          puts "   Endpoint #{endpoint_id}: #{device.name} - #{state}#{reachable}"
        end
        puts ""
      end
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
      puts "   add           - Add a new bridged device"
      puts "   remove <n>    - Remove device on endpoint n"
      puts "   list          - List all bridged devices"
      puts "   toggle <n>    - Toggle device on endpoint n"
      puts "   on <n>        - Turn on device on endpoint n"
      puts "   off <n>       - Turn off device on endpoint n"
      puts "   reachable <n> - Toggle reachability of device n"
      puts "   status        - Show bridge status"
      puts "   reset         - Reset to factory defaults"
      puts "   quit          - Exit the application"
      puts ""

      loop do
        print "> "
        input = gets
        break unless input
        handle_command(input.strip)
      end
    end

    private def handle_command(command : String) : Nil
      parts = command.split(/\s+/, 2)
      cmd = parts[0].downcase
      arg = parts[1]?

      case cmd
      when "add"
        add_bridged_device
      when "remove"
        if endpoint = parse_endpoint(arg)
          unless remove_bridged_device(endpoint)
            puts "  No device on endpoint #{endpoint}"
          end
        end
      when "list"
        list_devices
      when "toggle"
        if endpoint = parse_endpoint(arg)
          if device = @bridged_devices[endpoint]?
            device.toggle
          else
            puts "  No device on endpoint #{endpoint}"
          end
        end
      when "on"
        if endpoint = parse_endpoint(arg)
          if device = @bridged_devices[endpoint]?
            device.on = true
          else
            puts "  No device on endpoint #{endpoint}"
          end
        end
      when "off"
        if endpoint = parse_endpoint(arg)
          if device = @bridged_devices[endpoint]?
            device.on = false
          else
            puts "  No device on endpoint #{endpoint}"
          end
        end
      when "reachable"
        if endpoint = parse_endpoint(arg)
          if device = @bridged_devices[endpoint]?
            new_state = !device.reachable?
            device.reachable = new_state
            puts "  Endpoint #{endpoint} reachability: #{new_state ? "REACHABLE" : "UNREACHABLE"}"
          else
            puts "  No device on endpoint #{endpoint}"
          end
        end
      when "status"
        print_state
      when "reset"
        factory_reset
      when "quit", "exit", "q"
        puts "Shutting down..."
        shutdown!
      when "help", "?"
        show_help
      when ""
        # Ignore empty input
      else
        puts "Unknown command: #{cmd}"
        puts "   Type 'help' for available commands"
      end
    end

    private def parse_endpoint(arg : String?) : UInt16?
      return unless arg
      endpoint = arg.to_u16?
      unless endpoint
        puts "  Invalid endpoint number: #{arg}"
        return
      end
      endpoint
    end

    private def list_devices : Nil
      if @bridged_devices.empty?
        puts "  No bridged devices"
        return
      end

      puts ""
      puts "Bridged Devices:"
      @bridged_devices.each do |endpoint_id, device|
        state = device.on? ? "ON" : "OFF"
        reachable = device.reachable? ? "" : " [UNREACHABLE]"
        puts "   Endpoint #{endpoint_id}: #{device.name} - #{state}#{reachable}"
      end
      puts ""
    end

    private def show_help : Nil
      puts ""
      puts "Available Commands:"
      puts "   add           - Add a new bridged On/Off device"
      puts "   remove <n>    - Remove the bridged device on endpoint n"
      puts "   list          - List all bridged devices with their states"
      puts "   toggle <n>    - Toggle the On/Off state of device on endpoint n"
      puts "   on <n>        - Turn on the device on endpoint n"
      puts "   off <n>       - Turn off the device on endpoint n"
      puts "   reachable <n> - Toggle reachability of device on endpoint n"
      puts "   status        - Show detailed bridge status"
      puts "   reset         - Reset bridge to factory defaults"
      puts "   quit          - Shut down the bridge and exit"
      puts ""
    end

    private def factory_reset : Nil
      print "Are you sure you want to reset to factory defaults? (yes/no): "
      confirmation = gets
      return unless confirmation && confirmation.strip.downcase == "yes"

      puts "Performing factory reset..."
      shutdown!
      File.delete(STORAGE_FILE) if File.exists?(STORAGE_FILE)
      puts "Factory reset complete"
      puts "Please restart the application"
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

puts "Starting Matter Bridge Device..."
puts ""

Log.setup(:debug)

device = MatterBridge::Device.new

Process.on_terminate do
  puts "\n\nReceived interrupt signal"
  device.shutdown!
end

device.start
device.await_shutdown
