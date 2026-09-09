require "./e2e_helper"

# examples/matter_level_control_device.cr - Dimmable Light on endpoint 1
describe "matter_level_control example" do
  device = E2E::Device["matter_level_control"]

  it "commissions with chip-tool" do
    device.commission!
  end

  it "is a dimmable light with two fixed labels" do
    expect_success(device.read("descriptor", "device-type-list", 1)).int("DeviceType").should eq 0x0101_i64
    expect_success(device.read("fixedlabel", "label-list")).values("Value").should eq ["Example Level", "Example Mute"]
  end

  it "reads the current level and its limits" do
    read_int(device, "levelcontrol", "min-level", "MinLevel").should eq 1
    read_int(device, "levelcontrol", "max-level", "MaxLevel").should eq 254
    read_int(device, "levelcontrol", "current-level", "CurrentLevel").should be_in(1..254)
  end

  it "moves to a level" do
    expect_success(device.invoke("levelcontrol", "move-to-level", ["200", "0", "0", "0"]))
    read_int(device, "levelcontrol", "current-level", "CurrentLevel").should eq 200
    read_bool(device, "onoff", "on-off", "OnOff").should be_true
  end

  it "turns the light off when moved to the minimum level" do
    expect_success(device.invoke("levelcontrol", "move-to-level", ["1", "0", "0", "0"]))
    read_int(device, "levelcontrol", "current-level", "CurrentLevel").should eq 1
    read_bool(device, "onoff", "on-off", "OnOff").should be_false
  end

  it "clamps out of range levels" do
    expect_success(device.invoke("levelcontrol", "move-to-level", ["255", "0", "0", "0"]))
    read_int(device, "levelcontrol", "current-level", "CurrentLevel").should eq 254
  end

  it "writes the OnLevel attribute" do
    expect_success(device.write("levelcontrol", "on-level", 100))
    read_int(device, "levelcontrol", "on-level", "OnLevel").should eq 100
  end

  it "toggles on/off" do
    before = read_bool(device, "onoff", "on-off", "OnOff")
    expect_success(device.invoke("onoff", "toggle"))
    read_bool(device, "onoff", "on-off", "OnOff").should eq !before
  end
end
