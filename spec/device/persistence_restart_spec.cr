require "../spec_helper"
require "../../src/matter/device"
require "../../src/matter/cluster/on_off"
require "../../src/matter/cluster/identify"
require "../../src/matter/cluster/groups"

# An on/off light on endpoint 1 (as in `examples/matter_switch_device.cr`)
# whose whole state lives in one `YamlFile`, so two instances booted on the
# same path model a device process restarting.
class PersistenceRestartDevice < Matter::Device
  LIGHT_ENDPOINT = 1_u16

  # Bind an ephemeral UDP port so instances never collide with each other or a
  # running device.
  EPHEMERAL_PORT = 0

  @switch : Matter::Cluster::OnOff?

  def initialize(path : String)
    super(Matter::Storage::YamlFile.new(path), port: EPHEMERAL_PORT)
  end

  def device_name : String
    "Restart Light"
  end

  def vendor_id : UInt16
    0xFFF1_u16
  end

  def product_id : UInt16
    0x8000_u16
  end

  def discriminator : UInt16
    3840_u16
  end

  def setup_pin : UInt32
    20202021_u32
  end

  def primary_device_type_id : UInt32
    Matter::DeviceType::ON_OFF_LIGHT
  end

  def switch : Matter::Cluster::OnOff
    @switch.as(Matter::Cluster::OnOff)
  end

  protected def device_clusters : Array(Matter::Cluster::Base)
    endpoint = endpoint(LIGHT_ENDPOINT)
    @switch = Matter::Cluster::OnOff.new(endpoint, feature_map: Matter::Cluster::OnOff::Feature::Lighting)

    # Identify and Groups are mandatory on an On/Off Light.
    [
      switch,
      Matter::Cluster::Identify.new(endpoint),
      Matter::Cluster::Groups.new(endpoint),
    ] of Matter::Cluster::Base
  end

  protected def endpoint_device_types : Hash(UInt16, UInt32)
    {LIGHT_ENDPOINT => Matter::DeviceType::ON_OFF_LIGHT}
  end

  # Releases the socket and the store without `shutdown!` (which also flushes).
  def release : Nil
    message_handler.close
    persistence.close
    transport.close
  end
end

module PersistenceRestartSpec
  CLUSTERS = Matter::Storage::Collections::CLUSTERS

  # The debounce fires after `SAVE_DEBOUNCE`, but a loaded machine can schedule
  # the writer fiber much later than that, so the spec polls up to this deadline
  # instead of sleeping a fixed interval once.
  DEBOUNCE_DEADLINE = Matter::Device::Persistence::SAVE_DEBOUNCE * 40
  DEBOUNCE_POLL     = 10.milliseconds

  # A fabric id above Int64::MAX exercises the UInt64 path of the store.
  FABRIC_INDEX =                      1_u8
  FABRIC_ID    = 0xFFFF_FFFF_FFFF_FFF0_u64
  NODE_ID      = 0x0000_0000_1234_5678_u64
  LABEL        = "Home"

  NODE_LABEL = "Hallway"

  def self.with_temp_file(& : String ->) : Nil
    path = File.join(Dir.tempdir, "matter-restart-#{Random::Secure.hex(6)}.yml")
    yield path
  ensure
    File.delete?(path) if path
  end

  def self.build_fabric : Matter::Fabric
    Matter::Fabric.new(
      fabric_id: FABRIC_ID,
      fabric_index: FABRIC_INDEX,
      node_id: NODE_ID,
      root_public_key: Random::Secure.random_bytes(65),
      operational_cert: Random::Secure.random_bytes(200),
      operational_key: Matter::Crypto::Key.generate_key_pair,
      ipk: Random::Secure.random_bytes(Matter::Fabric::IPK_SIZE),
      label: LABEL
    )
  end

  # Commissions the device with `fabric` and mutates both persisted clusters.
  def self.commission_and_mutate(device : PersistenceRestartDevice, fabric : Matter::Fabric) : Nil
    device.fabric_table.add_fabric(fabric).should be_true
    device.switch.on = true
    expect_success(write(device.basic_info, Matter::Cluster::BasicInformation::ATTR_NODE_LABEL, NODE_LABEL))
  end

  # What a second boot on the same store must see.
  def self.assert_restored(device : PersistenceRestartDevice, previous : PersistenceRestartDevice, fabric : Matter::Fabric) : Nil
    device.persistence.fabric_table.size.should eq(1)
    restored = device.fabric_table.get_fabric(FABRIC_INDEX).as(Matter::Fabric)
    restored.fabric_id.should eq(FABRIC_ID)
    restored.node_id.should eq(NODE_ID)
    restored.ipk.should eq(fabric.ipk)
    restored.label.should eq(LABEL)

    device.switch.on?.should be_true
    device.basic_info.node_label.should eq(NODE_LABEL)

    device.hostname.should eq(previous.hostname)
    device.basic_info.serial_number.should eq(previous.basic_info.serial_number)
    device.basic_info.unique_id.should eq(previous.basic_info.unique_id)
  end

  # Reads a cluster document straight from the file with a fresh backend.
  def self.stored_cluster?(path : String, endpoint : UInt16, cluster_id : UInt32) : Matter::Storage::Document?
    return unless File.exists?(path)
    store = Matter::Storage::YamlFile.new(path)
    store.open
    store.read(CLUSTERS, Matter::Cluster::Base.persistence_key(endpoint, cluster_id))
  ensure
    store.try(&.close)
  end

  # Waits for the debounced writer to have put the cluster in the file.
  def self.await_stored_cluster(path : String, endpoint : UInt16, cluster_id : UInt32) : Matter::Storage::Document
    deadline = Time.monotonic + DEBOUNCE_DEADLINE
    loop do
      if document = stored_cluster?(path, endpoint, cluster_id)
        return document
      end
      key = Matter::Cluster::Base.persistence_key(endpoint, cluster_id)
      raise "#{CLUSTERS}/#{key} never written to #{path}" if Time.monotonic > deadline
      sleep DEBOUNCE_POLL
    end
  end
end

describe "Device restart persistence" do
  it "survives a crash once the debounce has written the file" do
    PersistenceRestartSpec.with_temp_file do |path|
      fabric = PersistenceRestartSpec.build_fabric
      device_a = PersistenceRestartDevice.new(path)
      PersistenceRestartSpec.commission_and_mutate(device_a, fabric)

      # A real crash never reaches `close`, so prove the file already holds the
      # state before releasing device A's handles.
      on_off = PersistenceRestartSpec.await_stored_cluster(path, PersistenceRestartDevice::LIGHT_ENDPOINT, Matter::Cluster::OnOff::CLUSTER_ID)
      on_off["on_off"].should be_true
      basic = PersistenceRestartSpec.await_stored_cluster(path, 0_u16, Matter::Cluster::BasicInformation::CLUSTER_ID)
      basic["node_label"].should eq(PersistenceRestartSpec::NODE_LABEL)
      device_a.release

      device_b = PersistenceRestartDevice.new(path)
      PersistenceRestartSpec.assert_restored(device_b, device_a, fabric)
      device_b.release
    end
  end

  it "survives a flush and reset! leaves a fresh, uncommissioned device" do
    PersistenceRestartSpec.with_temp_file do |path|
      fabric = PersistenceRestartSpec.build_fabric
      device_a = PersistenceRestartDevice.new(path)
      PersistenceRestartSpec.commission_and_mutate(device_a, fabric)
      device_a.persistence.flush
      device_a.release

      device_b = PersistenceRestartDevice.new(path)
      PersistenceRestartSpec.assert_restored(device_b, device_a, fabric)

      device_b.persistence.reset!
      File.exists?(path).should be_false
      device_b.transport.close

      device_c = PersistenceRestartDevice.new(path)
      device_c.fabric_table.empty?.should be_true
      device_c.switch.off?.should be_true
      device_c.basic_info.node_label.should eq(device_c.product_name)
      device_c.hostname.should_not eq(device_b.hostname)
      device_c.basic_info.serial_number.should_not eq(device_b.basic_info.serial_number)
      device_c.basic_info.unique_id.should_not eq(device_b.basic_info.unique_id)
      device_c.release
    end
  end
end
