require "../../spec_helper"
require "../../../src/matter/session/case/case"
require "../../../src/matter/certificate/attestation_certificate_manager"
require "tlv"

# Encrypt `cert` the way a CASE responder does for Sigma2: with the
# Sigma2 key and nonce derived from the ECDH secret of the responder's key
# and the initiator's ephemeral public key.
private def encrypt_sigma2_cert(
  crypto : Matter::Crypto::StandardCrypto,
  peer_key : Matter::Crypto::Key,
  initiator_ephemeral_public_key : Bytes,
  cert : Bytes,
) : Bytes
  shared = Matter::Crypto::ECDH.compute_shared_secret(peer_key.private_key, initiator_ephemeral_public_key)
  key = crypto.create_hkdf_key(shared, Bytes.new(0), "Sigma2EncryptionKey".to_slice, 16)
  nonce = crypto.create_hkdf_key(shared, Bytes.new(0), "Sigma2Nonce".to_slice, 13)
  crypto.encrypt(key, cert, nonce)
end

describe Matter::Session::Case do
  describe "extract_node_id_from_tlv_cert" do
    it "extracts node ID from TLV cert with nested structure subject" do
      # Create a TLV cert with a nested structure subject field
      # Matter TLV cert structure:
      # - Tag 6: Subject (nested structure)
      #   - Tag 17 (0x11): Node ID
      #   - Tag 18 (0x12): Fabric ID
      # - Tag 9: Public Key (for completeness)

      expected_node_id = 0xDFC02ECA70EBC76F_u64
      fabric_id = 0x0000000000000001_u64

      # Build the nested subject structure
      subject = TLV::Structure.new
      subject[17_u8] = TLV::Any.new(expected_node_id, 17_u8)
      subject[18_u8] = TLV::Any.new(fabric_id, 18_u8)

      # Build the outer cert structure
      cert = TLV::Structure.new
      cert[6_u8] = TLV::Any.new(subject, 6_u8)
      cert[9_u8] = TLV::Any.new(Bytes.new(65, 0x04_u8), 9_u8)

      # Encode to bytes
      cert_tlv = TLV::Any.new(cert, nil).to_slice

      # Create a responder to test the extraction method
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      noc = Bytes.new(100)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)
      ipk = crypto.random_bytes(16)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: fabric_id,
        node_id: 0x1111111111111111_u64,
        ipk: ipk,
        crypto: crypto
      )

      # Test the extraction
      extracted = responder.extract_node_id_from_tlv_cert(cert_tlv)
      extracted.should eq(expected_node_id)
    end

    it "extracts node ID from TLV cert with List subject" do
      # Test with a List subject (like PathContainer)
      expected_node_id = 0x123456789ABCDEF0_u64
      fabric_id = 0x0000000000000002_u64

      # Build the subject as a List with tagged elements
      subject_list = TLV::List.new
      subject_list << TLV::Any.new(expected_node_id, 17_u8)
      subject_list << TLV::Any.new(fabric_id, 18_u8)

      # Build the outer cert structure
      cert = TLV::Structure.new
      cert[6_u8] = TLV::Any.new(subject_list, 6_u8)
      cert[9_u8] = TLV::Any.new(Bytes.new(65, 0x04_u8), 9_u8)

      # Encode to bytes
      cert_tlv = TLV::Any.new(cert, nil).to_slice

      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      noc = Bytes.new(100)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)
      ipk = crypto.random_bytes(16)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: fabric_id,
        node_id: 0x1111111111111111_u64,
        ipk: ipk,
        crypto: crypto
      )

      extracted = responder.extract_node_id_from_tlv_cert(cert_tlv)
      extracted.should eq(expected_node_id)
    end

    it "returns nil when subject field is missing" do
      # Create a cert without subject field (tag 6)
      cert = TLV::Structure.new
      cert[9_u8] = TLV::Any.new(Bytes.new(65, 0x04_u8), 9_u8)

      cert_tlv = TLV::Any.new(cert, nil).to_slice

      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      noc = Bytes.new(100)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)
      ipk = crypto.random_bytes(16)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: 0x1_u64,
        node_id: 0x1111111111111111_u64,
        ipk: ipk,
        crypto: crypto
      )

      extracted = responder.extract_node_id_from_tlv_cert(cert_tlv)
      extracted.should be_nil
    end

    it "returns nil when node ID field is missing in subject" do
      # Create a cert with subject but no node ID (only fabric ID)
      subject = TLV::Structure.new
      subject[18_u8] = TLV::Any.new(0x1_u64, 18_u8) # Only Fabric ID, no Node ID

      cert = TLV::Structure.new
      cert[6_u8] = TLV::Any.new(subject, 6_u8)
      cert[9_u8] = TLV::Any.new(Bytes.new(65, 0x04_u8), 9_u8)

      cert_tlv = TLV::Any.new(cert, nil).to_slice

      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      noc = Bytes.new(100)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)
      ipk = crypto.random_bytes(16)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: 0x1_u64,
        node_id: 0x1111111111111111_u64,
        ipk: ipk,
        crypto: crypto
      )

      extracted = responder.extract_node_id_from_tlv_cert(cert_tlv)
      extracted.should be_nil
    end
  end

  describe "OperationalCertChain" do
    it "creates a certificate chain with NOC only" do
      noc = Bytes.new(100, 1_u8)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)

      chain.noc.should eq(noc)
      chain.icac.should be_nil
      chain.root.should be_nil
    end

    it "creates a full certificate chain" do
      noc = Bytes.new(100, 1_u8)
      icac = Bytes.new(150, 2_u8)
      root = Bytes.new(200, 3_u8)

      chain = Matter::Session::Case::OperationalCertChain.new(noc, icac, root)

      chain.noc.should eq(noc)
      chain.icac.should eq(icac)
      chain.root.should eq(root)
    end
  end

  describe "CaseInitiator" do
    it "creates an initiator with operational credentials" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      cert = Bytes.new(100, 1_u8)
      fabric_id = 0x1111111111111111_u64
      node_id = 0x2222222222222222_u64

      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: cert,
        operational_key: key,
        fabric_id: fabric_id,
        node_id: node_id,
        crypto: crypto
      )

      initiator.operational_cert.should eq(cert)
      initiator.operational_key.should eq(key)
      initiator.fabric_id.should eq(fabric_id)
      initiator.node_id.should eq(node_id)
      initiator.ephemeral_key.should be_nil
    end

    it "generates Sigma1 message" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      cert = Bytes.new(100)

      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: cert,
        operational_key: key,
        fabric_id: 0x1111_u64,
        node_id: 0x2222_u64
      )

      sigma1 = initiator.generate_sigma1

      sigma1[:ephemeral_public_key].should be_a(Bytes)
      sigma1[:ephemeral_public_key].size.should eq(65) # Uncompressed EC point
      sigma1[:random].should be_a(Bytes)
      sigma1[:random].size.should eq(32)
      sigma1[:session_id].should be_a(UInt16)

      initiator.ephemeral_key.should_not be_nil
    end

    it "processes Sigma2 and generates Sigma3" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      cert = Bytes.new(100)

      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: cert,
        operational_key: key,
        fabric_id: 0x1111_u64,
        node_id: 0x2222_u64,
        crypto: crypto
      )

      # Generate Sigma1 first
      sigma1 = initiator.generate_sigma1

      # Simulate peer response
      peer_key = crypto.create_key_pair
      peer_ephemeral = peer_key.public_key
      peer_random = crypto.random_bytes(32)
      peer_cert = Bytes.new(100, 0x42_u8)
      peer_encrypted_cert = encrypt_sigma2_cert(crypto, peer_key, sigma1[:ephemeral_public_key], peer_cert)
      peer_session_id = crypto.random_uint16

      sigma3 = initiator.process_sigma2(
        peer_ephemeral,
        peer_random,
        peer_encrypted_cert,
        peer_session_id
      )

      initiator.peer_cert.should eq(peer_cert)
      sigma3[:encrypted_cert].should be_a(Bytes)
      sigma3[:encrypted_cert].size.should eq(116) # 100 + 16 for MIC
      sigma3[:signature].should be_a(Bytes)
      sigma3[:signature].size.should eq(64) # ECDSA P-256 signature
    end

    it "fails the handshake when the Sigma2 certificate does not decrypt" do
      crypto = Matter::Crypto::StandardCrypto.new
      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: Bytes.new(100),
        operational_key: crypto.create_key_pair,
        fabric_id: 0x1111_u64,
        node_id: 0x2222_u64,
        crypto: crypto
      )
      initiator.generate_sigma1

      peer_key = crypto.create_key_pair
      forged_cert = crypto.random_bytes(116) # 100 + 16 for MIC, not encrypted with the shared secret

      error = expect_raises(Matter::AuthenticationError, /Sigma2 certificate decryption failed/) do
        initiator.process_sigma2(peer_key.public_key, crypto.random_bytes(32), forged_cert, crypto.random_uint16)
      end
      error.cause.should be_a(Matter::AuthenticationError)
      initiator.peer_cert.should be_nil
    end

    it "verifies a Sigma3 signature with the peer certificate" do
      crypto = Matter::Crypto::StandardCrypto.new
      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: Bytes.new(100),
        operational_key: crypto.create_key_pair,
        fabric_id: 0x1111_u64,
        node_id: 0x2222_u64,
        crypto: crypto
      )
      manager = Matter::Certificate::AttestationCertificateManager.new(0xFFF1_u16)
      peer_cert_der, peer_key = manager.get_dac_cert(0x8000_u16)
      initiator.peer_cert = peer_cert_der
      transcript = crypto.random_bytes(64)

      signature = crypto.sign_ecdsa(peer_key, transcript, "der")
      initiator.verify_sigma3(signature, transcript)

      other_key = crypto.create_key_pair
      forged = crypto.sign_ecdsa(other_key, transcript, "der")
      expect_raises(Matter::AuthenticationError, /Sigma3 signature verification failed/) do
        initiator.verify_sigma3(forged, transcript)
      end
    end

    it "rejects Sigma3 when the peer certificate cannot be parsed" do
      crypto = Matter::Crypto::StandardCrypto.new
      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: Bytes.new(100),
        operational_key: crypto.create_key_pair,
        fabric_id: 0x1111_u64,
        node_id: 0x2222_u64,
        crypto: crypto
      )
      initiator.peer_cert = Bytes.new(100, 0x42_u8)

      expect_raises(Matter::AuthenticationError, /peer certificate cannot be parsed/) do
        initiator.verify_sigma3(crypto.random_bytes(64), crypto.random_bytes(64))
      end
    end

    it "derives session keys" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      cert = Bytes.new(100)

      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: cert,
        operational_key: key,
        fabric_id: 0x1111_u64,
        node_id: 0x2222_u64,
        crypto: crypto
      )

      # Must go through protocol flow to compute shared secret
      sigma1 = initiator.generate_sigma1

      # Simulate peer response
      peer_key = crypto.create_key_pair
      peer_ephemeral = peer_key.public_key
      peer_random = crypto.random_bytes(32)
      peer_encrypted_cert = encrypt_sigma2_cert(crypto, peer_key, sigma1[:ephemeral_public_key], Bytes.new(100))
      peer_session_id = crypto.random_uint16

      initiator.process_sigma2(peer_ephemeral, peer_random, peer_encrypted_cert, peer_session_id)

      # Now can derive keys
      keys = initiator.derive_session_keys

      keys[:encryption].should be_a(Bytes)
      keys[:encryption].size.should eq(16)
      keys[:decryption].should be_a(Bytes)
      keys[:decryption].size.should eq(16)
    end
  end

  describe "CaseResponder" do
    it "creates a responder with certificate chain" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      noc = Bytes.new(100, 1_u8)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)
      fabric_id = 0x3333333333333333_u64
      node_id = 0x4444444444444444_u64
      ipk = crypto.random_bytes(16) # Test IPK

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: fabric_id,
        node_id: node_id,
        ipk: ipk,
        crypto: crypto
      )

      responder.cert_chain.should eq(chain)
      responder.operational_key.should eq(key)
      responder.fabric_id.should eq(fabric_id)
      responder.node_id.should eq(node_id)
      responder.ephemeral_key.should be_nil
    end

    it "processes Sigma1 and generates Sigma2" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      noc = Bytes.new(100)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)
      ipk = crypto.random_bytes(16)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: 0x3333_u64,
        node_id: 0x4444_u64,
        ipk: ipk,
        crypto: crypto
      )

      # Simulate peer Sigma1
      peer_key = crypto.create_key_pair
      peer_ephemeral = peer_key.public_key
      peer_random = crypto.random_bytes(32)
      peer_session_id = crypto.random_uint16
      sigma1_bytes = crypto.random_bytes(100) # Mock Sigma1 TLV for transcript

      sigma2 = responder.process_sigma1(
        peer_ephemeral,
        peer_random,
        peer_session_id,
        sigma1_bytes
      )

      sigma2[:ephemeral_public_key].should be_a(Bytes)
      sigma2[:ephemeral_public_key].size.should eq(65)
      sigma2[:random].should be_a(Bytes)
      sigma2[:random].size.should eq(32)
      sigma2[:encrypted_cert].should be_a(Bytes)
      # The encrypted cert includes TLV-wrapped NOC + signature + resumption_id + MIC
      # Size varies based on TLV encoding
      sigma2[:encrypted_cert].size.should be > 100
      sigma2[:session_id].should be_a(UInt16)

      responder.ephemeral_key.should_not be_nil
    end

    it "processes Sigma3 and verifies" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      noc = Bytes.new(100)
      chain = Matter::Session::Case::OperationalCertChain.new(noc)
      ipk = crypto.random_bytes(16)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: 0x3333_u64,
        node_id: 0x4444_u64,
        ipk: ipk,
        crypto: crypto
      )

      # Process Sigma1 first
      peer_key = crypto.create_key_pair
      sigma1_bytes = crypto.random_bytes(100) # Mock Sigma1 TLV for transcript
      responder.process_sigma1(peer_key.public_key, crypto.random_bytes(32), crypto.random_uint16, sigma1_bytes)

      # Process Sigma3 with random data - this will fail verification
      # because the encrypted_cert needs to be properly AES-CCM encrypted
      # and the decryption will fail with invalid/random bytes
      encrypted_cert = crypto.random_bytes(116)
      signature = crypto.random_bytes(64)

      # With random data, process_sigma3 returns false (decryption fails)
      result = responder.process_sigma3(encrypted_cert, signature)
      result.should be_false
    end
  end

  describe "CASE session establishment" do
    it "initiator can generate Sigma1 message" do
      crypto = Matter::Crypto::StandardCrypto.new

      # Create initiator credentials
      initiator_key = crypto.create_key_pair
      initiator_cert = Bytes.new(100, 1_u8)

      fabric_id = 0x1111111111111111_u64
      initiator_node_id = 0x2222222222222222_u64

      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: initiator_cert,
        operational_key: initiator_key,
        fabric_id: fabric_id,
        node_id: initiator_node_id,
        crypto: crypto
      )

      # Generate Sigma1
      sigma1 = initiator.generate_sigma1

      # Verify Sigma1 contains expected fields
      sigma1[:ephemeral_public_key].size.should eq(65) # Uncompressed P-256 point
      sigma1[:random].size.should eq(32)
      sigma1[:session_id].should be > 0_u16
    end

    it "responder can process Sigma1 and generate Sigma2 response" do
      crypto = Matter::Crypto::StandardCrypto.new

      # Create responder credentials
      responder_key = crypto.create_key_pair
      responder_noc = Bytes.new(100, 2_u8)
      responder_chain = Matter::Session::Case::OperationalCertChain.new(responder_noc)
      ipk = crypto.random_bytes(16)

      fabric_id = 0x1111111111111111_u64
      responder_node_id = 0x3333333333333333_u64

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: responder_chain,
        operational_key: responder_key,
        fabric_id: fabric_id,
        node_id: responder_node_id,
        ipk: ipk,
        crypto: crypto
      )

      # Generate a mock Sigma1 message (peer ephemeral key and random)
      peer_key = crypto.create_key_pair
      peer_random = crypto.random_bytes(32)
      peer_session_id = 0x1234_u16
      # Mock sigma1 bytes (the raw TLV message)
      sigma1_bytes = crypto.random_bytes(64)

      # Process Sigma1 and generate Sigma2 response
      sigma2 = responder.process_sigma1(
        peer_ephemeral_public_key: peer_key.public_key,
        peer_random: peer_random,
        peer_session_id: peer_session_id,
        sigma1_bytes: sigma1_bytes
      )

      # Verify Sigma2 contains expected fields
      sigma2[:ephemeral_public_key].size.should eq(65)
      sigma2[:random].size.should eq(32)
      sigma2[:encrypted_cert].size.should be > 0
      sigma2[:session_id].should be > 0_u16
      sigma2[:sigma2_bytes].size.should be > 0
    end
  end
end
