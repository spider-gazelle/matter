require "goban"
require "../src/matter"

# Matter Temperature Sensor Device Example
#
# - Presents as a Temperature Sensor (endpoint 1)
# - Exposes Identify + TemperatureMeasurement clusters
# - Picks a random temperature in [15.0, 35.0] C every 10 seconds
# - Persists cluster state via per-cluster JSON persistence

module MatterTemperatureSensor
  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Temperature Sensor"
    STORAGE_FILE = "matter_temperature_sensor_storage.json"

    UPDATE_INTERVAL_SECONDS =       10
    MIN_TEMP_C              =     15.0
    MAX_TEMP_C              =     35.0
    MIN_TEMP_CENTI          = 1500_i16
    MAX_TEMP_CENTI          = 3500_i16

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    @temperature : Matter::Cluster::TemperatureMeasurementCluster? = nil
    @identify : Matter::Cluster::IdentifyCluster? = nil
    @fixed_label : Matter::Cluster::FixedLabelCluster? = nil
    @running : Bool = false

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
      Matter::DeviceTypes::TEMPERATURE_SENSOR
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

    def temperature : Matter::Cluster::TemperatureMeasurementCluster
      @temperature.as(Matter::Cluster::TemperatureMeasurementCluster)
    end

    protected def build_storage_manager : Matter::Storage::Manager
      Matter::Storage::Manager.new(Matter::Storage::JsonFileBackend.new(STORAGE_FILE))
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      initial_temp = random_temperature_centi
      @temperature = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint,
        measured_value: initial_temp,
        min_measured_value: MIN_TEMP_CENTI,
        max_measured_value: MAX_TEMP_CENTI,
        tolerance: 25_u16
      )
      temperature.on_temperature_changed do |_old_value, new_value|
        if new_value
          puts ""
          puts "Temperature update: #{format_temperature(new_value)} C"
          puts "Data version: #{temperature.data_version}"
          print "> "
        end
      end

      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )

      @fixed_label = Matter::Cluster::FixedLabelCluster.new(
        endpoint,
        [Matter::Cluster::LabelStruct.new("name", "Example Temperature Sensor")]
      )

      [
        temperature,
        @identify.as(Matter::Cluster::IdentifyCluster),
        @fixed_label.as(Matter::Cluster::FixedLabelCluster),
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

    protected def on_started : Nil
      @running = true
      spawn { run_sensor_loop }

      interactive = !ARGV.includes?("--no-interactive")
      if interactive
        spawn { run_interactive_loop }
      else
        puts "Running in non-interactive mode (--no-interactive)"
        puts "Press Ctrl+C to stop."
        puts ""
      end
    end

    protected def on_shutdown : Nil
      @running = false
      puts "Shutdown complete"
    end

    private def run_sensor_loop : Nil
      while @running
        UPDATE_INTERVAL_SECONDS.times do
          break unless @running
          sleep 1.second
        end

        update_temperature if @running
      end
    end

    private def update_temperature : Nil
      value = random_temperature_centi
      temperature.update_temperature(value)
    end

    private def random_temperature_centi : Int16
      rand(MIN_TEMP_CENTI..MAX_TEMP_CENTI)
    end

    private def format_temperature(centi_celsius : Int16) : String
      celsius = Matter::Cluster::TemperatureMeasurementCluster.to_celsius(centi_celsius)
      "%.2f" % celsius
    end

    private def print_header : Nil
      puts "\n" + "=" * 70
      puts "  Matter Temperature Sensor Device"
      puts "  Device Type: Temperature Sensor"
      puts "=" * 70
      puts ""
    end

    private def print_state : Nil
      puts "Loading device state..."
      puts "  Name: #{device_name}"
      puts "  Temperature: #{format_temperature(temperature.measured_value || MIN_TEMP_CENTI)} C"
      puts "  Configured range: #{MIN_TEMP_C} C .. #{MAX_TEMP_C} C"
      puts "  Update interval: #{UPDATE_INTERVAL_SECONDS}s"
      puts "  Data Version: #{temperature.data_version}"
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
      puts "  status - Show current status"
      puts "  sample - Force an immediate temperature sample"
      puts "  reset  - Reset to factory defaults"
      puts "  quit   - Exit the application"
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
      when "status"
        show_status
      when "sample"
        update_temperature
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
        puts "Unknown command: #{command}"
        puts "Type 'help' for available commands"
      end
    end

    private def show_status : Nil
      puts ""
      measured = temperature.measured_value
      puts "Device Status:"
      puts "  Name: #{device_name}"
      puts "  Temperature: #{measured ? format_temperature(measured) : "unknown"} C"
      puts "  Data Version: #{temperature.data_version}"
      puts "  Commissioned: #{fabric_table.empty? ? "No" : "Yes"}"
      puts "  Fabrics: #{fabric_table.size}"
      puts "  Sessions: #{message_handler.sessions.size}"
      puts "  Subscriptions: #{message_handler.active_subscriptions.size}"
      puts ""
    end

    private def show_help : Nil
      puts ""
      puts "Available Commands:"
      puts "  status - Show detailed device status"
      puts "  sample - Force an immediate temperature sample"
      puts "  reset  - Reset device to factory defaults"
      puts "  quit   - Shut down the device and exit"
      puts ""
    end

    private def factory_reset : Nil
      print "Are you sure you want to reset to factory defaults? (yes/no): "
      confirmation = gets
      return unless confirmation && confirmation.strip.downcase == "yes"

      puts "Performing factory reset..."
      shutdown!
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

puts "Starting Matter Temperature Sensor Device..."
puts ""

Log.setup(:debug)

device = MatterTemperatureSensor::Device.new

Process.on_terminate do
  puts "\n\nReceived interrupt signal"
  device.shutdown!
end

device.start
device.await_shutdown
