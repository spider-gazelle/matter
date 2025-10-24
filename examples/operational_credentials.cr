require "../src/matter"

Log.setup(:info)

# Example: Operational Credentials Management
#
# This example demonstrates how to use the Operational Credentials cluster
# to manage device certificates and fabric membership during Matter commissioning.

module OperationalCredentialsExample
  # Create an Operational Credentials cluster (always on endpoint 0)
  endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
  cluster = Matter::Cluster::OperationalCredentialsCluster.new(endpoint_id)

  puts "Created Operational Credentials Cluster"
  puts "  Cluster ID: 0x#{cluster.cluster_id.id.to_s(16)}"
  puts "  Supported Fabrics: #{cluster.supported_fabrics}"
  puts "  Commissioned Fabrics: #{cluster.commissioned_fabrics}"
  puts

  # Set up Device Attestation Certificate (DAC) and key
  # In a real device, these would be provisioned during manufacturing
  puts "=== Device Attestation Setup ==="
  dac_key = Matter::Crypto.create_key_pair
  puts "Generated DAC key pair"

  # Mock DAC certificate (in reality this would be a proper X.509 cert)
  cluster.dac_certificate = "MOCK_DAC_CERTIFICATE_DER_ENCODED".to_slice
  cluster.dac_private_key = dac_key
  puts "Loaded Device Attestation Certificate (DAC)"
  puts

  # Set up Product Attestation Intermediate (PAI) certificate
  cluster.pai_certificate = "MOCK_PAI_CERTIFICATE_DER_ENCODED".to_slice
  puts "Loaded Product Attestation Intermediate (PAI)"
  puts

  # Set up callbacks for attestation and CSR
  cluster.on_attestation_request = ->(nonce : Bytes) {
    puts "Attestation requested with nonce: #{nonce.hexstring}"

    # In a real implementation:
    # 1. Build attestation elements TLV structure
    # 2. Sign with DAC private key
    # 3. Return attestation elements and signature

    attestation_elements = "MOCK_ATTESTATION_ELEMENTS".to_slice
    signature = "MOCK_ATTESTATION_SIGNATURE".to_slice

    puts "  Generated attestation response"
    {attestation_elements, signature}
  }

  cluster.on_csr_request = ->(nonce : Bytes) {
    puts "Certificate Signing Request (CSR) with nonce: #{nonce.hexstring}"

    # In a real implementation:
    # 1. Generate new operational key pair
    # 2. Build CSR elements TLV structure
    # 3. Sign with the new operational private key
    # 4. Return CSR elements and signature

    csr_elements = "MOCK_CSR_ELEMENTS".to_slice
    csr_signature = "MOCK_CSR_SIGNATURE".to_slice

    puts "  Generated CSR response"
    {csr_elements, csr_signature}
  }

  cluster.on_add_noc = ->(noc : Bytes, icac : Bytes?, ipk : Bytes, case_admin_subject : UInt64, admin_vendor_id : UInt16) {
    puts "Adding Node Operational Certificate (NOC)"
    puts "  Admin Subject: 0x#{case_admin_subject.to_s(16)}"
    puts "  Admin Vendor ID: 0x#{admin_vendor_id.to_s(16)}"

    # Validate NOC
    # In a real implementation:
    # 1. Verify NOC is signed by a trusted root
    # 2. Extract fabric ID and node ID from NOC
    # 3. Allocate fabric index

    # Check capacity
    unless cluster.has_fabric_capacity?
      puts "  ERROR: Fabric table full"
      return Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::TableFull
    end

    # Allocate fabric index
    fabric_index = cluster.allocate_fabric_index
    unless fabric_index
      puts "  ERROR: No fabric index available"
      return Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::TableFull
    end

    # Store NOC
    noc_struct = Matter::Cluster::OperationalCredentialsCluster::NOCStruct.new(
      noc: noc,
      icac: icac,
      fabric_index: fabric_index
    )
    cluster.nocs << noc_struct

    # Create fabric descriptor
    # In reality, these would be extracted from the NOC
    root_public_key = Bytes.new(65, 0_u8)
    fabric_id = 0x1234567890ABCDEF_u64
    node_id = 0xFEDCBA0987654321_u64

    fabric = Matter::Cluster::OperationalCredentialsCluster::FabricDescriptorStruct.new(
      root_public_key: root_public_key,
      vendor_id: admin_vendor_id,
      fabric_id: fabric_id,
      node_id: node_id,
      label: "Fabric #{fabric_index}",
      fabric_index: fabric_index
    )
    cluster.fabrics << fabric

    cluster.update_commissioned_fabrics
    cluster.current_fabric_index = fabric_index

    puts "  SUCCESS: Added NOC with fabric index #{fabric_index}"
    puts "  Fabric ID: 0x#{fabric_id.to_s(16)}"
    puts "  Node ID: 0x#{node_id.to_s(16)}"

    Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::OK
  }

  cluster.on_remove_fabric = ->(fabric_index : UInt8) {
    puts "Removing fabric with index #{fabric_index}"

    # Find and remove fabric
    fabric = cluster.get_fabric_by_index(fabric_index)
    unless fabric
      puts "  ERROR: Fabric index not found"
      return Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::InvalidFabricIndex
    end

    # Remove NOC and fabric
    cluster.nocs.reject! { |n| n.fabric_index == fabric_index }
    cluster.fabrics.reject! { |f| f.fabric_index == fabric_index }

    cluster.update_commissioned_fabrics

    # Reset current fabric index if we removed the current fabric
    if cluster.current_fabric_index == fabric_index
      cluster.current_fabric_index = 0_u8
    end

    puts "  SUCCESS: Removed fabric #{fabric_index}"
    Matter::Cluster::OperationalCredentialsCluster::NodeOperationalCertStatus::OK
  }

  # Demonstrate usage
  puts "=== Operational Credentials Example ==="
  puts

  # 1. Read cluster attributes
  puts "1. Reading cluster attributes..."
  supported = cluster.read_attribute(
    Matter::Cluster::OperationalCredentialsCluster::ATTR_SUPPORTED_FABRICS
  )
  puts "  Supported Fabrics: #{supported.as(Bytes)[0]}" if supported.is_a?(Bytes)

  commissioned = cluster.read_attribute(
    Matter::Cluster::OperationalCredentialsCluster::ATTR_COMMISSIONED_FABRICS
  )
  puts "  Commissioned Fabrics: #{commissioned.as(Bytes)[0]}" if commissioned.is_a?(Bytes)

  current = cluster.read_attribute(
    Matter::Cluster::OperationalCredentialsCluster::ATTR_CURRENT_FABRIC_INDEX
  )
  puts "  Current Fabric Index: #{current.as(Bytes)[0]}" if current.is_a?(Bytes)
  puts

  # 2. Simulate attestation request
  puts "2. Simulating attestation request..."
  attestation_callback = cluster.on_attestation_request
  if attestation_callback
    nonce = Matter::Crypto.random_bytes(32)
    elements, signature = attestation_callback.call(nonce)
    puts "  Attestation Elements: #{elements.size} bytes"
    puts "  Signature: #{signature.size} bytes"
  end
  puts

  # 3. Simulate CSR request
  puts "3. Simulating CSR request..."
  csr_callback = cluster.on_csr_request
  if csr_callback
    nonce = Matter::Crypto.random_bytes(32)
    csr_elements, csr_signature = csr_callback.call(nonce)
    puts "  CSR Elements: #{csr_elements.size} bytes"
    puts "  CSR Signature: #{csr_signature.size} bytes"
  end
  puts

  # 4. Add trusted root certificate
  puts "4. Adding trusted root certificate..."
  root_cert = "MOCK_ROOT_CERTIFICATE_DER_ENCODED".to_slice
  cluster.trusted_root_certificates << root_cert
  puts "  Added root certificate (#{root_cert.size} bytes)"
  puts "  Total trusted roots: #{cluster.trusted_root_certificates.size}"
  puts

  # 5. Add NOC (commission device to fabric)
  puts "5. Adding Node Operational Certificate (NOC)..."
  add_noc_callback = cluster.on_add_noc
  if add_noc_callback
    mock_noc = "MOCK_NOC_CERTIFICATE_DER_ENCODED".to_slice
    mock_icac = "MOCK_ICAC_CERTIFICATE_DER_ENCODED".to_slice
    mock_ipk = Matter::Crypto.random_bytes(16)
    admin_subject = 0x1122334455667788_u64
    admin_vendor = 0xFFF1_u16

    status = add_noc_callback.call(mock_noc, mock_icac, mock_ipk, admin_subject, admin_vendor)
    puts "  Status: #{status}"
  end
  puts

  # 6. Check fabric state
  puts "6. Checking fabric state..."
  puts "  Commissioned Fabrics: #{cluster.commissioned_fabrics}"
  puts "  Current Fabric Index: #{cluster.current_fabric_index}"
  puts "  Fabrics:"
  cluster.fabrics.each do |fabric|
    puts "    - Index #{fabric.fabric_index}: #{fabric.label}"
    puts "      Vendor ID: 0x#{fabric.vendor_id.to_s(16)}"
    puts "      Fabric ID: 0x#{fabric.fabric_id.to_s(16)}"
    puts "      Node ID: 0x#{fabric.node_id.to_s(16)}"
  end
  puts

  # 7. Add another fabric
  puts "7. Adding a second fabric..."
  if add_noc_callback
    mock_noc2 = "MOCK_NOC_CERTIFICATE_2_DER_ENCODED".to_slice
    mock_ipk2 = Matter::Crypto.random_bytes(16)
    admin_subject2 = 0x8877665544332211_u64
    admin_vendor2 = 0xFFF2_u16

    status = add_noc_callback.call(mock_noc2, nil, mock_ipk2, admin_subject2, admin_vendor2)
    puts "  Status: #{status}"
    puts "  Commissioned Fabrics: #{cluster.commissioned_fabrics}"
  end
  puts

  # 8. List all NOCs
  puts "8. Listing all NOCs..."
  cluster.nocs.each do |noc|
    puts "  - Fabric Index #{noc.fabric_index}:"
    puts "      NOC: #{noc.noc.size} bytes"
    if icac = noc.icac
      puts "      ICAC: #{icac.size} bytes"
    else
      puts "      ICAC: none"
    end
  end
  puts

  # 9. Check fabric capacity
  puts "9. Checking fabric capacity..."
  puts "  Has capacity: #{cluster.has_fabric_capacity?}"
  puts "  Used: #{cluster.commissioned_fabrics}/#{cluster.supported_fabrics}"
  puts

  # 10. Remove a fabric
  puts "10. Removing fabric 1..."
  remove_callback = cluster.on_remove_fabric
  if remove_callback
    status = remove_callback.call(1_u8)
    puts "  Status: #{status}"
    puts "  Commissioned Fabrics: #{cluster.commissioned_fabrics}"
    puts "  Remaining fabrics:"
    cluster.fabrics.each do |fabric|
      puts "    - Index #{fabric.fabric_index}: #{fabric.label}"
    end
  end
  puts

  # 11. Check cluster metadata
  puts "11. Cluster metadata:"
  puts "  Name: #{cluster.name}"
  puts "  Attributes: #{cluster.attributes.size}"
  cluster.attributes.each do |attr|
    puts "    - #{attr.name} (0x#{attr.id.id.to_s(16)}): writable=#{attr.writable}"
  end
  puts
  puts "  Commands: #{cluster.commands.size}"
  cluster.commands.each do |cmd|
    puts "    - #{cmd.name} (0x#{cmd.id.id.to_s(16)})"
  end
  puts

  # 12. Final state
  puts "12. Final state:"
  puts "  Total NOCs: #{cluster.nocs.size}"
  puts "  Total Fabrics: #{cluster.fabrics.size}"
  puts "  Trusted Root Certificates: #{cluster.trusted_root_certificates.size}"
  puts "  Current Fabric Index: #{cluster.current_fabric_index}"
  puts

  puts "=== Example Complete ==="
end
