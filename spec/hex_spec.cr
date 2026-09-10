require "./spec_helper"

describe Matter::Hex do
  it "formats prefixed, zero-padded, lowercase hex at each width" do
    Matter::Hex.u8(0x0A_u8).should eq("0x0a")
    Matter::Hex.u16(0x1F_u16).should eq("0x001f")
    Matter::Hex.u32(0xBEEF_u32).should eq("0x0000beef")
    Matter::Hex.u64(1_u64).should eq("0x0000000000000001")
  end

  it "keeps every digit of values wider than the nominal width" do
    Matter::Hex.u16(0xFFF1_0006_u32).should eq("0xfff10006")
  end

  it "formats node ids as 16 uppercase digits without a prefix" do
    Matter::Hex.node_id(0xDEAD_BEEF_u64).should eq("00000000DEADBEEF")
  end

  it "formats VID/PID as 4 uppercase digits without a prefix" do
    Matter::Hex.u16_upper(0xFFF1_u16).should eq("FFF1")
    Matter::Hex.u16_upper(0x0001_u16).should eq("0001")
  end
end
