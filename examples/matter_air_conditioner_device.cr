require "goban"
require "../src/matter"
require "../src/matter/cluster/thermostat"
require "../src/matter/cluster/fan_control"
require "../src/matter/cluster/temperature_measurement"
require "../src/matter/cluster/on_off"

# Matter Air Conditioner Device Example
#
# Two-endpoint architecture for Matter spec compliance:
# - Endpoint 1: Thermostat (0x301) - temperature control
# - Endpoint 2: Fan (0x002B) - fan control with OnOff
#
# This architecture is spec-correct because:
# - Thermostat device type has FanControl as a CLIENT cluster (talks TO a fan)
# - Fan device type has FanControl as a SERVER cluster (IS the controller)
#
# Clusters by endpoint:
# - Endpoint 1: Thermostat, TemperatureMeasurement, Identify, FixedLabel, Groups, ScenesManagement
# - Endpoint 2: FanControl, OnOff, Identify, Groups
#
# Fan speed maps 0-100% to 5 discrete steps: Quiet, Low, Medium, High, Max
# Simulates ambient temperature updates every 10 seconds
# Supports modes: Off, Cool, Heat, Fan Only

module MatterAirConditioner
  FAN_SPEED_NAMES = {0_u8 => "Off", 1_u8 => "Quiet", 2_u8 => "Low", 3_u8 => "Medium", 4_u8 => "High", 5_u8 => "Max"}

  class Device < Matter::Device::Base
    DEVICE_NAME  = "Crystal Air Conditioner"
    STORAGE_FILE = "matter_air_conditioner_storage.yml"

    UPDATE_INTERVAL_SECONDS =       10
    MIN_TEMP_C              =     15.0
    MAX_TEMP_C              =     35.0
    MIN_TEMP_CENTI          = 1500_i16
    MAX_TEMP_CENTI          = 3500_i16

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    FAN_ONLY_PERCENT            = 60_u8
    HEATING_COOLING_FAN_PERCENT = 40_u8

    # Endpoint 1: Thermostat clusters
    @thermostat : Matter::Cluster::Thermostat? = nil
    @temperature : Matter::Cluster::TemperatureMeasurement? = nil
    @identify1 : Matter::Cluster::Identify? = nil
    @fixed_label : Matter::Cluster::FixedLabel? = nil
    @groups1 : Matter::Cluster::Groups? = nil
    @scenes_management : Matter::Cluster::ScenesManagement? = nil

    # Endpoint 2: Fan clusters
    @fan_control : Matter::Cluster::FanControl? = nil
    @fan_on_off : Matter::Cluster::OnOff? = nil
    @identify2 : Matter::Cluster::Identify? = nil
    @groups2 : Matter::Cluster::Groups? = nil

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
      Matter::DeviceType::THERMOSTAT
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def product_appearance : Matter::Cluster::BasicInformation::ProductAppearanceStruct?
      Matter::Cluster::BasicInformation::ProductAppearanceStruct.new(
        Matter::Cluster::BasicInformation::ProductFinish::Satin
      )
    end

    def thermostat : Matter::Cluster::Thermostat
      @thermostat.as(Matter::Cluster::Thermostat)
    end

    def fan_control : Matter::Cluster::FanControl
      @fan_control.as(Matter::Cluster::FanControl)
    end

    def fan_on_off : Matter::Cluster::OnOff
      @fan_on_off.as(Matter::Cluster::OnOff)
    end

    def temperature : Matter::Cluster::TemperatureMeasurement
      @temperature.as(Matter::Cluster::TemperatureMeasurement)
    end

    protected def endpoint_device_types : Hash(UInt16, UInt32)
      {
        1_u16 => Matter::DeviceType::THERMOSTAT,
        2_u16 => Matter::DeviceType::FAN,
      }
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      endpoint1 = Matter::DataType::EndpointNumber.new(1_u16)
      endpoint2 = Matter::DataType::EndpointNumber.new(2_u16)

      # ========================================================================
      # Endpoint 1: Thermostat device type
      # ========================================================================

      # Thermostat cluster — cooling + heating, defaults to Off
      @thermostat = Matter::Cluster::Thermostat.new(
        endpoint1,
        feature_map: Matter::Cluster::Thermostat::Feature::Cooling | Matter::Cluster::Thermostat::Feature::Heating,
        occupied_cooling_setpoint: 2400_i16, # 24°C
        occupied_heating_setpoint: 2000_i16, # 20°C
        system_mode: Matter::Cluster::Thermostat::SystemMode::Off
      )
      thermostat.on_system_mode_changed do |old_mode, new_mode|
        puts ""
        puts "Mode changed: #{old_mode} -> #{new_mode}"
        # Sync fan: turn off fan when thermostat is off, ensure fan is on otherwise
        if new_mode == Matter::Cluster::Thermostat::SystemMode::Off
          # Turn off fan via OnOff cluster
          fan_on_off.on_off = false
        elsif new_mode == Matter::Cluster::Thermostat::SystemMode::FanOnly
          # Fan-only mode: ensure fan is running (default to Medium if off)
          fan_on_off.on_off = true
          if fan_control.fan_mode == Matter::Cluster::FanControl::FanMode::Off
            fan_control.write_attribute(Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, TLV::Any.new(FAN_ONLY_PERCENT))
          end
        else
          # Cooling/Heating: ensure fan is running
          fan_on_off.on_off = true
          if fan_control.fan_mode == Matter::Cluster::FanControl::FanMode::Off
            fan_control.write_attribute(Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, TLV::Any.new(HEATING_COOLING_FAN_PERCENT))
          end
        end
        print_state_line
        print "> "
      end
      thermostat.on_setpoint_changed do |type, old_val, new_val|
        puts ""
        old_c = Matter::Cluster::TemperatureMeasurement.to_celsius(old_val)
        new_c = Matter::Cluster::TemperatureMeasurement.to_celsius(new_val)
        puts "#{type} setpoint changed: #{"%.1f" % old_c}°C -> #{"%.1f" % new_c}°C"
        print "> "
      end

      # Temperature sensor — ambient temperature
      initial_temp = random_temperature_centi
      @temperature = Matter::Cluster::TemperatureMeasurement.new(
        endpoint1,
        measured_value: initial_temp,
        min_measured_value: MIN_TEMP_CENTI,
        max_measured_value: MAX_TEMP_CENTI,
        tolerance: 50_u16 # 0.5°C tolerance
      )
      # Feed temperature into thermostat's local temperature
      thermostat.update_local_temperature(initial_temp)
      temperature.on_temperature_changed do |_old_val, new_val|
        thermostat.update_local_temperature(new_val)
        if new_val
          puts ""
          puts "Ambient temperature: #{format_temperature(new_val)}°C"
          print "> "
        end
      end

      @identify1 = Matter::Cluster::Identify.new(
        endpoint1,
        identify_type: Matter::Cluster::Identify::IdentifyType::VisibleLight
      )
      @fixed_label = Matter::Cluster::FixedLabel.new(
        endpoint1,
        [Matter::Cluster::LabelStruct.new("name", "Air Conditioner")]
      )
      @groups1 = Matter::Cluster::Groups.new(endpoint1)
      @scenes_management = Matter::Cluster::ScenesManagement.new(endpoint1)

      # ========================================================================
      # Endpoint 2: Fan device type
      # ========================================================================

      # Fan control — 5 discrete speed steps (Quiet/Low/Medium/High/Max)
      @fan_control = Matter::Cluster::FanControl.new(
        endpoint2,
        feature_map: Matter::Cluster::FanControl::Feature::Step,
        fan_mode: Matter::Cluster::FanControl::FanMode::Off,
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowMedHigh,
        speed_max: 5_u8,
        step_percent: 20_u8
      )
      fan_control.on_percent_changed do |_old_pct, new_pct|
        speed = fan_control.speed_current
        name = FAN_SPEED_NAMES[speed]? || "Speed #{speed}"
        puts ""
        puts "Fan: #{name} (#{new_pct}%)"
        print "> "
      end

      # OnOff cluster for fan power control
      @fan_on_off = Matter::Cluster::OnOff.new(endpoint2, on_off: false)
      fan_on_off.on_state_changed do |is_on|
        puts ""
        puts "Fan power: #{is_on ? "ON" : "OFF"}"
        # When fan is turned off via OnOff, also set fan mode to Off
        if !is_on && fan_control.fan_mode != Matter::Cluster::FanControl::FanMode::Off
          fan_control.write_attribute(Matter::Cluster::FanControl::ATTR_FAN_MODE, TLV::Any.new(Matter::Cluster::FanControl::FanMode::Off.value))
        end
        print "> "
      end

      @identify2 = Matter::Cluster::Identify.new(
        endpoint2,
        identify_type: Matter::Cluster::Identify::IdentifyType::VisibleLight
      )
      @groups2 = Matter::Cluster::Groups.new(endpoint2)

      # Return all clusters for both endpoints
      [
        # Endpoint 1: Thermostat
        thermostat,
        temperature,
        @identify1.as(Matter::Cluster::Identify),
        @fixed_label.as(Matter::Cluster::FixedLabel),
        @groups1.as(Matter::Cluster::Groups),
        @scenes_management.as(Matter::Cluster::ScenesManagement),
        # Endpoint 2: Fan
        fan_control,
        fan_on_off,
        @identify2.as(Matter::Cluster::Identify),
        @groups2.as(Matter::Cluster::Groups),
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

        if @running
          value = random_temperature_centi
          temperature.update_temperature(value)
        end
      end
    end

    private def random_temperature_centi : Int16
      rand(MIN_TEMP_CENTI..MAX_TEMP_CENTI)
    end

    private def format_temperature(centi_celsius : Int16) : String
      celsius = Matter::Cluster::TemperatureMeasurement.to_celsius(centi_celsius)
      "%.1f" % celsius
    end

    private def print_header : Nil
      puts "\n" + "=" * 70
      puts "  Matter Air Conditioner Device"
      puts "  Endpoint 1: Thermostat (0x301) - Temperature Control"
      puts "  Endpoint 2: Fan (0x002B) - Fan Control with OnOff"
      puts "=" * 70
      puts ""
    end

    private def print_state : Nil
      puts "Loading device state..."
      puts "  Name: #{device_name}"
      print_state_line
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

    private def print_state_line : Nil
      mode = thermostat.system_mode
      temp = temperature.measured_value
      cool_sp = thermostat.occupied_cooling_setpoint
      heat_sp = thermostat.occupied_heating_setpoint
      speed = fan_control.speed_current
      fan_name = FAN_SPEED_NAMES[speed]? || "Speed #{speed}"
      fan_power = fan_on_off.on_off? ? "ON" : "OFF"

      puts "  Mode: #{mode}"
      puts "  Ambient: #{temp ? format_temperature(temp) : "unknown"}°C"
      puts "  Cool Setpoint: #{format_temperature(cool_sp)}°C"
      puts "  Heat Setpoint: #{format_temperature(heat_sp)}°C"
      puts "  Fan Power: #{fan_power}"
      puts "  Fan Speed: #{fan_name} (#{fan_control.percent_current}%)"
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
      puts "  mode <off|cool|heat|fan>  - Set operating mode"
      puts "  cool <temp>               - Set cooling setpoint (°C)"
      puts "  heat <temp>               - Set heating setpoint (°C)"
      puts "  power <on|off>            - Set fan power (endpoint 2)"
      puts "  fan <off|quiet|low|med|high|max|0-100>  - Set fan speed"
      puts "  status                    - Show current status"
      puts "  reset                     - Reset to factory defaults"
      puts "  quit                      - Exit the application"
      puts ""

      loop do
        print "> "
        input = gets
        break unless input
        handle_command(input.strip)
      end
    end

    private def handle_command(command : String) : Nil
      parts = command.strip.split
      return if parts.empty?

      case parts[0].downcase
      when "mode"
        set_mode(parts)
      when "cool"
        set_cool_setpoint(parts)
      when "heat"
        set_heat_setpoint(parts)
      when "power"
        set_fan_power(parts)
      when "fan"
        set_fan(parts)
      when "status"
        show_status
      when "reset"
        factory_reset
      when "quit", "exit", "q"
        puts "Shutting down..."
        shutdown!
      when "help", "?"
        show_help
      else
        puts "Unknown command: #{command}"
        puts "Type 'help' for available commands."
      end
    end

    private def set_mode(parts : Array(String)) : Nil
      if parts.size < 2
        puts "Usage: mode <off|cool|heat|fan>"
        return
      end

      mode = case parts[1].downcase
             when "off"  then Matter::Cluster::Thermostat::SystemMode::Off
             when "cool" then Matter::Cluster::Thermostat::SystemMode::Cool
             when "heat" then Matter::Cluster::Thermostat::SystemMode::Heat
             when "fan"  then Matter::Cluster::Thermostat::SystemMode::FanOnly
             when "dry"  then Matter::Cluster::Thermostat::SystemMode::Dry
             else
               puts "Unknown mode: #{parts[1]}. Use: off, cool, heat, fan, dry"
               return
             end

      thermostat.mode = mode
    end

    private def set_cool_setpoint(parts : Array(String)) : Nil
      if parts.size < 2
        puts "Usage: cool <temperature in °C>"
        return
      end

      temp = parts[1].to_f?
      unless temp
        puts "Invalid temperature: #{parts[1]}"
        return
      end

      setpoint = Matter::Cluster::TemperatureMeasurement.from_celsius(temp)
      thermostat.cooling_setpoint = setpoint
    end

    private def set_heat_setpoint(parts : Array(String)) : Nil
      if parts.size < 2
        puts "Usage: heat <temperature in °C>"
        return
      end

      temp = parts[1].to_f?
      unless temp
        puts "Invalid temperature: #{parts[1]}"
        return
      end

      setpoint = Matter::Cluster::TemperatureMeasurement.from_celsius(temp)
      thermostat.heating_setpoint = setpoint
    end

    private def set_fan_power(parts : Array(String)) : Nil
      if parts.size < 2
        puts "Usage: power <on|off>"
        return
      end

      case parts[1].downcase
      when "on"
        fan_on_off.on_off = true
      when "off"
        fan_on_off.on_off = false
      else
        puts "Invalid power state: #{parts[1]}. Use: on, off"
      end
    end

    private def set_fan(parts : Array(String)) : Nil
      if parts.size < 2
        puts "Usage: fan <off|quiet|low|med|high|max|0-100>"
        return
      end

      percent = case parts[1].downcase
                when "off"           then 0_u8
                when "quiet"         then 20_u8
                when "low"           then 40_u8
                when "med", "medium" then 60_u8
                when "high"          then 80_u8
                when "max"           then 100_u8
                else
                  val = parts[1].to_u8?
                  unless val && val <= 100
                    puts "Invalid fan speed: #{parts[1]}. Use: off, quiet, low, med, high, max, or 0-100"
                    return
                  end
                  val
                end

      # If setting fan speed > 0, ensure fan is on
      if percent > 0
        fan_on_off.on_off = true
      end
      fan_control.write_attribute(Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, TLV::Any.new(percent))
    end

    private def show_status : Nil
      puts ""
      puts "Device Status:"
      puts "  Name: #{device_name}"
      print_state_line
      puts "  Running Mode: #{thermostat.thermostat_running_mode}"
      puts "  Commissioned: #{fabric_table.empty? ? "No" : "Yes"}"
      puts "  Fabrics: #{fabric_table.size}"
      puts "  Sessions: #{message_handler.sessions.size}"
      puts "  Subscriptions: #{message_handler.active_subscriptions.size}"
      puts ""
    end

    private def show_help : Nil
      puts ""
      puts "Available Commands:"
      puts "  mode <off|cool|heat|fan>  - Set operating mode (endpoint 1)"
      puts "  cool <temp>               - Set cooling setpoint in °C (e.g. 'cool 24')"
      puts "  heat <temp>               - Set heating setpoint in °C (e.g. 'heat 20')"
      puts "  power <on|off>            - Set fan power on/off (endpoint 2)"
      puts "  fan <off|quiet|low|med|high|max|0-100>"
      puts "                            - Set fan speed by name or percentage (endpoint 2)"
      puts "    Fan Speed Mapping:"
      puts "      off=0%, quiet=20%, low=40%, med=60%, high=80%, max=100%"
      puts "  status                    - Show detailed device status"
      puts "  reset                     - Reset device to factory defaults"
      puts "  quit                      - Shut down the device and exit"
      puts ""
      puts "chip-tool Commands for Testing:"
      puts "  chip-tool thermostat read local-temperature 1 1"
      puts "  chip-tool fancontrol read fan-mode 1 2"
      puts "  chip-tool onoff on 1 2"
      puts "  chip-tool onoff off 1 2"
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

puts "Starting Matter Air Conditioner Device..."
puts ""

Log.setup(Log::Severity.parse(ENV["MATTER_LOG"]? || "info"))

device = MatterAirConditioner::Device.new

Process.on_terminate do
  puts "\n\nReceived interrupt signal"
  device.shutdown!
end

device.start
device.await_shutdown
