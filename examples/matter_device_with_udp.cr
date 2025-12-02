require "json"
require "file_utils"
require "goban"
require "../src/matter/mdns/responder"
require "../src/matter/mdns/service_type"
require "../src/matter/mdns/service_description"
require "../src/matter/constants/device_types"
require "../src/matter/fabric"
require "../src/matter/fabric_table"
require "../src/matter/storage/memory_backend"
require "../src/matter/setup_payload"
require "../src/matter"
require "../src/matter/transport/udp_transport"
require "../src/matter/codec/message_codec"
require "../src/matter/protocol/message_handler"

# Matter Device with UDP Transport
#
# This version actually listens for Matter protocol messages via UDP
# and logs what it receives from chip-tool for debugging

module MatterDevice
  class DeviceState
    include JSON::Serializable

    property device_name : String
    property on_off : Bool
    property data_version : UInt32
    property commissioned : Bool
    property discriminator : UInt16
    property vendor_id : UInt16
    property product_id : UInt16
    property setup_pin : UInt32

    def initialize(
      @device_name = "Matter Device",
      @on_off = false,
      @data_version = 0_u32,
      @commissioned = false,
      @discriminator = 3840_u16, # Fixed for easier testing
      @vendor_id = 0xFFF1_u16,
      @product_id = 0x8001_u16,
      @setup_pin = 20202021_u32, # Fixed PIN for easier testing
    )
    end

    def self.load(path : String) : DeviceState
      if File.exists?(path)
        from_json(File.read(path))
      else
        new
      end
    rescue ex
      puts "⚠️  Failed to load state: #{ex.message}"
      new
    end

    def save(path : String)
      File.write(path, to_pretty_json)
    end
  end

  class Device
    STATE_FILE = "matter_device_state.json"

    property state : DeviceState
    property responder : Matter::MDNS::Responder
    property transport : Matter::Transport::UDPTransport
    property message_handler : Matter::Protocol::MessageHandler
    property fabric_table : Matter::FabricTable
    property hostname : String
    property ip_addresses : Array(Socket::IPAddress)
    property port : Int32

    def initialize(@hostname = "matter-device.local", @port = 5540)
      @state = DeviceState.load(STATE_FILE)
      @ip_addresses = get_local_ips

      # Create mDNS responder with all available IP addresses
      @responder = Matter::MDNS::Responder.new(
        hostname: @hostname,
        ip_addresses: @ip_addresses
      )

      # Set callback to log mDNS queries
      @responder.on_query = ->(query : DNS::Packet, peer : Socket::IPAddress) do
        puts "\n🔍 Received mDNS query from #{peer.address}:#{peer.port}"
        query.questions.each do |q|
          puts "   Question: #{q.name} (type=#{q.type})"
        end
      end

      # Create UDP transport
      @transport = Matter::Transport::UDPTransport.new(port: @port)

      # Create fabric table with in-memory storage (could use file-based for persistence)
      storage = Matter::Storage::MemoryBackend.new
      @fabric_table = Matter::FabricTable.new(storage)

      # Create protocol message handler with fabric table
      @message_handler = Matter::Protocol::MessageHandler.new(
        transport: @transport,
        setup_pin: @state.setup_pin,
        discriminator: @state.discriminator,
        fabric_table: @fabric_table,
        vendor_id: @state.vendor_id,
        product_id: @state.product_id
      )

      # Set up commissioned callback to switch from commissioning to operational mDNS
      @message_handler.on_commissioned = ->(fabric : Matter::Fabric) do
        puts "\n🎉 Device commissioned to fabric!"
        puts "   Fabric ID: #{fabric.fabric_id}"
        puts "   Node ID: #{fabric.node_id}"
        puts "   Compressed Fabric ID: #{fabric.compressed_fabric_id.hexstring.upcase}"
        puts ""

        # Stop commissioning advertisement and start operational advertisement
        start_operational_advertisement(fabric)
      end

      # Set up on_get_fabric callback for CASE session establishment
      # This allows the message handler to retrieve fabric data for CASE
      @message_handler.on_get_fabric = -> do
        # Return the first fabric (for single-fabric devices)
        # For multi-fabric devices, this would need to be smarter
        @fabric_table.all_fabrics.first?
      end
    end

    def get_local_ips : Array(Socket::IPAddress)
      ips = [] of Socket::IPAddress

      # Get IPv6 address
      begin
        socket = UDPSocket.new(:inet6)
        socket.connect("2606:4700:4700::1111", 53)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
        # IPv6 not available
      end

      # Get IPv4 address
      begin
        socket = UDPSocket.new(:inet)
        socket.connect("8.8.8.8", 80)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
        # IPv4 not available
      end

      # Fallback to localhost if nothing worked
      ips << Socket::IPAddress.new("127.0.0.1", 0) if ips.empty?
      ips
    end

    def get_local_ip : Socket::IPAddress
      # For backwards compatibility - return first available IP
      get_local_ips.first
    end

    def start
      print_header
      print_device_info

      # Start mDNS responder
      start_mdns_advertisement

      # Start UDP transport
      puts "🔌 Starting UDP transport..."
      @transport.start
      puts "   ✅ Listening on all interfaces, port #{@port}"
      puts ""

      # Keep running
      puts "⌨️  Press Ctrl+C to stop"
      puts ""

      # Keep alive
      loop do
        sleep 1.second
      end
    end

    def print_header
      puts "\n" + "=" * 70
      puts "  Matter Device with UDP Transport"
      puts "  Device Type: On/Off Light"
      puts "=" * 70
      puts ""
    end

    def print_device_info
      puts "📁 Device Information:"
      puts "   Name: #{@state.device_name}"
      puts "   Vendor ID: 0x#{@state.vendor_id.to_s(16).upcase}"
      puts "   Product ID: 0x#{@state.product_id.to_s(16).upcase}"
      puts "   Discriminator: #{@state.discriminator}"
      puts "   Setup PIN: #{@state.setup_pin}"
      puts "   IP Addresses:"
      @ip_addresses.each do |ip|
        puts "      - #{ip.address} (#{ip.family == Socket::Family::INET ? "IPv4" : "IPv6"})"
      end
      puts "   Port: #{@port}"
      puts ""
    end

    def start_mdns_advertisement
      puts "📡 Starting mDNS advertisement..."

      info = Matter::MDNS::CommissioningInfo.new(
        device_name: @state.device_name,
        vendor_id: @state.vendor_id,
        product_id: @state.product_id,
        discriminator: @state.discriminator,
        device_type: Matter::DeviceTypes::ON_OFF_LIGHT,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      @responder.advertise_commissioning(info, port: @port)
      @responder.start

      puts "   ✅ mDNS service: _matterc._udp.local"
      puts "   ✅ Instance: #{@state.device_name}._matterc._udp.local"
      puts ""

      # Generate and display pairing codes
      manual_code = generate_manual_code
      qr_code = generate_qr_code

      puts "💡 Pairing Information:"
      puts "   Manual Code: #{manual_code}"
      puts ""

      print_qr_code(qr_code)
      puts ""

      puts "📝 To commission with chip-tool:"
      puts "   chip-tool pairing code <node-id> #{manual_code}"
      puts "   Example: chip-tool pairing code 1 #{manual_code}"
      puts ""
    end

    def start_operational_advertisement(fabric : Matter::Fabric)
      puts "📡 Switching to operational mDNS advertisement..."

      # Stop commissioning advertisement
      @responder.stop_commissioning

      # Create operational info from fabric
      info = Matter::MDNS::OperationalInfo.new(
        compressed_fabric_id: fabric.compressed_fabric_id,
        node_id: fabric.node_id,
        session_idle_interval: 500_u32,   # 500ms - MRP idle retransmit interval
        session_active_interval: 300_u32, # 300ms - MRP active retransmit interval
        tcp_supported: false
      )

      # Start operational advertisement
      @responder.advertise_operational(info, port: @port)

      instance_name = Matter::MDNS::ServiceNames.operational_instance(
        fabric.compressed_fabric_id, fabric.node_id
      )
      puts "   ✅ mDNS service: _matter._tcp.local"
      puts "   ✅ Instance: #{instance_name}._matter._tcp.local"
      puts ""

      # Mark device as commissioned
      @state.commissioned = true
      @state.save(STATE_FILE)
      puts "💾 Device state saved (commissioned=true)"
      puts ""
    end

    def generate_manual_code : String
      Matter::SetupPayload.generate_manual_code(@state.discriminator, @state.setup_pin)
    end

    def generate_qr_code : String
      Matter::SetupPayload::QRCode.generate_qr_code(
        discriminator: @state.discriminator,
        pin: @state.setup_pin,
        vendor_id: @state.vendor_id,
        product_id: @state.product_id,
        flow: Matter::SetupPayload::QRCode::CommissionFlow::Standard,
        capabilities: Matter::SetupPayload::QRCode::DiscoveryCapability::BLE
      )
    end

    def print_qr_code(qr_payload : String)
      begin
        qr = Goban::QR.encode_string(qr_payload, Goban::ECC::Level::Low)
        puts "📱 QR Code:"
        puts ""
        qr.print_to_console
        puts ""
      rescue ex
        puts "⚠️  Failed to generate QR code: #{ex.message}"
      end
    end

    def shutdown
      puts "\n\n🛑 Shutting down..."
      puts "📁 Saving state..."
      @state.save(STATE_FILE)

      puts "🛑 Stopping UDP transport..."
      @transport.close

      puts "🛑 Stopping mDNS responder..."
      @responder.stop

      puts "✅ Shutdown complete"
    end
  end
end

# Main entry point
puts "Starting Matter Device with UDP Transport..."
puts ""

# Set up logging - enable DEBUG level
Log.setup(:debug)

device = MatterDevice::Device.new

# Trap Ctrl+C for clean shutdown
Process.on_terminate do
  device.shutdown
  exit(0)
end

device.start
