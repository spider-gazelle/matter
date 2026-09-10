require "../spec_helper"
require "../../src/matter/device/base"

# Test device that uses default serial_number and unique_id (auto-generated)
class TestDeviceWithDefaults < Matter::Device::Base
  def initialize(backend : Matter::Storage::Backend = Matter::Storage::Memory.new)
    super(backend)
  end

  def device_name : String
    "Test Device"
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
    Matter::DeviceType::ROOT_NODE
  end

  protected def device_clusters : Array(Matter::Cluster::Base)
    [] of Matter::Cluster::Base
  end

  protected def endpoint_device_types : Hash(UInt16, UInt32)
    {} of UInt16 => UInt32
  end
end

# Test device that provides custom serial_number and unique_id
class TestDeviceWithCustomIdentity < Matter::Device::Base
  CUSTOM_SERIAL = "CUSTOM-SERIAL-123"
  CUSTOM_UNIQUE = "custom-unique-id-456"

  def initialize
    super(Matter::Storage::Memory.new)
  end

  def device_name : String
    "Test Device Custom"
  end

  def vendor_id : UInt16
    0xFFF1_u16
  end

  def product_id : UInt16
    0x8001_u16
  end

  def discriminator : UInt16
    3841_u16
  end

  def setup_pin : UInt32
    20202022_u32
  end

  def primary_device_type_id : UInt32
    Matter::DeviceType::ROOT_NODE
  end

  def serial_number : String?
    CUSTOM_SERIAL
  end

  def unique_id : String?
    CUSTOM_UNIQUE
  end

  protected def device_clusters : Array(Matter::Cluster::Base)
    [] of Matter::Cluster::Base
  end

  protected def endpoint_device_types : Hash(UInt16, UInt32)
    {} of UInt16 => UInt32
  end
end

# Storage backend whose identity reads fail, as a corrupt store would.
class FailingIdentityBackend < Matter::Storage::Memory
  def read(collection : String, id : String) : Matter::Storage::Document?
    if collection == Matter::Storage::Collections::DEVICE && id == Matter::Device::Persistence::IDENTITY_ID
      raise Matter::StorageError.new("identity store unavailable")
    end
    super
  end
end

describe "Device Identity" do
  describe "with a failing storage backend" do
    it "still generates every identity value" do
      device = TestDeviceWithDefaults.new(FailingIdentityBackend.new)

      device.basic_info.serial_number.should match(/^[0-9A-F]{16}$/)
      device.basic_info.unique_id.size.should eq(32)
      device.hostname.should match(/^[0-9A-F]{16}\.local$/)
    end
  end

  describe "serial_number" do
    it "auto-generates serial number when not provided" do
      device = TestDeviceWithDefaults.new
      serial = device.basic_info.serial_number

      serial.should_not be_empty
      serial.size.should eq(16) # hex(8) = 16 chars
      serial.should match(/^[0-9A-F]+$/)
    end

    it "persists serial number across device instances" do
      backend = Matter::Storage::Memory.new

      device1 = TestDeviceWithDefaults.new(backend)
      serial1 = device1.basic_info.serial_number

      device2 = TestDeviceWithDefaults.new(backend)
      serial2 = device2.basic_info.serial_number

      serial1.should eq(serial2)
    end

    it "uses custom serial number when provided by subclass" do
      device = TestDeviceWithCustomIdentity.new
      device.basic_info.serial_number.should eq(TestDeviceWithCustomIdentity::CUSTOM_SERIAL)
    end
  end

  describe "unique_id" do
    it "auto-generates unique_id when not provided" do
      device = TestDeviceWithDefaults.new
      unique_id = device.basic_info.unique_id

      unique_id.should_not be_empty
      unique_id.size.should eq(32) # hex(16) = 32 chars
      unique_id.should match(/^[0-9a-f]+$/)
    end

    it "persists unique_id across device instances" do
      backend = Matter::Storage::Memory.new

      device1 = TestDeviceWithDefaults.new(backend)
      unique_id1 = device1.basic_info.unique_id

      device2 = TestDeviceWithDefaults.new(backend)
      unique_id2 = device2.basic_info.unique_id

      unique_id1.should eq(unique_id2)
    end

    it "uses custom unique_id when provided by subclass" do
      device = TestDeviceWithCustomIdentity.new
      device.basic_info.unique_id.should eq(TestDeviceWithCustomIdentity::CUSTOM_UNIQUE)
    end
  end

  describe "hostname" do
    it "auto-generates hostname when not provided" do
      device = TestDeviceWithDefaults.new
      hostname = device.hostname

      hostname.should_not be_empty
      hostname.should end_with(".local")
      hostname.size.should eq(22) # 16 hex chars + ".local"
    end

    it "persists hostname across device instances" do
      backend = Matter::Storage::Memory.new

      device1 = TestDeviceWithDefaults.new(backend)
      hostname1 = device1.hostname

      device2 = TestDeviceWithDefaults.new(backend)
      hostname2 = device2.hostname

      hostname1.should eq(hostname2)
    end
  end
end
