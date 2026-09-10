require "../spec_helper"
require "../../src/matter/crypto/crypto"
require "../../src/matter/crypto/spake2p"

# Ported from matter.js PasePairingTest.ts
# Tests PASE SPAKE2+ computation against matter.js test vectors
describe "PASE Compatibility with matter.js" do
  crypto = Matter::Crypto::StandardCrypto.new

  describe "Test PASE Spake2 process" do
    it "test fix for elliptic library failure" do
      # From matter.js PasePairingTest.ts line 14-69
      # Tests w0 computation with leading 00 (elliptic library bug fix)

      server_pbkdf_parameters = Matter::Crypto::Spake2p::PbkdfParameters.new(
        iterations: 1000,
        salt: "03959ebc20b8fcbda262d97f9a7a9e76e32d7a1b9c5166b6a3721e88acad8808".hexbytes
      )

      pin = 20202021_u32

      # Compute w0 and L
      w0_l = Matter::Crypto::Spake2p.compute_w0_l(crypto, server_pbkdf_parameters, pin)

      # Expected w0 from matter.js (note: 63 hex chars, so has leading 0)
      expected_w0_hex = "177867f1e564cc4d9f347edfc28263ee5a50f1e21177cfb9a7dc2504437ccb"
      expected_w0 = BigInt.new(expected_w0_hex, 16)

      # Expected L from matter.js
      expected_l = "04cf26d253cae2dd44c6954d443c7badc1e8811b8484eaae2d7bf43ec2f7e3173527877ea4a554513063036f55d2871e87e294dfdc18cd39edd6519fb4dfcde976".hexbytes

      w0_l.w0.should eq(expected_w0)
      w0_l.l.should eq(expected_l)

      # SPAKE context from matter.js
      spake_context = "CHIP PAKE V1 Commissioning".to_slice

      # Request and response payloads from matter.js test
      request_payload = "1530012094eab5c37d101df5ef01b2c8ecada03a7c3b0cf5e26a08feda72617f9cd391a6240247240300280418".hexbytes
      response_payload = "1530012094eab5c37d101df5ef01b2c8ecada03a7c3b0cf5e26a08feda72617f9cd391a630022022820a42684102fd4a92c0bad66ad1f21f3c5366f5a6d84203035e2c7caf3bae250357de35042501e80330022003959ebc20b8fcbda262d97f9a7a9e76e32d7a1b9c5166b6a3721e88acad88081818".hexbytes

      # Compute context hash for SPAKE2+
      context_hash = crypto.compute_sha256([spake_context, request_payload, response_payload])

      # Random value from matter.js test
      random = BigInt.new("de583b5685529de9544b92c9c8cba696751b14d65092d13458879b3bc9814b53", 16)

      # Create SPAKE2+ instance with fixed random value
      spake = Matter::Crypto::Spake2p.new(crypto, context_hash, random, w0_l.w0)

      # X value from matter.js test (commissioner's public value)
      x = "04cce1e192a645d54a3ac9a3a3f0b334f37c03400b826b14d873124dfb96a35815f80202f05c72d055b6da24942d0a6cac18caf310100ecef23248ac8fd2ced196".hexbytes

      # Compute Y (responder's public value)
      y = spake.compute_y

      # Expected Y from matter.js
      expected_y = "0404f972c7232cde8911de7d93e37ad752b90ad095888ac83da5f3a1d5a7eb063288ed6d358e9092a8606dac6cd6b8fdfc0b3960df85434ed60c6b6091d23da7bb".hexbytes

      y.should eq(expected_y)

      # Compute shared secret and verifiers
      secret_and_verifiers = spake.compute_secret_and_verifiers_from_x(w0_l.l, x, y)

      # Expected verifier (h_bx) from matter.js
      expected_h_bx = "d6a13c26b6c5b7c514033a0370b1830dff5116fd53de43eb2374737e9b64e4bb".hexbytes

      # This was the old (wrong) value from the elliptic library bug
      wrong_h_bx = "13c986aeaf2415c3ae1228b213564fb10b66e013cc1cc9fa2c2b31e8b6c4b0db".hexbytes

      secret_and_verifiers.h_bx.should_not eq(wrong_h_bx)
      secret_and_verifiers.h_bx.should eq(expected_h_bx)
    end

    it "do special successful pase process" do
      # From matter.js PasePairingTest.ts line 71-122
      # Another complete PASE test with different salt

      server_pbkdf_parameters = Matter::Crypto::Spake2p::PbkdfParameters.new(
        iterations: 1000,
        salt: "2bb41e9d75f30c2e6b2f059410c56965717cc2bf14ed6c73a169435326a89652".hexbytes
      )

      pin = 20202021_u32

      # Compute w0 and L
      w0_l = Matter::Crypto::Spake2p.compute_w0_l(crypto, server_pbkdf_parameters, pin)

      # Expected w0 from matter.js
      expected_w0 = BigInt.new("501f85a83d1da77983ff6f0c1f742d6d98f6d0ab0ba740a38032200099c8981f", 16)

      # Expected L from matter.js
      expected_l = "0463e7f225296bcd9b100e605d636a3d2c84524665cbd9b8b75e737d04bca1241486b37bdba74284de76f2db9df271d2c5bda21b8e26bc0943dcbf0542665c3aa8".hexbytes

      w0_l.w0.should eq(expected_w0)
      w0_l.l.should eq(expected_l)

      # SPAKE context from matter.js
      spake_context = "CHIP PAKE V1 Commissioning".to_slice

      # Request and response payloads from matter.js test
      request_payload = "15300120913cc0622eca85f8d4c132c89663c5d7afa780667be930e5c11bec865479c6172502e68b240300280418".hexbytes
      response_payload = "15300120913cc0622eca85f8d4c132c89663c5d7afa780667be930e5c11bec865479c6173002205682c0732b37c045ebeb416904c187a58b5341088e0172123becfb855f94a72c2503844235042501e8033002202bb41e9d75f30c2e6b2f059410c56965717cc2bf14ed6c73a169435326a896521818".hexbytes

      # Compute context hash for SPAKE2+
      context_hash = crypto.compute_sha256([spake_context, request_payload, response_payload])

      # Random value from matter.js test
      random = BigInt.new("fee695b4972a4f620951010c87390d3fe1313efce399fbc2c9c7cdc04d22b4c6", 16)

      # Create SPAKE2+ instance with fixed random value
      spake = Matter::Crypto::Spake2p.new(crypto, context_hash, random, w0_l.w0)

      # X value from matter.js test (commissioner's public value)
      x = "04db4f7c7f4dbf478440753d578825da01ae177c89dad6637f9c91ef86880e8d67571b2fdc0e0564985cd6b2cbbee82ab5655b0fbae7254ff4b13f88a30076612c".hexbytes

      # Compute Y (responder's public value)
      y = spake.compute_y

      # Expected Y from matter.js
      expected_y = "04cd3a2937c598cfd46e197e786e4194e65164ed1a0bf23f224947b4f4c140f72b4742792b86ae6c427ae9d4a6d345cd6e1f9ae0f950d5399d38c8031d7975ca82".hexbytes

      y.should eq(expected_y)

      # Compute shared secret and verifiers
      secret_and_verifiers = spake.compute_secret_and_verifiers_from_x(w0_l.l, x, y)

      # Expected verifier (h_bx) from matter.js
      expected_h_bx = "52b9b5cb79dafd150b8729102ede22795d0f522ad884d29452818d8c54ca7508".hexbytes

      secret_and_verifiers.h_bx.should eq(expected_h_bx)
    end
  end
end
