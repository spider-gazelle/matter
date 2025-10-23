require "./spec_helper"
require "../src/matter/crypto/key"
require "../src/matter/crypto/crypto"
require "../src/matter/crypto/ecdh"
require "../src/matter/crypto/spake2p"

# Test vector structure for AES-CCM tests
struct CcmTestVector
  property name : String
  property key : String
  property nonce : String
  property adata : String
  property pt : String
  property ct : String
  property tag : String

  def initialize(@name, @key, @nonce, @adata, @pt, @ct, @tag)
  end
end

# Test vectors from matter.js to ensure compatibility
# These test the currently implemented crypto features
describe "Matter::Crypto Compatibility (matter.js test vectors)" do
  describe "StandardCrypto test vectors" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Test vectors from matter.js StandardCryptoTest.ts
    describe "HKDF computation" do
      it "performs correct HKDF computation matching matter.js" do
        secret = "dbc94ee08a5ee674b4c1bfa7b05bfd339faa0cd67853a10d367e9790a6d064af5ea3650da79a228adfaf771970f5f31cdc3f0ebde443640185a6e0f488f0a243".hexbytes
        salt = "0000000000000001".hexbytes
        info = "436f6d70726573736564466162726963".hexbytes # "CompressedFabric"

        hash = crypto.create_hkdf_key(secret, salt, info, 8)

        hash.hexstring.should eq("ab4a2b4fba653117")
      end

      it "derives encryption keys with HKDF" do
        # Test HKDF with different parameters
        secret = crypto.random_bytes(32)
        salt = crypto.random_bytes(16)
        info = "SessionKeys".to_slice

        key1 = crypto.create_hkdf_key(secret, salt, info, 16)
        key2 = crypto.create_hkdf_key(secret, salt, info, 32)
        key3 = crypto.create_hkdf_key(secret, salt, info, 48)

        key1.size.should eq(16)
        key2.size.should eq(32)
        key3.size.should eq(48)

        # First 16 bytes of key2 should match key1
        key2[0, 16].should eq(key1)
      end
    end

    describe "SHA-256 hashing" do
      it "creates correct EC hash matching matter.js" do
        data = "047e708746f3d9fb3265a73f0c69ad18cdd48860d7956731eb72873f3d09c17b667c13737017574bf3f826239ff27cdb52fb3e69ff4a06ffd2cbccfdc695ff6096".hexbytes

        hash = crypto.compute_sha256(data)

        hash.hexstring.should eq("582418375f09bff6b3bbb2421206ad6aec3c79ff2602f95a68d3e4d23bebe36f")
      end

      it "hashes multiple buffers correctly" do
        # Test SHA-256 with multiple input buffers
        part1 = "Hello, ".to_slice
        part2 = "Matter".to_slice
        part3 = "!".to_slice

        hash_combined = crypto.compute_sha256("Hello, Matter!".to_slice)
        hash_parts = crypto.compute_sha256([part1, part2, part3])

        hash_parts.should eq(hash_combined)
      end
    end

    describe "PBKDF2 key derivation" do
      it "derives keys with correct iterations" do
        password = "matter123".to_slice
        salt = crypto.random_bytes(16)

        # Test different iteration counts
        key_1k = crypto.create_pbkdf2_key(password, salt, 1000, 32)
        key_10k = crypto.create_pbkdf2_key(password, salt, 10000, 32)

        key_1k.size.should eq(32)
        key_10k.size.should eq(32)
        key_1k.should_not eq(key_10k) # Different iterations = different keys
      end

      it "produces consistent results" do
        password = "test_password".to_slice
        salt = "fixed_salt_123456".to_slice
        iterations = 1000

        key1 = crypto.create_pbkdf2_key(password, salt, iterations, 32)
        key2 = crypto.create_pbkdf2_key(password, salt, iterations, 32)

        key1.should eq(key2)
      end
    end

    describe "HMAC-SHA256" do
      it "produces consistent HMAC signatures" do
        key = "secret_key_12345".to_slice
        data = "data to sign".to_slice

        hmac1 = crypto.sign_hmac(key, data)
        hmac2 = crypto.sign_hmac(key, data)

        hmac1.should eq(hmac2)
        hmac1.size.should eq(32)
      end

      it "produces different signatures for different keys" do
        key1 = "key1".to_slice
        key2 = "key2".to_slice
        data = "same data".to_slice

        hmac1 = crypto.sign_hmac(key1, data)
        hmac2 = crypto.sign_hmac(key2, data)

        hmac1.should_not eq(hmac2)
      end

      it "produces different signatures for different data" do
        key = "same_key".to_slice
        data1 = "data1".to_slice
        data2 = "data2".to_slice

        hmac1 = crypto.sign_hmac(key, data1)
        hmac2 = crypto.sign_hmac(key, data2)

        hmac1.should_not eq(hmac2)
      end
    end

    describe "Random number generation" do
      it "generates cryptographically random bytes" do
        bytes1 = crypto.random_bytes(32)
        bytes2 = crypto.random_bytes(32)
        bytes3 = crypto.random_bytes(32)

        bytes1.size.should eq(32)
        bytes2.size.should eq(32)
        bytes3.size.should eq(32)

        # Should be different (extremely unlikely to be same)
        bytes1.should_not eq(bytes2)
        bytes2.should_not eq(bytes3)
        bytes1.should_not eq(bytes3)
      end

      it "generates random BigInts within range" do
        max = BigInt.new(1000)

        10.times do
          random = crypto.random_big_int(2, max)
          random.should be < max
          random.should be >= 0
        end
      end

      it "generates random integers of different sizes" do
        val8 = crypto.random_uint8
        val16 = crypto.random_uint16
        val32 = crypto.random_uint32
        val64 = crypto.random_uint64

        val8.should be_a(UInt8)
        val16.should be_a(UInt16)
        val32.should be_a(UInt32)
        val64.should be_a(UInt64)
      end
    end
  end

  describe "Key test vectors from matter.js" do
    # Test vectors from matter.js KeyTest.ts
    describe "SEC1 key format" do
      it "decodes SEC1 private key" do
        sec1 = "30770201010420aef3484116e9481ec57be0472df41bf499064e5024ad869eca5e889802d48075a00a06082a8648ce3d030107a144034200043c398922452b55caf389c25bd1bca4656952ccb90e8869249ad8474653014cbf95d687965e036b521c51037e6b8cedefca1eb44046694fa08882eed6519decba".hexbytes

        key = Matter::Crypto::Key.new
        key.import_sec1(sec1)

        key.type.should eq(Matter::Crypto::KeyType::EC)
        key.curve.should eq(Matter::Crypto::CurveType::P256)
        key.private_key.size.should eq(32)
        key.public_key.size.should eq(65)
      end
    end

    describe "PKCS#8 key format" do
      it "decodes PKCS#8 private key" do
        pkcs8 = "308141020100301306072a8648ce3d020106082a8648ce3d030107042730250201010420727F1005CBA47ED7822A9D930943621617CFD3B79D9AF528B801ECF9F1992204".hexbytes

        key = Matter::Crypto::Key.new
        key.import_pkcs8(pkcs8)

        key.type.should eq(Matter::Crypto::KeyType::EC)
        key.curve.should eq(Matter::Crypto::CurveType::P256)
        key.private_key.size.should eq(32)
        key.public_key.size.should eq(65)
      end
    end

    describe "SPKI key format" do
      it "decodes SPKI public key" do
        spki = "3059301306072a8648ce3d020106082a8648ce3d0301070342000462e2b6e1baff8d74a6fd8216c4cb67a3363a31e691492792e61aee610261481396725ef95e142686ba98f339b0ff65bc338bec7b9e8be0bdf3b2774982476220".hexbytes

        key = Matter::Crypto::Key.new
        key.import_spki(spki)

        key.type.should eq(Matter::Crypto::KeyType::EC)
        key.curve.should eq(Matter::Crypto::CurveType::P256)
        key.public_key.size.should eq(65)
      end
    end

    describe "Public key format" do
      it "decodes uncompressed public key" do
        public_key = "0410ef02a81a87b68121fba8d31978f807a317e50aa8a828446828914b933de8edd4a5c39c9ff71a4ce3647fd7f62653b7d2495fcba4c0f47f876880039e07204a".hexbytes

        key = Matter::Crypto::Key.new
        key.public_bits = public_key

        key.type.should eq(Matter::Crypto::KeyType::EC)
        key.curve.should eq(Matter::Crypto::CurveType::P256)
        key.x_bits.should_not be_nil
        key.y_bits.should_not be_nil
        key.x_bits.not_nil!.size.should eq(32)
        key.y_bits.not_nil!.size.should eq(32)
      end
    end

    describe "Key generation" do
      it "generates working EC key pairs" do
        key = Matter::Crypto::Key.generate_key_pair

        key.type.should eq(Matter::Crypto::KeyType::EC)
        key.curve.should eq(Matter::Crypto::CurveType::P256)
        key.private_bits.should_not be_nil
        key.x_bits.should_not be_nil
        key.y_bits.should_not be_nil

        key.private_bits.not_nil!.size.should eq(32)
        key.public_key.size.should eq(65)
        key.public_key[0].should eq(0x04) # Uncompressed format
      end

      it "generates unique keys" do
        key1 = Matter::Crypto::Key.generate_key_pair
        key2 = Matter::Crypto::Key.generate_key_pair
        key3 = Matter::Crypto::Key.generate_key_pair

        key1.private_bits.should_not eq(key2.private_bits)
        key2.private_bits.should_not eq(key3.private_bits)
        key1.public_key.should_not eq(key2.public_key)
      end
    end
  end

  describe "SPAKE2+ test vectors from matter.js" do
    crypto = Matter::Crypto::StandardCrypto.new

    describe "SPAKE2+ draft-01 test vectors" do
      # Test vectors from https://datatracker.ietf.org/doc/html/draft-bar-cfrg-spake2plus-01
      context = "SPAKE2+-P256-SHA256-HKDF draft-01".to_slice
      w0 = BigInt.new("e6887cf9bdfb7579c69bf47928a84514b5e355ac034863f7ffaf4390e67d798c", 16)
      w1 = BigInt.new("24b5ae4abda868ec9336ffc3b78ee31c5755bef1759227ef5372ca139b94e512", 16)
      l = "0495645cfb74df6e58f9748bb83a86620bab7c82e107f57d6870da8cbcb2ff9f7063a14b6402c62f99afcb9706a4d1a143273259fe76f1c605a3639745a92154b9".hexbytes
      x = BigInt.new("5b478619804f4938d361fbba3a20648725222f0a54cc4c876139efe7d9a21786", 16)
      y = BigInt.new("766770dad8c8eecba936823c0aed044b8c3c4f7655e8beec44a15dcbcaf78e5e", 16)
      expected_x = "04a6db23d001723fb01fcfc9d08746c3c2a0a3feff8635d29cad2853e7358623425cf39712e928054561ba71e2dc11f300f1760e71eb177021a8f85e78689071cd".hexbytes
      expected_y = "04390d29bf185c3abf99f150ae7c13388c82b6be0c07b1b8d90d26853e84374bbdc82becdb978ca3792f472424106a2578012752c11938fcf60a41df75ff7cf947".hexbytes
      expected_ke = "ea3276d68334576097e04b19ee5a3a8b".hexbytes
      expected_h_ay = "71d9412779b6c45a2c615c9df3f1fd93dc0aaf63104da8ece4aa1b5a3a415fea".hexbytes
      expected_h_bx = "095dc0400355cc233fde7437811815b3c1524aae80fd4e6810cf531cf11d20e3".hexbytes

      it "generates X (prover)" do
        # Now works with SPAKE2Plus library
        spake2p_initiator = Matter::Crypto::Spake2p.new(crypto, context, x, w0)
        result = spake2p_initiator.compute_x
        result.should eq(expected_x)
      end

      it "generates Y (verifier)" do
        # Now works with SPAKE2Plus library
        spake2p_receiver = Matter::Crypto::Spake2p.new(crypto, context, y, w0)
        result = spake2p_receiver.compute_y
        result.should eq(expected_y)
      end

      it "generates shared secret for initiator" do
        # Now works with SPAKE2Plus library
        spake2p_initiator = Matter::Crypto::Spake2p.new(crypto, context, x, w0)
        result = spake2p_initiator.compute_secret_and_verifiers_from_y(w1, expected_x, expected_y)

        result.ke.should eq(expected_ke)
        result.h_ay.should eq(expected_h_ay)
        result.h_bx.should eq(expected_h_bx)
      end

      it "generates shared secret for receiver" do
        # Now works with SPAKE2Plus library
        spake2p_receiver = Matter::Crypto::Spake2p.new(crypto, context, y, w0)
        result = spake2p_receiver.compute_secret_and_verifiers_from_x(l, expected_x, expected_y)

        result.ke.should eq(expected_ke)
        result.h_ay.should eq(expected_h_ay)
        result.h_bx.should eq(expected_h_bx)
      end
    end

    describe "SPAKE2+ context hash" do
      it "generates the correct context hash for CHIP PAKE" do
        # Test data captured from Project CHIP
        context = [
          "434849502050414b4520563120436f6d6d697373696f6e696e67".hexbytes, # "CHIP PAKE V1 Commissioning"
          "15300120b2901e92036f7bca007a3a1bf24bd71f18772105e83479c92b7a8af35e8182742502498d240300280435052501881325022c011818".hexbytes,
          "15300120b2901e92036f7bca007a3a1bf24bd71f18772105e83479c92b7a8af35e81827430022008070f685f2077779b824adf91e4bab6253b9d1a3c0f6615c6d447780f0feef325039c8d35042501e803300220163f8501fbbc0e6a8f69a9b999d038ca388ecffccc18fe259c4253f26e494dda1835052501881325022c011818".hexbytes,
        ]

        result = crypto.compute_sha256(context)

        result.hexstring.should eq("c49718b0275b6f81fd6a081f6c34c5833382b75b3bd997895d13a51c71a02855")
      end
    end

    describe "SPAKE2+ w0/w1 computation" do
      it "computes w0 and w1 from PIN" do
        params = Matter::Crypto::Spake2p::PbkdfParameters.new(
          iterations: 1000,
          salt: "test_salt_123456".to_slice
        )
        pin = 12345678_u32

        result = Matter::Crypto::Spake2p.compute_w0_w1(crypto, params, pin)

        result.w0.should be_a(BigInt)
        result.w1.should be_a(BigInt)
        result.w0.should be > 0
        result.w1.should be > 0

        # w0 and w1 should be different
        result.w0.should_not eq(result.w1)
      end

      it "produces consistent w0/w1 for same inputs" do
        params = Matter::Crypto::Spake2p::PbkdfParameters.new(
          iterations: 2000,
          salt: "fixed_salt".to_slice
        )
        pin = 20202021_u32

        result1 = Matter::Crypto::Spake2p.compute_w0_w1(crypto, params, pin)
        result2 = Matter::Crypto::Spake2p.compute_w0_w1(crypto, params, pin)

        result1.w0.should eq(result2.w0)
        result1.w1.should eq(result2.w1)
      end

      it "produces different w0/w1 for different PINs" do
        params = Matter::Crypto::Spake2p::PbkdfParameters.new(
          iterations: 1000,
          salt: "salt".to_slice
        )

        result1 = Matter::Crypto::Spake2p.compute_w0_w1(crypto, params, 11111111_u32)
        result2 = Matter::Crypto::Spake2p.compute_w0_w1(crypto, params, 22222222_u32)

        result1.w0.should_not eq(result2.w0)
        result1.w1.should_not eq(result2.w1)
      end
    end
  end

  describe "AES-CCM test vectors from matter.js" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Test vectors from matter.js StandardCryptoTest.ts
    key = "abf227feffea8c38e688ddcbffc459f1".hexbytes
    encrypted_data = "c4527bd6965518e8382edbbd28f27f42492d0766124f9961a772".hexbytes
    plain_data = "03104f3c0000e98ceb00".hexbytes
    nonce = "000ce399000000000000000000".hexbytes
    aad = "00456a000ce39900".hexbytes

    key_2 = "4e4c1353a133397f7a7557c1fbd9ca38".hexbytes
    encrypted_data_2 = "cb50871ccd35d430b9d9f9f2a50c07f6b0e68ac78f671de670bc6622c3538b10184ac58e70475301edae3d45dd169bfad3a4367cb8eb821676b162".hexbytes
    plain_data_2 = "0609523c01000fe399001528003601153501370024000024013e24020b1835012400001818181824ff0118".hexbytes
    nonce_2 = "00ec8ceb000000000000000000".hexbytes
    aad_2 = "00c7a200ec8ceb00".hexbytes

    it "encrypts data matching matter.js" do
      result = crypto.encrypt(key_2, plain_data_2, nonce_2, aad_2)
      result.should eq(encrypted_data_2)
    end

    it "decrypts data matching matter.js" do
      result = crypto.decrypt(key, encrypted_data, nonce, aad)
      result.should eq(plain_data)
    end
  end

  describe "ECDSA test vectors" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Test vectors from matter.js
    private_key_bytes = "727F1005CBA47ED7822A9D930943621617CFD3B79D9AF528B801ECF9F1992204".hexbytes
    public_key_bytes = "0462e2b6e1baff8d74a6fd8216c4cb67a3363a31e691492792e61aee610261481396725ef95e142686ba98f339b0ff65bc338bec7b9e8be0bdf3b2774982476220".hexbytes
    data_to_sign = "c4527bd6965518e8382edbbd28f27f42492d0766124f9961a772".hexbytes

    it "signs and verifies with raw keys" do
      private_key = Matter::Crypto.private_key(private_key_bytes)
      private_key.public_bits = public_key_bytes # Set public key for signing

      public_key = Matter::Crypto.public_key(public_key_bytes)

      signature = crypto.sign_ecdsa(private_key, data_to_sign)
      crypto.verify_ecdsa(public_key, data_to_sign, signature)
      # Should not raise
    end

    it "generates working key pair for signing" do
      key = crypto.create_key_pair
      data = "test data".to_slice

      signature = crypto.sign_ecdsa(key, data)
      crypto.verify_ecdsa(key, data, signature)
      # Should not raise
    end
  end

  describe "ECDH test vectors" do
    crypto = Matter::Crypto::StandardCrypto.new

    it "computes correct DH shared secret" do
      key1 = crypto.create_key_pair
      key2 = crypto.create_key_pair

      secret1 = crypto.generate_dh_secret(key1, Matter::Crypto.public_key(key2.public_key))
      secret2 = crypto.generate_dh_secret(key2, Matter::Crypto.public_key(key1.public_key))

      secret1.should eq(secret2)
      secret1.size.should eq(32)
    end
  end

  describe "AES-CCM NIST test vectors (from matter.js)" do
    crypto = Matter::Crypto::StandardCrypto.new

    # NIST test vectors that adhere to Matter specification constraints
    # (13-byte nonce, 16-byte tag)
    vectors = [
      CcmTestVector.new(
        "NIST tcId 0",
        "0953fa93e7caac9638f58820220a398e",
        "00800000011201000012345678",
        "",
        "fffd034b50057e400000010000",
        "b5e5bfdacbaf6cb7fb6bff871f",
        "b0d6dd827d35bf372fa6425dcd17d356"
      ),
      CcmTestVector.new(
        "NIST tcId 1",
        "0953fa93e7caac9638f58820220a398e",
        "00800148202345000012345678",
        "",
        "120104320308ba072f",
        "79d7dbc0c9b4d43eeb",
        "281508e50d58dbbd27c39597800f4733"
      ),
      CcmTestVector.new(
        "NIST tcId 2",
        "0953fa93e7caac9638f58820220a398e",
        "00802b38322fe3000012345678",
        "",
        "120104fa0205a6000a",
        "53273086b8c5ee00bd",
        "d52b87a8ce6290a772d472b8c62bdc13"
      ),
      CcmTestVector.new(
        "NIST tcId 3",
        "be635105434859f484fc798e043ce40e",
        "00800000021201000012345678",
        "",
        "23450100",
        "b0e5d0ad",
        "6078e0ddbb7cd43faea57c7051e5b4ae"
      ),
      CcmTestVector.new(
        "NIST tcId 4",
        "be635105434859f484fc798e043ce40e",
        "00800148342345000012345678",
        "",
        "120102001234567800",
        "5c39da1792b1fee9ec",
        "a9233958aced64f2343b9d610e876440"
      ),
      CcmTestVector.new(
        "NIST tcId 10 (with AAD)",
        "63964771734fbd76e3b40519d1d94a48",
        "010007080d1234973612345677",
        "f4a002c7fb1e4ca0a469a021de0db875",
        "ea0a00576f726c64",
        "de1547118463123e",
        "14604c1ddb4f5987064b1736f3923962"
      ),
      CcmTestVector.new(
        "Matter message payload 1",
        "bacb178b2588443d5d5b1e4559e7accc",
        "00221453000000000000000000",
        "001d350022145300",
        "05028d040100153600172403312504fcff18172402002403302404001817240200240330240401181724020024033024040218172402002403302404031817240200240328240402181724020024032824040418172403312404031818290324ff0118",
        "ec2b931025dada82ed67521c966d2454d131a271023be699e4e2796650f568e590fd9b65f456c720a60a0da127eaa53974c5d41d3d933ed7b58a9ce5b5cb96ad94a7762611c48774cf75458327e74c34668a45dc9943546f8a6aa1dcd40bd4b8014bef",
        "b49954a097a60cbdff333ee3f2fd1f49"
      ),
    ]

    vectors.each do |v|
      it "encrypts correctly: #{v.name}" do
        key = v.key.hexbytes
        nonce = v.nonce.hexbytes
        adata = v.adata.empty? ? nil : v.adata.hexbytes
        plaintext = v.pt.hexbytes
        expected_ct = v.ct.hexbytes
        expected_tag = v.tag.hexbytes

        ciphertext = crypto.encrypt(key, plaintext, nonce, adata)

        # Should match ciphertext + tag
        ciphertext[0, expected_ct.size].should eq(expected_ct)
        ciphertext[expected_ct.size, 16].should eq(expected_tag)
      end

      it "decrypts correctly: #{v.name}" do
        key = v.key.hexbytes
        nonce = v.nonce.hexbytes
        adata = v.adata.empty? ? nil : v.adata.hexbytes
        expected_pt = v.pt.hexbytes
        ct_with_tag = (v.ct + v.tag).hexbytes

        plaintext = crypto.decrypt(key, ct_with_tag, nonce, adata)

        plaintext.should eq(expected_pt)
      end
    end

    it "fails decryption with wrong key" do
      key1 = "0953fa93e7caac9638f58820220a398e".hexbytes
      key2 = "be635105434859f484fc798e043ce40e".hexbytes
      nonce = "00800000011201000012345678".hexbytes
      plaintext = "fffd034b50057e400000010000".hexbytes

      ciphertext = crypto.encrypt(key1, plaintext, nonce)

      expect_raises(Exception, /authentication failed/) do
        crypto.decrypt(key2, ciphertext, nonce)
      end
    end

    it "fails decryption with wrong AAD" do
      key = "63964771734fbd76e3b40519d1d94a48".hexbytes
      nonce = "010007080d1234973612345677".hexbytes
      aad1 = "f4a002c7fb1e4ca0a469a021de0db875".hexbytes
      aad2 = "f4a002c7fb1e4ca0a469a021de0db876".hexbytes # Last byte different
      plaintext = "ea0a00576f726c64".hexbytes

      ciphertext = crypto.encrypt(key, plaintext, nonce, aad1)

      expect_raises(Exception, /authentication failed/) do
        crypto.decrypt(key, ciphertext, nonce, aad2)
      end
    end

    it "fails decryption with tampered ciphertext" do
      key = "0953fa93e7caac9638f58820220a398e".hexbytes
      nonce = "00800000011201000012345678".hexbytes
      plaintext = "fffd034b50057e400000010000".hexbytes

      ciphertext = crypto.encrypt(key, plaintext, nonce)

      # Tamper with the ciphertext
      ciphertext[0] = ciphertext[0] ^ 0xFF_u8

      expect_raises(Exception, /authentication failed/) do
        crypto.decrypt(key, ciphertext, nonce)
      end
    end
  end
end
