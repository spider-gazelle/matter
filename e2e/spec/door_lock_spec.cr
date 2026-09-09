require "./e2e_helper"

# examples/matter_door_lock_device.cr - Door Lock on endpoint 1 (PIN 2468 required)
describe "matter_door_lock example" do
  device = E2E::Device["matter_door_lock"]
  timed = ["--timedInteractionTimeoutMs", "2000"]
  pin = ["--PINCode", "2468"]

  locked = 1_i64
  unlocked = 2_i64

  it "commissions with chip-tool" do
    device.commission!
  end

  it "is a door lock" do
    expect_success(device.read("descriptor", "device-type-list", 1)).int("DeviceType").should eq 0x000A_i64
    expect_success(device.read("fixedlabel", "label-list")).values("Value").should eq ["Example Door Lock"]
  end

  it "reads the lock state" do
    read_int(device, "doorlock", "lock-state", "LockState").should be_in(0..3)
    read_bool(device, "doorlock", "require-pinfor-remote-operation", "RequirePINforRemoteOperation").should be_true
  end

  it "unlocks with the PIN" do
    expect_success(device.invoke("doorlock", "unlock-door", options: timed + pin))
    read_int(device, "doorlock", "lock-state", "LockState").should eq unlocked
  end

  it "locks with the PIN" do
    expect_success(device.invoke("doorlock", "lock-door", options: timed + pin))
    read_int(device, "doorlock", "lock-state", "LockState").should eq locked
  end

  it "rejects remote operation without a PIN" do
    result = device.invoke("doorlock", "unlock-door", options: timed)
    result.success?.should be_false
    read_int(device, "doorlock", "lock-state", "LockState").should eq locked
  end

  it "writes the AutoRelockTime attribute" do
    expect_success(device.write("doorlock", "auto-relock-time", 30, options: timed))
    read_int(device, "doorlock", "auto-relock-time", "AutoRelockTime").should eq 30
  end
end
