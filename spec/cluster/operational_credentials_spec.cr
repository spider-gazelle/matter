require "../spec_helper"
require "../../src/matter/cluster/operational_credentials_cluster"

# Helper functions for TLV encoding command data
def create_attestation_request_tlv(nonce : Bytes) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  data = {
    0_u8 => nonce,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_certificate_chain_request_tlv(cert_type : UInt8) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  data = {
    0_u8 => cert_type,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_csr_request_tlv(nonce : Bytes, is_for_update : Bool? = nil) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  data = {
    0_u8 => nonce,
  } of TLV::Tag => TLV::Value
  data[1_u8] = is_for_update if is_for_update

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_add_noc_request_tlv(noc : Bytes, icac : Bytes?, ipk : Bytes, admin_subject : UInt64, admin_vendor : UInt16) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # Create DataType wrappers and get their TLV representations
  subject_id = Matter::DataType::SubjectId.new(admin_subject)
  vendor_id = Matter::DataType::VendorId.new(admin_vendor)

  data = {
    0_u8 => noc,
    2_u8 => ipk,
    3_u8 => subject_id.to_h,
    4_u8 => vendor_id.to_h,
  } of TLV::Tag => TLV::Value
  data[1_u8] = icac if icac

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_update_noc_request_tlv(noc : Bytes, icac : Bytes?, fabric_index : UInt8) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # Create FabricIndex wrapper and get its TLV representation
  fabric_idx = Matter::DataType::FabricIndex.new(fabric_index)

  data = {
      0_u8 => noc,
    254_u8 => fabric_idx.to_h,
  } of TLV::Tag => TLV::Value
  data[1_u8] = icac if icac

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_add_trusted_root_cert_request_tlv(cert : Bytes) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  data = {
    0_u8 => cert,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_remove_fabric_request_tlv(fabric_index : UInt8) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # Create FabricIndex wrapper and get its TLV representation
  fabric_idx = Matter::DataType::FabricIndex.new(fabric_index)

  data = {
    0_u8 => fabric_idx.to_h,
  } of TLV::Tag => TLV::Value

  writer.put(nil, data)
  io.rewind.to_slice
end

describe Matter::Cluster::OperationalCredentialsCluster do
  describe "initialization" do
    it "creates operational credentials cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

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
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_NOCS)
      value.should be_a(Bytes)
      # Empty list encoded
      value.as(Bytes).should eq(Bytes.new(0))
    end

    it "reads Fabrics attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_FABRICS)
      value.should be_a(Bytes)
    end

    it "reads SupportedFabrics attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_SUPPORTED_FABRICS)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes[16])
    end

    it "reads CommissionedFabrics attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_COMMISSIONED_FABRICS)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes[0])
    end

    it "reads TrustedRootCertificates attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_TRUSTED_ROOT_CERTIFICATES)
      value.should be_a(Bytes)
    end

    it "reads CurrentFabricIndex attribute when not set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_CURRENT_FABRIC_INDEX)
      value.should be_a(Bytes)
      value.as(Bytes).should eq(Bytes[0])
    end

    it "returns status for unsupported attribute write" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::OperationalCredentialsCluster::ATTR_SUPPORTED_FABRICS,
        Bytes[32]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 5

      supported_fabrics = attributes.find { |a| a.id.id == Matter::Cluster::OperationalCredentialsCluster::ATTR_SUPPORTED_FABRICS }
      supported_fabrics.should_not be_nil
      supported_fabrics.not_nil!.name.should eq("SupportedFabrics")
      supported_fabrics.not_nil!.writable.should be_false
    end

    it "provides command metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      commands = cluster.commands
      commands.should_not be_empty
      commands.size.should be >= 6

      attestation_cmd = commands.find { |c| c.id.id == Matter::Cluster::OperationalCredentialsCluster::CMD_ATTESTATION_REQUEST }
      attestation_cmd.should_not be_nil
      attestation_cmd.not_nil!.name.should eq("AttestationRequest")
    end
  end

  describe "NOCStruct" do
    it "creates NOC struct" do
      noc_cert = "mock_noc_certificate".to_slice
      icac_cert = "mock_icac".to_slice

      noc = Matter::Cluster::OperationalCredentialsCluster::NOCStruct.new(
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

      fabric = Matter::Cluster::OperationalCredentialsCluster::FabricDescriptorStruct.new(
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
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::OK.value.should eq(0_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidPublicKey.value.should eq(1_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidNodeOpId.value.should eq(2_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidNOC.value.should eq(3_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::MissingCsr.value.should eq(4_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::TableFull.value.should eq(5_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InsufficientPrivilege.value.should eq(8_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::FabricConflict.value.should eq(9_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::LabelConflict.value.should eq(10_u8)
      Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidFabricIndex.value.should eq(11_u8)
    end
  end

  describe "commands" do
    it "handles AttestationRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      nonce = Bytes.new(32, 0x42_u8)
      command_data = create_attestation_request_tlv(nonce)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_ATTESTATION_REQUEST, command_data)
      result.should be_a(Bytes)
    end

    it "handles CertificateChainRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      command_data = create_certificate_chain_request_tlv(1_u8) # DACCertificate
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_CERTIFICATE_CHAIN_REQUEST, command_data)
      result.should be_a(Bytes)
    end

    it "handles CSRRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      nonce = Bytes.new(32, 0x42_u8)
      command_data = create_csr_request_tlv(nonce)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST, command_data)
      result.should be_a(Bytes)
    end

    it "handles AddNOC command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      noc = Bytes.new(100, 0x01_u8)
      ipk = Bytes.new(16, 0x02_u8)
      command_data = create_add_noc_request_tlv(noc, nil, ipk, 0x1234567890_u64, 0xFFF1_u16)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC, command_data)
      result.should be_a(Bytes)
    end

    it "handles UpdateNOC command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      noc = Bytes.new(100, 0x01_u8)
      command_data = create_update_noc_request_tlv(noc, nil, 1_u8)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_UPDATE_NOC, command_data)
      result.should be_a(Bytes)
    end

    it "handles AddTrustedRootCertificate command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cert = Bytes.new(100, 0x01_u8)
      command_data = create_add_trusted_root_cert_request_tlv(cert)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE, command_data)
      result.should be_a(Bytes)
    end

    it "handles RemoveFabric command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      command_data = create_remove_fabric_request_tlv(1_u8)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_REMOVE_FABRIC, command_data)
      result.should be_a(Bytes)
    end
  end

  describe "fabric management" do
    it "tracks fabric list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cluster.fabrics.should be_empty
      cluster.commissioned_fabrics.should eq(0_u8)
    end

    it "finds fabric by index" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      fabric = cluster.get_fabric_by_index(1_u8)
      fabric.should be_nil
    end

    it "checks fabric count against limit" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cluster.has_fabric_capacity?.should be_true
    end
  end

  describe "NOC management" do
    it "tracks NOC list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cluster.nocs.should be_empty
    end

    it "finds NOC by fabric index" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      noc = cluster.get_noc_by_fabric_index(1_u8)
      noc.should be_nil
    end
  end

  describe "trusted root certificates" do
    it "tracks trusted root certificate list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cluster.trusted_root_certificates.should be_empty
    end

    it "can add trusted root certificate" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      root_cert = "mock_root_certificate".to_slice
      cluster.trusted_root_certificates << root_cert

      cluster.trusted_root_certificates.size.should eq(1)
      cluster.trusted_root_certificates[0].should eq(root_cert)
    end
  end

  describe "certificate types" do
    it "defines certificate types" do
      Matter::Cluster::OperationalCredentialsCluster::CertificateChainType::DACCertificate.value.should eq(1_u8)
      Matter::Cluster::OperationalCredentialsCluster::CertificateChainType::PAICertificate.value.should eq(2_u8)
    end
  end

  describe "current fabric" do
    it "tracks current fabric index" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cluster.current_fabric_index.should eq(0_u8)
    end

    it "updates current fabric index" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cluster.current_fabric_index = 1_u8
      cluster.current_fabric_index.should eq(1_u8)
    end
  end
end
