require "../src/matter"

Log.setup(:info)

# Example: Network Commissioning for WiFi
#
# This example demonstrates how to use the Network Commissioning cluster
# to configure WiFi networks on a Matter device during commissioning.

module NetworkCommissioningExample
  # Create a WiFi Network Commissioning cluster
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
  cluster = Matter::Cluster::NetworkCommissioningCluster.new(
    endpoint_id,
    Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi,
    Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
  )

  puts "Created Network Commissioning Cluster"
  puts "  Cluster ID: 0x#{cluster.cluster_id.id.to_s(16)}"
  puts "  Network Type: #{cluster.network_type}"
  puts "  Max Networks: #{cluster.max_networks}"
  puts "  Interface Enabled: #{cluster.interface_enabled}"
  puts

  # Set up callbacks for network operations
  cluster.on_scan_networks = ->(network_type : Matter::Cluster::NetworkCommissioningCluster::NetworkType, ssid : Bytes?) {
    puts "Scanning for #{network_type} networks..."

    # Simulate WiFi network scan results
    results = [
      Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult.new(
        security: Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA2,
        ssid: "HomeNetwork".to_slice,
        bssid: Bytes[0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
        channel: 6_u16,
        wifi_band: 1_u8, # 2.4 GHz
        rssi: -45_i8
      ),
      Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult.new(
        security: Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA3,
        ssid: "OfficeWiFi".to_slice,
        bssid: Bytes[0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
        channel: 11_u16,
        wifi_band: 1_u8, # 2.4 GHz
        rssi: -62_i8
      ),
      Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult.new(
        security: Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA2,
        ssid: "GuestNetwork".to_slice,
        bssid: Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66],
        channel: 1_u16,
        wifi_band: 1_u8, # 2.4 GHz
        rssi: -70_i8
      ),
    ] of Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult |
         Matter::Cluster::NetworkCommissioningCluster::ThreadInterfaceScanResult

    puts "  Found #{results.size} networks"
    results.each do |result|
      if result.is_a?(Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult)
        puts "    - SSID: #{String.new(result.ssid)}, Security: #{result.security}, RSSI: #{result.rssi} dBm"
      end
    end
    puts

    results
  }

  cluster.on_add_network = ->(network_id : Bytes, credentials : Bytes) {
    ssid = String.new(network_id)
    puts "Adding/Updating network: #{ssid}"

    # Store credentials (in real implementation, this would be securely stored)
    cluster.wifi_credentials[network_id] = credentials

    # Add to networks list if not already present
    unless cluster.has_network?(network_id)
      cluster.networks << Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(
        network_id,
        false # Not connected yet
      )
      puts "  Network added successfully"
    else
      puts "  Network credentials updated"
    end

    Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success
  }

  cluster.on_remove_network = ->(network_id : Bytes) {
    ssid = String.new(network_id)
    puts "Removing network: #{ssid}"

    # Remove from networks list
    cluster.networks.reject! { |n| n.network_id == network_id }
    cluster.wifi_credentials.delete(network_id)

    puts "  Network removed successfully"
    Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success
  }

  cluster.on_connect_network = ->(network_id : Bytes) {
    ssid = String.new(network_id)
    puts "Connecting to network: #{ssid}"

    # Check if network exists
    network = cluster.networks.find { |n| n.network_id == network_id }
    unless network
      puts "  Error: Network not found"
      error_value = nil.as(Int32?)
      return {Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::NetworkIDNotFound, error_value}
    end

    # Simulate connection attempt
    unless cluster.wifi_credentials.has_key?(network_id)
      puts "  Error: No credentials for network"
      error_value = nil.as(Int32?)
      return {Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::AuthFailure, error_value}
    end

    # Disconnect any currently connected network
    cluster.networks.each { |n| n.connected = false }

    # Connect to the new network
    network.connected = true
    cluster.last_networking_status = Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success
    cluster.last_network_id = network_id

    puts "  Successfully connected to #{ssid}"
    error_value = nil.as(Int32?)
    {Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success, error_value}
  }

  # Demonstrate usage
  puts "=== Network Commissioning Example ==="
  puts

  # 1. Scan for networks
  puts "1. Scanning for WiFi networks..."
  scan_callback = cluster.on_scan_networks
  if scan_callback
    results = scan_callback.call(
      Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi,
      nil
    )
  end
  puts

  # 2. Add a network
  puts "2. Adding WiFi network..."
  add_callback = cluster.on_add_network
  if add_callback
    status = add_callback.call(
      "HomeNetwork".to_slice,
      "password123".to_slice
    )
    puts "  Status: #{status}"
  end
  puts

  # 3. Read network attributes
  puts "3. Reading cluster attributes..."

  max_networks = cluster.read_attribute(
    Matter::Cluster::NetworkCommissioningCluster::ATTR_MAX_NETWORKS
  )
  puts "  Max Networks: #{max_networks.as(Bytes)[0]}" if max_networks.is_a?(Bytes)

  scan_time = cluster.read_attribute(
    Matter::Cluster::NetworkCommissioningCluster::ATTR_SCAN_MAX_TIME_SECONDS
  )
  puts "  Scan Max Time: #{scan_time.as(Bytes)[0]} seconds" if scan_time.is_a?(Bytes)

  connect_time = cluster.read_attribute(
    Matter::Cluster::NetworkCommissioningCluster::ATTR_CONNECT_MAX_TIME_SECONDS
  )
  puts "  Connect Max Time: #{connect_time.as(Bytes)[0]} seconds" if connect_time.is_a?(Bytes)

  interface_enabled = cluster.read_attribute(
    Matter::Cluster::NetworkCommissioningCluster::ATTR_INTERFACE_ENABLED
  )
  puts "  Interface Enabled: #{interface_enabled.as(Bytes)[0] != 0}" if interface_enabled.is_a?(Bytes)
  puts

  # 4. Write interface enabled attribute
  puts "4. Disabling network interface..."
  status = cluster.write_attribute(
    Matter::Cluster::NetworkCommissioningCluster::ATTR_INTERFACE_ENABLED,
    Bytes[0]
  )
  puts "  Status: #{status.status}"
  puts "  Interface Enabled: #{cluster.interface_enabled}"
  puts

  # Re-enable interface
  puts "5. Re-enabling network interface..."
  status = cluster.write_attribute(
    Matter::Cluster::NetworkCommissioningCluster::ATTR_INTERFACE_ENABLED,
    Bytes[1]
  )
  puts "  Status: #{status.status}"
  puts "  Interface Enabled: #{cluster.interface_enabled}"
  puts

  # 6. Connect to network
  puts "6. Connecting to network..."
  connect_callback = cluster.on_connect_network
  if connect_callback
    status, error = connect_callback.call("HomeNetwork".to_slice)
    puts "  Status: #{status}"

    if connected = cluster.connected_network
      puts "  Connected to: #{String.new(connected.network_id)}"
    end
  end
  puts

  # 7. Check cluster metadata
  puts "7. Cluster metadata:"
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

  # 8. Demonstrate network management
  puts "8. Network management:"
  puts "  Current networks: #{cluster.networks.size}"
  cluster.networks.each do |net|
    puts "    - #{String.new(net.network_id)}: connected=#{net.connected}"
  end
  puts

  # 9. Add another network
  puts "9. Adding another network..."
  if add_callback
    status = add_callback.call(
      "OfficeWiFi".to_slice,
      "office_password".to_slice
    )
    puts "  Status: #{status}"
    puts "  Total networks: #{cluster.networks.size}"
  end
  puts

  # 10. Remove a network
  puts "10. Removing a network..."
  remove_callback = cluster.on_remove_network
  if remove_callback
    status = remove_callback.call("OfficeWiFi".to_slice)
    puts "  Status: #{status}"
    puts "  Total networks: #{cluster.networks.size}"
  end
  puts

  puts "=== Example Complete ==="
end
