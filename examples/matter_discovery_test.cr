require "../src/matter/mdns/scanner"
require "../src/matter/setup_payload"

# Simple Matter Device Discovery Test
#
# This tool helps identify issues with Matter device implementations by:
# - Discovering devices via mDNS
# - Validating advertisements
# - Checking QR/manual codes
# - Reporting any issues found

puts "Matter Device Discovery Test"
puts "=" * 70
puts ""

# Create scanner
scanner = Matter::MDNS::Scanner.new

# Track discovered devices
devices_found = [] of Matter::MDNS::DiscoveredDevice

# Set up callbacks
scanner.on_device_discovered = ->(device : Matter::MDNS::DiscoveredDevice) do
  puts "✅ Discovered: #{device.device_name || device.instance_name}"
  puts "   Type: #{device.service_type}"
  puts "   Hostname: #{device.hostname}"
  puts "   Addresses: #{device.addresses.map(&.address).join(", ")}"
  puts "   Port: #{device.port}"

  if device.service_type.commissioning?
    puts "   Vendor ID: #{device.vendor_id}"
    puts "   Product ID: #{device.product_id}"
    puts "   Discriminator: #{device.discriminator}"
    puts "   Device Type: #{device.device_type}"
    puts "   Commissioning Mode: #{device.commissioning_mode}"
    puts "   Device Name: #{device.device_name}"

    # Validate TXT records
    puts ""
    puts "   TXT Records:"
    device.txt_records.each do |key, value|
      puts "     #{key}=#{value}"
    end

    # Check for issues
    puts ""
    puts "   Validation:"

    issues = [] of String

    if device.discriminator.nil?
      issues << "Missing discriminator (D)"
    elsif device.discriminator.not_nil! > 4095
      issues << "Invalid discriminator: #{device.discriminator} (must be 0-4095)"
    end

    if device.vendor_id.nil?
      issues << "Missing vendor ID"
    end

    if device.product_id.nil?
      issues << "Missing product ID"
    end

    if device.device_name.nil? || device.device_name.not_nil!.empty?
      issues << "Missing or empty device name (DN)"
    end

    if device.commissioning_mode.nil?
      issues << "Missing commissioning mode (CM)"
    elsif device.commissioning_mode == 0
      issues << "Commissioning disabled (CM=0)"
    end

    if issues.empty?
      puts "     ✅ All required fields present"
    else
      puts "     ⚠️  Issues found:"
      issues.each do |issue|
        puts "       - #{issue}"
      end
    end
  else
    # Operational device
    puts "   Fabric ID: 0x#{device.fabric_id.not_nil!.to_s(16).upcase}"
    puts "   Node ID: 0x#{device.node_id.not_nil!.to_s(16).upcase}"
  end

  puts ""
  devices_found << device
end

scanner.on_device_updated = ->(device : Matter::MDNS::DiscoveredDevice) do
  puts "🔄 Updated: #{device.device_name || device.instance_name}"
end

scanner.on_device_removed = ->(instance_name : String) do
  puts "❌ Removed: #{instance_name}"
  devices_found.reject! { |d| d.instance_name == instance_name }
end

puts "🔍 Starting mDNS scanner..."
puts "   Listening for Matter devices on the network"
puts "   Press Ctrl+C to stop"
puts ""

scanner.start

# Query for commissioning devices
puts "📡 Querying for commissioning devices..."
scanner.query_commissioning
sleep 2

# Query for operational devices
puts "📡 Querying for operational devices..."
scanner.query_operational
sleep 2

# Keep running and scanning
Signal::INT.trap do
  puts "\n\n🛑 Stopping scanner..."
  scanner.close
  puts "\n📊 Summary:"
  puts "   Total devices discovered: #{devices_found.size}"

  if devices_found.empty?
    puts "\n⚠️  No devices found!"
    puts "\n💡 Troubleshooting:"
    puts "   1. Ensure your Matter device is running"
    puts "   2. Check that device is in commissioning mode"
    puts "   3. Verify mDNS/DNS-SD is working:"
    puts "      - Linux: avahi-browse -a -t"
    puts "      - macOS: dns-sd -B _services._dns-sd._udp"
    puts "   4. Check firewall settings (UDP port 5353)"
  else
    puts "\n✅ Devices:"
    devices_found.each do |device|
      puts "   - #{device.device_name || device.instance_name}"
      if device.service_type.commissioning?
        puts "     Ready for commissioning"
        puts "     Discriminator: #{device.discriminator}"
      else
        puts "     Operational (commissioned)"
      end
    end
  end

  exit(0)
end

# Run for 60 seconds by default
sleep 60
puts "\n⏱️  Scan complete (60s elapsed)"
puts "\n📊 Found #{devices_found.size} device(s)"

scanner.close
