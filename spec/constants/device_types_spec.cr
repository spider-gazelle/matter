require "../spec_helper"
require "../../src/matter/constants/device_types"

describe Matter::DeviceTypes do
  describe "constants" do
    it "defines common device types" do
      Matter::DeviceTypes::ON_OFF_LIGHT.should eq(0x0100_u16)
      Matter::DeviceTypes::DIMMABLE_LIGHT.should eq(0x0101_u16)
      Matter::DeviceTypes::ON_OFF_PLUG_IN_UNIT.should eq(0x010A_u16)
      Matter::DeviceTypes::THERMOSTAT.should eq(0x0301_u16)
      Matter::DeviceTypes::DOOR_LOCK.should eq(0x000A_u16)
      Matter::DeviceTypes::CONTACT_SENSOR.should eq(0x0015_u16)
    end

    it "defines utility device types" do
      Matter::DeviceTypes::ROOT_NODE.should eq(0x0016_u16)
      Matter::DeviceTypes::POWER_SOURCE.should eq(0x0011_u16)
      Matter::DeviceTypes::OTA_REQUESTOR.should eq(0x0012_u16)
    end
  end

  describe ".name" do
    it "returns device type names" do
      Matter::DeviceTypes.name(Matter::DeviceTypes::ON_OFF_LIGHT).should eq("On/Off Light")
      Matter::DeviceTypes.name(Matter::DeviceTypes::DIMMABLE_LIGHT).should eq("Dimmable Light")
      Matter::DeviceTypes.name(Matter::DeviceTypes::THERMOSTAT).should eq("Thermostat")
      Matter::DeviceTypes.name(Matter::DeviceTypes::DOOR_LOCK).should eq("Door Lock")
      Matter::DeviceTypes.name(Matter::DeviceTypes::CONTACT_SENSOR).should eq("Contact Sensor")
    end

    it "returns nil for unknown device types" do
      Matter::DeviceTypes.name(0xFFFF_u16).should be_nil
    end
  end
end
