require "./e2e_helper"

# examples/matter_humidity_sensor_device.cr - Humidity Sensor on endpoint 1
describe "matter_humidity_sensor example" do
  device = E2E::Device["matter_humidity_sensor"]

  it "commissions with chip-tool" do
    device.commission!
  end

  it "is a humidity sensor" do
    expect_success(device.read("descriptor", "device-type-list", 1)).int("DeviceType").should eq 0x0307_i64
    expect_success(device.read("fixedlabel", "label-list")).values("Value").should eq ["Example Humidity Sensor"]
  end

  it "reads the measured humidity within the configured range" do
    read_int(device, "relativehumiditymeasurement", "min-measured-value", "MinMeasuredValue").should eq 3500
    read_int(device, "relativehumiditymeasurement", "max-measured-value", "MaxMeasuredValue").should eq 8000
    read_int(device, "relativehumiditymeasurement", "tolerance", "Tolerance").should eq 150
    read_int(device, "relativehumiditymeasurement", "measured-value", "MeasuredValue").should be_in(3500..8000)
  end

  it "writes the IdentifyTime attribute" do
    expect_success(device.write("identify", "identify-time", 60))
    read_int(device, "identify", "identify-time", "IdentifyTime").should be_in(1..60)
  end
end
