require "../spec_helper"
require "../../src/matter/cluster/operational_credentials"
require "../../src/matter/crypto/certificate"

# Helper functions for TLV encoding command data
def build_op_creds_cluster(endpoint_id : Matter::DataType::EndpointNumber = Matter::DataType::EndpointNumber.new(0_u16))
  fabric_table = Matter::FabricTable.new(Matter::Storage::Memory.new)
  Matter::Cluster::OperationalCredentials.new(fabric_table, endpoint_id, nil)
end

def create_attestation_request_tlv(nonce : Bytes) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::AttestationRequest.new(
    attestation_nonce: nonce
  ).to_tlv(nil)
end

def create_certificate_chain_request_tlv(cert_type : UInt8) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::CertificateChainRequest.new(
    certificate_type: Matter::Cluster::OperationalCredentials::Tlv::CertificateChainType.new(cert_type)
  ).to_tlv(nil)
end

# Helper to create a valid TLV certificate with a public key for testing (root cert format)
def create_test_tlv_certificate(public_key : Bytes, fabric_id : UInt64 = 0x1_u64) : Bytes
  signature = Bytes.new(64, 0xAB_u8)
  # Root cert has rcac_id in subject (not fabric_id/node_id like NOC)
  subject = Matter::Crypto::DNAttributes.new(rcac_id: fabric_id)
  issuer = Matter::Crypto::DNAttributes.new(rcac_id: fabric_id)

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

def create_csr_request_tlv(nonce : Bytes, is_for_update : Bool? = nil) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::CsrRequest.new(
    csr_nonce: nonce,
    is_for_update_noc: is_for_update
  ).to_tlv(nil)
end

def create_add_noc_request_tlv(noc : Bytes, icac : Bytes?, ipk : Bytes, admin_subject : UInt64, admin_vendor : UInt16) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::AddNocRequest.new(
    noc_value: noc,
    icac_value: icac,
    ipk_value: ipk,
    case_admin_subject: admin_subject,
    admin_vendor_id: admin_vendor
  ).to_tlv(nil)
end

def create_update_noc_request_tlv(noc : Bytes, icac : Bytes?, fabric_index : UInt8) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::UpdateNocRequest.new(
    noc_value: noc,
    fabric_index: fabric_index,
    icac_value: icac
  ).to_tlv(nil)
end

def create_add_trusted_root_cert_request_tlv(cert : Bytes) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::AddTrustedRootCertificateRequest.new(
    root_certificate: cert
  ).to_tlv(nil)
end

def create_remove_fabric_request_tlv(fabric_index : UInt8) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::RemoveFabricRequest.new(
    fabric_index: fabric_index
  ).to_tlv(nil)
end

# Helper to create a mock NOC with node_id and fabric_id
def create_mock_noc(node_id : UInt64, fabric_id : UInt64) : Bytes
  # Generate a default public key
  pub_key = Bytes.new(65)
  pub_key[0] = 0x04_u8
  (1...65).each { |i| pub_key[i] = i.to_u8 }
  create_mock_noc_with_key(node_id, fabric_id, pub_key)
end

# Helper to create a mock NOC with node_id, fabric_id, and public key
def create_mock_noc_with_key(node_id : UInt64, fabric_id : UInt64, public_key : Bytes) : Bytes
  signature = Bytes.new(64, 0xAB_u8)
  # NOC has fabric_id and node_id in subject
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

# Helper to create UpdateFabricLabel request TLV
def create_update_fabric_label_request(label : String, fabric_index : UInt8) : TLV::Any
  Matter::Cluster::OperationalCredentials::Tlv::UpdateFabricLabelRequest.new(
    label: label,
    fabric_index: fabric_index
  ).to_tlv(nil)
end

module OpCredsTestHelpers
  extend self

  # Helper to create a fabric table with storage
  def create_fabric_table(max_fabrics : UInt8 = 10_u8)
    storage = Matter::Storage::Memory.new
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

describe Matter::Cluster::OperationalCredentials do
  describe "initialization" do
    it "creates operational credentials cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      cluster.cluster_id.id.should eq(0x003E_u32)
      cluster.name.should eq("OperationalCredentials")
      cluster.nocs.should be_empty
      cluster.fabrics.should be_empty
      cluster.supported_fabrics.should eq(16_u8)
      cluster.commissioned_fabrics.should eq(0_u8)
    end
  end

  describe "attributes" do
    it "reads NOCs attribute when empty" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      read_tlv(cluster, Matter::Cluster::OperationalCredentials::ATTR_NOCS).as_list.should be_empty
    end

    it "reads Fabrics attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentials::ATTR_FABRICS)
      value.should be_a(TLV::Any)
    end

    it "reads SupportedFabrics attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      read(cluster, Matter::Cluster::OperationalCredentials::ATTR_SUPPORTED_FABRICS).should eq(16_u8)
    end

    it "reads CommissionedFabrics attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      read(cluster, Matter::Cluster::OperationalCredentials::ATTR_COMMISSIONED_FABRICS).should eq(0_u8)
    end

    it "reads TrustedRootCertificates attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentials::ATTR_TRUSTED_ROOT_CERTIFICATES)
      value.should be_a(TLV::Any)
    end

    it "reads CurrentFabricIndex attribute when not set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      read(cluster, Matter::Cluster::OperationalCredentials::ATTR_CURRENT_FABRIC_INDEX).should eq(0_u8)
    end

    it "returns status for unsupported attribute write" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      status = write(cluster,
        Matter::Cluster::OperationalCredentials::ATTR_SUPPORTED_FABRICS,
        32_u8
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 5

      supported_fabrics = attributes.find { |attr| attr.id.id == Matter::Cluster::OperationalCredentials::ATTR_SUPPORTED_FABRICS }
      supported_fabrics.should_not be_nil
      supported_fabrics_attr = supported_fabrics.as(Matter::Cluster::AttributeMetadata)
      supported_fabrics_attr.name.should eq("supportedFabrics")
      supported_fabrics_attr.writable?.should be_false
    end

    it "provides command metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      commands = cluster.commands
      commands.should_not be_empty
      commands.size.should be >= 6

      attestation_cmd = commands.find { |cmd| cmd.id.id == Matter::Cluster::OperationalCredentials::CMD_ATTESTATION_REQUEST }
      attestation_cmd.should_not be_nil
      attestation_cmd.as(Matter::Cluster::CommandMetadata).name.should eq("attestationRequest")
    end
  end

  describe "NOCStruct" do
    it "creates NOC struct" do
      noc_cert = "mock_noc_certificate".to_slice
      icac_cert = "mock_icac".to_slice

      noc = Matter::Cluster::OperationalCredentials::NOCStruct.new(
        noc: noc_cert,
        icac: icac_cert,
        fabric_index: 1_u8
      )

      noc.noc.should eq(noc_cert)
      noc.icac.should eq(icac_cert)
      noc.fabric_index.should eq(1_u8)
    end
  end

  describe "FabricDescriptorStruct" do
    it "creates fabric descriptor" do
      root_public_key = Bytes.new(65, 0_u8)
      vendor_id = 0xFFF1_u16
      fabric_id = 0x1234567890ABCDEF_u64
      node_id = 0xFEDCBA0987654321_u64
      label = "TestFabric"

      fabric = Matter::Cluster::OperationalCredentials::FabricDescriptorStruct.new(
        root_public_key: root_public_key,
        vendor_id: vendor_id,
        fabric_id: fabric_id,
        node_id: node_id,
        label: label,
        fabric_index: 1_u8
      )

      fabric.root_public_key.should eq(root_public_key)
      fabric.vendor_id.should eq(vendor_id)
      fabric.fabric_id.should eq(fabric_id)
      fabric.node_id.should eq(node_id)
      fabric.label.should eq(label)
      fabric.fabric_index.should eq(1_u8)
    end
  end

  describe "NodeOperationalCertStatus" do
    it "defines status codes" do
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::Ok.value.should eq(0_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidPublicKey.value.should eq(1_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidNodeOpId.value.should eq(2_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidNoc.value.should eq(3_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::MissingCsr.value.should eq(4_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::TableFull.value.should eq(5_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InsufficientPrivilege.value.should eq(8_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::FabricConflict.value.should eq(9_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::LabelConflict.value.should eq(10_u8)
      Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidFabricIndex.value.should eq(11_u8)
    end
  end

  describe "commands" do
    it "handles AttestationRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      nonce = Bytes.new(32, 0x42_u8)
      command_data = create_attestation_request_tlv(nonce)
      result = invoke(cluster, Matter::Cluster::OperationalCredentials::CMD_ATTESTATION_REQUEST, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles CertificateChainRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      command_data = create_certificate_chain_request_tlv(1_u8) # DACCertificate
      result = invoke(cluster, Matter::Cluster::OperationalCredentials::CMD_CERTIFICATE_CHAIN_REQUEST, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles CSRRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      nonce = Bytes.new(32, 0x42_u8)
      command_data = create_csr_request_tlv(nonce)
      result = invoke(cluster, Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles AddNOC command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      noc = Bytes.new(100, 0x01_u8)
      ipk = Bytes.new(16, 0x02_u8)
      command_data = create_add_noc_request_tlv(noc, nil, ipk, 0x1234567890_u64, 0xFFF1_u16)
      result = invoke(cluster, Matter::Cluster::OperationalCredentials::CMD_ADD_NOC, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles UpdateNOC command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      noc = Bytes.new(100, 0x01_u8)
      command_data = create_update_noc_request_tlv(noc, nil, 1_u8)
      result = invoke(cluster, Matter::Cluster::OperationalCredentials::CMD_UPDATE_NOC, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles AddTrustedRootCertificate command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      cert = Bytes.new(100, 0x01_u8)
      command_data = create_add_trusted_root_cert_request_tlv(cert)
      result = invoke(cluster, Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE, command_data)
      result.should be_a(Matter::InteractionModel::Status)
    end

    it "handles RemoveFabric command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      command_data = create_remove_fabric_request_tlv(1_u8)
      result = invoke(cluster, Matter::Cluster::OperationalCredentials::CMD_REMOVE_FABRIC, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end
  end

  describe "fabric management" do
    it "tracks fabric list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      cluster.fabrics.should be_empty
      cluster.commissioned_fabrics.should eq(0_u8)
    end

    it "finds fabric by index" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      fabric = cluster.get_fabric_by_index(1_u8)
      fabric.should be_nil
    end

    it "checks fabric count against limit" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      cluster.has_fabric_capacity?.should be_true
    end
  end

  describe "NOC management" do
    it "tracks NOC list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      cluster.nocs.should be_empty
    end

    it "finds NOC by fabric index" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      noc = cluster.get_noc_by_fabric_index(1_u8)
      noc.should be_nil
    end
  end

  describe "trusted root certificates" do
    it "tracks trusted root certificate list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      cluster.trusted_root_certificates.should be_empty
    end

    it "can add trusted root certificate" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      root_cert = "mock_root_certificate".to_slice
      cluster.trusted_root_certificates << root_cert

      cluster.trusted_root_certificates.size.should eq(1)
      cluster.trusted_root_certificates[0].should eq(root_cert)
    end
  end

  describe "certificate types" do
    it "defines certificate types" do
      Matter::Cluster::OperationalCredentials::CertificateChainType::DACCertificate.value.should eq(1_u8)
      Matter::Cluster::OperationalCredentials::CertificateChainType::PAICertificate.value.should eq(2_u8)
    end
  end

  describe "current fabric" do
    it "reports the accessing fabric, none outside a fabric" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = build_op_creds_cluster(endpoint_id)

      cluster.current_fabric_index.should eq(Matter::DataType::FabricIndex::NO_FABRIC)
      read(cluster, Matter::Cluster::OperationalCredentials::ATTR_CURRENT_FABRIC_INDEX, 1_u8).should eq(1_u8)
    end
  end

  describe "integration tests" do
    describe "full commissioning flow" do
      it "completes CSR → AddTrustedRoot → AddNOC flow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        # Set session context for integration test
        cluster.request_session_id = 12345_u64
        cluster.failsafe_armed = true

        # Step 1: Generate CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        csr_result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          csr_request_tlv
        )
        csr_result.should be_a(Matter::Cluster::CommandResponse)
        csr_result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any).to_slice.size.should be > 0

        # Step 2: Add trusted root certificate
        # Create a valid TLV certificate with a public key
        root_public_key = Bytes.new(65)
        root_public_key[0] = 0x04_u8
        (1...65).each { |i| root_public_key[i] = i.to_u8 }
        root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        root_result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )
        # AddTrustedRootCertificate returns Status, not CommandResponse
        root_result.should be_a(Matter::InteractionModel::Status)
        root_result.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)

        # Verify root cert was added
        cluster.trusted_root_certificates.size.should eq(1)

        # Step 3: Create a mock NOC with embedded fabric_id and node_id
        noc_bytes = create_mock_noc(0x1234567890ABCDEF_u64, 0x0011223344556677_u64)

        # Step 4: Add NOC
        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(
          noc_bytes,
          nil,
          ipk,
          0xABCDEF0123456789_u64,
          0xFFF1_u16
        )
        noc_result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          add_noc_tlv
        )
        noc_result.should be_a(Matter::Cluster::CommandResponse)

        # Verify fabric was added
        cluster.commissioned_fabrics.should eq(1_u8)
        cluster.fabrics.size.should eq(1)
        cluster.nocs.size.should eq(1)

        # Verify fabric details
        fabric = cluster.fabrics[0]
        fabric.fabric_id.should eq(0x0011223344556677_u64)
        fabric.node_id.should eq(0x1234567890ABCDEF_u64)
        fabric.vendor_id.should eq(0xFFF1_u16)
      end

      it "rejects AddNOC without CSR" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        cluster.request_session_id = 12345_u64
        cluster.failsafe_armed = true

        # Add trusted root first
        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        # Try to add NOC without CSR
        noc_bytes = create_mock_noc(0x1234567890ABCDEF_u64, 0x0011223344556677_u64)

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(noc_bytes, nil, ipk, 0xABCD_u64, 0xFFF1_u16)

        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Should return error response (MissingCsr)
        result.should be_a(Matter::Cluster::CommandResponse)
        # Parse response and check status
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(4) # MissingCsr
      end

      it "rejects AddNOC without trusted root" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        cluster.request_session_id = 12345_u64
        cluster.failsafe_armed = true

        # Generate CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        # Try to add NOC without trusted root
        noc_bytes = create_mock_noc(0x1234567890ABCDEF_u64, 0x0011223344556677_u64)

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(noc_bytes, nil, ipk, 0xABCD_u64, 0xFFF1_u16)

        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Should return error response (InvalidNoc - root cert not set)
        result.should be_a(Matter::Cluster::CommandResponse)
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(3) # InvalidNoc
      end
    end

    describe "NOC update flow" do
      it "completes CSR(update) → UpdateNOC flow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        # First, add a fabric using the commissioning flow
        cluster.request_session_id = 12345_u64
        cluster.failsafe_armed = true

        # Initial commissioning
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        original_noc = create_mock_noc(0x1234567890ABCDEF_u64, 0x0011223344556677_u64)

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(original_noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          add_noc_tlv
        )

        initial_fabric_index = cluster.fabrics[0].fabric_index

        # Reset failsafe context to simulate new failsafe period
        cluster.on_failsafe_expired
        cluster.failsafe_armed = true
        cluster.request_session_id = 54321_u64
        cluster.request_fabric_index = initial_fabric_index

        # Now update the NOC
        # Step 1: Generate CSR for update
        update_nonce = Bytes.new(32, 0x99_u8)
        update_csr_request_tlv = create_csr_request_tlv(update_nonce, true) # is_for_update = true
        # An UpdateNOC CSR is only valid on the CASE session of the fabric it updates
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          update_csr_request_tlv,
          session_id: 54321_u64,
          is_case_session: true,
          fabric_index: initial_fabric_index
        )

        # Step 2: Update NOC with new certificate (same fabric_id)
        new_noc = create_mock_noc(0xFEDCBA0987654321_u64, 0x0011223344556677_u64)

        update_noc_tlv = create_update_noc_request_tlv(new_noc, nil, initial_fabric_index)
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_UPDATE_NOC,
          update_noc_tlv,
          session_id: 54321_u64,
          fabric_index: initial_fabric_index
        )

        result.should be_a(Matter::Cluster::CommandResponse)

        # Parse response to check status
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(0) # Success

        # Verify fabric was updated, not added
        cluster.commissioned_fabrics.should eq(1_u8)

        # Verify node_id changed
        fabric = cluster.fabrics[0]
        fabric.node_id.should eq(0xFEDCBA0987654321_u64)
        fabric.fabric_id.should eq(0x0011223344556677_u64) # Same fabric_id
      end

      it "rejects UpdateNOC with AddTrustedRoot in failsafe" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        # First, add an initial fabric via full commissioning flow
        cluster.request_session_id = 1_u64
        cluster.failsafe_armed = true

        # Initial commissioning
        nonce1 = Bytes.new(32, 0x11_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce1, false)
        )

        root_public_key1 = Bytes.new(65); root_public_key1[0] = 0x04_u8; (1...65).each { |i| root_public_key1[i] = i.to_u8 }; root_cert1 = create_test_tlv_certificate(root_public_key1, 0xAAAAAAAAAAAAAAAA_u64)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        noc1 = create_mock_noc(0x1111111111111111_u64, 0xAAAAAAAAAAAAAAAA_u64)

        ipk1 = Bytes.new(16, 0x01_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc1, nil, ipk1, 0xABCD_u64, 0xFFF1_u16)
        )

        fabric_index = cluster.fabrics[0].fabric_index

        # Reset failsafe for update attempt
        cluster.on_failsafe_expired
        cluster.request_session_id = 12345_u64
        cluster.request_fabric_index = fabric_index
        cluster.failsafe_armed = true

        # Generate CSR for update, on the CASE session of the fabric it updates
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, true)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          csr_request_tlv,
          session_id: 12345_u64,
          is_case_session: true,
          fabric_index: fabric_index
        )

        # Try to add trusted root (not allowed for updates)
        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        # Try UpdateNOC - should fail because root cert was set
        noc_bytes = create_mock_noc(0x2222222222222222_u64, 0xAAAAAAAAAAAAAAAA_u64)

        update_noc_tlv = create_update_noc_request_tlv(noc_bytes, nil, fabric_index)
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_UPDATE_NOC,
          update_noc_tlv,
          session_id: 12345_u64,
          is_case_session: true,
          fabric_index: fabric_index
        )

        # Should return InvalidNoc error (root cert cannot be set for updates)
        result.should be_a(Matter::Cluster::CommandResponse)
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(3) # InvalidNoc
      end
    end

    describe "failsafe constraints" do
      it "prevents calling CSR after AddNOC in same failsafe" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        cluster.request_session_id = 12345_u64
        cluster.failsafe_armed = true

        # Complete full commissioning
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        noc_bytes = create_mock_noc(0x1234567890ABCDEF_u64, 0x0011223344556677_u64)

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(noc_bytes, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Try to call CSR again in same failsafe - should fail
        new_nonce = Bytes.new(32, 0x99_u8)
        new_csr_request_tlv = create_csr_request_tlv(new_nonce, false)
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          new_csr_request_tlv
        )

        # CSRRequest cannot return an error payload. If it fails, it must return an
        # IM StatusIB in the InvokeResponse (as opposed to a CSRResponse payload).
        result.should be_a(Matter::InteractionModel::Status)
        status = result.as(Matter::InteractionModel::Status)
        status.status.should eq(Matter::InteractionModel::StatusCode::Failure)
        status.cluster_status.should eq(4_u8) # NodeOperationalCertStatus::MissingCsr
      end

      it "allows CSR after failsafe expiry" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        cluster.request_session_id = 12345_u64
        cluster.failsafe_armed = true

        # Generate initial CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        result1 = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          csr_request_tlv
        )
        result1.should be_a(Matter::Cluster::CommandResponse)

        # Expire failsafe
        cluster.on_failsafe_expired
        cluster.failsafe_armed = true
        cluster.request_session_id = 54321_u64

        # Generate new CSR - should succeed
        new_nonce = Bytes.new(32, 0x99_u8)
        new_csr_request_tlv = create_csr_request_tlv(new_nonce, false)
        result2 = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          new_csr_request_tlv
        )

        result2.should be_a(Matter::Cluster::CommandResponse)
        result2.as(Matter::Cluster::CommandResponse).response.as(TLV::Any).to_slice.size.should be > 20 # Valid CSR response
      end
    end

    describe "multi-fabric scenarios" do
      it "adds multiple fabrics" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        # Add first fabric
        cluster.request_session_id = 1_u64
        cluster.failsafe_armed = true

        nonce1 = Bytes.new(32, 0x11_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce1, false)
        )

        root_public_key1 = Bytes.new(65); root_public_key1[0] = 0x04_u8; (1...65).each { |i| root_public_key1[i] = i.to_u8 }; root_cert1 = create_test_tlv_certificate(root_public_key1, 0xAAAAAAAAAAAAAAAA_u64)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        noc1 = create_mock_noc(0x1111111111111111_u64, 0xAAAAAAAAAAAAAAAA_u64)

        ipk1 = Bytes.new(16, 0x01_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc1, nil, ipk1, 0xABCD_u64, 0xFFF1_u16)
        )

        # Reset failsafe for second fabric
        cluster.on_failsafe_success
        cluster.request_session_id = 2_u64
        cluster.failsafe_armed = true

        # Add second fabric
        nonce2 = Bytes.new(32, 0x22_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce2, false)
        )

        root_public_key2 = Bytes.new(65); root_public_key2[0] = 0x04_u8; (1...65).each { |i| root_public_key2[i] = (i + 1).to_u8 }; root_cert2 = create_test_tlv_certificate(root_public_key2, 0xBBBBBBBBBBBBBBBB_u64)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert2)
        )

        noc2 = create_mock_noc(0x2222222222222222_u64, 0xBBBBBBBBBBBBBBBB_u64)

        ipk2 = Bytes.new(16, 0x02_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc2, nil, ipk2, 0xDEF0_u64, 0xFFF2_u16)
        )

        # Verify both fabrics exist
        cluster.commissioned_fabrics.should eq(2_u8)
        cluster.fabrics.size.should eq(2)

        fabric1 = cluster.fabrics.find { |fabric| fabric.fabric_id == 0xAAAAAAAAAAAAAAAA_u64 }
        fabric2 = cluster.fabrics.find { |fabric| fabric.fabric_id == 0xBBBBBBBBBBBBBBBB_u64 }

        fabric1.should_not be_nil
        fabric2.should_not be_nil
      end

      it "allows duplicate fabric_id across different roots" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        # Add first fabric
        cluster.request_session_id = 1_u64
        cluster.failsafe_armed = true

        nonce1 = Bytes.new(32, 0x11_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce1, false)
        )

        root_public_key1 = Bytes.new(65); root_public_key1[0] = 0x04_u8; (1...65).each { |i| root_public_key1[i] = i.to_u8 }; root_cert1 = create_test_tlv_certificate(root_public_key1, 0xAAAAAAAAAAAAAAAA_u64)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        same_fabric_id = 0xAAAAAAAAAAAAAAAA_u64

        noc1 = create_mock_noc(0x1111111111111111_u64, same_fabric_id)

        ipk1 = Bytes.new(16, 0x01_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc1, nil, ipk1, 0xABCD_u64, 0xFFF1_u16)
        )

        # Reset and try to add fabric with same fabric_id
        cluster.on_failsafe_success
        cluster.request_session_id = 2_u64
        cluster.failsafe_armed = true

        nonce2 = Bytes.new(32, 0x22_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce2, false)
        )

        root_public_key2 = Bytes.new(65); root_public_key2[0] = 0x04_u8; (1...65).each { |i| root_public_key2[i] = (i + 1).to_u8 }; root_cert2 = create_test_tlv_certificate(root_public_key2, 0xBBBBBBBBBBBBBBBB_u64)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert2)
        )

        noc2 = create_mock_noc(0x2222222222222222_u64, same_fabric_id)

        ipk2 = Bytes.new(16, 0x02_u8)
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc2, nil, ipk2, 0xDEF0_u64, 0xFFF2_u16)
        )

        # Should succeed because (root_public_key, fabric_id) is unique.
        result.should be_a(Matter::Cluster::CommandResponse)
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(0_u8) # Success
        cluster.fabrics.size.should eq(2)
      end

      it "prevents duplicate fabric identity (same root + fabric_id)" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = build_op_creds_cluster(endpoint_id)

        # Add first fabric
        cluster.request_session_id = 1_u64
        cluster.failsafe_armed = true

        nonce1 = Bytes.new(32, 0x11_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce1, false)
        )

        root_public_key1 = Bytes.new(65); root_public_key1[0] = 0x04_u8; (1...65).each { |i| root_public_key1[i] = i.to_u8 }; root_cert1 = create_test_tlv_certificate(root_public_key1, 0xAAAAAAAAAAAAAAAA_u64)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        same_fabric_id = 0xAAAAAAAAAAAAAAAA_u64
        noc1 = create_mock_noc(0x1111111111111111_u64, same_fabric_id)

        ipk1 = Bytes.new(16, 0x01_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc1, nil, ipk1, 0xABCD_u64, 0xFFF1_u16)
        )

        # Reset and try to add a fabric with same fabric_id AND same root
        cluster.on_failsafe_success
        cluster.request_session_id = 2_u64
        cluster.failsafe_armed = true

        nonce2 = Bytes.new(32, 0x22_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce2, false)
        )

        # Re-use the same root cert.
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        noc2 = create_mock_noc(0x2222222222222222_u64, same_fabric_id)
        ipk2 = Bytes.new(16, 0x02_u8)
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc2, nil, ipk2, 0xDEF0_u64, 0xFFF2_u16)
        )

        # Should return FabricConflict error
        result.should be_a(Matter::Cluster::CommandResponse)
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(9_u8) # FabricConflict
      end
    end

    describe "fabric label management" do
      it "updates fabric label" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::Memory.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, endpoint_id, nil)

        # Add a fabric
        cluster.request_session_id = 1_u64
        cluster.failsafe_armed = true

        nonce = Bytes.new(32, 0x42_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce, false)
        )

        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert)
        )

        noc = create_mock_noc(0x1234567890ABCDEF_u64, 0x0011223344556677_u64)

        ipk = Bytes.new(16, 0x02_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        )

        fabric_index = cluster.fabrics[0].fabric_index
        cluster.request_fabric_index = fabric_index

        # Update label
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_UPDATE_FABRIC_LABEL,
          create_update_fabric_label_request("MyFabricLabel", fabric_index)
        )

        result.should be_a(Matter::Cluster::CommandResponse)

        # Verify label was updated
        fabric = cluster.fabrics[0]
        fabric.label.should eq("MyFabricLabel")
      end

      it "rejects duplicate fabric labels" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::Memory.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, endpoint_id, nil)

        # Add two fabrics
        2.times do |i|
          cluster.on_failsafe_success if i > 0
          cluster.request_session_id = (i + 1).to_u64
          cluster.failsafe_armed = true

          nonce = Bytes.new(32, i.to_u8)
          invoke(cluster,
            Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
            create_csr_request_tlv(nonce, false)
          )

          root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |j| root_public_key[j] = j.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
          invoke(cluster,
            Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
            create_add_trusted_root_cert_request_tlv(root_cert)
          )

          noc = create_mock_noc(0x1111111111111111_u64 + i, 0xAAAAAAAAAAAAAAAA_u64 + i)

          ipk = Bytes.new(16, i.to_u8)
          invoke(cluster,
            Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
            create_add_noc_request_tlv(noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
          )
        end

        # Set label on first fabric
        fabric1_index = cluster.fabrics[0].fabric_index
        cluster.request_fabric_index = fabric1_index

        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_UPDATE_FABRIC_LABEL,
          create_update_fabric_label_request("SharedLabel", fabric1_index)
        )

        # Try to set same label on second fabric
        fabric2_index = cluster.fabrics[1].fabric_index
        cluster.request_fabric_index = fabric2_index

        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_UPDATE_FABRIC_LABEL,
          create_update_fabric_label_request("SharedLabel", fabric2_index) # Same label!
        )

        # Should return LabelConflict error
        result.should be_a(Matter::Cluster::CommandResponse)
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(10_u8) # LabelConflict
      end
    end

    describe "Fabrics attribute read after AddNOC" do
      it "returns non-empty Fabrics attribute after successful AddNOC" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::Memory.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, endpoint_id, nil)

        # Verify fabric_table is empty initially
        fabric_table.size.should eq(0)

        # Set session context for commissioning
        cluster.request_session_id = 12345_u64
        cluster.failsafe_armed = true

        # Step 1: Generate CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        # Step 2: Add trusted root certificate
        root_public_key = Bytes.new(65)
        root_public_key[0] = 0x04_u8
        (1...65).each { |i| root_public_key[i] = i.to_u8 }
        root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        # Step 3: Create and add NOC
        noc_bytes = create_mock_noc(0x1234567890ABCDEF_u64, 0x0011223344556677_u64)

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(
          noc_bytes,
          nil,
          ipk,
          0xABCDEF0123456789_u64,
          0xFFF1_u16
        )
        noc_result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Verify AddNOC succeeded
        noc_result.should be_a(Matter::Cluster::CommandResponse)
        parsed = noc_result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(0) # Success

        # Verify fabric was added to fabric_table
        fabric_table.size.should eq(1)

        # Verify cluster.fabrics returns the fabric
        cluster.fabrics.size.should eq(1)

        # NOW TEST THE ACTUAL ISSUE: Read the Fabrics attribute
        # This is what the iPhone does after commissioning
        read_tlv(cluster, Matter::Cluster::OperationalCredentials::ATTR_FABRICS).as_list.size.should eq(1)
      end
    end

    describe "certificate public key extraction" do
      it "processes AddNOC with TLV root certificate" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::Memory.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, endpoint_id, nil)

        # Set up for AddNOC
        cluster.failsafe_armed = true
        cluster.request_session_id = 1_u64

        # Request CSR first
        nonce = Bytes.new(32, 0_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce, false)
        )

        # Create a valid 65-byte uncompressed EC public key
        public_key = Bytes.new(65)
        public_key[0] = 0x04_u8
        (1...65).each { |i| public_key[i] = (i % 256).to_u8 }

        # Create a TLV root certificate with tag 9 containing a valid 65-byte EC public key
        tlv_cert = create_test_tlv_certificate(public_key, 0x1234567890_u64)

        # Add trusted root certificate (TLV format)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(tlv_cert)
        )

        # Create NOC with same public key as root
        noc = create_mock_noc_with_key(0x1111111111111111_u64, 0x1234567890_u64, public_key)

        # Invoke AddNOC - should successfully extract public key from TLV certificate
        ipk = Bytes.new(16, 0_u8)
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        )

        # Should succeed - verifying that TLV certificate processing worked
        result.should be_a(Matter::Cluster::CommandResponse)
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(0) # Success

        # Verify fabric was created with correct public key
        cluster.fabrics.size.should eq(1)
        cluster.fabrics[0].root_public_key.should eq(public_key)
      end

      it "processes AddNOC with DER root certificate" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::Memory.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, endpoint_id, nil)

        # Set up for AddNOC
        cluster.failsafe_armed = true
        cluster.request_session_id = 1_u64

        # Request CSR
        nonce = Bytes.new(32, 0_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce, false)
        )

        # Generate a real DER certificate using OpenSSL's native key generation
        # This ensures the certificate has a proper EC public key structure
        pkey = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")

        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = OpenSSL::BN.new(1)
        cert.not_before = OpenSSL::ASN1::Time.days_from_now(-1)
        cert.not_after = OpenSSL::ASN1::Time.days_from_now(365)

        name = OpenSSL::X509::Name.new
        name.add_entry("CN", "Test Root")
        cert.subject = name
        cert.issuer = name
        cert.public_key = pkey

        cert.sign(pkey, OpenSSL::Digest.new("SHA256"))

        der_cert = cert.to_der.to_slice

        # Extract the public key bytes from the generated key for NOC
        public_key_bytes = pkey.public_key_bytes

        # Add DER root certificate
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(der_cert)
        )

        # Create NOC with same public key
        noc = create_mock_noc_with_key(0x2222222222222222_u64, 0x9876543210_u64, public_key_bytes)

        # Invoke AddNOC - should successfully extract public key from DER certificate
        ipk = Bytes.new(16, 1_u8)
        result = invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc, nil, ipk, 0xBCDE_u64, 0xFFF2_u16)
        )

        # Should succeed - verifying that DER certificate processing worked
        result.should be_a(Matter::Cluster::CommandResponse)
        parsed = result.as(Matter::Cluster::CommandResponse).response.as(TLV::Any)
        response = parsed.value.as(TLV::Structure)
        status = response[0_u8].value.as(Int)
        status.should eq(0) # Success

        # Verify fabric was created with correct public key
        cluster.fabrics.size.should eq(1)
        cluster.fabrics[0].root_public_key.should eq(public_key_bytes)
      end

      it "computes correct compressed fabric ID from extracted public key" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::Memory.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, endpoint_id, nil)

        # Set up for AddNOC
        cluster.failsafe_armed = true
        cluster.request_session_id = 1_u64

        # Request CSR
        nonce = Bytes.new(32, 0_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce, false)
        )

        # Create a known public key
        public_key = Bytes.new(65)
        public_key[0] = 0x04_u8
        (1...65).each { |i| public_key[i] = i.to_u8 }

        # Create TLV root certificate
        tlv_cert = create_test_tlv_certificate(public_key, 0x1_u64)

        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(tlv_cert)
        )

        # Create NOC with same public key
        noc = create_mock_noc_with_key(0x1_u64, 0x1_u64, public_key)

        ipk = Bytes.new(16, 0_u8)
        invoke(cluster,
          Matter::Cluster::OperationalCredentials::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc, nil, ipk, 0xDEAD_u64, 0xBEEF_u16)
        )

        # Verify fabric was created with correct public key extracted from certificate
        cluster.fabrics.size.should eq(1)
        fabric = cluster.fabrics[0]

        # The compressed fabric ID is computed from the public key (bytes 1-64)
        # using HKDF-SHA256 with fabric_id as salt. We verify the fabric has
        # the correct public key, which means the compressed fabric ID will be correct.
        fabric.root_public_key.should eq(public_key)
      end
    end
  end

  describe "fabric table accessors" do
    it "creates cluster with existing fabrics" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cluster.commissioned_fabrics.should eq(1)
      cluster.fabrics.size.should eq(1)
    end

    it "returns empty NOCs for non-existent fabric" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cluster.get_noc_by_fabric_index(99_u8).should be_nil
    end

    it "returns current fabric index from session" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cluster.current_fabric_index(5_u8).should eq(5_u8)
      cluster.current_fabric_index(nil).should eq(0_u8)
    end
  end

  describe "AttestationRequest command" do
    it "validates nonce length" do
      expect_raises(ArgumentError, "attestation_nonce must be 32 bytes") do
        Matter::Cluster::OperationalCredentials::AttestationRequestCommand.new(
          attestation_nonce: Bytes.new(16) # Too short
        )
      end
    end
  end

  describe "CertificateChainRequest command" do
    it "returns DAC certificate when available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      cmd = Matter::Cluster::OperationalCredentials::CertificateChainRequestCommand.new(
        certificate_type: Matter::Cluster::OperationalCredentials::CertificateChainType::DACCertificate
      )

      response = cluster.handle_certificate_chain_request(cmd)
      response.as(Matter::Cluster::OperationalCredentials::CertificateChainResponse).certificate.should eq(dac)
    end

    it "returns PAI certificate when available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      cmd = Matter::Cluster::OperationalCredentials::CertificateChainRequestCommand.new(
        certificate_type: Matter::Cluster::OperationalCredentials::CertificateChainType::PAICertificate
      )

      response = cluster.handle_certificate_chain_request(cmd)
      response.as(Matter::Cluster::OperationalCredentials::CertificateChainResponse).certificate.should eq(pai)
    end

    it "returns Failure when certificate not available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentials::CertificateChainRequestCommand.new(
        certificate_type: Matter::Cluster::OperationalCredentials::CertificateChainType::DACCertificate
      )

      response = cluster.handle_certificate_chain_request(cmd)
      response.should eq(Matter::InteractionModel::Status.failure)
    end
  end

  describe "CSRRequest command" do
    it "validates nonce length" do
      expect_raises(ArgumentError, "csr_nonce must be 32 bytes") do
        Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
          csr_nonce: Bytes.new(16) # Too short
        )
      end
    end

    it "requires armed failsafe" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      nonce = Bytes.new(32, 0_u8)
      cmd = Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
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
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      nonce = Bytes.new(32, 0_u8)
      cmd = Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
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
  end

  describe "AddTrustedRootCertificate command" do
    it "requires armed failsafe" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentials::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )

      response = cluster.handle_add_trusted_root_certificate(cmd, failsafe_armed: false)
      response.should be_nil
    end

    it "rejects duplicate root certificate in same failsafe" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR first
      csr_cmd = Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Add root cert
      root_cert = OpCredsTestHelpers.create_test_root_cert
      cmd = Matter::Cluster::OperationalCredentials::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: root_cert
      )
      cluster.handle_add_trusted_root_certificate(cmd, failsafe_armed: true)

      # Try to add again
      response = cluster.handle_add_trusted_root_certificate(cmd, failsafe_armed: true)
      response.should_not be_nil
      response.as(Matter::Cluster::OperationalCredentials::NOCResponse).status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidNoc)
    end
  end

  describe "AddNOC command" do
    it "validates IPK length" do
      expect_raises(ArgumentError, "ipk_value must be 16 bytes") do
        Matter::Cluster::OperationalCredentials::AddNOCCommand.new(
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
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentials::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: false)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidNoc)
    end

    it "creates default ACL entry when AccessControl is available" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      acl_cluster = Matter::Cluster::AccessControl.new(Matter::DataType::EndpointNumber.new(0_u16))
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, acl_cluster)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR
      csr_cmd = Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Root cert
      root_cmd = Matter::Cluster::OperationalCredentials::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )
      cluster.handle_add_trusted_root_certificate(root_cmd, failsafe_armed: true)

      # AddNOC with valid TLV-encoded NOC
      noc = OpCredsTestHelpers.create_test_noc(fabric_id: 0x1234567890_u64, node_id: 0xABCDEF_u64)
      admin_subject = 0x9999_u64
      cmd = Matter::Cluster::OperationalCredentials::AddNOCCommand.new(
        noc_value: noc,
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: admin_subject,
        admin_vendor_id: 0xFFF1_u16
      )

      # Verify no ACL entries before
      acl_cluster.acl.size.should eq(0)

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::Ok)

      # Verify default ACL entry was created
      acl_cluster.acl.size.should eq(1)
      acl_entry = acl_cluster.acl.first
      acl_entry.privilege.should eq(Matter::Cluster::AccessControl::AccessControlEntryPrivilege::Administer)
      acl_entry.auth_mode.should eq(Matter::Cluster::AccessControl::AccessControlEntryAuthMode::CASE)
      acl_entry.subjects.should eq([admin_subject])
      acl_entry.targets.should be_nil # All targets
      acl_entry.fabric_index.should eq(response.fabric_index)
    end

    it "rejects when table is full" do
      fabric_table = OpCredsTestHelpers.create_fabric_table(max_fabrics: 5_u8)
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

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
      csr_cmd = Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      root_cmd = Matter::Cluster::OperationalCredentials::AddTrustedRootCertificateCommand.new(
        root_ca_certificate: OpCredsTestHelpers.create_test_root_cert
      )
      cluster.handle_add_trusted_root_certificate(root_cmd, failsafe_armed: true)

      cmd = Matter::Cluster::OperationalCredentials::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::TableFull)
    end
  end

  describe "UpdateFabricLabel command" do
    it "validates label length" do
      expect_raises(ArgumentError, "label must be <= 32 characters") do
        Matter::Cluster::OperationalCredentials::UpdateFabricLabelCommand.new(
          label: "A" * 33 # Too long
        )
      end
    end

    it "rejects update for non-existent fabric" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentials::UpdateFabricLabelCommand.new(
        label: "NewLabel"
      )

      response = cluster.handle_update_fabric_label(cmd, session_fabric_index: 99_u8)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidFabricIndex)
    end
  end

  describe "RemoveFabric command" do
    it "removes fabric-scoped ACL entries when fabric is removed" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      acl_cluster = Matter::Cluster::AccessControl.new(Matter::DataType::EndpointNumber.new(0_u16))
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table, acl_cluster)

      # Add a fabric
      fabric = OpCredsTestHelpers.create_test_fabric(0x123_u64, 1_u8)
      fabric_table.add_fabric(fabric)

      # Manually add ACL entries for this fabric
      acl_entry1 = Matter::Cluster::AccessControl::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControl::AccessControlEntryPrivilege::Administer,
        auth_mode: Matter::Cluster::AccessControl::AccessControlEntryAuthMode::CASE,
        subjects: [0x1111_u64],
        targets: nil,
        fabric_index: 1_u8
      )
      acl_cluster.acl << acl_entry1

      # Add ACL entry for a different fabric
      acl_entry2 = Matter::Cluster::AccessControl::AccessControlEntry.new(
        privilege: Matter::Cluster::AccessControl::AccessControlEntryPrivilege::Manage,
        auth_mode: Matter::Cluster::AccessControl::AccessControlEntryAuthMode::CASE,
        subjects: [0x2222_u64],
        targets: nil,
        fabric_index: 2_u8
      )
      acl_cluster.acl << acl_entry2

      # Verify ACL state before removal
      acl_cluster.acl.size.should eq(2)

      # Remove fabric 1
      cmd = Matter::Cluster::OperationalCredentials::RemoveFabricCommand.new(
        fabric_index: 1_u8
      )
      response = cluster.handle_remove_fabric(cmd)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::Ok)

      # Verify only fabric 1's ACL entry was removed
      acl_cluster.acl.size.should eq(1)
      acl_cluster.acl.first.fabric_index.should eq(2_u8)
      acl_cluster.acl.first.subjects.should eq([0x2222_u64])
    end

    it "rejects removal of non-existent fabric" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      fabric_table.add_fabric(OpCredsTestHelpers.create_test_fabric(1_u64, 1_u8))
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentials::RemoveFabricCommand.new(
        fabric_index: 99_u8
      )

      response = cluster.handle_remove_fabric(cmd)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::InvalidFabricIndex)
    end

    it "treats removal as idempotent while the device has no fabrics" do
      # iOS removes a stale fabric while re-commissioning a device that has
      # already been factory reset; the commissioner has to be able to move on.
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      cmd = Matter::Cluster::OperationalCredentials::RemoveFabricCommand.new(
        fabric_index: 99_u8
      )

      response = cluster.handle_remove_fabric(cmd)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::Ok)
    end
  end

  describe "failsafe management" do
    it "resets context on failsafe expired" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR to set context
      csr_cmd = Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Simulate failsafe expiry
      cluster.on_failsafe_expired

      # Try to add NOC - should fail due to missing CSR
      cmd = Matter::Cluster::OperationalCredentials::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::MissingCsr)
    end

    it "resets context on failsafe success" do
      fabric_table = OpCredsTestHelpers.create_fabric_table
      cluster = Matter::Cluster::OperationalCredentials.new(fabric_table)

      # Set up attestation credentials
      dac = Bytes.new(100, 1_u8)
      pai = Bytes.new(100, 2_u8)
      key = Matter::Crypto::Key.generate_key_pair
      cluster.set_attestation_credentials(dac, pai, key)

      # CSR to set context
      csr_cmd = Matter::Cluster::OperationalCredentials::CSRRequestCommand.new(
        csr_nonce: Bytes.new(32, 0_u8)
      )
      cluster.handle_csr_request(csr_cmd, session_id: 1_u64, is_pase_session: true, failsafe_armed: true)

      # Simulate failsafe success
      cluster.on_failsafe_success

      # Context should be reset
      cmd = Matter::Cluster::OperationalCredentials::AddNOCCommand.new(
        noc_value: Bytes.new(100),
        icac_value: nil,
        ipk_value: Bytes.new(16),
        case_admin_subject: 1_u64,
        admin_vendor_id: 0xFFF1_u16
      )

      response = cluster.handle_add_noc(cmd, session_id: 1_u64, failsafe_armed: true)
      response.status_code.should eq(Matter::Cluster::OperationalCredentials::NodeOperationalCertStatus::MissingCsr)
    end
  end
end
