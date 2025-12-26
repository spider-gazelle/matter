require "../spec_helper"
require "../../src/matter/controller/certificate_util"

describe Matter::Controller::CertificateUtil do
  it "extracts an uncompressed P-256 public key from a CSR DER blob" do
    pub = Bytes[0x04_u8] + Bytes.new(64) { |i| (i & 0xFF).to_u8 }
    # Embed a BIT STRING of length 66: 0 unused bits + 65-byte EC point.
    csr = Bytes[0x30, 0x00, 0x03, 0x42, 0x00] + pub

    extracted = Matter::Controller::CertificateUtil.extract_uncompressed_public_key_from_csr(csr)
    extracted.should eq(pub)
  end

  it "raises when no suitable BIT STRING is present" do
    expect_raises(Exception, /CSR public key not found/) do
      Matter::Controller::CertificateUtil.extract_uncompressed_public_key_from_csr(Bytes[0x30, 0x00])
    end
  end
end
