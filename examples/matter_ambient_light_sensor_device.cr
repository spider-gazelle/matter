require "../src/matter"

module MatterAmbientLightSensor
  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Ambient Light Sensor"
    STORAGE_FILE = "matter_ambient_light_sensor_storage.json"

    UPDATE_INTERVAL_SECONDS =     10
    MIN_LUX                 =   25.0
    MAX_LUX                 = 1500.0

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    @illuminance : Matter::Cluster::IlluminanceMeasurementCluster? = nil
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

    def primary_device_type_id : UInt32
      Matter::DeviceType::LIGHT_SENSOR
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def illuminance : Matter::Cluster::IlluminanceMeasurementCluster
      @illuminance.as(Matter::Cluster::IlluminanceMeasurementCluster)
    end

    protected def build_storage_manager : Matter::Storage::Manager
      Matter::Storage::Manager.new(Matter::Storage::JsonFileBackend.new(STORAGE_FILE))
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      initial_lux = rand(MIN_LUX..MAX_LUX)
      @illuminance = Matter::Cluster::IlluminanceMeasurementCluster.new(
        endpoint,
        measured_value: Matter::Cluster::IlluminanceMeasurementCluster.from_lux(initial_lux)
      )
      illuminance.on_illuminance_changed do |_old_value, new_value|
        if new_value
          lux = Matter::Cluster::IlluminanceMeasurementCluster.to_lux(new_value)
          puts "Ambient light: #{"%.1f" % lux} lx"
        end
      end

      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED
      )

      @fixed_label = Matter::Cluster::FixedLabelCluster.new(
        endpoint,
        [Matter::Cluster::LabelStruct.new("name", "Example Ambient Light Sensor")]
      )

      [
        illuminance,
        @identify.as(Matter::Cluster::IdentifyCluster),
        @fixed_label.as(Matter::Cluster::FixedLabelCluster),
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
      puts "Sampling ambient light every #{UPDATE_INTERVAL_SECONDS}s"
      spawn { run_sensor_loop }
    end

    protected def on_shutdown : Nil
      @running = false
      puts "Shutdown complete"
    end

    private def run_sensor_loop : Nil
      while @running
        sleep UPDATE_INTERVAL_SECONDS.seconds
        break unless @running

        lux = rand(MIN_LUX..MAX_LUX)
        measured = Matter::Cluster::IlluminanceMeasurementCluster.from_lux(lux)
        illuminance.update_illuminance(measured)
      end
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

puts "Starting Matter Ambient Light Sensor Device..."
puts ""

Log.setup(Log::Severity.parse(ENV["MATTER_LOG"]? || "info"))

device = MatterAmbientLightSensor::Device.new

Process.on_terminate do
  puts "\n\nReceived interrupt signal"
  device.shutdown!
end

device.start
device.await_shutdown
