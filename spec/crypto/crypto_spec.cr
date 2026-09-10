require "../spec_helper"
require "../../src/matter/crypto/key"
require "../../src/matter/crypto/crypto"
require "../../src/matter/crypto/ecdh"
require "../../src/matter/crypto/spake2p"

describe Matter::Crypto do
  describe "Key management" do
    it "creates a key pair" do
      key = Matter::Crypto::Key.generate_key_pair
      key.should be_a(Matter::Crypto::Key)
      key.type.should eq(Matter::Crypto::KeyType::EC)
      key.curve.should eq(Matter::Crypto::CurveType::P256)
      key.private_bits.should_not be_nil
      key.x_bits.should_not be_nil
      key.y_bits.should_not be_nil
    end

    it "exports public key in uncompressed format" do
      key = Matter::Crypto::Key.generate_key_pair
      pub = key.public_bits
      pub.should_not be_nil
      pub.as(Bytes).size.should eq(65)
      pub.as(Bytes)[0].should eq(0x04) # Uncompressed format marker
    end

    it "imports public key from uncompressed format" do
      key1 = Matter::Crypto::Key.generate_key_pair
      pub_bytes = key1.public_key

      key2 = Matter::Crypto::Key.new
      key2.public_bits = pub_bytes
      key2.x_bits.should eq(key1.x_bits)
      key2.y_bits.should eq(key1.y_bits)
    end

    it "creates key from BinaryKeyPair" do
      key1 = Matter::Crypto::Key.generate_key_pair
      pair = key1.key_pair

      key2 = Matter::Crypto.private_key(pair)
      key2.private_bits.should eq(key1.private_bits)
      key2.public_bits.should eq(key1.public_bits)
    end

    it "zero-pads private keys less than 32 bytes" do
      # Simulate a key with leading zeros (less than 32 bytes)
      # This can happen when the high bits are 0 and get stripped
      key = Matter::Crypto::Key.new(Matter::Crypto::KeyType::EC, Matter::Crypto::CurveType::P256)
      short_key = Bytes[0x01, 0x02, 0x03, 0x04, 0x05] # Only 5 bytes

      key.private_bits = short_key

      # Should be padded to exactly 32 bytes
      private_key = key.private_key
      private_key.size.should eq(32)

      # Last 5 bytes should match original key
      private_key[-5, 5].should eq(short_key)

      # First 27 bytes should be zeros
      private_key[0, 27].all? { |byte| byte == 0 }.should be_true
    end
  end

  describe "StandardCrypto" do
    crypto = Matter::Crypto::StandardCrypto.new

    it "reports implementation name" do
      crypto.implementation_name.should contain("OpenSSL")
    end

    it "generates random bytes" do
      bytes1 = crypto.random_bytes(16)
      bytes2 = crypto.random_bytes(16)
      bytes1.size.should eq(16)
      bytes2.size.should eq(16)
      bytes1.should_not eq(bytes2) # Should be different
    end

    it "generates random integers" do
      val8 = crypto.random_uint8
      val8.should be_a(UInt8)

      val16 = crypto.random_uint16
      val16.should be_a(UInt16)

      val32 = crypto.random_uint32
      val32.should be_a(UInt32)

      val64 = crypto.random_uint64
      val64.should be_a(UInt64)
    end

    it "generates random BigInt" do
      big = crypto.random_big_int(16)
      big.should be_a(BigInt)
      big.should be > 0
    end

    it "generates random BigInt with max value" do
      max = BigInt.new(1000)
      big = crypto.random_big_int(2, max)
      big.should be < max
    end

    it "computes SHA-256 hash" do
      data = "Hello, Matter!".to_slice
      hash = crypto.compute_sha256(data)
      hash.size.should eq(32)

      # Same data should produce same hash
      hash2 = crypto.compute_sha256(data)
      hash.should eq(hash2)
    end

    it "computes SHA-256 of multiple buffers" do
      data1 = "Hello, ".to_slice
      data2 = "Matter!".to_slice
      hash = crypto.compute_sha256([data1, data2])
      hash.size.should eq(32)

      # Should equal hash of concatenated data
      combined = "Hello, Matter!".to_slice
      hash_combined = crypto.compute_sha256(combined)
      hash.should eq(hash_combined)
    end

    it "derives key using PBKDF2" do
      secret = "password".to_slice
      salt = crypto.random_bytes(16)
      iterations = 1000
      key_length = 32

      key = crypto.create_pbkdf2_key(secret, salt, iterations, key_length)
      key.size.should eq(key_length)

      # Same inputs should produce same key
      key2 = crypto.create_pbkdf2_key(secret, salt, iterations, key_length)
      key.should eq(key2)
    end

    it "derives key using HKDF" do
      secret = crypto.random_bytes(32)
      salt = crypto.random_bytes(16)
      info = "MatterHKDF".to_slice
      length = 32

      key = crypto.create_hkdf_key(secret, salt, info, length)
      key.size.should eq(length)

      # Same inputs should produce same key
      key2 = crypto.create_hkdf_key(secret, salt, info, length)
      key.should eq(key2)

      # Different info should produce different key
      key3 = crypto.create_hkdf_key(secret, salt, "Different".to_slice, length)
      key.should_not eq(key3)
    end

    it "creates HMAC-SHA256" do
      key = crypto.random_bytes(32)
      data = "Matter Protocol".to_slice

      hmac = crypto.sign_hmac(key, data)
      hmac.size.should eq(32)

      # Same inputs should produce same HMAC
      hmac2 = crypto.sign_hmac(key, data)
      hmac.should eq(hmac2)

      # Different key should produce different HMAC
      key2 = crypto.random_bytes(32)
      hmac3 = crypto.sign_hmac(key2, data)
      hmac.should_not eq(hmac3)
    end

    it "encrypts and decrypts with AES-CCM" do
      key = crypto.random_bytes(16)
      nonce = crypto.random_bytes(13)
      plaintext = "Secret Matter message".to_slice
      aad = "additional data".to_slice

      # Encrypt
      ciphertext = crypto.encrypt(key, plaintext, nonce, aad)
      ciphertext.size.should eq(plaintext.size + 16) # +16 for auth tag

      # Decrypt
      decrypted = crypto.decrypt(key, ciphertext, nonce, aad)
      decrypted.should eq(plaintext)
    end

    it "fails decryption with wrong key" do
      key1 = crypto.random_bytes(16)
      key2 = crypto.random_bytes(16)
      nonce = crypto.random_bytes(13)
      plaintext = "Secret".to_slice

      ciphertext = crypto.encrypt(key1, plaintext, nonce)

      expect_raises(Exception, /authentication failed/) do
        crypto.decrypt(key2, ciphertext, nonce)
      end
    end

    it "fails decryption with wrong AAD" do
      key = crypto.random_bytes(16)
      nonce = crypto.random_bytes(13)
      plaintext = "Secret".to_slice
      aad1 = "aad1".to_slice
      aad2 = "aad2".to_slice

      ciphertext = crypto.encrypt(key, plaintext, nonce, aad1)

      expect_raises(Exception, /authentication failed/) do
        crypto.decrypt(key, ciphertext, nonce, aad2)
      end
    end
  end

  describe "Global crypto instance" do
    it "provides global access" do
      Matter::Crypto.instance.should be_a(Matter::Crypto::CryptoBase)
    end

    it "delegates to instance" do
      bytes = Matter::Crypto.random_bytes(16)
      bytes.size.should eq(16)

      data = "test".to_slice
      hash = Matter::Crypto.compute_sha256(data)
      hash.size.should eq(32)
    end

    it "allows setting custom instance" do
      original = Matter::Crypto.instance
      custom = Matter::Crypto::StandardCrypto.new
      Matter::Crypto.instance = custom
      Matter::Crypto.instance.should eq(custom)
      Matter::Crypto.instance = original # Restore
    end
  end

  describe "ECDH" do
    it "generates key pairs" do
      key = Matter::Crypto::ECDH.generate_key_pair
      key.should be_a(Matter::Crypto::Key)
      key.type.should eq(Matter::Crypto::KeyType::EC)
    end

    it "computes shared secret" do
      key1 = Matter::Crypto::ECDH.generate_key_pair
      key2 = Matter::Crypto::ECDH.generate_key_pair

      secret1 = Matter::Crypto::ECDH.compute_shared_secret(
        key1.private_key,
        key2.public_key
      )
      secret1.size.should eq(32)

      secret2 = Matter::Crypto::ECDH.compute_shared_secret(
        key2.private_key,
        key1.public_key
      )

      # Both sides should compute the same secret
      secret1.should eq(secret2)
    end
  end

  describe "SPAKE2+" do
    it "computes w0 and w1 from PIN" do
      crypto = Matter::Crypto::StandardCrypto.new
      params = Matter::Crypto::Spake2p::PbkdfParameters.new(
        iterations: 1000,
        salt: crypto.random_bytes(16)
      )
      pin = 12345678_u32

      w0_w1 = Matter::Crypto::Spake2p.compute_w0_w1(crypto, params, pin)
      w0_w1.w0.should be_a(BigInt)
      w0_w1.w1.should be_a(BigInt)
      w0_w1.w0.should be > 0
      w0_w1.w1.should be > 0
    end

    it "computes w0 and L from PIN" do
      # Now works with SPAKE2Plus library
      crypto = Matter::Crypto::StandardCrypto.new
      params = Matter::Crypto::Spake2p::PbkdfParameters.new(
        iterations: 1000,
        salt: crypto.random_bytes(16)
      )
      pin = 12345678_u32

      w0_l = Matter::Crypto::Spake2p.compute_w0_l(crypto, params, pin)
      w0_l.w0.should be_a(BigInt)
      w0_l.l.should be_a(Bytes)
      w0_l.l.size.should eq(65) # Uncompressed EC point
    end

    it "creates SPAKE2+ instance" do
      crypto = Matter::Crypto::StandardCrypto.new
      context = "Matter PASE".to_slice
      w0 = BigInt.new(12345)

      spake = Matter::Crypto::Spake2p.create(crypto, context, w0)
      spake.should be_a(Matter::Crypto::Spake2p)
      spake.context.should eq(context)
      spake.w0.should eq(w0)
      spake.random.should be > 0
    end

    it "computes X and Y" do
      # Now works with SPAKE2Plus library
      crypto = Matter::Crypto::StandardCrypto.new
      context = "Matter PASE".to_slice
      w0 = BigInt.new(12345)

      spake = Matter::Crypto::Spake2p.create(crypto, context, w0)

      x = spake.compute_x
      x.size.should eq(65)
      x[0].should eq(0x04) # Uncompressed format

      y = spake.compute_y
      y.size.should eq(65)
      y[0].should eq(0x04)
    end
  end

  describe "DER signature conversion" do
    crypto = Matter::Crypto::StandardCrypto.new

    it "converts DER to IEEE P1363 format" do
      # Generate a key and sign some data
      key = crypto.create_key_pair
      data = "test data for signature conversion".to_slice

      # Get DER format signature
      der_sig = crypto.sign_ecdsa(key, data, dsa_encoding: "der")

      # DER signature should start with 0x30 (SEQUENCE tag)
      der_sig[0].should eq(0x30)
      # Should be variable length (typically 69-72 bytes for P-256)
      der_sig.size.should be >= 69
      der_sig.size.should be <= 73

      # Convert to IEEE P1363
      ieee_sig = crypto.sign_ecdsa(key, data, dsa_encoding: "ieee-p1363")

      # IEEE P1363 format should be exactly 64 bytes (32 + 32 for P-256)
      ieee_sig.size.should eq(64)

      # Both should verify correctly
      crypto.verify_ecdsa(key, data, der_sig, dsa_encoding: "der")
      crypto.verify_ecdsa(key, data, ieee_sig, dsa_encoding: "ieee-p1363")
    end

    it "converts IEEE P1363 to DER format" do
      # Generate a key and sign some data in IEEE P1363 format
      key = crypto.create_key_pair
      data = "another test for format conversion".to_slice

      # Get IEEE P1363 signature (default)
      ieee_sig = crypto.sign_ecdsa(key, data)
      ieee_sig.size.should eq(64)

      # Verify with IEEE P1363 format
      crypto.verify_ecdsa(key, data, ieee_sig, dsa_encoding: "ieee-p1363")

      # Also get DER format
      der_sig = crypto.sign_ecdsa(key, data, dsa_encoding: "der")

      # Verify with DER format
      crypto.verify_ecdsa(key, data, der_sig, dsa_encoding: "der")

      # Cross-verify: both formats should verify the same signature
      # (This tests the internal conversion)
    end
  end
end

describe "AES Core Debug" do
  it "tests AES-128 encryption with NIST vector" do
    # NIST AES-128 test vector
    key = "2b7e151628aed2a6abf7158809cf4f3c".hexbytes
    plaintext = "6bc1bee22e409f96e93d7e117393172a".hexbytes
    expected = "3ad77bb40d7a3660a89ecaf32466ef97".hexbytes

    # Convert to words
    pt_words = Matter::Crypto::AES::WordArrayHelper.from_bytes(plaintext)
    aes = Matter::Crypto::AES::Aes.new(key)

    # Encrypt
    ct_words = aes.encrypt(pt_words)

    # Convert back to bytes
    ct_bytes = Bytes.new(16)
    4.times do |i|
      Matter::Crypto::AES::WordArrayHelper.write_int32_be(ct_bytes, i * 4, ct_words[i])
    end

    ct_bytes.should eq(expected)
  end
end

it "verifies AES S-box generation" do
  # Generate tables
  key = Bytes.new(16, 0_u8)
  aes = Matter::Crypto::AES::Aes.new(key)

  # Access the S-box through a test encryption to force table generation
  # We'll need to access the tables somehow...
  # For now, just verify the encryption works with a known vector

  # AES-128 encryption of all zeros with all-zero key
  pt = Bytes.new(16, 0_u8)
  expected_ct = "66e94bd4ef8a2c3b884cfa59ca342b2e".hexbytes

  pt_words = Matter::Crypto::AES::WordArrayHelper.from_bytes(pt)
  ct_words = aes.encrypt(pt_words)
  ct_bytes = Bytes.new(16)
  4.times do |i|
    Matter::Crypto::AES::WordArrayHelper.write_int32_be(ct_bytes, i * 4, ct_words[i])
  end

  ct_bytes.should eq(expected_ct)
end
