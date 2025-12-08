require "./spec_helper"
require "../src/matter/crypto/crypto"

# Ported from matter.js StandardCryptoTest.ts
# Tests crypto implementation compatibility with matter.js
describe "StandardCrypto Compatibility" do
  crypto = Matter::Crypto::StandardCrypto.new

  # Test vectors from matter.js
  key : Bytes = "abf227feffea8c38e688ddcbffc459f1".hexbytes
  encrypted_data : Bytes = "c4527bd6965518e8382edbbd28f27f42492d0766124f9961a772".hexbytes
  plain_data : Bytes = "03104f3c0000e98ceb00".hexbytes
  nonce : Bytes = "000ce399000000000000000000".hexbytes
  additional_auth_data : Bytes = "00456a000ce39900".hexbytes

  key_2 : Bytes = "4e4c1353a133397f7a7557c1fbd9ca38".hexbytes
  encrypted_data_2 : Bytes = "cb50871ccd35d430b9d9f9f2a50c07f6b0e68ac78f671de670bc6622c3538b10184ac58e70475301edae3d45dd169bfad3a4367cb8eb821676b162".hexbytes
  plain_data_2 : Bytes = "0609523c01000fe399001528003601153501370024000024013e24020b1835012400001818181824ff0118".hexbytes
  nonce_2 : Bytes = "00ec8ceb000000000000000000".hexbytes
  additional_auth_data_2 : Bytes = "00c7a200ec8ceb00".hexbytes

  private_key : Bytes = "727F1005CBA47ED7822A9D930943621617CFD3B79D9AF528B801ECF9F1992204".hexbytes
  public_key : Bytes = "0462e2b6e1baff8d74a6fd8216c4cb67a3363a31e691492792e61aee610261481396725ef95e142686ba98f339b0ff65bc338bec7b9e8be0bdf3b2774982476220".hexbytes

  describe "AES-CCM encryption/decryption" do
    it "encrypts (test vector 2)" do
      result = crypto.encrypt(key_2, plain_data_2, nonce_2, additional_auth_data_2)
      result.hexstring.should eq(encrypted_data_2.hexstring)
    end

    it "decrypts (test vector 1)" do
      result = crypto.decrypt(key, encrypted_data, nonce, additional_auth_data)
      result.hexstring.should eq(plain_data.hexstring)
    end
  end

  describe "SHA-256" do
    it "creates correct EC hash" do
      input = "047e708746f3d9fb3265a73f0c69ad18cdd48860d7956731eb72873f3d09c17b667c13737017574bf3f826239ff27cdb52fb3e69ff4a06ffd2cbccfdc695ff6096".hexbytes
      hash = crypto.compute_sha256(input)
      hash.hexstring.should eq("582418375f09bff6b3bbb2421206ad6aec3c79ff2602f95a68d3e4d23bebe36f")
    end
  end

  describe "HKDF" do
    it "performs correct HKDF computation" do
      # This test is CRITICAL for verifying session key derivation
      secret = "dbc94ee08a5ee674b4c1bfa7b05bfd339faa0cd67853a10d367e9790a6d064af5ea3650da79a228adfaf771970f5f31cdc3f0ebde443640185a6e0f488f0a243".hexbytes
      salt = "0000000000000001".hexbytes
      info = "436f6d70726573736564466162726963".hexbytes # "CompressedFabric"

      result = crypto.create_hkdf_key(secret, salt, info, 8)
      result.hexstring.should eq("ab4a2b4fba653117")
    end
  end

  describe "ECDH" do
    it "computes correct DH shared secret" do
      ecdh_key1 = crypto.create_key_pair
      ecdh_key2 = crypto.create_key_pair

      secret1 = crypto.generate_dh_secret(ecdh_key1, ecdh_key2)
      secret2 = crypto.generate_dh_secret(ecdh_key2, ecdh_key1)

      secret1.should eq(secret2)
      secret1.size.should eq(32)
    end
  end

  describe "ECDSA signing" do
    it "signs & verifies with raw keys" do
      # Use test vectors from matter.js
      ecdsa_key = Matter::Crypto::Key.new(Matter::Crypto::KeyType::EC, Matter::Crypto::CurveType::P256)
      ecdsa_key.private_bits = private_key
      ecdsa_key.public_bits = public_key

      # Sign some data
      test_data = "test data for signing".to_slice
      signature = crypto.sign_ecdsa(ecdsa_key, test_data)

      # Signature should be 64 bytes for P-256 in IEEE P1363 format
      signature.size.should eq(64)

      # Verify the signature - verify_ecdsa raises on failure, returns nil on success
      crypto.verify_ecdsa(ecdsa_key, test_data, signature)
    end

    it "generates a working DSA key pair" do
      # verify_ecdsa raises on failure, returns nil on success
      ecdsa_key = crypto.create_key_pair
      signature = crypto.sign_ecdsa(ecdsa_key, encrypted_data)

      # Should not raise - verification succeeds
      crypto.verify_ecdsa(ecdsa_key, encrypted_data, signature)
    end
  end
end
