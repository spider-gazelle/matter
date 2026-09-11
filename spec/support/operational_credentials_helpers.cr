# Fixtures shared by the operational_credentials_*_spec.cr files:
# certificate/NOC builders and the request TLV encoders.
require "../spec_helper"
require "../../src/matter/cluster/operational_credentials"
require "../../src/matter/crypto/certificate"

# Helper functions for TLV encoding command data
def build_op_creds_cluster(endpoint_id : Matter::DataType::EndpointNumber = endpoint(0))
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
