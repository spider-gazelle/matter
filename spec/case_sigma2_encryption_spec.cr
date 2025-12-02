require "./spec_helper"
require "../src/matter/session/case/case"
require "../src/matter/session/case/definitions"
require "../src/matter/crypto/crypto"

# Compatibility tests for CASE Sigma2 encryption flow
# Test vectors generated from matter.js to ensure byte-level compatibility
# This tests: salt construction, HKDF key derivation, TBE_Data2 encoding, and AES-CCM encryption

describe "CASE Sigma2 Encryption" do
  # Test vectors from matter.js test_sigma2_encryption.mjs
  it "matches matter.js salt construction" do
    ipk = "00112233445566778899aabbccddeeff".hexbytes
    responder_random = "0102030405060708091011121314151617181920212223242526272829303132".hexbytes
    responder_ecdh_public_key = "040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40".hexbytes
    sigma1_bytes = "15300120".hexbytes

    # Expected values from matter.js
    expected_sigma1_hash = "f932046a68d85eda2a50c5bf0a56ca7134b0cf22cd798df236eaff7099771a68".hexbytes
    expected_salt = "00112233445566778899aabbccddeeff0102030405060708091011121314151617181920212223242526272829303132040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40f932046a68d85eda2a50c5bf0a56ca7134b0cf22cd798df236eaff7099771a68".hexbytes

    crypto = Matter::Crypto::StandardCrypto.new

    # Compute SHA256 of sigma1_bytes
    sigma1_hash = crypto.compute_sha256(sigma1_bytes)
    sigma1_hash.should eq(expected_sigma1_hash)

    # Build salt: IPK + responderRandom + responderEcdhPublicKey + SHA256(sigma1_bytes)
    salt = IO::Memory.new
    salt.write(ipk)
    salt.write(responder_random)
    salt.write(responder_ecdh_public_key)
    salt.write(sigma1_hash)
    salt_bytes = salt.to_slice

    salt_bytes.should eq(expected_salt)
  end

  it "matches matter.js HKDF key derivation" do
    shared_secret = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".hexbytes
    salt = "00112233445566778899aabbccddeeff0102030405060708091011121314151617181920212223242526272829303132040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40f932046a68d85eda2a50c5bf0a56ca7134b0cf22cd798df236eaff7099771a68".hexbytes
    info = "Sigma2".to_slice

    expected_key = "3e1fdb37952e097fda2971c2d1bba82d".hexbytes

    crypto = Matter::Crypto::StandardCrypto.new
    sigma2_key = crypto.create_hkdf_key(shared_secret, salt, info, 16)

    sigma2_key.should eq(expected_key)
  end

  it "matches matter.js TBE_Data2 encoding" do
    noc = "1530010101".hexbytes
    icac = "15300202".hexbytes
    signature = "50515253545556575859505152535455565758595051525354555657585950515253545556575859505152535455565758595051525354555657585950515253".hexbytes
    resumption_id = "aabbccddeeff00112233445566778899".hexbytes

    expected_tbe_data2 = "1530010515300101013002041530020230034050515253545556575859505152535455565758595051525354555657585950515253545556575859505152535455565758595051525354555657585950515253300410aabbccddeeff0011223344556677889918".hexbytes

    encrypted_data = Matter::Session::Case::Definitions::EncryptedDataSigma2.new(
      responder_noc: noc,
      responder_icac: icac,
      signature: signature,
      resumption_id: resumption_id
    )

    result = encrypted_data.to_bytes
    result.should eq(expected_tbe_data2)
  end

  it "matches matter.js AES-CCM encryption" do
    sigma2_key = "3e1fdb37952e097fda2971c2d1bba82d".hexbytes
    tbe_data2 = "1530010515300101013002041530020230034050515253545556575859505152535455565758595051525354555657585950515253545556575859505152535455565758595051525354555657585950515253300410aabbccddeeff0011223344556677889918".hexbytes
    nonce = "NCASE_Sigma2N".to_slice

    expected_encrypted = "2d3cf858c743d081a8af3713fc165d22db41608fa50c32a174c319bf5589963068f71064c239616d42a807d6c974de3c7c48418d57eef058aedcad27dcd3cb04ab10d056b9e05cb6b8c8efa9515da0a84dc2bfaea2f9a37244e9e8a7b825e79a1c95de127248ec9472aa330bc0beedc8c1315575ce1620".hexbytes

    crypto = Matter::Crypto::StandardCrypto.new
    encrypted = crypto.encrypt(sigma2_key, tbe_data2, nonce)

    encrypted.should eq(expected_encrypted)
  end

  it "matches matter.js full Sigma2 encryption flow" do
    # All inputs
    ipk = "00112233445566778899aabbccddeeff".hexbytes
    responder_random = "0102030405060708091011121314151617181920212223242526272829303132".hexbytes
    responder_ecdh_public_key = "040102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40".hexbytes
    sigma1_bytes = "15300120".hexbytes
    shared_secret = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".hexbytes

    noc = "1530010101".hexbytes
    icac = "15300202".hexbytes
    signature = "50515253545556575859505152535455565758595051525354555657585950515253545556575859505152535455565758595051525354555657585950515253".hexbytes
    resumption_id = "aabbccddeeff00112233445566778899".hexbytes

    expected_encrypted = "2d3cf858c743d081a8af3713fc165d22db41608fa50c32a174c319bf5589963068f71064c239616d42a807d6c974de3c7c48418d57eef058aedcad27dcd3cb04ab10d056b9e05cb6b8c8efa9515da0a84dc2bfaea2f9a37244e9e8a7b825e79a1c95de127248ec9472aa330bc0beedc8c1315575ce1620".hexbytes

    crypto = Matter::Crypto::StandardCrypto.new

    # Step 1: Build salt
    sigma1_hash = crypto.compute_sha256(sigma1_bytes)
    salt = IO::Memory.new
    salt.write(ipk)
    salt.write(responder_random)
    salt.write(responder_ecdh_public_key)
    salt.write(sigma1_hash)

    # Step 2: Derive key
    sigma2_key = crypto.create_hkdf_key(shared_secret, salt.to_slice, "Sigma2".to_slice, 16)

    # Step 3: Encode TBE_Data2
    encrypted_data = Matter::Session::Case::Definitions::EncryptedDataSigma2.new(
      responder_noc: noc,
      responder_icac: icac,
      signature: signature,
      resumption_id: resumption_id
    )
    tbe_data2 = encrypted_data.to_bytes

    # Step 4: Encrypt
    encrypted = crypto.encrypt(sigma2_key, tbe_data2, "NCASE_Sigma2N".to_slice)

    encrypted.should eq(expected_encrypted)
  end
end
