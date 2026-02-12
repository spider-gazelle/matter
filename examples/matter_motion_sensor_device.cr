require "../src/matter"

module MatterMotionSensor
  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Motion Sensor"
    STORAGE_FILE = "matter_motion_sensor_storage.json"

    UPDATE_INTERVAL_SECONDS = 10

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    @occupancy : Matter::Cluster::OccupancySensingCluster? = nil
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
      Matter::DeviceTypes::OCCUPANCY_SENSOR
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def occupancy : Matter::Cluster::OccupancySensingCluster
      @occupancy.as(Matter::Cluster::OccupancySensingCluster)
    end

    protected def build_storage_manager : Matter::Storage::Manager
      Matter::Storage::Manager.new(Matter::Storage::JsonFileBackend.new(STORAGE_FILE))
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      @occupancy = Matter::Cluster::OccupancySensingCluster.new(
        endpoint,
        feature_map: Matter::Cluster::OccupancySensingCluster::Feature::PassiveInfrared,
        occupancy: 0_u8,
        occupancy_sensor_type: Matter::Cluster::OccupancySensingCluster::OccupancySensorType::PIR,
        occupancy_sensor_type_bitmap: 0x01_u8
      )
      occupancy.on_occupancy_changed do |_old_value, new_value|
        puts "Motion: #{new_value == 1_u8 ? "occupied" : "clear"}"
      end

      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED
      )

      @fixed_label = Matter::Cluster::FixedLabelCluster.new(
        endpoint,
        [Matter::Cluster::LabelStruct.new("name", "Example Motion Sensor")]
      )

      [
        occupancy,
        @identify.as(Matter::Cluster::IdentifyCluster),
        @fixed_label.as(Matter::Cluster::FixedLabelCluster),
      ] of Matter::Cluster::Base
    end

    protected def on_started : Nil
      @running = true
      puts "Sampling motion every #{UPDATE_INTERVAL_SECONDS}s"
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

        occupied = rand(0..99) < 35
        occupancy.update_occupancy(occupied)
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

puts "Starting Matter Motion Sensor Device..."
puts ""

Log.setup(:debug)

device = MatterMotionSensor::Device.new

Process.on_terminate do
  puts "\n\nReceived interrupt signal"
  device.shutdown!
end

device.start
device.await_shutdown
