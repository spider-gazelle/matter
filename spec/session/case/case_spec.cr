require "../../spec_helper"
require "../../../src/matter/session/case/case"
require "../../../src/matter/certificate/attestation_certificate_manager"
require "tlv"

# Node ID carried by the fixture certificates below
private NODE_ID = 0x2222222222222222_u64
# Fabric the fixture handshakes run on
private FABRIC_ID = 0x1111111111111111_u64
# Responder node ID used by the fixture handshakes
private RESPONDER_NODE_ID = 0x3333333333333333_u64
# Matter TLV certificate context tags used to build fixture certificates
private SUBJECT_TAG    =  6_u8
private PUBLIC_KEY_TAG =  9_u8
private NODE_ID_TAG    = 17_u8
private FABRIC_ID_TAG  = 18_u8
private CAT_TAG        = 22_u8

# A Sigma1 destination id is an HMAC-SHA256 tag; its content is opaque here
private def destination_id(crypto : Matter::Crypto::StandardCrypto) : Bytes
  crypto.random_bytes(Matter::Session::Case::DESTINATION_ID_LENGTH)
end

# Build a minimal Matter TLV certificate carrying `public_key` in tag 9 and a
# subject DN with the given node id.
private def tlv_certificate(public_key : Bytes, node_id : UInt64 = NODE_ID) : Bytes
  subject = TLV::Structure.new
  subject[NODE_ID_TAG] = TLV::Any.new(node_id, NODE_ID_TAG)
  subject[FABRIC_ID_TAG] = TLV::Any.new(FABRIC_ID, FABRIC_ID_TAG)

  cert = TLV::Structure.new
  cert[SUBJECT_TAG] = TLV::Any.new(subject, SUBJECT_TAG)
  cert[PUBLIC_KEY_TAG] = TLV::Any.new(public_key, PUBLIC_KEY_TAG)

  TLV::Any.new(cert, nil).to_slice
end

# A fabric's certificate authority. Handshake fixtures issue real certificates
# under one, because the responder checks that the peer's certificate chains to
# the fabric root.
private RCAC_ID = 1_u64

private def fabric_authority(crypto : Matter::Crypto::StandardCrypto) : Matter::Crypto::Key
  crypto.create_key_pair
end

private def issue(crypto : Matter::Crypto::StandardCrypto, authority : Matter::Crypto::Key, public_key : Bytes, node_id : UInt64) : Bytes
  Matter::Crypto::MatterCertificate::Builder.node(
    public_key: public_key,
    fabric_id: FABRIC_ID,
    node_id: node_id,
    issuer_key: authority,
    issuer_rcac_id: RCAC_ID,
    serial: crypto.random_bytes(8),
    crypto: crypto
  )
end

private def new_initiator(
  crypto : Matter::Crypto::StandardCrypto,
  ipk : Bytes,
  authority : Matter::Crypto::Key = crypto.create_key_pair,
  key : Matter::Crypto::Key = crypto.create_key_pair,
) : Matter::Session::Case::CaseInitiator
  Matter::Session::Case::CaseInitiator.new(
    operational_cert: issue(crypto, authority, key.public_key, NODE_ID),
    operational_key: key,
    fabric_id: FABRIC_ID,
    node_id: NODE_ID,
    ipk: ipk,
    crypto: crypto
  )
end

private def new_responder(
  crypto : Matter::Crypto::StandardCrypto,
  ipk : Bytes,
  authority : Matter::Crypto::Key = crypto.create_key_pair,
  key : Matter::Crypto::Key = crypto.create_key_pair,
) : Matter::Session::Case::CaseResponder
  Matter::Session::Case::CaseResponder.new(
    cert_chain: Matter::Session::Case::OperationalCertChain.new(issue(crypto, authority, key.public_key, RESPONDER_NODE_ID)),
    operational_key: key,
    fabric_id: FABRIC_ID,
    node_id: RESPONDER_NODE_ID,
    ipk: ipk,
    crypto: crypto,
    root_public_key: authority.public_key
  )
end

describe Matter::Session::Case do
  describe "Matter::Crypto::MatterCertificate TLV helpers" do
    it "extracts node ID from TLV cert with nested structure subject" do
      expected_node_id = 0xDFC02ECA70EBC76F_u64

      subject = TLV::Structure.new
      subject[NODE_ID_TAG] = TLV::Any.new(expected_node_id, NODE_ID_TAG)
      subject[FABRIC_ID_TAG] = TLV::Any.new(FABRIC_ID, FABRIC_ID_TAG)

      cert = TLV::Structure.new
      cert[SUBJECT_TAG] = TLV::Any.new(subject, SUBJECT_TAG)
      cert[PUBLIC_KEY_TAG] = TLV::Any.new(Bytes.new(65, 0x04_u8), PUBLIC_KEY_TAG)

      cert_tlv = TLV::Any.new(cert, nil).to_slice

      Matter::Crypto::MatterCertificate.node_id_from_tlv(cert_tlv).should eq(expected_node_id)
    end

    it "extracts node ID from TLV cert with List subject" do
      expected_node_id = 0x123456789ABCDEF0_u64

      subject_list = TLV::List.new
      subject_list << TLV::Any.new(expected_node_id, NODE_ID_TAG)
      subject_list << TLV::Any.new(FABRIC_ID, FABRIC_ID_TAG)

      cert = TLV::Structure.new
      cert[SUBJECT_TAG] = TLV::Any.new(subject_list, SUBJECT_TAG)
      cert[PUBLIC_KEY_TAG] = TLV::Any.new(Bytes.new(65, 0x04_u8), PUBLIC_KEY_TAG)

      cert_tlv = TLV::Any.new(cert, nil).to_slice

      Matter::Crypto::MatterCertificate.node_id_from_tlv(cert_tlv).should eq(expected_node_id)
    end

    it "returns nil when subject field is missing" do
      cert = TLV::Structure.new
      cert[PUBLIC_KEY_TAG] = TLV::Any.new(Bytes.new(65, 0x04_u8), PUBLIC_KEY_TAG)

      cert_tlv = TLV::Any.new(cert, nil).to_slice

      Matter::Crypto::MatterCertificate.node_id_from_tlv(cert_tlv).should be_nil
    end

    it "returns nil when node ID field is missing in subject" do
      subject = TLV::Structure.new
      subject[FABRIC_ID_TAG] = TLV::Any.new(FABRIC_ID, FABRIC_ID_TAG)

      cert = TLV::Structure.new
      cert[SUBJECT_TAG] = TLV::Any.new(subject, SUBJECT_TAG)
      cert[PUBLIC_KEY_TAG] = TLV::Any.new(Bytes.new(65, 0x04_u8), PUBLIC_KEY_TAG)

      cert_tlv = TLV::Any.new(cert, nil).to_slice

      Matter::Crypto::MatterCertificate.node_id_from_tlv(cert_tlv).should be_nil
    end

    it "extracts the EC public key" do
      public_key = Bytes.new(65, 0x04_u8)

      Matter::Crypto::MatterCertificate.public_key_from_tlv(tlv_certificate(public_key)).should eq(public_key)
    end

    it "raises when the certificate carries no public key" do
      subject = TLV::Structure.new
      subject[NODE_ID_TAG] = TLV::Any.new(NODE_ID, NODE_ID_TAG)

      cert = TLV::Structure.new
      cert[SUBJECT_TAG] = TLV::Any.new(subject, SUBJECT_TAG)

      expect_raises(Matter::CertificateError, /public key field/) do
        Matter::Crypto::MatterCertificate.public_key_from_tlv(TLV::Any.new(cert, nil).to_slice)
      end
    end

    it "extracts subject IDs with the node ID first and CATs after it" do
      cat_value = 0x0001_0001_u32

      subject_list = TLV::List.new
      subject_list << TLV::Any.new(NODE_ID, NODE_ID_TAG)
      subject_list << TLV::Any.new(FABRIC_ID, FABRIC_ID_TAG)
      subject_list << TLV::Any.new(cat_value, CAT_TAG)

      cert = TLV::Structure.new
      cert[SUBJECT_TAG] = TLV::Any.new(subject_list, SUBJECT_TAG)
      cert[PUBLIC_KEY_TAG] = TLV::Any.new(Bytes.new(65, 0x04_u8), PUBLIC_KEY_TAG)

      subject_ids = Matter::Crypto::MatterCertificate.subject_ids_from_tlv(TLV::Any.new(cert, nil).to_slice)

      expected_cat_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(
        Matter::DataType::CaseAuthenticatedTag.new(cat_value)
      ).id
      subject_ids.should eq([NODE_ID, expected_cat_node_id])
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
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)

      initiator = new_initiator(crypto, ipk, key: key)

      initiator.operational_key.should eq(key)
      initiator.fabric_id.should eq(FABRIC_ID)
      initiator.node_id.should eq(NODE_ID)
      initiator.ipk.should eq(ipk)
      initiator.ephemeral_key.should be_nil
    end

    it "generates Sigma1 message" do
      crypto = Matter::Crypto::StandardCrypto.new
      initiator = new_initiator(crypto, crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH))

      destination = destination_id(crypto)
      sigma1 = initiator.generate_sigma1(destination)

      sigma1[:ephemeral_public_key].size.should eq(65) # Uncompressed EC point
      sigma1[:random].size.should eq(Matter::Session::Case::RANDOM_LENGTH)
      sigma1[:session_id].should be_a(UInt16)
      initiator.ephemeral_key.should_not be_nil

      # The message it stored for the transcript is the encoded Sigma1
      decoded = Matter::Session::Case::Definitions::Sigma1.from_slice(sigma1[:sigma1_bytes])
      decoded.initiator_random.should eq(sigma1[:random])
      decoded.initiator_session_id.should eq(sigma1[:session_id])
      decoded.initiator_eph_pub_key.should eq(sigma1[:ephemeral_public_key])
      decoded.destination_id.should eq(destination)
      initiator.sigma1_bytes.should eq(sigma1[:sigma1_bytes])
    end

    it "processes Sigma2 from a responder and generates Sigma3" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)
      authority = crypto.create_key_pair
      initiator = new_initiator(crypto, ipk, authority)
      responder = new_responder(crypto, ipk, authority)

      sigma1 = initiator.generate_sigma1(destination_id(crypto))
      sigma2 = responder.process_sigma1(
        sigma1[:ephemeral_public_key],
        sigma1[:random],
        sigma1[:session_id],
        sigma1[:sigma1_bytes]
      )

      sigma2_bytes = sigma2[:sigma2_bytes]
      sigma3 = initiator.process_sigma2(
        Matter::Session::Case::Definitions::Sigma2.from_slice(sigma2_bytes),
        sigma2_bytes
      )

      # The initiator unwrapped TBE_Data2 and kept the responder's credentials
      initiator.peer_cert.should eq(responder.cert_chain.noc)
      initiator.peer_icac.should be_nil
      initiator.peer_signature.try(&.size).should eq(64)
      initiator.peer_resumption_id.try(&.size).should eq(Matter::Session::Case::RESUMPTION_ID_LENGTH)
      initiator.peer_session_id.should eq(sigma2[:session_id])

      sigma3[:signature].size.should eq(64) # ECDSA P-256 signature
      sigma3[:encrypted_cert].size.should be > 0
      Matter::Session::Case::Definitions::Sigma3.from_slice(sigma3[:sigma3_bytes]).encrypted3.should eq(sigma3[:encrypted_cert])
    end

    it "signs TBS_Data3 with its operational key" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)
      key = crypto.create_key_pair
      authority = crypto.create_key_pair
      initiator = new_initiator(crypto, ipk, authority, key)
      responder = new_responder(crypto, ipk, authority)

      sigma1 = initiator.generate_sigma1(destination_id(crypto))
      sigma2 = responder.process_sigma1(
        sigma1[:ephemeral_public_key],
        sigma1[:random],
        sigma1[:session_id],
        sigma1[:sigma1_bytes]
      )
      sigma2_bytes = sigma2[:sigma2_bytes]
      sigma3 = initiator.process_sigma2(
        Matter::Session::Case::Definitions::Sigma2.from_slice(sigma2_bytes),
        sigma2_bytes
      )

      # TBS_Data3: our NOC, our ephemeral key, then the responder's, exactly as
      # the responder rebuilds it to verify.
      signed_data = Matter::Session::Case::Definitions::SignedData.new(
        responder_noc: initiator.operational_cert,
        responder_icac: nil,
        responder_public_key: sigma1[:ephemeral_public_key],
        initiator_public_key: sigma2[:ephemeral_public_key]
      )

      crypto.verify_ecdsa(key, signed_data.to_slice, sigma3[:signature])
    end

    it "fails the handshake when the Sigma2 certificate does not decrypt" do
      crypto = Matter::Crypto::StandardCrypto.new
      initiator = new_initiator(crypto, crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH))
      initiator.generate_sigma1(destination_id(crypto))

      peer_key = crypto.create_key_pair
      sigma2 = Matter::Session::Case::Definitions::Sigma2.new(
        responder_random: crypto.random_bytes(Matter::Session::Case::RANDOM_LENGTH),
        responder_session_id: crypto.random_uint16,
        responder_eph_pub_key: peer_key.public_key,
        encrypted2: crypto.random_bytes(116) # not encrypted with the shared secret
      )

      error = expect_raises(Matter::AuthenticationError, /Sigma2 certificate decryption failed/) do
        initiator.process_sigma2(sigma2, sigma2.to_slice)
      end
      error.cause.should be_a(Matter::AuthenticationError)
      initiator.peer_cert.should be_nil
    end

    it "verifies a Sigma3 signature with the peer certificate" do
      crypto = Matter::Crypto::StandardCrypto.new
      initiator = new_initiator(crypto, crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH))
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
      initiator = new_initiator(crypto, crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH))
      initiator.peer_cert = Bytes.new(100, 0x42_u8)

      expect_raises(Matter::AuthenticationError, /peer certificate cannot be parsed/) do
        initiator.verify_sigma3(crypto.random_bytes(64), crypto.random_bytes(64))
      end
    end

    it "refuses to derive session keys before the handshake completes" do
      crypto = Matter::Crypto::StandardCrypto.new
      initiator = new_initiator(crypto, crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH))

      expect_raises(Matter::ProtocolError, /Shared secret not computed/) do
        initiator.derive_session_keys
      end
    end
  end

  describe "CaseResponder" do
    it "creates a responder with certificate chain" do
      crypto = Matter::Crypto::StandardCrypto.new
      key = crypto.create_key_pair
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)

      responder = new_responder(crypto, ipk, key: key)

      responder.operational_key.should eq(key)
      responder.fabric_id.should eq(FABRIC_ID)
      responder.node_id.should eq(RESPONDER_NODE_ID)
      responder.ephemeral_key.should be_nil
    end

    it "processes Sigma1 and generates Sigma2" do
      crypto = Matter::Crypto::StandardCrypto.new
      responder = new_responder(crypto, crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH))

      peer_key = crypto.create_key_pair
      sigma1_bytes = crypto.random_bytes(100) # Mock Sigma1 TLV for transcript

      sigma2 = responder.process_sigma1(
        peer_key.public_key,
        crypto.random_bytes(Matter::Session::Case::RANDOM_LENGTH),
        crypto.random_uint16,
        sigma1_bytes
      )

      sigma2[:ephemeral_public_key].size.should eq(65)
      sigma2[:random].size.should eq(Matter::Session::Case::RANDOM_LENGTH)
      # The encrypted cert includes TLV-wrapped NOC + signature + resumption_id + MIC
      sigma2[:encrypted_cert].size.should be > 100
      sigma2[:session_id].should be_a(UInt16)
      sigma2[:sigma2_bytes].size.should be > 0

      responder.ephemeral_key.should_not be_nil
    end

    it "processes Sigma3 and verifies" do
      crypto = Matter::Crypto::StandardCrypto.new
      responder = new_responder(crypto, crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH))

      peer_key = crypto.create_key_pair
      responder.process_sigma1(
        peer_key.public_key,
        crypto.random_bytes(Matter::Session::Case::RANDOM_LENGTH),
        crypto.random_uint16,
        crypto.random_bytes(100)
      )

      # With random data, process_sigma3 returns false (decryption fails)
      responder.process_sigma3(crypto.random_bytes(116), crypto.random_bytes(64)).should be_false
    end
  end

  describe "certificate chain validation" do
    it "behaves identically whichever side it is called from" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)
      authority = crypto.create_key_pair
      initiator = new_initiator(crypto, ipk, authority)
      responder = new_responder(crypto, ipk, authority)

      manager = Matter::Certificate::AttestationCertificateManager.new(0xFFF1_u16)
      roots = [manager.paa_cert] of Bytes | OpenSSL::X509::Certificate
      no_roots = [] of Bytes | OpenSSL::X509::Certificate

      # No peer certificate received yet
      initiator.validate_certificate_chain(roots).should be_false
      responder.validate_certificate_chain(roots).should be_false

      # The PAI is signed by the PAA, so it validates against it on both sides
      initiator.peer_cert = manager.pai_cert
      responder.peer_cert = manager.pai_cert
      initiator.validate_certificate_chain(roots).should be_true
      responder.validate_certificate_chain(roots).should be_true

      # Without a trusted root both reject it
      initiator.validate_certificate_chain(no_roots).should be_false
      responder.validate_certificate_chain(no_roots).should be_false

      # An unparseable peer certificate is rejected, not raised, on both sides
      garbage = crypto.random_bytes(64)
      initiator.peer_cert = garbage
      responder.peer_cert = garbage
      initiator.validate_certificate_chain(roots).should be_false
      responder.validate_certificate_chain(roots).should be_false
    end
  end

  describe "CASE session establishment" do
    it "derives the same session keys on both sides of an in-process handshake" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)
      authority = crypto.create_key_pair
      initiator = new_initiator(crypto, ipk, authority)
      responder = new_responder(crypto, ipk, authority)

      sigma1 = initiator.generate_sigma1(destination_id(crypto))
      sigma2 = responder.process_sigma1(
        sigma1[:ephemeral_public_key],
        sigma1[:random],
        sigma1[:session_id],
        sigma1[:sigma1_bytes]
      )

      sigma2_bytes = sigma2[:sigma2_bytes]
      sigma3 = initiator.process_sigma2(
        Matter::Session::Case::Definitions::Sigma2.from_slice(sigma2_bytes),
        sigma2_bytes
      )

      responder.process_sigma3(sigma3[:encrypted_cert], sigma3[:sigma3_bytes]).should be_true
      responder.peer_cert.should eq(initiator.operational_cert)
      responder.peer_node_id.should eq(NODE_ID)

      initiator_keys = initiator.derive_session_keys
      responder_keys = responder.derive_session_keys(sigma3[:sigma3_bytes])

      # I2R on the initiator is what the responder decrypts with, and vice versa
      initiator_keys[:encryption].size.should eq(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)
      initiator_keys[:encryption].should eq(responder_keys[:decryption])
      initiator_keys[:decryption].should eq(responder_keys[:encryption])
      initiator_keys[:encryption].should_not eq(initiator_keys[:decryption])
      initiator_keys[:attestation_challenge].should eq(responder_keys[:attestation_challenge])
    end

    it "derives the keys the Matter spec constants prescribe" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)
      authority = crypto.create_key_pair
      initiator = new_initiator(crypto, ipk, authority)
      responder = new_responder(crypto, ipk, authority)

      sigma1 = initiator.generate_sigma1(destination_id(crypto))
      sigma2 = responder.process_sigma1(
        sigma1[:ephemeral_public_key],
        sigma1[:random],
        sigma1[:session_id],
        sigma1[:sigma1_bytes]
      )
      sigma2_bytes = sigma2[:sigma2_bytes]
      sigma3 = initiator.process_sigma2(
        Matter::Session::Case::Definitions::Sigma2.from_slice(sigma2_bytes),
        sigma2_bytes
      )

      shared_secret = initiator.shared_secret
      shared_secret.should eq(responder.shared_secret)
      raise "the handshake computed no shared secret" if shared_secret.nil?

      # SessionKeys = HKDF(sharedSecret, IPK ‖ SHA256(sigma1 ‖ sigma2 ‖ sigma3), "SessionKeys", 48)
      transcript_hash = crypto.compute_sha256([sigma1[:sigma1_bytes], sigma2_bytes, sigma3[:sigma3_bytes]])
      salt = IO::Memory.new
      salt.write(ipk)
      salt.write(transcript_hash)
      expected = crypto.create_hkdf_key(
        shared_secret,
        salt.to_slice,
        "SessionKeys".to_slice,
        Matter::Session::Case::SESSION_KEYS_LENGTH
      )

      keys = initiator.derive_session_keys
      keys[:encryption].should eq(expected[0, 16])
      keys[:decryption].should eq(expected[16, 16])
      keys[:attestation_challenge].should eq(expected[32, 16])
    end

    it "establishes matching secure contexts for both ends" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)
      initiator_key = crypto.create_key_pair
      responder_key = crypto.create_key_pair
      authority = crypto.create_key_pair

      contexts = Matter::Session::Case.establish_session(
        initiator_cert: issue(crypto, authority, initiator_key.public_key, NODE_ID),
        initiator_key: initiator_key,
        responder_cert_chain: Matter::Session::Case::OperationalCertChain.new(
          issue(crypto, authority, responder_key.public_key, RESPONDER_NODE_ID)
        ),
        responder_key: responder_key,
        fabric_id: FABRIC_ID,
        initiator_node_id: NODE_ID,
        responder_node_id: RESPONDER_NODE_ID,
        crypto: crypto,
        ipk: ipk,
        root_public_key: authority.public_key
      )

      initiator_context = contexts[:initiator]
      responder_context = contexts[:responder]

      initiator_context.encryption_key.should eq(responder_context.decryption_key)
      initiator_context.decryption_key.should eq(responder_context.encryption_key)
      initiator_context.attestation_challenge.should eq(responder_context.attestation_challenge)
      initiator_context.session_id.should eq(responder_context.peer_session_id)
      initiator_context.peer_session_id.should eq(responder_context.session_id)
      initiator_context.initiator?.should be_true
      responder_context.initiator?.should be_false
      initiator_context.case_session?.should be_true
    end

    it "rejects a peer whose certificate was issued by another root" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)

      # The attacker holds the fabric's IPK, so Sigma1 and the Sigma3 signature
      # both pass, but it signed its own certificate rather than obtaining one.
      attacker_authority = crypto.create_key_pair
      initiator = new_initiator(crypto, ipk, attacker_authority)
      responder = new_responder(crypto, ipk, crypto.create_key_pair)

      sigma1 = initiator.generate_sigma1(destination_id(crypto))
      sigma2 = responder.process_sigma1(
        sigma1[:ephemeral_public_key],
        sigma1[:random],
        sigma1[:session_id],
        sigma1[:sigma1_bytes]
      )

      sigma2_bytes = sigma2[:sigma2_bytes]
      sigma3 = initiator.process_sigma2(
        Matter::Session::Case::Definitions::Sigma2.from_slice(sigma2_bytes),
        sigma2_bytes
      )

      responder.process_sigma3(sigma3[:encrypted_cert], sigma3[:sigma3_bytes]).should be_false
    end

    it "rejects a Sigma3 whose signature does not match the NOC it presents" do
      crypto = Matter::Crypto::StandardCrypto.new
      ipk = crypto.random_bytes(Matter::Session::Case::SYMMETRIC_KEY_LENGTH)

      # The attacker replays a NOC that is not theirs. They reach Sigma3 (the
      # IPK is a fabric secret they hold) but cannot sign TBS_Data3 with the key
      # that NOC names, so they sign with their own.
      authority = crypto.create_key_pair
      victim_key = crypto.create_key_pair
      attacker_key = crypto.create_key_pair
      initiator = Matter::Session::Case::CaseInitiator.new(
        operational_cert: issue(crypto, authority, victim_key.public_key, NODE_ID),
        operational_key: attacker_key,
        fabric_id: FABRIC_ID,
        node_id: NODE_ID,
        ipk: ipk,
        crypto: crypto
      )
      responder = new_responder(crypto, ipk, authority)

      sigma1 = initiator.generate_sigma1(destination_id(crypto))
      sigma2 = responder.process_sigma1(
        sigma1[:ephemeral_public_key],
        sigma1[:random],
        sigma1[:session_id],
        sigma1[:sigma1_bytes]
      )

      sigma2_bytes = sigma2[:sigma2_bytes]
      sigma3 = initiator.process_sigma2(
        Matter::Session::Case::Definitions::Sigma2.from_slice(sigma2_bytes),
        sigma2_bytes
      )

      responder.process_sigma3(sigma3[:encrypted_cert], sigma3[:sigma3_bytes]).should be_false
    end
  end
end
