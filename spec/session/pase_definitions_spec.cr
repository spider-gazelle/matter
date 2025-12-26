require "../spec_helper"
require "../../src/matter/session/pase/definitions"

describe Matter::Session::Pase::Definitions do
  it "round-trips Pake1 with explicit initializer" do
    x = Bytes.new(65, 0x11_u8)
    msg = Matter::Session::Pase::Definitions::Pake1.new(x: x)
    parsed = Matter::Session::Pase::Definitions::Pake1.from_slice(msg.to_slice)
    parsed.x.should eq(x)
  end

  it "round-trips Pake3 with explicit initializer" do
    v = Bytes.new(32, 0x22_u8)
    msg = Matter::Session::Pase::Definitions::Pake3.new(verifier: v)
    parsed = Matter::Session::Pase::Definitions::Pake3.from_slice(msg.to_slice)
    parsed.verifier.should eq(v)
  end
end
