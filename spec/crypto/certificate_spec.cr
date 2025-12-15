require "../spec_helper"
require "../../src/matter/crypto/certificate"

describe Matter::Crypto::MatterCertificate do
  describe "parsing" do
    it "parses a minimal NOC certificate" do
      # Create a minimal valid Matter NOC certificate with all required fields
      # Structure:
      #   tag 1: serial_number (bytes)
      #   tag 2: signature_algorithm (u8)
      #   tag 3: issuer (list with rcac_id)
      #   tag 4: not_before (u32)
      #   tag 5: not_after (u32)
      #   tag 6: subject (list with fabric_id and node_id)
      #   tag 7: public_key_algorithm (u8)
      #   tag 8: elliptic_curve_id (u8)
      #   tag 9: ec_public_key (65 bytes)
      #   tag 11: signature (64 bytes)

      noc_bytes = create_valid_noc_certificate(
        fabric_id: 0x1122334455667788_u64,
        node_id: 0xAABBCCDDEEFF0011_u64
      )

      cert = Matter::Crypto::MatterCertificate.from_slice(noc_bytes)

      cert.fabric_id.should eq(0x1122334455667788_u64)
      cert.node_id.should eq(0xAABBCCDDEEFF0011_u64)
      cert.noc?.should be_true
    end

    it "parses a root CA certificate" do
      root_bytes = create_valid_root_certificate(
        rcac_id: 0x123456789ABCDEF0_u64
      )

      cert = Matter::Crypto::MatterCertificate.from_slice(root_bytes)

      cert.subject.rcac_id.should eq(0x123456789ABCDEF0_u64)
      cert.root_ca?.should be_true
      cert.noc?.should be_false
    end

    it "extracts public key correctly" do
      public_key = Bytes.new(65) { |i| i == 0 ? 0x04_u8 : (i % 256).to_u8 }
      noc_bytes = create_valid_noc_certificate(
        fabric_id: 1_u64,
        node_id: 1_u64,
        public_key: public_key
      )

      cert = Matter::Crypto::MatterCertificate.from_slice(noc_bytes)

      cert.ec_public_key.should eq(public_key)
    end
  end

  describe "DNAttributes" do
    it "handles optional fields" do
      dn = Matter::Crypto::DNAttributes.new(
        fabric_id: 123_u64,
        node_id: 456_u64
      )

      dn.fabric_id.should eq(123_u64)
      dn.node_id.should eq(456_u64)
      dn.rcac_id.should be_nil
      dn.icac_id.should be_nil
    end
  end
end

# Helper to create a valid Matter NOC certificate for testing
def create_valid_noc_certificate(
  fabric_id : UInt64,
  node_id : UInt64,
  public_key : Bytes? = nil,
) : Bytes
  pub_key = public_key || begin
    key = Bytes.new(65)
    key[0] = 0x04_u8
    (1...65).each { |i| key[i] = i.to_u8 }
    key
  end

  signature = Bytes.new(64, 0xAB_u8)

  # Build subject DN with fabric_id and node_id
  subject = Matter::Crypto::DNAttributes.new(
    fabric_id: fabric_id,
    node_id: node_id
  )

  # Build issuer DN (can be empty or have rcac_id for simplicity)
  issuer = Matter::Crypto::DNAttributes.new(rcac_id: 1_u64)

  cert = Matter::Crypto::MatterCertificate.new(
    serial_number: Bytes[0x01],
    signature_algorithm: 1_u8,
    issuer: issuer,
    not_before: 0_u32,
    not_after: 0xFFFFFFFF_u32,
    subject: subject,
    public_key_algorithm: 1_u8,
    elliptic_curve_id: 1_u8,
    ec_public_key: pub_key,
    signature: signature
  )

  cert.to_slice
end

# Helper to create a valid Matter root certificate for testing
def create_valid_root_certificate(rcac_id : UInt64) : Bytes
  pub_key = Bytes.new(65)
  pub_key[0] = 0x04_u8
  (1...65).each { |i| pub_key[i] = i.to_u8 }

  signature = Bytes.new(64, 0xCD_u8)

  # Root cert has rcac_id in subject
  subject = Matter::Crypto::DNAttributes.new(rcac_id: rcac_id)
  issuer = Matter::Crypto::DNAttributes.new(rcac_id: rcac_id) # Self-signed

  cert = Matter::Crypto::MatterCertificate.new(
    serial_number: Bytes[0x01],
    signature_algorithm: 1_u8,
    issuer: issuer,
    not_before: 0_u32,
    not_after: 0xFFFFFFFF_u32,
    subject: subject,
    public_key_algorithm: 1_u8,
    elliptic_curve_id: 1_u8,
    ec_public_key: pub_key,
    signature: signature
  )

  cert.to_slice
end
