require "../src/matter"

Log.setup(:info)

# Example: General Commissioning
#
# This example demonstrates how to use the General Commissioning cluster
# to manage the commissioning flow, fail-safe, and regulatory configuration.

module GeneralCommissioningExample
  # Create a General Commissioning cluster (always on endpoint 0)
  endpoint_id = Matter::DataType::EndpointNumber.new(0_u16)
  cluster = Matter::Cluster::GeneralCommissioningCluster.new(endpoint_id)

  puts "Created General Commissioning Cluster"
  puts "  Cluster ID: 0x#{cluster.cluster_id.id.to_s(16)}"
  puts "  Location Capability: #{cluster.location_capability}"
  puts "  Supports Concurrent Connection: #{cluster.supports_concurrent_connection}"
  puts

  # Set up callbacks
  cluster.on_arm_fail_safe = ->(expiry_seconds : UInt16, breadcrumb : UInt64) {
    puts "Arming fail-safe for #{expiry_seconds} seconds"
    puts "  Breadcrumb: 0x#{breadcrumb.to_s(16)}"

    # Validate parameters
    if expiry_seconds > cluster.basic_commissioning_info.fail_safe_expiry_length
      puts "  ERROR: Expiry seconds exceeds maximum"
      return Matter::Cluster::GeneralCommissioningCluster::CommissioningError::ValueOutsideRange
    end

    # Check if already busy
    if cluster.fail_safe_active && !cluster.is_fail_safe_expired?
      puts "  ERROR: Fail-safe already active"
      return Matter::Cluster::GeneralCommissioningCluster::CommissioningError::BusyWithOtherAdmin
    end

    # Arm the fail-safe
    cluster.arm_fail_safe(expiry_seconds)
    cluster.breadcrumb = breadcrumb

    puts "  SUCCESS: Fail-safe armed until #{cluster.fail_safe_expiry_time}"
    Matter::Cluster::GeneralCommissioningCluster::CommissioningError::OK
  }

  cluster.on_set_regulatory_config = ->(location : Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType, country_code : String, breadcrumb : UInt64) {
    puts "Setting regulatory configuration"
    puts "  Location: #{location}"
    puts "  Country Code: #{country_code}"
    puts "  Breadcrumb: 0x#{breadcrumb.to_s(16)}"

    # Validate fail-safe is active
    unless cluster.fail_safe_active && !cluster.is_fail_safe_expired?
      puts "  ERROR: Fail-safe not active"
      return Matter::Cluster::GeneralCommissioningCluster::CommissioningError::NoFailSafe
    end

    # Validate location against capability
    case cluster.location_capability
    when .indoor?
      unless location.indoor?
        puts "  ERROR: Device only supports indoor use"
        return Matter::Cluster::GeneralCommissioningCluster::CommissioningError::ValueOutsideRange
      end
    when .outdoor?
      unless location.outdoor?
        puts "  ERROR: Device only supports outdoor use"
        return Matter::Cluster::GeneralCommissioningCluster::CommissioningError::ValueOutsideRange
      end
    when .indoor_outdoor?
      # Any location is acceptable
    end

    # Validate country code format (2-letter ISO 3166-1 alpha-2)
    unless country_code.size == 2 && country_code.chars.all?(&.ascii_uppercase?)
      puts "  ERROR: Invalid country code format"
      return Matter::Cluster::GeneralCommissioningCluster::CommissioningError::ValueOutsideRange
    end

    # Apply configuration
    cluster.regulatory_config = location
    cluster.country_code = country_code
    cluster.breadcrumb = breadcrumb

    puts "  SUCCESS: Regulatory configuration updated"
    Matter::Cluster::GeneralCommissioningCluster::CommissioningError::OK
  }

  cluster.on_commissioning_complete = -> {
    puts "Commissioning complete requested"

    # Validate fail-safe is active
    unless cluster.fail_safe_active && !cluster.is_fail_safe_expired?
      puts "  ERROR: Fail-safe not active"
      return Matter::Cluster::GeneralCommissioningCluster::CommissioningError::NoFailSafe
    end

    # Validate regulatory config has been set
    if cluster.country_code == "XX"
      puts "  WARNING: Country code not set, but continuing"
    end

    # Disarm fail-safe
    cluster.disarm_fail_safe
    puts "  SUCCESS: Commissioning complete, fail-safe disarmed"

    Matter::Cluster::GeneralCommissioningCluster::CommissioningError::OK
  }

  # Demonstrate usage
  puts "=== General Commissioning Example ==="
  puts

  # 1. Read cluster attributes
  puts "1. Reading cluster attributes..."
  breadcrumb = cluster.read_attribute(
    Matter::Cluster::GeneralCommissioningCluster::ATTR_BREADCRUMB
  )
  if breadcrumb.is_a?(Bytes)
    io = IO::Memory.new(breadcrumb)
    value = io.read_bytes(UInt64, IO::ByteFormat::LittleEndian)
    puts "  Breadcrumb: 0x#{value.to_s(16)}"
  end

  regulatory = cluster.read_attribute(
    Matter::Cluster::GeneralCommissioningCluster::ATTR_REGULATORY_CONFIG
  )
  puts "  Regulatory Config: #{regulatory.as(Bytes)[0]}" if regulatory.is_a?(Bytes)

  location_cap = cluster.read_attribute(
    Matter::Cluster::GeneralCommissioningCluster::ATTR_LOCATION_CAPABILITY
  )
  puts "  Location Capability: #{location_cap.as(Bytes)[0]}" if location_cap.is_a?(Bytes)

  concurrent = cluster.read_attribute(
    Matter::Cluster::GeneralCommissioningCluster::ATTR_SUPPORTS_CONCURRENT_CONNECTION
  )
  puts "  Supports Concurrent Connection: #{concurrent.as(Bytes)[0] != 0}" if concurrent.is_a?(Bytes)
  puts

  # 2. Check basic commissioning info
  puts "2. Basic commissioning info:"
  info = cluster.basic_commissioning_info
  puts "  Max Fail-Safe Expiry: #{info.fail_safe_expiry_length} seconds"
  puts "  Max Cumulative Fail-Safe: #{info.max_cumulative_failsafe_seconds} seconds"
  puts

  # 3. Set breadcrumb
  puts "3. Setting breadcrumb..."
  io = IO::Memory.new
  io.write_bytes(0x0000000000000001_u64, IO::ByteFormat::LittleEndian)
  breadcrumb_value = io.to_slice

  status = cluster.write_attribute(
    Matter::Cluster::GeneralCommissioningCluster::ATTR_BREADCRUMB,
    breadcrumb_value
  )
  puts "  Status: #{status.status}"
  puts "  Current Breadcrumb: 0x#{cluster.breadcrumb.to_s(16)}"
  puts

  # 4. Arm fail-safe (start commissioning)
  puts "4. Arming fail-safe to start commissioning..."
  arm_callback = cluster.on_arm_fail_safe
  if arm_callback
    error = arm_callback.call(60_u16, 0x0000000000000002_u64)
    puts "  Result: #{error}"
    puts "  Fail-Safe Active: #{cluster.fail_safe_active}"
    puts "  Current Breadcrumb: 0x#{cluster.breadcrumb.to_s(16)}"
  end
  puts

  # 5. Check fail-safe state
  puts "5. Checking fail-safe state..."
  puts "  Active: #{cluster.fail_safe_active}"
  puts "  Expiry Time: #{cluster.fail_safe_expiry_time}"
  puts "  Expired: #{cluster.is_fail_safe_expired?}"
  puts

  # 6. Set regulatory configuration
  puts "6. Setting regulatory configuration..."
  regulatory_callback = cluster.on_set_regulatory_config
  if regulatory_callback
    error = regulatory_callback.call(
      Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
      "US",
      0x0000000000000003_u64
    )
    puts "  Result: #{error}"
    puts "  Regulatory Config: #{cluster.regulatory_config}"
    puts "  Country Code: #{cluster.country_code}"
    puts "  Current Breadcrumb: 0x#{cluster.breadcrumb.to_s(16)}"
  end
  puts

  # 7. Try to set invalid country code
  puts "7. Attempting to set invalid country code..."
  if regulatory_callback
    error = regulatory_callback.call(
      Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor,
      "USA", # Invalid - must be 2 characters
      0x0000000000000004_u64
    )
    puts "  Result: #{error}"
  end
  puts

  # 8. Try to set invalid location
  puts "8. Attempting to set outdoor location on indoor-only device..."
  # First, change location capability to indoor-only
  original_capability = cluster.location_capability
  cluster.location_capability = Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Indoor

  if regulatory_callback
    error = regulatory_callback.call(
      Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::Outdoor,
      "GB",
      0x0000000000000005_u64
    )
    puts "  Result: #{error}"
  end

  # Restore capability
  cluster.location_capability = original_capability
  puts

  # 9. Try to arm fail-safe while already active
  puts "9. Attempting to arm fail-safe while already active..."
  if arm_callback
    error = arm_callback.call(30_u16, 0x0000000000000006_u64)
    puts "  Result: #{error}"
  end
  puts

  # 10. Complete commissioning
  puts "10. Completing commissioning..."
  complete_callback = cluster.on_commissioning_complete
  if complete_callback
    error = complete_callback.call
    puts "  Result: #{error}"
    puts "  Fail-Safe Active: #{cluster.fail_safe_active}"
  end
  puts

  # 11. Try to complete commissioning without fail-safe
  puts "11. Attempting to complete commissioning without fail-safe..."
  if complete_callback
    error = complete_callback.call
    puts "  Result: #{error}"
  end
  puts

  # 12. Demonstrate full commissioning flow
  puts "12. Demonstrating full commissioning flow..."
  puts

  puts "  Step 1: Arm fail-safe"
  if arm_callback
    error = arm_callback.call(120_u16, 0x0000000000000100_u64)
    puts "    Result: #{error}"
  end

  puts
  puts "  Step 2: Set regulatory config"
  if regulatory_callback
    error = regulatory_callback.call(
      Matter::Cluster::GeneralCommissioningCluster::RegulatoryLocationType::IndoorOutdoor,
      "CA",
      0x0000000000000101_u64
    )
    puts "    Result: #{error}"
  end

  puts
  puts "  Step 3: [Other commissioning operations would happen here]"
  puts "    - Network credentials configuration"
  puts "    - Operational credentials installation"
  puts "    - etc."

  puts
  puts "  Step 4: Complete commissioning"
  if complete_callback
    error = complete_callback.call
    puts "    Result: #{error}"
  end
  puts

  # 13. Final state
  puts "13. Final state:"
  puts "  Breadcrumb: 0x#{cluster.breadcrumb.to_s(16)}"
  puts "  Regulatory Config: #{cluster.regulatory_config}"
  puts "  Country Code: #{cluster.country_code}"
  puts "  Fail-Safe Active: #{cluster.fail_safe_active}"
  puts

  # 14. Check cluster metadata
  puts "14. Cluster metadata:"
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

  puts "=== Example Complete ==="
end
