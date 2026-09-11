require "../src/matter"

module MatterHumiditySensor
  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Humidity Sensor"
    STORAGE_FILE = "matter_humidity_sensor_storage.yml"

    UPDATE_INTERVAL_SECONDS =       10
    MIN_HUMIDITY            = 3500_u16 # 35.00%
    MAX_HUMIDITY            = 8000_u16 # 80.00%

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    @humidity : Matter::Cluster::RelativeHumidityMeasurement? = nil
    @identify : Matter::Cluster::Identify? = nil
    @fixed_label : Matter::Cluster::FixedLabel? = nil
    @running : Bool = false

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
      Matter::DeviceType::HUMIDITY_SENSOR
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def humidity : Matter::Cluster::RelativeHumidityMeasurement
      @humidity.as(Matter::Cluster::RelativeHumidityMeasurement)
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      @humidity = Matter::Cluster::RelativeHumidityMeasurement.new(
        endpoint,
        measured_value: rand(MIN_HUMIDITY..MAX_HUMIDITY),
        min_measured_value: MIN_HUMIDITY,
        max_measured_value: MAX_HUMIDITY,
        tolerance: 150_u16
      )
      humidity.on_humidity_changed do |_old_value, new_value|
        if new_value
          percent = Matter::Cluster::RelativeHumidityMeasurement.to_percent(new_value)
          puts "Humidity: #{"%.2f" % percent}%"
        end
      end

      @identify = Matter::Cluster::Identify.new(
        endpoint,
        identify_type: Matter::Cluster::Identify::IdentifyType::VisibleLED
      )

      @fixed_label = Matter::Cluster::FixedLabel.new(
        endpoint,
        [Matter::Cluster::LabelStruct.new("name", "Example Humidity Sensor")]
      )

      [
        humidity,
        @identify.as(Matter::Cluster::Identify),
        @fixed_label.as(Matter::Cluster::FixedLabel),
      ] of Matter::Cluster::Base
    end

    protected def started_commissioning_mode : Nil
      manual_code = Matter::SetupPayload.generate_manual_code(discriminator, setup_pin)
      puts "Starting in Commissioning Mode"
      puts "  Discriminator: #{discriminator}"
      puts "  Setup PIN: #{setup_pin}"
      puts ""
      puts "To pair this device:"
      puts "  chip-tool pairing code 1 #{manual_code}"
      puts ""
    end

    protected def started_operational_mode : Nil
      puts "Starting in Operational Mode (already commissioned)"
      puts ""
    end

    protected def on_started : Nil
      @running = true
      puts "Sampling humidity every #{UPDATE_INTERVAL_SECONDS}s"
      spawn { run_sensor_loop }
      spawn { run_interactive_loop } unless ARGV.includes?("--no-interactive")
    end

    protected def on_shutdown : Nil
      @running = false
      puts "Shutdown complete"
    end

    private def run_sensor_loop : Nil
      while @running
        sleep UPDATE_INTERVAL_SECONDS.seconds
        break unless @running

        humidity.update_humidity(rand(MIN_HUMIDITY..MAX_HUMIDITY))
      end
    end

    private def run_interactive_loop : Nil
      puts "Interactive Commands:"
      puts "  status - Show current status"
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
      when "reset"
        factory_reset
      when "quit", "exit", "q"
        puts "Shutting down..."
        shutdown!
      when "help", "?"
        puts "Commands: status, reset, quit"
      when ""
        # Ignore empty input
      else
        puts "Unknown command: #{command}"
        puts "Type 'help' for available commands"
      end
    end

    private def show_status : Nil
      puts ""
      puts "Device Status:"
      puts "  Name: #{device_name}"
      puts "  Commissioned: #{fabric_table.empty? ? "No" : "Yes"}"
      puts "  Fabrics: #{fabric_table.size}"
      puts "  Sessions: #{message_handler.sessions.size}"
      puts "  Subscriptions: #{message_handler.active_subscriptions.size}"
      puts ""
    end

    private def factory_reset : Nil
      print "Are you sure you want to reset to factory defaults? (yes/no): "
      confirmation = gets
      return unless confirmation && confirmation.strip.downcase == "yes"

      puts "Performing factory reset..."
      shutdown!
      persistence.reset!
      puts "Factory reset complete."
      puts "Please restart the application."
      exit(0)
    end
  end
end

puts "Starting Matter Humidity Sensor Device..."
puts ""

Log.setup(Log::Severity.parse(ENV["MATTER_LOG"]? || "info"))

device = MatterHumiditySensor::Device.new

Process.on_terminate do
  puts "\n\nReceived interrupt signal"
  device.shutdown!
end

device.start
device.await_shutdown
