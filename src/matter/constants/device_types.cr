module Matter
  # Matter Device Type Constants (Spec Chapter 7)
  #
  # These are the standardized device type identifiers used in Matter.
  # They identify what kind of device is being advertised or described.
  #
  # This module contains only the constants without any dependencies,
  # making it suitable for use in examples and simple applications.
  module DeviceTypes
    # Utility Device Types
    ROOT_NODE     = 0x0016_u16 # Root Node (endpoint 0)
    POWER_SOURCE  = 0x0011_u16 # Power Source
    OTA_REQUESTOR = 0x0012_u16 # OTA Requestor
    OTA_PROVIDER  = 0x0014_u16 # OTA Provider
    AGGREGATOR    = 0x000E_u16 # Aggregator
    BRIDGED_NODE  = 0x0013_u16 # Bridged Node

    # Lighting Device Types
    ON_OFF_LIGHT            = 0x0100_u16 # On/Off Light
    DIMMABLE_LIGHT          = 0x0101_u16 # Dimmable Light
    COLOR_TEMPERATURE_LIGHT = 0x010C_u16 # Color Temperature Light
    EXTENDED_COLOR_LIGHT    = 0x010D_u16 # Extended Color Light

    # Smart Plug/Outlet Device Types
    ON_OFF_PLUG_IN_UNIT   = 0x010A_u16 # On/Off Plug-in Unit
    DIMMABLE_PLUG_IN_UNIT = 0x010B_u16 # Dimmable Plug-in Unit

    # Switch Device Types
    ON_OFF_LIGHT_SWITCH = 0x0103_u16 # On/Off Light Switch
    DIMMER_SWITCH       = 0x0104_u16 # Dimmer Switch
    COLOR_DIMMER_SWITCH = 0x0105_u16 # Color Dimmer Switch
    CONTROL_BRIDGE      = 0x0840_u16 # Control Bridge
    PUMP_CONTROLLER     = 0x0304_u16 # Pump Controller
    PUMP                = 0x0303_u16 # Pump

    # Sensor Device Types
    CONTACT_SENSOR     = 0x0015_u16 # Contact Sensor
    LIGHT_SENSOR       = 0x0106_u16 # Light Sensor
    OCCUPANCY_SENSOR   = 0x0107_u16 # Occupancy Sensor
    TEMPERATURE_SENSOR = 0x0302_u16 # Temperature Sensor
    PRESSURE_SENSOR    = 0x0305_u16 # Pressure Sensor
    FLOW_SENSOR        = 0x0306_u16 # Flow Sensor
    HUMIDITY_SENSOR    = 0x0307_u16 # Humidity Sensor

    # Closure Device Types
    DOOR_LOCK                  = 0x000A_u16 # Door Lock
    DOOR_LOCK_CONTROLLER       = 0x000B_u16 # Door Lock Controller
    WINDOW_COVERING            = 0x0202_u16 # Window Covering
    WINDOW_COVERING_CONTROLLER = 0x0203_u16 # Window Covering Controller

    # HVAC Device Types
    HEATING_COOLING_UNIT = 0x0300_u16 # Heating/Cooling Unit
    THERMOSTAT           = 0x0301_u16 # Thermostat
    FAN                  = 0x002B_u16 # Fan

    # Media Device Types
    BASIC_VIDEO_PLAYER   = 0x0028_u16 # Basic Video Player
    CASTING_VIDEO_PLAYER = 0x0023_u16 # Casting Video Player
    SPEAKER              = 0x0022_u16 # Speaker
    CONTENT_APP          = 0x0024_u16 # Content App
    CASTING_VIDEO_CLIENT = 0x0029_u16 # Casting Video Client
    VIDEO_REMOTE_CONTROL = 0x002A_u16 # Video Remote Control

    # Helper method to get device type name
    def self.name(device_type : UInt16) : String?
      case device_type
      when ROOT_NODE                  then "Root Node"
      when POWER_SOURCE               then "Power Source"
      when OTA_REQUESTOR              then "OTA Requestor"
      when OTA_PROVIDER               then "OTA Provider"
      when AGGREGATOR                 then "Aggregator"
      when BRIDGED_NODE               then "Bridged Node"
      when ON_OFF_LIGHT               then "On/Off Light"
      when DIMMABLE_LIGHT             then "Dimmable Light"
      when COLOR_TEMPERATURE_LIGHT    then "Color Temperature Light"
      when EXTENDED_COLOR_LIGHT       then "Extended Color Light"
      when ON_OFF_PLUG_IN_UNIT        then "On/Off Plug-in Unit"
      when DIMMABLE_PLUG_IN_UNIT      then "Dimmable Plug-in Unit"
      when ON_OFF_LIGHT_SWITCH        then "On/Off Light Switch"
      when DIMMER_SWITCH              then "Dimmer Switch"
      when COLOR_DIMMER_SWITCH        then "Color Dimmer Switch"
      when CONTROL_BRIDGE             then "Control Bridge"
      when PUMP_CONTROLLER            then "Pump Controller"
      when PUMP                       then "Pump"
      when CONTACT_SENSOR             then "Contact Sensor"
      when LIGHT_SENSOR               then "Light Sensor"
      when OCCUPANCY_SENSOR           then "Occupancy Sensor"
      when TEMPERATURE_SENSOR         then "Temperature Sensor"
      when PRESSURE_SENSOR            then "Pressure Sensor"
      when FLOW_SENSOR                then "Flow Sensor"
      when HUMIDITY_SENSOR            then "Humidity Sensor"
      when DOOR_LOCK                  then "Door Lock"
      when DOOR_LOCK_CONTROLLER       then "Door Lock Controller"
      when WINDOW_COVERING            then "Window Covering"
      when WINDOW_COVERING_CONTROLLER then "Window Covering Controller"
      when HEATING_COOLING_UNIT       then "Heating/Cooling Unit"
      when THERMOSTAT                 then "Thermostat"
      when FAN                        then "Fan"
      when BASIC_VIDEO_PLAYER         then "Basic Video Player"
      when CASTING_VIDEO_PLAYER       then "Casting Video Player"
      when SPEAKER                    then "Speaker"
      when CONTENT_APP                then "Content App"
      when CASTING_VIDEO_CLIENT       then "Casting Video Client"
      when VIDEO_REMOTE_CONTROL       then "Video Remote Control"
      else
        nil
      end
    end
  end
end
