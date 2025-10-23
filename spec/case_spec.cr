require "./spec_helper"
require "../src/matter/session/case/case"

describe Matter::Session::Case do
  describe "CertificateChain" do
    it "creates a certificate chain with DAC only" do
      dac = Bytes.new(100, 1_u8)
      chain = Matter::Session::Case::CertificateChain.new(dac)

      chain.dac.should eq(dac)
      chain.pai.should be_nil
      chain.paa.should be_nil
    end

    it "creates a full certificate chain" do
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(150, 2_u8)
      paa = Bytes.new(200, 3_u8)

      chain = Matter::Session::Case::CertificateChain.new(dac, pai, paa)

      chain.dac.should eq(dac)
      chain.pai.should eq(pai)
      chain.paa.should eq(paa)
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
      peer_encrypted_cert = crypto.random_bytes(116) # 100 + 16 for MIC
      peer_session_id = crypto.random_uint16

      sigma3 = initiator.process_sigma2(
        peer_ephemeral,
        peer_random,
        peer_encrypted_cert,
        peer_session_id
      )

      sigma3[:encrypted_cert].should be_a(Bytes)
      sigma3[:encrypted_cert].size.should eq(116) # 100 + 16 for MIC
      sigma3[:signature].should be_a(Bytes)
      sigma3[:signature].size.should eq(64) # ECDSA P-256 signature
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

      # Must generate Sigma1 first
      initiator.generate_sigma1

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
      dac = Bytes.new(100, 1_u8)
      chain = Matter::Session::Case::CertificateChain.new(dac)
      fabric_id = 0x3333333333333333_u64
      node_id = 0x4444444444444444_u64

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: fabric_id,
        node_id: node_id,
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
      dac = Bytes.new(100)
      chain = Matter::Session::Case::CertificateChain.new(dac)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: 0x3333_u64,
        node_id: 0x4444_u64,
        crypto: crypto
      )

      # Simulate peer Sigma1
      peer_key = crypto.create_key_pair
      peer_ephemeral = peer_key.public_key
      peer_random = crypto.random_bytes(32)
      peer_session_id = crypto.random_uint16

      sigma2 = responder.process_sigma1(
        peer_ephemeral,
        peer_random,
        peer_session_id
      )

      sigma2[:ephemeral_public_key].should be_a(Bytes)
      sigma2[:ephemeral_public_key].size.should eq(65)
      sigma2[:random].should be_a(Bytes)
      sigma2[:random].size.should eq(32)
      sigma2[:encrypted_cert].should be_a(Bytes)
      sigma2[:encrypted_cert].size.should eq(116) # 100 + 16 for MIC
      sigma2[:session_id].should be_a(UInt16)

      responder.ephemeral_key.should_not be_nil
    end

    it "processes Sigma3 and verifies" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      dac = Bytes.new(100)
      chain = Matter::Session::Case::CertificateChain.new(dac)

      responder = Matter::Session::Case::CaseResponder.new(
        cert_chain: chain,
        operational_key: key,
        fabric_id: 0x3333_u64,
        node_id: 0x4444_u64,
        crypto: crypto
      )

      # Process Sigma1 first
      peer_key = crypto.create_key_pair
      responder.process_sigma1(peer_key.public_key, crypto.random_bytes(32), crypto.random_uint16)

      # Process Sigma3
      encrypted_cert = crypto.random_bytes(116)
      signature = crypto.random_bytes(64)

      result = responder.process_sigma3(encrypted_cert, signature)
      result.should be_true
    end
  end

  describe "CASE session establishment" do
    it "establishes a CASE session between initiator and responder" do
      crypto = Matter::Crypto::StandardCrypto.new

      # Create credentials for both sides
      initiator_key = crypto.create_key_pair
      initiator_cert = Bytes.new(100, 1_u8)

      responder_key = crypto.create_key_pair
      responder_dac = Bytes.new(100, 2_u8)
      responder_chain = Matter::Session::Case::CertificateChain.new(responder_dac)

      fabric_id = 0x1111111111111111_u64
      initiator_node_id = 0x2222222222222222_u64
      responder_node_id = 0x3333333333333333_u64

      result = Matter::Session::Case.establish_session(
        initiator_cert,
        initiator_key,
        responder_chain,
        responder_key,
        fabric_id,
        initiator_node_id,
        responder_node_id,
        crypto
      )

      # Check initiator context
      result[:initiator].session_type.should eq(Matter::Session::SessionType::Unicast)
      result[:initiator].is_initiator.should be_true
      result[:initiator].encryption_key.size.should eq(16)
      result[:initiator].decryption_key.size.should eq(16)
      result[:initiator].local_node_id.try(&.id).should eq(initiator_node_id)
      result[:initiator].peer_node_id.try(&.id).should eq(responder_node_id)

      # Check responder context
      result[:responder].session_type.should eq(Matter::Session::SessionType::Unicast)
      result[:responder].is_initiator.should be_false
      result[:responder].encryption_key.size.should eq(16)
      result[:responder].decryption_key.size.should eq(16)
      result[:responder].local_node_id.try(&.id).should eq(responder_node_id)
      result[:responder].peer_node_id.try(&.id).should eq(initiator_node_id)

      # Session IDs should be set and cross-reference each other
      result[:initiator].peer_session_id.should eq(result[:responder].session_id)
      result[:responder].peer_session_id.should eq(result[:initiator].session_id)
    end
  end
end
