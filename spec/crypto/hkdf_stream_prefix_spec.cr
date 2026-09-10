require "../spec_helper"
require "../../src/matter/crypto/crypto"

# PASE derives SessionKeys as HKDF(Ke, salt="", info="SessionKeys", length=48):
# I2R key (16 bytes), R2I key (16 bytes) and AttestationChallenge (16 bytes).
# HKDF-Expand is a deterministic stream, so requesting 48 bytes must leave the
# first 32 bytes (the two session keys) identical to a 32-byte derivation.
describe "HKDF output stream prefix" do
  session_keys_info = "SessionKeys".to_slice
  key_length = Matter::Crypto::CRYPTO_SYMMETRIC_KEY_LENGTH
  two_key_length = key_length * 2
  three_key_length = key_length * 3
  shared_secret = ("01417b606624ae9a7235e9afaef2d747" + "0" * 32).hexbytes

  it "leaves the I2R key unchanged when 48 bytes are requested instead of 32" do
    crypto = Matter::Crypto::StandardCrypto.new

    keys_32 = crypto.create_hkdf_key(shared_secret, Bytes.new(0), session_keys_info, two_key_length)
    keys_48 = crypto.create_hkdf_key(shared_secret, Bytes.new(0), session_keys_info, three_key_length)

    keys_48[0, key_length].should eq(keys_32[0, key_length])
  end

  it "leaves the R2I key unchanged when 48 bytes are requested instead of 32" do
    crypto = Matter::Crypto::StandardCrypto.new

    keys_32 = crypto.create_hkdf_key(shared_secret, Bytes.new(0), session_keys_info, two_key_length)
    keys_48 = crypto.create_hkdf_key(shared_secret, Bytes.new(0), session_keys_info, three_key_length)

    keys_48[key_length, key_length].should eq(keys_32[key_length, key_length])
  end
end
