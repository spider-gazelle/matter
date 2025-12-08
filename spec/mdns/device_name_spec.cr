require "../spec_helper"
require "../../src/matter/mdns/service_type"

describe Matter::MDNS::CommissioningInfo do
  describe "#to_txt_records" do
    it "includes DN (Device Name) TXT record with the device name" do
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "Crystal Switch",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8004_u16,
        discriminator: 3840_u16,
        device_type: 259_u16, # On/Off Light Switch
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      txt_records = info.to_txt_records

      # DN (Device Name) should be present and match the device_name
      txt_records["DN"].should eq("Crystal Switch")
    end

    it "includes all required TXT records for commissioning" do
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "Test Device",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 1234_u16,
        device_type: 256_u16, # On/Off Light
        commissioning_mode: Matter::MDNS::CommissioningMode::Enhanced
      )

      txt_records = info.to_txt_records

      # Per Matter spec, commissionable devices MUST advertise:
      # - VP: Vendor+Product IDs
      # - D: Discriminator
      # - CM: Commissioning Mode
      # - DT: Device Type
      # - DN: Device Name

      txt_records["VP"].should eq("65521+32768") # 0xFFF1 + 0x8000
      txt_records["D"].should eq("1234")
      txt_records["CM"].should eq("2") # Enhanced = 2
      txt_records["DT"].should eq("256")
      txt_records["DN"].should eq("Test Device")
    end

    it "includes optional pairing hint when provided" do
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "Test Device",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 1234_u16,
        device_type: 256_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic,
        pairing_hint: 33_u16 # QR Code + Power Cycle
      )

      txt_records = info.to_txt_records

      txt_records["PH"].should eq("33")
    end

    it "includes optional pairing instruction when provided" do
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "Test Device",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 1234_u16,
        device_type: 256_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic,
        pairing_hint: 4_u16,
        pairing_instruction: "Press button for 5 seconds"
      )

      txt_records = info.to_txt_records

      txt_records["PI"].should eq("Press button for 5 seconds")
    end
  end

  describe "device name in mDNS instance name" do
    # Per Matter spec, the mDNS instance name should include the device name
    # Format: <device-name>._matterc._udp.local
    it "uses device_name for mDNS instance name" do
      device_name = "My Smart Light"

      # The ServiceNames.commissioning_instance method should use device_name
      instance = Matter::MDNS::ServiceNames.commissioning_instance(device_name)

      instance.should eq("My Smart Light._matterc._udp.local")
    end

    it "handles special characters in device name" do
      device_name = "Eve Weather"

      instance = Matter::MDNS::ServiceNames.commissioning_instance(device_name)

      instance.should eq("Eve Weather._matterc._udp.local")
    end
  end
end

# Test that the device name flows through from DeviceNode configuration
# to the actual mDNS advertisement
describe "End-to-end device name flow" do
  it "device_name from CommissioningInfo becomes DN TXT record" do
    # Simulate what DeviceNode.ts does in matter.js:
    # productDescription: {
    #     name: deviceName,  // <-- This becomes DN
    #     deviceType: ...,
    # }

    device_name = "Crystal Switch"

    # Our CommissioningInfo (equivalent to matter.js ProductDescription + commissioning options)
    info = Matter::MDNS::CommissioningInfo.new(
      device_name: device_name,
      vendor_id: 0xFFF1_u16,
      product_id: 0x8004_u16,
      discriminator: 3840_u16,
      device_type: 259_u16,
      commissioning_mode: Matter::MDNS::CommissioningMode::Basic
    )

    # The DN TXT record should match the device_name
    info.to_txt_records["DN"].should eq(device_name)

    # The mDNS instance name should also include the device_name
    instance = Matter::MDNS::ServiceNames.commissioning_instance(device_name)
    instance.should contain(device_name)
  end
end
