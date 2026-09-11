require "goban"
require "../src/matter"

# Matter Door Lock Device Example
#
# - Presents as a Door Lock (endpoint 1)
# - Exposes Identify + DoorLock clusters
# - Supports lock/unlock/unbolt + door open/close simulation
# - Persists cluster state via per-cluster JSON persistence

module MatterDoorLock
  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Door Lock"
    STORAGE_FILE = "matter_door_lock_storage.yml"

    UPDATE_INTERVAL_SECONDS = 10

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    @door_lock : Matter::Cluster::DoorLockCluster? = nil
    @identify : Matter::Cluster::IdentifyCluster? = nil
    @fixed_label : Matter::Cluster::FixedLabelCluster? = nil
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
      Matter::DeviceType::DOOR_LOCK
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def door_lock : Matter::Cluster::DoorLockCluster
      @door_lock.as(Matter::Cluster::DoorLockCluster)
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)

      @door_lock = Matter::Cluster::DoorLockCluster.new(
        endpoint,
        auto_relock_time: 15_u32,
        require_pin_for_remote_operation: true,
        default_pin_code: "2468"
      )

      door_lock.on_lock_state_changed do |_old_state, new_state|
        puts "Lock state changed: #{format_lock_state(new_state)} (data version: #{door_lock.data_version})"
      end

      door_lock.on_door_state_changed do |_old_state, new_state|
        puts "Door state changed: #{format_door_state(new_state)}"
      end

      @identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED
      )

      @fixed_label = Matter::Cluster::FixedLabelCluster.new(
        endpoint,
        [Matter::Cluster::LabelStruct.new("name", "Example Door Lock")]
      )

      [
        door_lock,
        @identify.as(Matter::Cluster::IdentifyCluster),
        @fixed_label.as(Matter::Cluster::FixedLabelCluster),
      ] of Matter::Cluster::Base
    end

    protected def before_start : Nil
      puts "Starting Matter Door Lock Device"
      puts "Default remote PIN: #{door_lock.default_pin_code}"
      puts "Auto relock: #{door_lock.auto_relock_time}s"
      puts ""
    end

    protected def started_commissioning_mode : Nil
      puts "Commissioning mode"
      puts "Discriminator: #{discriminator}"
      puts "Setup PIN: #{setup_pin}"
      puts ""
      print_qr_code

      manual_code = setup_code
      puts "Pair with chip-tool:"
      puts "  chip-tool pairing code 1 #{manual_code}"
      puts ""
    end

    protected def started_operational_mode : Nil
      puts "Operational mode"
      puts ""
    end

    protected def on_started : Nil
      @running = true

      interactive = !ARGV.includes?("--no-interactive")
      if interactive
        spawn { run_interactive_loop }
      else
        puts "Running in non-interactive mode (--no-interactive)"
        puts ""
      end

      spawn { run_door_state_simulation }
    end

    protected def on_shutdown : Nil
      @running = false
      puts "Shutdown complete"
    end

    private def run_door_state_simulation : Nil
      opened = false

      while @running
        sleep UPDATE_INTERVAL_SECONDS.seconds
        break unless @running

        opened = !opened
        if opened
          door_lock.update_door_state(Matter::Cluster::DoorLockCluster::DoorState::DoorOpen)
        else
          door_lock.update_door_state(Matter::Cluster::DoorLockCluster::DoorState::DoorClosed)
        end
      end
    end

    private def run_interactive_loop : Nil
      puts "Interactive commands:"
      puts "  lock [pin]    - lock the door"
      puts "  unlock [pin]  - unlock the door"
      puts "  unbolt [pin]  - unbolt the door"
      puts "  open          - mark door open"
      puts "  close         - mark door closed"
      puts "  status        - print device status"
      puts "  reset         - factory reset"
      puts "  quit          - exit"
      puts ""

      loop do
        print "> "
        input = gets
        break unless input
        handle_command(input.strip)
      end
    end

    private def handle_command(input : String) : Nil
      return if input.empty?

      parts = input.split(' ', remove_empty: true)
      command = parts[0].downcase
      pin = parts.size > 1 ? parts[1] : nil

      case command
      when "lock"
        show_status(door_lock.lock(pin: pin))
      when "unlock"
        show_status(door_lock.unlock(pin: pin))
      when "unbolt"
        show_status(door_lock.unbolt(pin: pin))
      when "open"
        door_lock.update_door_state(Matter::Cluster::DoorLockCluster::DoorState::DoorOpen)
      when "close"
        door_lock.update_door_state(Matter::Cluster::DoorLockCluster::DoorState::DoorClosed)
      when "status"
        print_status
      when "reset"
        factory_reset
      when "quit", "exit", "q"
        shutdown!
      else
        puts "Unknown command: #{command}"
      end
    end

    private def show_status(status : Matter::InteractionModel::Status) : Nil
      if status.success?
        puts "Command succeeded"
      else
        puts "Command failed: #{status}"
      end
    end

    private def print_status : Nil
      puts ""
      puts "Door lock status"
      puts "  lockState: #{format_lock_state(door_lock.lock_state)}"
      puts "  doorState: #{format_door_state(door_lock.door_state)}"
      puts "  doorOpenEvents: #{door_lock.door_open_events}"
      puts "  doorClosedEvents: #{door_lock.door_closed_events}"
      puts "  autoRelockTime: #{door_lock.auto_relock_time}s"
      puts "  dataVersion: #{door_lock.data_version}"
      puts "  subscriptions: #{message_handler.active_subscriptions.size}"
      puts ""
    end

    private def factory_reset : Nil
      print "Reset to factory defaults? (yes/no): "
      confirmation = gets
      return unless confirmation && confirmation.strip.downcase == "yes"

      puts "Performing factory reset..."
      shutdown!
      persistence.reset!
      puts "Factory reset complete. Restart the application."
      exit(0)
    end

    private def format_lock_state(state : Matter::Cluster::DoorLockCluster::LockState?) : String
      state ? state.to_s : "null"
    end

    private def format_door_state(state : Matter::Cluster::DoorLockCluster::DoorState?) : String
      state ? state.to_s : "null"
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
  end
end

Log.setup(Log::Severity.parse(ENV["MATTER_LOG"]? || "info"))

device = MatterDoorLock::Device.new

Process.on_terminate do
  device.shutdown!
end

device.start
device.await_shutdown
