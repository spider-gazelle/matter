require "../src/matter/mdns/responder"
require "../src/matter/mdns/service_type"
require "../src/matter/mdns/service_description"
require "../src/matter/constants/device_types"

# Example: mDNS Responder for a Matter device
#
# This demonstrates:
# - Advertising a commissioning service
# - Listening for mDNS queries
# - Responding to queries automatically
# - Query callback for custom handling

puts "Matter mDNS Responder Example"
puts "==============================\n"

# Create responder with device info
ip = Socket::IPAddress.new("192.168.1.100", 0)
responder = Matter::MDNS::Responder.new(
  hostname: "matter-device.local",
  ip_addresses: [ip]
)

# Setup query callback for debugging
responder.on_query = ->(query : DNS::Packet, peer : Socket::IPAddress) do
  puts "\n[#{Time.utc}] Received query from #{peer}"
  query.questions.each do |q|
    puts "  Question: #{q.name} (type: #{q.type})"
  end
end

# Start listening for queries
puts "Starting responder..."
responder.start
puts "Responder listening on multicast 224.0.0.251:5353"

# Advertise commissioning service
puts "\nAdvertising commissioning service..."
info = Matter::MDNS::CommissioningInfo.new(
  device_name: "ExampleDevice",
  vendor_id: 0xFFF1_u16,
  product_id: 0x8000_u16,
  discriminator: 3840_u16,
  device_type: Matter::DeviceTypes::ON_OFF_LIGHT,
  commissioning_mode: Matter::MDNS::CommissioningMode::Basic
)

responder.advertise_commissioning(info, port: 5540)

puts "Service advertised: _matterc._udp.local"
puts "Instance: ExampleDevice._matterc._udp.local"
puts "Device Type: #{Matter::DeviceTypes.name(Matter::DeviceTypes::ON_OFF_LIGHT)} (0x#{Matter::DeviceTypes::ON_OFF_LIGHT.to_s(16).upcase})"
puts "TXT Records:"
info.to_txt_records.each do |key, value|
  puts "  #{key}=#{value}"
end

puts "\nResponder is active. It will:"
puts "  1. Announce the service via multicast"
puts "  2. Listen for mDNS queries"
puts "  3. Automatically respond to matching queries"
puts "\nPress Ctrl+C to stop"

# Keep running
Signal::INT.trap do
  puts "\n\nShutting down..."
  responder.close
  puts "Responder closed"
  exit
end

sleep
