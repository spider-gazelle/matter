require "../spec_helper"
require "../../src/matter/device/base"

# Minimal device exposing a fixed discriminator for commissioning-window specs
class CommissioningWindowTestDevice < Matter::Device::Base
  DEVICE_DISCRIMINATOR = 3840_u16

  def initialize
    super()
  end

  def device_name : String
    "Window Test Device"
  end

  def vendor_id : UInt16
    0xFFF1_u16
  end

  def product_id : UInt16
    0x8000_u16
  end

  def discriminator : UInt16
    DEVICE_DISCRIMINATOR
  end

  def setup_pin : UInt32
    20202021_u32
  end

  def primary_device_type_id : UInt16
    Matter::DeviceTypes::ROOT_NODE
  end

  protected def build_storage_manager : Matter::Storage::Manager
    Matter::Storage::Manager.new(Matter::Storage::MemoryBackend.new)
  end

  protected def device_clusters : Array(Matter::Cluster::Base)
    [] of Matter::Cluster::Base
  end

  protected def endpoint_device_types : Hash(UInt16, UInt32)
    {} of UInt16 => UInt32
  end
end

# The advertising callback the device installs on its AdministratorCommissioning cluster
private def start_advertising(device : Matter::Device::Base) : Proc(UInt16?, Matter::MDNS::CommissioningMode, Nil)
  device.administrator_commissioning.on_start_commissioning_advertising || raise "advertising callback not installed"
end

private def advertised_info(device : Matter::Device::Base) : Matter::MDNS::CommissioningInfo
  device.responder.advertised_commissioning_info || raise "no commissioning advertisement"
end

describe "Device commissioning window advertising" do
  it "advertises the device discriminator for a basic window" do
    require_udp_sockets!
    device = CommissioningWindowTestDevice.new

    start_advertising(device).call(nil, Matter::MDNS::CommissioningMode::Basic)

    info = advertised_info(device)
    info.discriminator.should eq(CommissioningWindowTestDevice::DEVICE_DISCRIMINATOR)
    info.commissioning_mode.should eq(Matter::MDNS::CommissioningMode::Basic)
    device.responder.stop_commissioning
  end

  it "advertises the requested discriminator for an enhanced window" do
    require_udp_sockets!
    device = CommissioningWindowTestDevice.new

    start_advertising(device).call(1234_u16, Matter::MDNS::CommissioningMode::Enhanced)

    info = advertised_info(device)
    info.discriminator.should eq(1234_u16)
    info.commissioning_mode.should eq(Matter::MDNS::CommissioningMode::Enhanced)
    device.responder.stop_commissioning
  end
end
