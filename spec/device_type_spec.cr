require "./spec_helper"
require "../src/matter/device_type"

describe Matter::DeviceType do
  describe "constants" do
    it "defines common device types" do
      Matter::DeviceType::ON_OFF_LIGHT.should eq(0x0100_u32)
      Matter::DeviceType::DIMMABLE_LIGHT.should eq(0x0101_u32)
      Matter::DeviceType::ON_OFF_PLUG_IN_UNIT.should eq(0x010A_u32)
      Matter::DeviceType::THERMOSTAT.should eq(0x0301_u32)
      Matter::DeviceType::DOOR_LOCK.should eq(0x000A_u32)
      Matter::DeviceType::CONTACT_SENSOR.should eq(0x0015_u32)
    end

    it "defines utility device types" do
      Matter::DeviceType::ROOT_NODE.should eq(0x0016_u32)
      Matter::DeviceType::POWER_SOURCE.should eq(0x0011_u32)
      Matter::DeviceType::OTA_REQUESTOR.should eq(0x0012_u32)
    end

    it "matches the ids carried by the factory device types" do
      Matter::DeviceType.root_node.device_type_id.id.should eq(Matter::DeviceType::ROOT_NODE)
      Matter::DeviceType.on_off_light.device_type_id.id.should eq(Matter::DeviceType::ON_OFF_LIGHT)
      Matter::DeviceType.thermostat.device_type_id.id.should eq(Matter::DeviceType::THERMOSTAT)
    end
  end

  describe ".name" do
    it "returns device type names" do
      Matter::DeviceType.name(Matter::DeviceType::ON_OFF_LIGHT).should eq("On/Off Light")
      Matter::DeviceType.name(Matter::DeviceType::DIMMABLE_LIGHT).should eq("Dimmable Light")
      Matter::DeviceType.name(Matter::DeviceType::THERMOSTAT).should eq("Thermostat")
      Matter::DeviceType.name(Matter::DeviceType::DOOR_LOCK).should eq("Door Lock")
      Matter::DeviceType.name(Matter::DeviceType::CONTACT_SENSOR).should eq("Contact Sensor")
    end

    it "agrees with the factory device type names" do
      Matter::DeviceType.name(Matter::DeviceType::ROOT_NODE).should eq(Matter::DeviceType.root_node.name)
      Matter::DeviceType.name(Matter::DeviceType::FAN).should eq(Matter::DeviceType.fan.name)
    end

    it "returns nil for unknown device types" do
      Matter::DeviceType.name(0xFFFF_FFFF_u32).should be_nil
    end
  end
end
