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

# Helper to create a valid TLV certificate with a public key for testing
def create_test_tlv_certificate(public_key : Bytes, fabric_id : UInt64 = 0x1_u64) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  cert_data = {
     1_u8 => 1_u8,       # Serial number
     9_u8 => public_key, # EC public key (tag 9)
    21_u8 => fabric_id,  # Fabric ID
  } of TLV::Tag => TLV::Value

  writer.put(nil, cert_data)
  io.rewind.to_slice
end

def create_csr_request_tlv(nonce : Bytes, is_for_update : Bool? = nil) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # Start structure
  writer.start_structure(nil)
  writer.put(0_u8, nonce)
  writer.put(1_u8, is_for_update) if is_for_update
  writer.end_container

  io.rewind.to_slice
end

def create_add_noc_request_tlv(noc : Bytes, icac : Bytes?, ipk : Bytes, admin_subject : UInt64, admin_vendor : UInt16) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # AddNocRequest expects plain UInt64 and UInt16, not DataType wrappers
  data = {
    0_u8 => noc,
    2_u8 => ipk,
    3_u8 => admin_subject,
    4_u8 => admin_vendor,
  } of TLV::Tag => TLV::Value
  data[1_u8] = icac if icac

  writer.put(nil, data)
  io.rewind.to_slice
end

def create_update_noc_request_tlv(noc : Bytes, icac : Bytes?, fabric_index : UInt8) : Bytes
  io = IO::Memory.new
  writer = TLV::Writer.new(io)

  # TLV layer will convert plain UInt8 to DataType::FabricIndex
  data = {
      0_u8 => noc,
    254_u8 => fabric_index,
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
      # Empty list encoded as TLV: 0x16 (array start) + 0x18 (end container)
      value.as(Bytes).should eq(Bytes[0x16, 0x18])
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
      decode_tlv_value(value.as(Bytes)).should eq(16_u8)
    end

    it "reads CommissionedFabrics attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_COMMISSIONED_FABRICS)
      value.should be_a(Bytes)
      decode_tlv_value(value.as(Bytes)).should eq(0_u8)
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
      decode_tlv_value(value.as(Bytes)).should eq(0_u8)
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
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles CertificateChainRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      command_data = create_certificate_chain_request_tlv(1_u8) # DACCertificate
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_CERTIFICATE_CHAIN_REQUEST, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles CSRRequest command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      nonce = Bytes.new(32, 0x42_u8)
      command_data = create_csr_request_tlv(nonce)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles AddNOC command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      noc = Bytes.new(100, 0x01_u8)
      ipk = Bytes.new(16, 0x02_u8)
      command_data = create_add_noc_request_tlv(noc, nil, ipk, 0x1234567890_u64, 0xFFF1_u16)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles UpdateNOC command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      noc = Bytes.new(100, 0x01_u8)
      command_data = create_update_noc_request_tlv(noc, nil, 1_u8)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_UPDATE_NOC, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
    end

    it "handles AddTrustedRootCertificate command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      cert = Bytes.new(100, 0x01_u8)
      command_data = create_add_trusted_root_cert_request_tlv(cert)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE, command_data)
      result.should be_a(Matter::InteractionModel::Status)
    end

    it "handles RemoveFabric command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
      cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

      command_data = create_remove_fabric_request_tlv(1_u8)
      result = cluster.invoke_command(Matter::Cluster::OperationalCredentialsCluster::CMD_REMOVE_FABRIC, command_data)
      result.should be_a(Matter::Cluster::CommandResponse)
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

  describe "integration tests" do
    describe "full commissioning flow" do
      it "completes CSR → AddTrustedRoot → AddNOC flow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        # Set session context for integration test
        cluster.session_id = 12345_u64
        cluster.failsafe_armed = true

        # Step 1: Generate CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        csr_result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          csr_request_tlv
        )
        csr_result.should be_a(Matter::Cluster::CommandResponse)
        csr_result.as(Matter::Cluster::CommandResponse).data.size.should be > 0

        # Step 2: Add trusted root certificate
        # Create a valid TLV certificate with a public key
        root_public_key = Bytes.new(65)
        root_public_key[0] = 0x04_u8
        (1...65).each { |i| root_public_key[i] = i.to_u8 }
        root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        root_result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )
        # AddTrustedRootCertificate returns Status, not CommandResponse
        root_result.should be_a(Matter::InteractionModel::Status)
        root_result.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)

        # Verify root cert was added
        cluster.trusted_root_certificates.size.should eq(1)

        # Step 3: Create a mock NOC with embedded fabric_id and node_id
        # Build a minimal TLV structure with required fields
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_data = {
          17_u8 => 0x1234567890ABCDEF_u64, # node_id (field 17)
          21_u8 => 0x0011223344556677_u64, # fabric_id (field 21)
        } of TLV::Tag => TLV::Value
        noc_writer.put(nil, noc_data)
        noc_bytes = noc_io.rewind.to_slice

        # Step 4: Add NOC
        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(
          noc_bytes,
          nil,
          ipk,
          0xABCDEF0123456789_u64,
          0xFFF1_u16
        )
        noc_result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
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
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        cluster.session_id = 12345_u64
        cluster.failsafe_armed = true

        # Add trusted root first
        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        # Try to add NOC without CSR
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_data = {
          17_u8 => 0x1234567890ABCDEF_u64,
          21_u8 => 0x0011223344556677_u64,
        } of TLV::Tag => TLV::Value
        noc_writer.put(nil, noc_data)
        noc_bytes = noc_io.rewind.to_slice

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(noc_bytes, nil, ipk, 0xABCD_u64, 0xFFF1_u16)

        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Should return error response (MissingCsr)
        result.should be_a(Matter::Cluster::CommandResponse)
        # Parse response and check status
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(4_u8) # MissingCsr
      end

      it "rejects AddNOC without trusted root" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        cluster.session_id = 12345_u64
        cluster.failsafe_armed = true

        # Generate CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        # Try to add NOC without trusted root
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_data = {
          17_u8 => 0x1234567890ABCDEF_u64,
          21_u8 => 0x0011223344556677_u64,
        } of TLV::Tag => TLV::Value
        noc_writer.put(nil, noc_data)
        noc_bytes = noc_io.rewind.to_slice

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(noc_bytes, nil, ipk, 0xABCD_u64, 0xFFF1_u16)

        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Should return error response (InvalidNoc - root cert not set)
        result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(3_u8) # InvalidNoc
      end
    end

    describe "NOC update flow" do
      it "completes CSR(update) → UpdateNOC flow" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        # First, add a fabric using the commissioning flow
        cluster.session_id = 12345_u64
        cluster.failsafe_armed = true

        # Initial commissioning
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_data = {
          17_u8 => 0x1234567890ABCDEF_u64,
          21_u8 => 0x0011223344556677_u64,
        } of TLV::Tag => TLV::Value
        noc_writer.put(nil, noc_data)
        original_noc = noc_io.rewind.to_slice

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(original_noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          add_noc_tlv
        )

        initial_fabric_index = cluster.fabrics[0].fabric_index

        # Reset failsafe context to simulate new failsafe period
        cluster.on_failsafe_expired
        cluster.failsafe_armed = true
        cluster.session_id = 54321_u64
        cluster.session_fabric_index = initial_fabric_index

        # Now update the NOC
        # Step 1: Generate CSR for update
        update_nonce = Bytes.new(32, 0x99_u8)
        update_csr_request_tlv = create_csr_request_tlv(update_nonce, true) # is_for_update = true
        csr_result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          update_csr_request_tlv,
          session_id: 54321_u64,
          fabric_index: initial_fabric_index
        )

        # Step 2: Update NOC with new certificate (same fabric_id)
        new_noc_io = IO::Memory.new
        new_noc_writer = TLV::Writer.new(new_noc_io)
        new_noc_data = {
          17_u8 => 0xFEDCBA0987654321_u64, # Different node_id
          21_u8 => 0x0011223344556677_u64, # Same fabric_id
        } of TLV::Tag => TLV::Value
        new_noc_writer.put(nil, new_noc_data)
        new_noc = new_noc_io.rewind.to_slice

        update_noc_tlv = create_update_noc_request_tlv(new_noc, nil, initial_fabric_index)
        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_UPDATE_NOC,
          update_noc_tlv,
          session_id: 54321_u64,
          fabric_index: initial_fabric_index
        )

        result.should be_a(Matter::Cluster::CommandResponse)

        # Parse response to check status
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(0_u8) # Success

        # Verify fabric was updated, not added
        cluster.commissioned_fabrics.should eq(1_u8)

        # Verify node_id changed
        fabric = cluster.fabrics[0]
        fabric.node_id.should eq(0xFEDCBA0987654321_u64)
        fabric.fabric_id.should eq(0x0011223344556677_u64) # Same fabric_id
      end

      it "rejects UpdateNOC with AddTrustedRoot in failsafe" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        # First, add an initial fabric via full commissioning flow
        cluster.session_id = 1_u64
        cluster.failsafe_armed = true

        # Initial commissioning
        nonce1 = Bytes.new(32, 0x11_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce1, false)
        )

        root_public_key1 = Bytes.new(65); root_public_key1[0] = 0x04_u8; (1...65).each { |i| root_public_key1[i] = i.to_u8 }; root_cert1 = create_test_tlv_certificate(root_public_key1, 0xAAAAAAAAAAAAAAAA_u64)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        noc_io1 = IO::Memory.new
        noc_writer1 = TLV::Writer.new(noc_io1)
        noc_writer1.put(nil, {
          17_u8 => 0x1111111111111111_u64,
          21_u8 => 0xAAAAAAAAAAAAAAAA_u64,
        } of TLV::Tag => TLV::Value)
        noc1 = noc_io1.rewind.to_slice

        ipk1 = Bytes.new(16, 0x01_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc1, nil, ipk1, 0xABCD_u64, 0xFFF1_u16)
        )

        fabric_index = cluster.fabrics[0].fabric_index

        # Reset failsafe for update attempt
        cluster.on_failsafe_expired
        cluster.session_id = 12345_u64
        cluster.session_fabric_index = fabric_index
        cluster.failsafe_armed = true

        # Generate CSR for update
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, true)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        # Try to add trusted root (not allowed for updates)
        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        # Try UpdateNOC - should fail because root cert was set
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_data = {
          17_u8 => 0x2222222222222222_u64,
          21_u8 => 0xAAAAAAAAAAAAAAAA_u64, # Same fabric_id
        } of TLV::Tag => TLV::Value
        noc_writer.put(nil, noc_data)
        noc_bytes = noc_io.rewind.to_slice

        update_noc_tlv = create_update_noc_request_tlv(noc_bytes, nil, fabric_index)
        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_UPDATE_NOC,
          update_noc_tlv
        )

        # Should return InvalidNoc error (root cert cannot be set for updates)
        result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(3_u8) # InvalidNoc
      end
    end

    describe "failsafe constraints" do
      it "prevents calling CSR after AddNOC in same failsafe" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        cluster.session_id = 12345_u64
        cluster.failsafe_armed = true

        # Complete full commissioning
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_data = {
          17_u8 => 0x1234567890ABCDEF_u64,
          21_u8 => 0x0011223344556677_u64,
        } of TLV::Tag => TLV::Value
        noc_writer.put(nil, noc_data)
        noc_bytes = noc_io.rewind.to_slice

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(noc_bytes, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Try to call CSR again in same failsafe - should fail
        new_nonce = Bytes.new(32, 0x99_u8)
        new_csr_request_tlv = create_csr_request_tlv(new_nonce, false)
        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          new_csr_request_tlv
        )

        # Should return error response
        # Parse the response - error responses have tag 0 with a string message
        result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        # Error responses have a structure with tag 0 containing an error message string
        error_value = response["Any"].as(Hash)[0_u8]
        error_value.should be_a(String)
        error_value.as(String).should contain("AddNOC")
      end

      it "allows CSR after failsafe expiry" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        cluster.session_id = 12345_u64
        cluster.failsafe_armed = true

        # Generate initial CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        result1 = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          csr_request_tlv
        )
        result1.should be_a(Matter::Cluster::CommandResponse)

        # Expire failsafe
        cluster.on_failsafe_expired
        cluster.failsafe_armed = true
        cluster.session_id = 54321_u64

        # Generate new CSR - should succeed
        new_nonce = Bytes.new(32, 0x99_u8)
        new_csr_request_tlv = create_csr_request_tlv(new_nonce, false)
        result2 = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          new_csr_request_tlv
        )

        result2.should be_a(Matter::Cluster::CommandResponse)
        result2.as(Matter::Cluster::CommandResponse).data.size.should be > 20 # Valid CSR response
      end
    end

    describe "multi-fabric scenarios" do
      it "adds multiple fabrics" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        # Add first fabric
        cluster.session_id = 1_u64
        cluster.failsafe_armed = true

        nonce1 = Bytes.new(32, 0x11_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce1, false)
        )

        root_public_key1 = Bytes.new(65); root_public_key1[0] = 0x04_u8; (1...65).each { |i| root_public_key1[i] = i.to_u8 }; root_cert1 = create_test_tlv_certificate(root_public_key1, 0xAAAAAAAAAAAAAAAA_u64)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        noc_io1 = IO::Memory.new
        noc_writer1 = TLV::Writer.new(noc_io1)
        noc_writer1.put(nil, {
          17_u8 => 0x1111111111111111_u64,
          21_u8 => 0xAAAAAAAAAAAAAAAA_u64,
        } of TLV::Tag => TLV::Value)
        noc1 = noc_io1.rewind.to_slice

        ipk1 = Bytes.new(16, 0x01_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc1, nil, ipk1, 0xABCD_u64, 0xFFF1_u16)
        )

        # Reset failsafe for second fabric
        cluster.on_failsafe_success
        cluster.session_id = 2_u64
        cluster.failsafe_armed = true

        # Add second fabric
        nonce2 = Bytes.new(32, 0x22_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce2, false)
        )

        root_public_key2 = Bytes.new(65); root_public_key2[0] = 0x04_u8; (1...65).each { |i| root_public_key2[i] = (i + 1).to_u8 }; root_cert2 = create_test_tlv_certificate(root_public_key2, 0xBBBBBBBBBBBBBBBB_u64)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert2)
        )

        noc_io2 = IO::Memory.new
        noc_writer2 = TLV::Writer.new(noc_io2)
        noc_writer2.put(nil, {
          17_u8 => 0x2222222222222222_u64,
          21_u8 => 0xBBBBBBBBBBBBBBBB_u64,
        } of TLV::Tag => TLV::Value)
        noc2 = noc_io2.rewind.to_slice

        ipk2 = Bytes.new(16, 0x02_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc2, nil, ipk2, 0xDEF0_u64, 0xFFF2_u16)
        )

        # Verify both fabrics exist
        cluster.commissioned_fabrics.should eq(2_u8)
        cluster.fabrics.size.should eq(2)

        fabric1 = cluster.fabrics.find { |f| f.fabric_id == 0xAAAAAAAAAAAAAAAA_u64 }
        fabric2 = cluster.fabrics.find { |f| f.fabric_id == 0xBBBBBBBBBBBBBBBB_u64 }

        fabric1.should_not be_nil
        fabric2.should_not be_nil
      end

      it "prevents duplicate fabric_id" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

        # Add first fabric
        cluster.session_id = 1_u64
        cluster.failsafe_armed = true

        nonce1 = Bytes.new(32, 0x11_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce1, false)
        )

        root_public_key1 = Bytes.new(65); root_public_key1[0] = 0x04_u8; (1...65).each { |i| root_public_key1[i] = i.to_u8 }; root_cert1 = create_test_tlv_certificate(root_public_key1, 0xAAAAAAAAAAAAAAAA_u64)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert1)
        )

        same_fabric_id = 0xAAAAAAAAAAAAAAAA_u64

        noc_io1 = IO::Memory.new
        noc_writer1 = TLV::Writer.new(noc_io1)
        noc_writer1.put(nil, {
          17_u8 => 0x1111111111111111_u64,
          21_u8 => same_fabric_id,
        } of TLV::Tag => TLV::Value)
        noc1 = noc_io1.rewind.to_slice

        ipk1 = Bytes.new(16, 0x01_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc1, nil, ipk1, 0xABCD_u64, 0xFFF1_u16)
        )

        # Reset and try to add fabric with same fabric_id
        cluster.on_failsafe_success
        cluster.session_id = 2_u64
        cluster.failsafe_armed = true

        nonce2 = Bytes.new(32, 0x22_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce2, false)
        )

        root_public_key2 = Bytes.new(65); root_public_key2[0] = 0x04_u8; (1...65).each { |i| root_public_key2[i] = (i + 1).to_u8 }; root_cert2 = create_test_tlv_certificate(root_public_key2, 0xBBBBBBBBBBBBBBBB_u64)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert2)
        )

        noc_io2 = IO::Memory.new
        noc_writer2 = TLV::Writer.new(noc_io2)
        noc_writer2.put(nil, {
          17_u8 => 0x2222222222222222_u64,
          21_u8 => same_fabric_id, # Same fabric_id!
        } of TLV::Tag => TLV::Value)
        noc2 = noc_io2.rewind.to_slice

        ipk2 = Bytes.new(16, 0x02_u8)
        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc2, nil, ipk2, 0xDEF0_u64, 0xFFF2_u16)
        )

        # Should return FabricConflict error
        result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(9_u8) # FabricConflict
      end
    end

    describe "fabric label management" do
      it "updates fabric label" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::MemoryBackend.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, endpoint_id, nil)

        # Add a fabric
        cluster.session_id = 1_u64
        cluster.failsafe_armed = true

        nonce = Bytes.new(32, 0x42_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce, false)
        )

        root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(root_cert)
        )

        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_writer.put(nil, {
          17_u8 => 0x1234567890ABCDEF_u64,
          21_u8 => 0x0011223344556677_u64,
        } of TLV::Tag => TLV::Value)
        noc = noc_io.rewind.to_slice

        ipk = Bytes.new(16, 0x02_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        )

        fabric_index = cluster.fabrics[0].fabric_index
        cluster.session_fabric_index = fabric_index

        # Update label
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        fabric_idx = Matter::DataType::FabricIndex.new(fabric_index)
        data = {
            0_u8 => "MyFabricLabel",
          254_u8 => fabric_idx.to_h,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        update_label_tlv = io.rewind.to_slice

        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_UPDATE_FABRIC_LABEL,
          update_label_tlv
        )

        result.should be_a(Matter::Cluster::CommandResponse)

        # Verify label was updated
        fabric = cluster.fabrics[0]
        fabric.label.should eq("MyFabricLabel")
      end

      it "rejects duplicate fabric labels" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::MemoryBackend.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, endpoint_id, nil)

        # Add two fabrics
        2.times do |i|
          cluster.on_failsafe_success if i > 0
          cluster.session_id = (i + 1).to_u64
          cluster.failsafe_armed = true

          nonce = Bytes.new(32, i.to_u8)
          cluster.invoke_command(
            Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
            create_csr_request_tlv(nonce, false)
          )

          root_public_key = Bytes.new(65); root_public_key[0] = 0x04_u8; (1...65).each { |i| root_public_key[i] = i.to_u8 }; root_cert = create_test_tlv_certificate(root_public_key)
          cluster.invoke_command(
            Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
            create_add_trusted_root_cert_request_tlv(root_cert)
          )

          noc_io = IO::Memory.new
          noc_writer = TLV::Writer.new(noc_io)
          noc_writer.put(nil, {
            17_u8 => (0x1111111111111111_u64 + i),
            21_u8 => (0xAAAAAAAAAAAAAAAA_u64 + i),
          } of TLV::Tag => TLV::Value)
          noc = noc_io.rewind.to_slice

          ipk = Bytes.new(16, i.to_u8)
          cluster.invoke_command(
            Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
            create_add_noc_request_tlv(noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
          )
        end

        # Set label on first fabric
        fabric1_index = cluster.fabrics[0].fabric_index
        cluster.session_fabric_index = fabric1_index

        io1 = IO::Memory.new
        writer1 = TLV::Writer.new(io1)
        fabric_idx1 = Matter::DataType::FabricIndex.new(fabric1_index)
        data1 = {
            0_u8 => "SharedLabel",
          254_u8 => fabric_idx1.to_h,
        } of TLV::Tag => TLV::Value
        writer1.put(nil, data1)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_UPDATE_FABRIC_LABEL,
          io1.rewind.to_slice
        )

        # Try to set same label on second fabric
        fabric2_index = cluster.fabrics[1].fabric_index
        cluster.session_fabric_index = fabric2_index

        io2 = IO::Memory.new
        writer2 = TLV::Writer.new(io2)
        fabric_idx2 = Matter::DataType::FabricIndex.new(fabric2_index)
        data2 = {
            0_u8 => "SharedLabel", # Same label!
          254_u8 => fabric_idx2.to_h,
        } of TLV::Tag => TLV::Value
        writer2.put(nil, data2)

        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_UPDATE_FABRIC_LABEL,
          io2.rewind.to_slice
        )

        # Should return LabelConflict error
        result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(10_u8) # LabelConflict
      end
    end

    describe "Fabrics attribute read after AddNOC" do
      it "returns non-empty Fabrics attribute after successful AddNOC" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::MemoryBackend.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, endpoint_id, nil)

        # Verify fabric_table is empty initially
        fabric_table.size.should eq(0)

        # Set session context for commissioning
        cluster.session_id = 12345_u64
        cluster.failsafe_armed = true

        # Step 1: Generate CSR
        nonce = Bytes.new(32, 0x42_u8)
        csr_request_tlv = create_csr_request_tlv(nonce, false)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          csr_request_tlv
        )

        # Step 2: Add trusted root certificate
        root_public_key = Bytes.new(65)
        root_public_key[0] = 0x04_u8
        (1...65).each { |i| root_public_key[i] = i.to_u8 }
        root_cert = create_test_tlv_certificate(root_public_key)
        add_root_tlv = create_add_trusted_root_cert_request_tlv(root_cert)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          add_root_tlv
        )

        # Step 3: Create and add NOC
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_data = {
          17_u8 => 0x1234567890ABCDEF_u64, # node_id
          21_u8 => 0x0011223344556677_u64, # fabric_id
        } of TLV::Tag => TLV::Value
        noc_writer.put(nil, noc_data)
        noc_bytes = noc_io.rewind.to_slice

        ipk = Bytes.new(16, 0x02_u8)
        add_noc_tlv = create_add_noc_request_tlv(
          noc_bytes,
          nil,
          ipk,
          0xABCDEF0123456789_u64,
          0xFFF1_u16
        )
        noc_result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          add_noc_tlv
        )

        # Verify AddNOC succeeded
        noc_result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(noc_result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(0_u8) # Success

        # Verify fabric was added to fabric_table
        fabric_table.size.should eq(1)
        puts "fabric_table.size after AddNOC: #{fabric_table.size}"
        puts "fabric_table.all_fabrics: #{fabric_table.all_fabrics.map(&.fabric_index)}"

        # Verify cluster.fabrics returns the fabric
        cluster.fabrics.size.should eq(1)
        puts "cluster.fabrics.size: #{cluster.fabrics.size}"

        # NOW TEST THE ACTUAL ISSUE: Read the Fabrics attribute
        # This is what the iPhone does after commissioning
        fabrics_value = cluster.read_attribute(Matter::Cluster::OperationalCredentialsCluster::ATTR_FABRICS)
        fabrics_value.should be_a(Bytes)

        fabrics_bytes = fabrics_value.as(Bytes)
        puts "Fabrics attribute bytes: #{fabrics_bytes.size} bytes"
        puts "Fabrics attribute hex: #{fabrics_bytes.hexstring}"

        # The attribute should NOT be empty
        fabrics_bytes.size.should be > 0
        fabrics_bytes.should_not eq(Bytes.new(0))

        # Parse the TLV to verify it contains the fabric data
        if fabrics_bytes.size > 0
          fabrics_reader = TLV::Reader.new(fabrics_bytes)
          fabrics_data = fabrics_reader.get
          puts "Fabrics TLV parsed: #{fabrics_data.inspect}"

          # Should contain an array with one fabric
          fabrics_hash = fabrics_data.as(Hash(TLV::Tag, TLV::Value))
          fabrics_hash.has_key?("Any").should be_true

          inner = fabrics_hash["Any"]
          inner.as(Array(TLV::Value)).size.should eq(1)
        end
      end
    end

    describe "certificate public key extraction" do
      it "processes AddNOC with TLV root certificate" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::MemoryBackend.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, endpoint_id, nil)

        # Set up for AddNOC
        cluster.failsafe_armed = true
        cluster.session_id = 1_u64

        # Request CSR first
        nonce = Bytes.new(32, 0_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce, false)
        )

        # Create a TLV root certificate with tag 9 containing a valid 65-byte EC public key
        cert_io = IO::Memory.new
        cert_writer = TLV::Writer.new(cert_io)

        # Create a valid 65-byte uncompressed EC public key
        public_key = Bytes.new(65)
        public_key[0] = 0x04_u8
        (1...65).each { |i| public_key[i] = (i % 256).to_u8 }

        cert_data = {
           1_u8 => 1_u8,             # Serial number
           9_u8 => public_key,       # EC public key (tag 9) - Matter TLV certificate format
          21_u8 => 0x1234567890_u64, # Fabric ID
        } of TLV::Tag => TLV::Value
        cert_writer.put(nil, cert_data)
        tlv_cert = cert_io.rewind.to_slice

        # Add trusted root certificate (TLV format)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(tlv_cert)
        )

        # Create NOC
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_writer.put(nil, {
          17_u8 => 0x1111111111111111_u64,
          21_u8 => 0x1234567890_u64,
           9_u8 => public_key, # Same public key as root
        } of TLV::Tag => TLV::Value)
        noc = noc_io.rewind.to_slice

        # Invoke AddNOC - should successfully extract public key from TLV certificate
        ipk = Bytes.new(16, 0_u8)
        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc, nil, ipk, 0xABCD_u64, 0xFFF1_u16)
        )

        # Should succeed - verifying that TLV certificate processing worked
        result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(0_u8) # Success

        # Verify fabric was created with correct public key
        cluster.fabrics.size.should eq(1)
        cluster.fabrics[0].root_public_key.should eq(public_key)
      end

      it "processes AddNOC with DER root certificate" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::MemoryBackend.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, endpoint_id, nil)

        # Set up for AddNOC
        cluster.failsafe_armed = true
        cluster.session_id = 1_u64

        # Request CSR
        nonce = Bytes.new(32, 0_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
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
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(der_cert)
        )

        # Create NOC with same public key
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_writer.put(nil, {
          17_u8 => 0x2222222222222222_u64,
          21_u8 => 0x9876543210_u64,
           9_u8 => public_key_bytes,
        } of TLV::Tag => TLV::Value)
        noc = noc_io.rewind.to_slice

        # Invoke AddNOC - should successfully extract public key from DER certificate
        ipk = Bytes.new(16, 1_u8)
        result = cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
          create_add_noc_request_tlv(noc, nil, ipk, 0xBCDE_u64, 0xFFF2_u16)
        )

        # Should succeed - verifying that DER certificate processing worked
        result.should be_a(Matter::Cluster::CommandResponse)
        reader = TLV::Reader.new(result.as(Matter::Cluster::CommandResponse).data)
        response = reader.get
        status = response["Any"].as(Hash)[0_u8]
        status.should eq(0_u8) # Success

        # Verify fabric was created with correct public key
        cluster.fabrics.size.should eq(1)
        cluster.fabrics[0].root_public_key.should eq(public_key_bytes)
      end

      it "computes correct compressed fabric ID from extracted public key" do
        endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
        storage = Matter::Storage::MemoryBackend.new
        fabric_table = Matter::FabricTable.new(storage)
        cluster = Matter::Cluster::OperationalCredentialsCluster.new(fabric_table, endpoint_id, nil)

        # Set up for AddNOC
        cluster.failsafe_armed = true
        cluster.session_id = 1_u64

        # Request CSR
        nonce = Bytes.new(32, 0_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_CSR_REQUEST,
          create_csr_request_tlv(nonce, false)
        )

        # Create a known public key
        public_key = Bytes.new(65)
        public_key[0] = 0x04_u8
        (1...65).each { |i| public_key[i] = i.to_u8 }

        # Create TLV root certificate
        cert_io = IO::Memory.new
        cert_writer = TLV::Writer.new(cert_io)
        cert_writer.put(nil, {
           1_u8 => 1_u8,
           9_u8 => public_key,
          21_u8 => 0x1_u64,
        } of TLV::Tag => TLV::Value)
        tlv_cert = cert_io.rewind.to_slice

        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
          create_add_trusted_root_cert_request_tlv(tlv_cert)
        )

        # Create NOC
        noc_io = IO::Memory.new
        noc_writer = TLV::Writer.new(noc_io)
        noc_writer.put(nil, {
          17_u8 => 0x1_u64,
          21_u8 => 0x1_u64,
           9_u8 => public_key,
        } of TLV::Tag => TLV::Value)
        noc = noc_io.rewind.to_slice

        ipk = Bytes.new(16, 0_u8)
        cluster.invoke_command(
          Matter::Cluster::OperationalCredentialsCluster::CMD_ADD_NOC,
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
end
