require "../spec_helper"

describe Matter::Crypto::Spake2p do
  it "computes passcode verifier as w0||L" do
    crypto = Matter::Crypto::StandardCrypto.new
    iterations = 1000
    salt = Bytes.new(32, &.to_u8)
    pin = 20202021_u32

    params = Matter::Crypto::Spake2p::PbkdfParameters.new(iterations, salt)
    w0_l = Matter::Crypto::Spake2p.compute_w0_l(crypto, params, pin)
    verifier = Matter::Crypto::Spake2p.compute_passcode_verifier(crypto, params, pin)

    verifier.size.should eq 97

    expected_w0 = w0_l.w0.to_s(16).rjust(64, '0').hexbytes
    verifier[0, 32].should eq expected_w0
    verifier[32, 65].should eq w0_l.l
  end
end
