require "./spec_helper"
require "../src/matter/cluster/operational_credentials_cluster"
require "../src/matter/storage/memory_backend"
require "../src/matter/crypto/certificate"

module OpCredsTestHelpers
  extend self

  # Helper to create a fabric table with storage
  def create_fabric_table(max_fabrics : UInt8 = 10_u8)
    storage = Matter::Storage::MemoryBackend.new
    Matter::FabricTable.new(storage, max_fabrics: max_fabrics)
  end

  # Helper to create test credentials
  def create_test_fabric(fabric_id : UInt64, fabric_index : UInt8, label : String = "Test")
    key = Matter::Crypto::Key.generate_key_pair
    Matter::Fabric.new(
      fabric_id: fabric_id,
      fabric_index: fabric_index,
      node_id: 0x1000_u64 + fabric_index,
      root_public_key: Bytes.new(65, 0_u8),
      operational_cert: Bytes.new(100, 0_u8),
      operational_key: key,
      ipk: Bytes.new(16, 0_u8),
      vendor_id: 0xFFF1_u16,
      label: label
    )
  end

  # Helper to create a TLV-encoded test NOC certificate
  # This creates a valid Matter NOC with proper subject DN containing fabricId and nodeId
  def create_test_noc(fabric_id : UInt64 = 0x1234567890_u64, node_id : UInt64 = 0xABCDEF_u64) : Bytes
    # Create a 65-byte uncompressed EC public key (0x04 || x || y)
    public_key = Bytes.new(65, 0_u8)
    public_key[0] = 0x04_u8
    (1..32).each { |i| public_key[i] = i.to_u8 }
    (33..64).each { |i| public_key[i] = (i - 32).to_u8 }

    signature = Bytes.new(64, 0xAB_u8)
    subject = Matter::Crypto::DNAttributes.new(fabric_id: fabric_id, node_id: node_id)
    issuer = Matter::Crypto::DNAttributes.new(rcac_id: 1_u64)

    Matter::Crypto::MatterCertificate.new(
      serial_number: Bytes[0x01],
      signature_algorithm: 1_u8,
      issuer: issuer,
      not_before: 0_u32,
      not_after: 0xFFFFFFFF_u32,
      subject: subject,
      public_key_algorithm: 1_u8,
      elliptic_curve_id: 1_u8,
      ec_public_key: public_key,
      signature: signature
    ).to_slice
  end

  # Helper to create a TLV-encoded root certificate for testing
  # Matter uses TLV-encoded certificates (starting with 0x15)
  # This creates a certificate with a valid public key field (tag 9)
  def create_test_root_cert : Bytes
    # Create a 65-byte uncompressed EC public key (0x04 || x || y)
    public_key = Bytes.new(65, 0_u8)
    public_key[0] = 0x04_u8 # Uncompressed point marker
    # Fill x and y coordinates with test data
    (1..32).each { |i| public_key[i] = i.to_u8 }
    (33..64).each { |i| public_key[i] = (i - 32).to_u8 }

    signature = Bytes.new(64, 0xCD_u8)
    subject = Matter::Crypto::DNAttributes.new(rcac_id: 1_u64)
    issuer = Matter::Crypto::DNAttributes.new(rcac_id: 1_u64)

    Matter::Crypto::MatterCertificate.new(
      serial_number: Bytes[0x01],
      signature_algorithm: 1_u8,
      issuer: issuer,
      not_before: 0_u32,
      not_after: 0xFFFFFFFF_u32,
      subject: subject,
      public_key_algorithm: 1_u8,
      elliptic_curve_id: 1_u8,
      ec_public_key: public_key,
      signature: signature
    ).to_slice
  end
end

describe Matter::Cluster::OperationalCredentialsCluster do
  describe "initialization" do
    it "creates cluster with empty fabric table" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cluster.commissioned_fabrics.should eq(0)
      cluster.fabrics.should be_empty
    end

    it "creates cluster with existing fabrics" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cluster.commissioned_fabrics.should eq(1)
      cluster.fabrics.size.should eq(1)
    end
  end

  describe "attributes" do
    it "returns supported fabrics" do
      fabric_table = OpCredsTestHelpers.create_fabric_table(max_fabrics: 16_u8)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cluster.supported_fabrics.should eq(16_u8)
    end

    it "returns commissioned fabrics count" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cluster.commissioned_fabrics.should eq(0)

      fabric_table.add_fabric(OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8))
      cluster.commissioned_fabrics.should eq(1)

      fabric_table.add_fabric(OpCredsTestHelpers.create_test_fabric(0x456_u64, 2_u8))
      cluster.commissioned_fabrics.should eq(2)
    end

    it "returns fabric descriptors" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8, "TestFabric")
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)
      descriptors = cluster.fabrics

      descriptors.size.should eq(1)
      descriptors[0].fabric_id.should eq(0x123_u64)
      descriptors[0].fabric_index.should eq(1_u8)
      descriptors[0].label.should eq("TestFabric")
    end

    it "returns NOCs for fabric" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)
      nocs = cluster.nocs(1_u8)

      nocs.size.should eq(1)
      nocs[0].fabric_index.should eq(1_u8)
      nocs[0].noc.should eq(fabric.operational_cert)
    end

    it "returns empty NOCs for non-existent fabric" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      nocs = cluster.nocs(99_u8)
      nocs.should be_empty
    end

    it "returns current fabric index from session" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cluster.current_fabric_index(5_u8).should eq(5_u8)
      cluster.current_fabric_index(nil).should eq(0_u8)
    end

    it "returns trusted root certificates" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cluster.trusted_root_certificates.should be_empty
    end
  end

  describe "AttestationRequest command" do
    it "validates nonce length" do
      expect_raises(ArgumentError, "attestation_nonce must be 32 bytes") do
        Matter::Cluster::OperationalCredentialsCluster::AttestationRequestCommand.new(
          attestation_nonce: Bytes.new(16) # Too short
        )
      end
    end

    it "handles valid attestation request" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      nonce = Bytes.new(32, 0_u8)
      cmd = Matter::Cluster::OperationalCredentialsCluster::AttestationRequestCommand.new(
        attestation_nonce: nonce
      )

      response = cluster.handle_attestation_request(cmd, session_id: 1_u64)
      response.attestation_elements.should_not be_nil
      response.attestation_signature.should_not be_nil
      response.attestation_signature.size.should eq(64) # IEEE P1363 format for P-256
    end
  end

  describe "CertificateChainRequest command" do
    it "returns DAC certificate when available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      cmd = Matter::Cluster::OperationalCredentialsCluster::CertificateChainRequestCommand.new(
        certificate_type: Matter::Cluster::OperationalCredentialsCluster::CertificateChainType::DACCertificate
      )

      response = cluster.handle_certificate_chain_request(cmd)
      response.certificate.should eq(dac)
    end

    it "returns PAI certificate when available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      cmd = Matter::Cluster::OperationalCredentialsCluster::CertificateChainRequestCommand.new(
        certificate_type: Matter::Cluster::OperationalCredentialsCluster::CertificateChainType::PAICertificate
      )

      response = cluster.handle_certificate_chain_request(cmd)
      response.certificate.should eq(pai)
    end

    it "raises error when certificate not available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentialsCluster::CertificateChainRequestCommand.new(
        certificate_type: Matter::Cluster::OperationalCredentialsCluster::CertificateChainType::DACCertificate
      )

      expect_raises(Exception, "Certificate not available") do
        cluster.handle_certificate_chain_request(cmd)
      end
    end
  end

  describe "CSRRequest command" do
    it "validates nonce length" do
      expect_raises(ArgumentError, "csr_nonce must be 32 bytes") do
        Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
          csr_nonce: Bytes.new(16) # Too short
        )
      end
    end

    it "requires armed failsafe" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      nonce = Bytes.new(32, 0_u8)
      cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: nonce
      )

      response = cluster.handle_csr_request(
        cmd,
        session_id: 1_u64,
        is_pase_session: true,
        failsafe_armed: false
      )

      response.should be_nil
    end

    it "rejects update NOC request on PASE session" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      nonce = Bytes.new(32, 0_u8)
      cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: nonce,
        is_for_update_noc: true
      )

      response = cluster.handle_csr_request(
        cmd,
        session_id: 1_u64,
        is_pase_session: true, # PASE session
        failsafe_armed: true
      )

      response.should be_nil
    end

    it "handles valid CSR request" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      nonce = Bytes.new(32, 0_u8)
      cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: nonce
      )

      response = cluster.handle_csr_request(
        cmd,
        session_id: 1_u64,
        is_pase_session: true,
        failsafe_armed: true
      )

      response.should_not be_nil
      response.not_nil!.nocsr_elements.should_not be_nil
      response.not_nil!.attestation_signature.should_not be_nil
      response.not_nil!.attestation_signature.size.should eq(64) # IEEE P1363 format for P-256
    end
  end

  describe "AddTrustedRootCertificate command" do
    it "requires armed failsafe" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentialsCluster::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )

      response = cluster.handle_add_trusted_root_certificate(cmd, failsafe_armed: false)
      response.should be_nil
    end

    it "adds trusted root certificate" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # First CSR to arm failsafe context
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      root_cert = OpCredsTestHelpers.create_test_root_cert
      cmd = Matter::Cluster::OperationalCredentialsCluster::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: root_cert
      )

      response = cluster.handle_add_trusted_root_certificate(cmd, failsafe_armed: true)
      response.should be_nil # No response for this command

      cluster.trusted_root_certificates.should contain(root_cert)
    end

    it "rejects duplicate root certificate in same failsafe" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR first
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Add root cert
      root_cert = OpCredsTestHelpers.create_test_root_cert
      cmd = Matter::Cluster::OperationalCredentialsCluster::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: root_cert
      )
      cluster.handle_add_trusted_root_certificate(cmd, failsafe_armed: true)

      # Try to add again
      response = cluster.handle_add_trusted_root_certificate(cmd, failsafe_armed: true)
      response.should_not be_nil
      response.not_nil!.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidNoc)
    end
  end

  describe "AddNOC command" do
    it "validates IPK length" do
      expect_raises(ArgumentError, "ipk_value must be 16 bytes") do
        Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
          noc_value: Bytes.new(100),
          icac_value: nil,
          ipk_value: Bytes.new(8), # Too short
          case_admin_subject: 1_u64,
          admin_vendor_id: 0xFFF1_u16
        )
      end
    end

    it "requires armed failsafe" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: false)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidNoc)
    end

    it "requires CSR from same session" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::MissingCsr)
    end

    it "requires trusted root certificate" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR first
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidNoc)
    end

    it "successfully adds NOC" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Root cert
      root_cmd = Matter::Cluster::OperationalCredentialsCluster::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )
      cluster.handle_add_trusted_root_certificate(root_cmd, failsafe_armed: true)

      # AddNOC with valid TLV-encoded NOC
      noc = OpCredsTestHelpers.create_test_noc(fabric_id: 0x1234567890_u64, node_id: 0xABCDEF_u64)
      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: noc,
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::Ok)
      response.fabric_index.should_not be_nil

      cluster.commissioned_fabrics.should eq(1)
    end

    it "creates default ACL entry when AccessControlCluster is available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      acl_cluster = Matter::Cluster::AccessControlCluster.new(Matter::DataType::EndpointNumber.new(0_u16))
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, acl_cluster)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Root cert
      root_cmd = Matter::Cluster::OperationalCredentialsCluster::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )
      cluster.handle_add_trusted_root_certificate(root_cmd, failsafe_armed: true)

      # AddNOC with valid TLV-encoded NOC
      noc = OpCredsTestHelpers.create_test_noc(fabric_id: 0x1234567890_u64, node_id: 0xABCDEF_u64)
      admin_subject = 0x9999_u64
      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: noc,
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: admin_subject,
        admin_vendor_id: 0xFFF1_u16
      )

      # Verify no ACL entries before
      acl_cluster.acl.size.should eq(0)

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::Ok)

      # Verify default ACL entry was created
      acl_cluster.acl.size.should eq(1)
      acl_entry = acl_cluster.acl.first
      acl_entry.privilege.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer)
      acl_entry.auth_mode.should eq(Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE)
      acl_entry.subjects.should eq([admin_subject])
      acl_entry.targets.should be_nil # All targets
      acl_entry.fabric_index.should eq(response.fabric_index)
    end

    it "rejects when table is full" do
      fabric_table = OpCredsTestHelpers.create_fabric_table(max_fabrics: 5_u8)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # Fill table
      (1..5).each do |i|
        fabric = OpCredsTestHelpers.create_test_fabric(i.to_u64, i.to_u8)
        fabric_table.add_fabric(fabric)
      end

      cluster.commissioned_fabrics.should eq(5)

      # Try to add another
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      root_cmd = Matter::Cluster::OperationalCredentialsCluster::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )
      cluster.handle_add_trusted_root_certificate(root_cmd, failsafe_armed: true)

      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::TableFull)
    end
  end

  describe "UpdateNOC command" do
    it "requires CSR with is_for_update_noc=true" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR without is_for_update_noc
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8),
        is_for_update_noc: false
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: false, failsafe_armed: true)

      cmd = Matter::Cluster::OperationalCredentialsCluster::UpdateNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil
      )

      response = cluster.handle_update_noc(cmd, session_id: 1_u64, session_fabric_index: 1_u8, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::MissingCsr)
    end

    it "rejects if root certificate was set" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR with is_for_update_noc
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8),
        is_for_update_noc: true
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: false, failsafe_armed: true)

      # Add root cert (not allowed for update)
      root_cmd = Matter::Cluster::OperationalCredentialsCluster::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )
      cluster.handle_add_trusted_root_certificate(root_cmd, failsafe_armed: true)

      cmd = Matter::Cluster::OperationalCredentialsCluster::UpdateNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil
      )

      response = cluster.handle_update_noc(cmd, session_id: 1_u64, session_fabric_index: 1_u8, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidNoc)
    end
  end

  describe "UpdateFabricLabel command" do
    it "validates label length" do
      expect_raises(ArgumentError, "label must be <= 32 characters") do
        Matter::Cluster::OperationalCredentialsCluster::UpdateFabricLabelCommand.new(
          label: "A" * 33 # Too long
        )
      end
    end

    it "updates fabric label successfully" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8, "OldLabel")
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentialsCluster::UpdateFabricLabelCommand.new(
        label: "NewLabel"
      )

      response = cluster.handle_update_fabric_label(cmd, session_fabric_index: 1_u8)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::Ok)

      updated_fabric = fabric_table.get_fabric(1_u8)
      updated_fabric.not_nil!.label.should eq("NewLabel")
    end

    it "rejects duplicate label" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric1 = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8, "Label1")
      fabric2 = OpCredsTestHelpers.create_test_fabric(0x456_u64, 2_u8, "Label2")
      fabric_table.add_fabric(fabric1)
      fabric_table.add_fabric(fabric2)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Try to change fabric2's label to "Label1" (duplicate)
      cmd = Matter::Cluster::OperationalCredentialsCluster::UpdateFabricLabelCommand.new(
        label: "Label1"
      )

      response = cluster.handle_update_fabric_label(cmd, session_fabric_index: 2_u8)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::LabelConflict)
    end

    it "rejects update for non-existent fabric" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentialsCluster::UpdateFabricLabelCommand.new(
        label: "NewLabel"
      )

      response = cluster.handle_update_fabric_label(cmd, session_fabric_index: 99_u8)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidFabricIndex)
    end
  end

  describe "RemoveFabric command" do
    it "removes fabric successfully" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)
      cluster.commissioned_fabrics.should eq(1)

      cmd = Matter::Cluster::OperationalCredentialsCluster::RemoveFabricCommand.new(
        fabric_index: 1_u8
      )

      response = cluster.handle_remove_fabric(cmd)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::Ok)

      cluster.commissioned_fabrics.should eq(0)
    end

    it "removes fabric-scoped ACL entries when fabric is removed" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      acl_cluster = Matter::Cluster::AccessControlCluster.new(Matter::DataType::EndpointNumber.new(0_u16))
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, acl_cluster)

      # Add a fabric
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      # Manually add ACL entries for this fabric
      acl_entry1 = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Administer,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 1_u8
      )
      acl_cluster.acl << acl_entry1

      # Add ACL entry for a different fabric
      acl_entry2 = Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::Manage,
        auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
        subjects: [0x2222_u64],
        targets: nil,
        fabric_index: 2_u8
      )
      acl_cluster.acl << acl_entry2

      # Verify ACL state before removal
      acl_cluster.acl.size.should eq(2)

      # Remove fabric 1
      cmd = Matter::Cluster::OperationalCredentialsCluster::RemoveFabricCommand.new(
        fabric_index: 1_u8
      )
      response = cluster.handle_remove_fabric(cmd)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::Ok)

      # Verify only fabric 1's ACL entry was removed
      acl_cluster.acl.size.should eq(1)
      acl_cluster.acl.first.fabric_index.should eq(2_u8)
      acl_cluster.acl.first.subjects.should eq([0x2222_u64])
    end

    it "rejects removal of non-existent fabric" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentialsCluster::RemoveFabricCommand.new(
        fabric_index: 99_u8
      )

      response = cluster.handle_remove_fabric(cmd)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidFabricIndex)
    end
  end

  describe "failsafe management" do
    it "resets context on failsafe expired" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR to set context
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Simulate failsafe expiry
      cluster.on_failsafe_expired

      # Try to add NOC - should fail due to missing CSR
      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::MissingCsr)
    end

    it "resets context on failsafe success" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR to set context
      csr_cmd = Matter::Cluster::OperationalCredentialsCluster::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Simulate failsafe success
      cluster.on_failsafe_success

      # Context should be reset
      cmd = Matter::Cluster::OperationalCredentialsCluster::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::MissingCsr)
    end
  end
end
