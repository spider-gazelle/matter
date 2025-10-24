require "../src/matter"

Log.setup(:info)

# Example: Administrator Commissioning
#
# This example demonstrates how to use the Administrator Commissioning cluster
# to manage commissioning windows for adding new administrators to a Matter device.

module AdministratorCommissioningExample
  # Create an Administrator Commissioning cluster (always on endpoint 0)
  endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
  cluster = Matter::Cluster::AdministratorCommissioningCluster.new(endpoint_id)

  puts "Created Administrator Commissioning Cluster"
  puts "  Cluster ID: 0x#{cluster.cluster_id.id.to_s(16)}"
  puts "  Window Status: #{cluster.window_status}"
  puts

  # Set up callbacks
  cluster.on_open_commissioning_window = ->(timeout : UInt16, verifier : Bytes, discriminator : UInt16, iterations : Bytes, salt : UInt32, fabric_index : UInt8, vendor_id : UInt16) {
    puts "Opening Enhanced Commissioning Window"
    puts "  Timeout: #{timeout} seconds"
    puts "  Discriminator: #{discriminator}"
    puts "  PAKE Verifier: #{verifier.size} bytes"
    puts "  Iterations: #{iterations.size} bytes"
    puts "  Salt: 0x#{salt.to_s(16)}"
    puts "  Fabric Index: #{fabric_index}"
    puts "  Vendor ID: 0x#{vendor_id.to_s(16)}"

    # Check if window already open
    if cluster.is_window_open? && !cluster.is_window_expired?
      puts "  ERROR: Commissioning window already open"
      return Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy
    end

    # Validate parameters
    if verifier.size != 97
      puts "  ERROR: Invalid PAKE verifier size (expected 97 bytes)"
      return Matter::Cluster::AdministratorCommissioningCluster::StatusCode::PAKEParameterError
    end

    # Store PAKE parameters
    cluster.pake_verifier = verifier
    cluster.discriminator = discriminator
    cluster.iterations = salt # Note: In real impl, parse iterations from bytes
    cluster.salt = iterations # Note: In real impl, salt is separate

    # Open enhanced window
    cluster.open_enhanced_window(timeout, fabric_index, vendor_id)

    puts "  SUCCESS: Enhanced commissioning window opened"
    puts "  Window expires at: #{cluster.window_timeout}"
    Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy # Return success (no error)
  }

  cluster.on_open_basic_commissioning_window = ->(timeout : UInt16, fabric_index : UInt8, vendor_id : UInt16) {
    puts "Opening Basic Commissioning Window"
    puts "  Timeout: #{timeout} seconds"
    puts "  Fabric Index: #{fabric_index}"
    puts "  Vendor ID: 0x#{vendor_id.to_s(16)}"

    # Check if window already open
    if cluster.is_window_open? && !cluster.is_window_expired?
      puts "  ERROR: Commissioning window already open"
      return Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy
    end

    # Open basic window
    cluster.open_basic_window(timeout, fabric_index, vendor_id)

    puts "  SUCCESS: Basic commissioning window opened"
    puts "  Window expires at: #{cluster.window_timeout}"
    Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy # Return success (no error)
  }

  cluster.on_revoke_commissioning = -> {
    puts "Revoking Commissioning Window"

    # Check if window is open
    unless cluster.is_window_open?
      puts "  ERROR: No commissioning window open"
      return Matter::Cluster::AdministratorCommissioningCluster::StatusCode::WindowNotOpen
    end

    # Close the window
    cluster.close_window

    puts "  SUCCESS: Commissioning window closed"
    Matter::Cluster::AdministratorCommissioningCluster::StatusCode::Busy # Return success (no error)
  }

  # Demonstrate usage
  puts "=== Administrator Commissioning Example ==="
  puts

  # 1. Read cluster attributes
  puts "1. Reading cluster attributes..."
  window_status = cluster.read_attribute(
    Matter::Cluster::AdministratorCommissioningCluster::ATTR_WINDOW_STATUS
  )
  puts "  Window Status: #{window_status.as(Bytes)[0]}" if window_status.is_a?(Bytes)

  admin_fabric = cluster.read_attribute(
    Matter::Cluster::AdministratorCommissioningCluster::ATTR_ADMIN_FABRIC_INDEX
  )
  if admin_fabric.is_a?(Bytes) && admin_fabric.size > 0
    puts "  Admin Fabric Index: #{admin_fabric[0]}"
  else
    puts "  Admin Fabric Index: null"
  end

  admin_vendor = cluster.read_attribute(
    Matter::Cluster::AdministratorCommissioningCluster::ATTR_ADMIN_VENDOR_ID
  )
  if admin_vendor.is_a?(Bytes) && admin_vendor.size > 0
    io = IO::Memory.new(admin_vendor)
    vendor = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
    puts "  Admin Vendor ID: 0x#{vendor.to_s(16)}"
  else
    puts "  Admin Vendor ID: null"
  end
  puts

  # 2. Check window state
  puts "2. Checking window state..."
  puts "  Is window open: #{cluster.is_window_open?}"
  puts "  Window status: #{cluster.window_status}"
  puts

  # 3. Open basic commissioning window
  puts "3. Opening basic commissioning window..."
  basic_callback = cluster.on_open_basic_commissioning_window
  if basic_callback
    status = basic_callback.call(180_u16, 1_u8, 0xFFF1_u16)
    puts "  Status: #{status}"
  end
  puts

  # 4. Check window state after opening
  puts "4. Checking window state after opening..."
  puts "  Is window open: #{cluster.is_window_open?}"
  puts "  Window status: #{cluster.window_status}"
  puts "  Admin Fabric Index: #{cluster.admin_fabric_index}"
  puts "  Admin Vendor ID: 0x#{cluster.admin_vendor_id.not_nil!.to_s(16)}"
  puts "  Window timeout: #{cluster.window_timeout}"
  puts "  Is expired: #{cluster.is_window_expired?}"
  puts

  # 5. Try to open another window while one is already open
  puts "5. Attempting to open another window..."
  if basic_callback
    status = basic_callback.call(120_u16, 2_u8, 0xFFF2_u16)
    puts "  Status: #{status}"
  end
  puts

  # 6. Revoke the commissioning window
  puts "6. Revoking commissioning window..."
  revoke_callback = cluster.on_revoke_commissioning
  if revoke_callback
    status = revoke_callback.call
    puts "  Status: #{status}"
  end
  puts

  # 7. Check window state after revocation
  puts "7. Checking window state after revocation..."
  puts "  Is window open: #{cluster.is_window_open?}"
  puts "  Window status: #{cluster.window_status}"
  puts "  Admin Fabric Index: #{cluster.admin_fabric_index.inspect}"
  puts "  Admin Vendor ID: #{cluster.admin_vendor_id.inspect}"
  puts

  # 8. Try to revoke when no window is open
  puts "8. Attempting to revoke when no window is open..."
  if revoke_callback
    status = revoke_callback.call
    puts "  Status: #{status}"
  end
  puts

  # 9. Open enhanced commissioning window
  puts "9. Opening enhanced commissioning window..."
  enhanced_callback = cluster.on_open_commissioning_window
  if enhanced_callback
    # Generate mock PAKE parameters
    verifier = Bytes.new(97, 0xAB_u8)
    iterations = Bytes.new(4, 0xCD_u8)
    salt = 0x12345678_u32

    status = enhanced_callback.call(
      300_u16,
      verifier,
      3840_u16,
      iterations,
      salt,
      1_u8,
      0xFFF1_u16
    )
    puts "  Status: #{status}"
  end
  puts

  # 10. Check enhanced window state
  puts "10. Checking enhanced window state..."
  puts "  Is window open: #{cluster.is_window_open?}"
  puts "  Window status: #{cluster.window_status}"
  puts "  Window type: #{cluster.window_status.enhanced_window_open? ? "Enhanced" : "Basic"}"
  puts "  Discriminator: #{cluster.discriminator}"
  puts "  PAKE Verifier size: #{cluster.pake_verifier.not_nil!.size} bytes"
  puts

  # 11. Try to open enhanced window with invalid verifier
  puts "11. Attempting to open with invalid PAKE verifier..."
  if enhanced_callback
    invalid_verifier = Bytes.new(50, 0xEF_u8) # Wrong size
    iterations = Bytes.new(4, 0xCD_u8)
    salt = 0x87654321_u32

    status = enhanced_callback.call(
      300_u16,
      invalid_verifier,
      3840_u16,
      iterations,
      salt,
      2_u8,
      0xFFF2_u16
    )
    puts "  Status: #{status}"
  end
  puts

  # 12. Close the enhanced window
  puts "12. Closing enhanced window..."
  if revoke_callback
    status = revoke_callback.call
    puts "  Status: #{status}"
  end
  puts

  # 13. Demonstrate window expiration
  puts "13. Demonstrating window expiration..."
  if basic_callback
    # Open with 0 second timeout (expires immediately)
    puts "  Opening window with 0 second timeout..."
    status = basic_callback.call(0_u16, 1_u8, 0xFFF1_u16)
    puts "  Window opened: #{cluster.is_window_open?}"
    puts "  Window expired: #{cluster.is_window_expired?}"
  end
  puts

  # 14. Read final attributes
  puts "14. Reading final attributes..."
  window_status = cluster.read_attribute(
    Matter::Cluster::AdministratorCommissioningCluster::ATTR_WINDOW_STATUS
  )
  puts "  Window Status: #{window_status.as(Bytes)[0]}" if window_status.is_a?(Bytes)

  if cluster.admin_fabric_index
    puts "  Admin Fabric Index: #{cluster.admin_fabric_index}"
  else
    puts "  Admin Fabric Index: null"
  end

  if cluster.admin_vendor_id
    puts "  Admin Vendor ID: 0x#{cluster.admin_vendor_id.not_nil!.to_s(16)}"
  else
    puts "  Admin Vendor ID: null"
  end
  puts

  # 15. Check cluster metadata
  puts "15. Cluster metadata:"
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

  # 16. Use case: Multi-admin provisioning
  puts "16. Use case: Multi-admin provisioning scenario"
  puts "  Scenario: Adding a new administrator to an already-commissioned device"
  puts

  puts "  Step 1: Current admin opens basic commissioning window"
  if basic_callback
    status = basic_callback.call(900_u16, 1_u8, 0xFFF1_u16)
    puts "    Current admin (Fabric 1, Vendor 0xFFF1) opens window"
    puts "    Status: #{status}"
  end

  puts
  puts "  Step 2: New administrator discovers device"
  puts "    New admin scans for commissionable devices via mDNS"
  puts "    Device advertises _matterc._udp service"

  puts
  puts "  Step 3: New administrator commissions device"
  puts "    New admin (Fabric 2) establishes PASE session"
  puts "    New admin installs operational credentials"
  puts "    Device now has 2 fabrics"

  puts
  puts "  Step 4: Window automatically closes"
  if revoke_callback
    status = revoke_callback.call
    puts "    Commissioning complete, window revoked"
    puts "    Status: #{status}"
  end

  puts
  puts "  Result: Device now has multiple administrators from different fabrics"
  puts

  puts "=== Example Complete ==="
end
