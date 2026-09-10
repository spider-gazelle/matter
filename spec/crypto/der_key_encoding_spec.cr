require "../spec_helper"
require "../../src/matter/crypto/crypto"
require "../../src/matter/crypto/key"

describe "DER Format Generation" do
  crypto = Matter::Crypto::StandardCrypto.new

  # Test vectors from crypto_compatibility_spec
  private_key_bytes = "727F1005CBA47ED7822A9D930943621617CFD3B79D9AF528B801ECF9F1992204".hexbytes
  public_key_bytes = "0462e2b6e1baff8d74a6fd8216c4cb67a3363a31e691492792e61aee610261481396725ef95e142686ba98f339b0ff65bc338bec7b9e8be0bdf3b2774982476220".hexbytes

  it "generates valid SEC1 DER for EC private key" do
    # Build our DER
    our_der = crypto.build_ec_private_key_der(private_key_bytes, public_key_bytes)

    # Try to load it
    pem = crypto.der_to_pem(our_der, "EC PRIVATE KEY")

    pkey = OpenSSL::PKey::EC.new(pem)
    pkey.private?.should be_true
  end

  it "generates valid SPKI DER for EC public key" do
    # Build our DER
    our_der = crypto.build_ec_public_key_der(public_key_bytes)

    # Try to load it
    pem = crypto.der_to_pem(our_der, "PUBLIC KEY")

    pkey = OpenSSL::PKey::EC.new(pem)
    pkey.public?.should be_true
  end
end
