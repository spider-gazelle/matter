require "../spec_helper"
require "../../src/matter/cluster/descriptor"

describe "DeviceType encoding for HomeKit compatibility" do
  describe "device_type_list attribute" do
    it "encodes On/Off Light device type correctly" do
      descriptor = build(Matter::Cluster::Descriptor)

      # Add On/Off Light device type (0x0100)
      descriptor.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: Matter::DeviceType::ON_OFF_LIGHT,
        revision: 2_u16
      )

      # Read the device_type_list attribute (0x0000)
      encoded = read_tlv(descriptor, 0x0000_u32).to_slice

      # Decode the TLV to verify structure
      # Should be an array containing one struct with device_type=0x0100 and revision=2
      # TLV format: array_start, struct_start, uint32(tag=0, value=0x0100), uint16(tag=1, value=2), struct_end, array_end

      # Verify the bytes contain the device type 0x0100 (256) as uint32 per Matter spec
      # Format: 26 (uint32) 00 (context tag 0) 00010000 (value 256 LE)
      encoded.hexstring.should contain("260000010000") # uint32 context-tag-0 value-256-LE
    end

    it "encodes Root Node device type correctly" do
      descriptor = build(Matter::Cluster::Descriptor, 0)

      # Add Root Node device type (0x0016)
      descriptor.device_type_list << Matter::Cluster::Descriptor::DeviceTypeStruct.new(
        device_type: Matter::DeviceType::ROOT_NODE,
        revision: 1_u16
      )

      encoded = read_tlv(descriptor, 0x0000_u32).to_slice

      # Device type is always uint32 per Matter spec
      # Format: 26 (uint32) 00 (context tag 0) 16000000 (value 22 LE as uint32)
      encoded.hexstring.should contain("260016000000") # uint32 context-tag-0 value-22-LE
    end

    it "encodes server_list correctly for On/Off Light" do
      descriptor = build(Matter::Cluster::Descriptor)

      # Add mandatory clusters for On/Off Light
      descriptor.server_list << 0x0003_u32 # Identify
      descriptor.server_list << 0x0004_u32 # Groups
      descriptor.server_list << 0x0062_u32 # Scenes Management
      descriptor.server_list << 0x0006_u32 # OnOff

      # Read the server_list attribute (0x0001)
      # Cluster ids use the compact TLV width: 04 (anonymous uint8) + value
      hex = read_tlv(descriptor, 0x0001_u32).to_slice.hexstring
      hex.should start_with("16") # array
      hex.should contain("0403")  # Identify
      hex.should contain("0404")  # Groups
      hex.should contain("0462")  # Scenes Management
      hex.should contain("0406")  # OnOff
      hex.should end_with("18")   # end of container
    end
  end

  describe "FeatureMap encoding" do
    it "encodes OnOff cluster with LIGHTING feature" do
      on_off = build(Matter::Cluster::OnOff,
        on_off: false,
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      # FeatureMap attribute ID is 0xFFFC (65532)
      # Compact TLV: 04 (anonymous uint8) + LIGHTING bit set
      read_tlv(on_off, 0xFFFC_u32).to_slice.hexstring.should eq("0401")
    end

    it "encodes OnOff cluster without LIGHTING feature" do
      on_off = build(Matter::Cluster::OnOff,
        on_off: false,
        feature_map: Matter::Cluster::OnOff::Feature::None
      )

      # Compact TLV: 04 (anonymous uint8) + no bits set
      read_tlv(on_off, 0xFFFC_u32).to_slice.hexstring.should eq("0400")
    end
  end

  describe "ClusterRevision encoding" do
    it "encodes OnOff cluster revision" do
      on_off = build(Matter::Cluster::OnOff)

      read_tlv(on_off, Matter::Cluster::Base::GLOBAL_CLUSTER_REVISION).as_u16.should eq(Matter::Cluster::OnOff::CLUSTER_REVISION)
    end

    it "encodes Descriptor cluster revision" do
      descriptor = build(Matter::Cluster::Descriptor)

      read_tlv(descriptor, Matter::Cluster::Base::GLOBAL_CLUSTER_REVISION).as_u16.should eq(Matter::Cluster::Descriptor::CLUSTER_REVISION)
    end
  end
end
