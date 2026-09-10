require "../spec_helper"
require "../../src/matter/session/case/case"
require "../../src/matter/session/case/definitions"
require "../../src/matter/crypto/crypto"

# CASE pairing compatibility tests ported from matter.js
# Source: matter.js/packages/protocol/build/esm/test/session/secure/CasePairingTest.js
describe Matter::Session::Case do
  describe "Sigma2 generation (matter.js compatibility)" do
    it "generates the right bytes for sigma 2" do
      # Test vectors from matter.js CasePairingTest.js
      noc = "153001010124020137032414001826048012542826058015203b370624150124115a1824070124080130094104531a14e4c1b4cc7ac69aa5e403d5ccc3c5152c29fddedc29ac98ecff6c8f8695317446029cf3eb3e295ee18f0fd0ba9f06f7fa229138db0bc8d8c6f9875c9707370a3501280118240201360304020401183004149038f60c3542d5e610f29abc5f42ac09b07ee0d7300514e766069362d7e35b79687161644d222bdde93a6818300b40cbd9a06e77e9a7bcd19d02da0f2e50042f7d78201e8be26e793e995ca8f02f1094b34d0fd53b1f1458908d0d29183f2611e6132c6401d15dfff081d1021358ad18".hexbytes

      pub_key = "04e2690445cc017a388853eaeca3a1ffd2712f6898e0bb523b8b496590804a39bf1555300bbd2a159e927b428397fb07a41e26c8cdf858ec62a310d0480d94eb64".hexbytes
      peer_pub_key = "04ae6e458cf40ad53761ee90bc458aa577e6a1acf75410524551bb0bc4c708832c6525991ee2eed47df35ce2d83dad743bff6769ebbf731395d62453cb37303e03".hexbytes
      fabric_pub_key = "04531a14e4c1b4cc7ac69aa5e403d5ccc3c5152c29fddedc29ac98ecff6c8f8695317446029cf3eb3e295ee18f0fd0ba9f06f7fa229138db0bc8d8c6f9875c9707".hexbytes

      # Expected outputs from matter.js
      expected_signature_data = "153001f1153001010124020137032414001826048012542826058015203b370624150124115a1824070124080130094104531a14e4c1b4cc7ac69aa5e403d5ccc3c5152c29fddedc29ac98ecff6c8f8695317446029cf3eb3e295ee18f0fd0ba9f06f7fa229138db0bc8d8c6f9875c9707370a3501280118240201360304020401183004149038f60c3542d5e610f29abc5f42ac09b07ee0d7300514e766069362d7e35b79687161644d222bdde93a6818300b40cbd9a06e77e9a7bcd19d02da0f2e50042f7d78201e8be26e793e995ca8f02f1094b34d0fd53b1f1458908d0d29183f2611e6132c6401d15dfff081d1021358ad1830034104e2690445cc017a388853eaeca3a1ffd2712f6898e0bb523b8b496590804a39bf1555300bbd2a159e927b428397fb07a41e26c8cdf858ec62a310d0480d94eb6430044104ae6e458cf40ad53761ee90bc458aa577e6a1acf75410524551bb0bc4c708832c6525991ee2eed47df35ce2d83dad743bff6769ebbf731395d62453cb37303e0318".hexbytes
      expected_signature = "1736972364d84c4ae069f642f491256c6e74c86eda9f5ed4d89dfd7cadb68b67574f032afa2764fcc890e9218eaedcc484576d2d65e4df1ae22dd916f12ab59e".hexbytes
      expected_encrypted_data_plain = "153001f1153001010124020137032414001826048012542826058015203b370624150124115a1824070124080130094104531a14e4c1b4cc7ac69aa5e403d5ccc3c5152c29fddedc29ac98ecff6c8f8695317446029cf3eb3e295ee18f0fd0ba9f06f7fa229138db0bc8d8c6f9875c9707370a3501280118240201360304020401183004149038f60c3542d5e610f29abc5f42ac09b07ee0d7300514e766069362d7e35b79687161644d222bdde93a6818300b40cbd9a06e77e9a7bcd19d02da0f2e50042f7d78201e8be26e793e995ca8f02f1094b34d0fd53b1f1458908d0d29183f2611e6132c6401d15dfff081d1021358ad183003401736972364d84c4ae069f642f491256c6e74c86eda9f5ed4d89dfd7cadb68b67574f032afa2764fcc890e9218eaedcc484576d2d65e4df1ae22dd916f12ab59e3004108731f8cec507136df7558fca9360e9fc18".hexbytes
      resumption_id = "8731f8cec507136df7558fca9360e9fc".hexbytes

      # Test SignedData TLV encoding
      signed_data = Matter::Session::Case::Definitions::SignedData.new(
        responder_noc: noc,
        responder_icac: nil,
        responder_public_key: pub_key,
        initiator_public_key: peer_pub_key
      )

      signed_data_bytes = signed_data.to_slice
      signed_data_bytes.hexstring.should eq expected_signature_data.hexstring

      # Test signature verification with fabric public key
      crypto = Matter::Crypto::StandardCrypto.new
      fabric_key = Matter::Crypto::Key.new(Matter::Crypto::KeyType::EC, Matter::Crypto::CurveType::P256)
      fabric_key.public_bits = fabric_pub_key

      # Verify the signature from matter.js
      crypto.verify_ecdsa(fabric_key, signed_data_bytes, expected_signature)

      # Test EncryptedDataSigma2 TLV encoding
      encrypted_data = Matter::Session::Case::Definitions::EncryptedDataSigma2.new(
        responder_noc: noc,
        responder_icac: nil,
        signature: expected_signature,
        resumption_id: resumption_id
      )

      encrypted_data_bytes = encrypted_data.to_slice
      encrypted_data_bytes.hexstring.should eq expected_encrypted_data_plain.hexstring
    end

    it "generates the right signature" do
      # Test signature verification test from matter.js
      fabric_pub_key = "049bfa105c3d209ff226c31da689dafb297b73499ec1844bba89c60ce65938b722300dd0abbb201e9451c6ab284ec99b8d90c5dd892388c59fde30c299c64af8c4".hexbytes
      signature_data = "153001f1153001010124020137032414001826048012542826058015203b370624150124115d18240701240801300941049bfa105c3d209ff226c31da689dafb297b73499ec1844bba89c60ce65938b722300dd0abbb201e9451c6ab284ec99b8d90c5dd892388c59fde30c299c64af8c4370a3501280118240201360304020401183004142c3494bc756f4b58a73bde64a3141285a3efd5c9300514e766069362d7e35b79687161644d222bdde93a6818300b406772b5445ef466a669d9e5e5663238b817511e73ce992937ddd975690abda8b86b0a79f2fd49bae78c653fad9bd3d53463d4abd7f996964988a7644c4cc1d0321830020030034104473bd04e2a9c4e6a12b9008739c64a16d0113295822faf17e3d2ffcb77b0cae437701b0f0525ddcc6139da5a56dfda2af2b86a2836ef6b03f8f5c231dbaf950b3004410441838848a7e58ab46a1a71a539c474780002bf22adccbeaa43ee07f5176c61aaa3d718102333fc856595ea3a6a5bfd37d2890049acb82c49440e1f490cd970e018".hexbytes
      signature = "75e35c22a5da60805d65772b3d4decc8c6eabe30bd2925608524ea12b729efd00a12faeb5757cdfc65aaefddd01c57be9f14d37e2c0beca43434f8ebdd81d635".hexbytes

      crypto = Matter::Crypto::StandardCrypto.new
      fabric_key = Matter::Crypto::Key.new(Matter::Crypto::KeyType::EC, Matter::Crypto::CurveType::P256)
      fabric_key.public_bits = fabric_pub_key

      # This should not raise - signature should verify
      crypto.verify_ecdsa(fabric_key, signature_data, signature)
    end
  end
end
