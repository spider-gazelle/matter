require "json"
require "file_utils"
require "goban"
require "../src/matter/mdns/responder"
require "../src/matter/mdns/service_type"
require "../src/matter/mdns/service_description"
require "../src/matter/constants/device_types"
require "../src/matter/fabric"
require "../src/matter/setup_payload"
require "../src/matter"
require "../src/matter/transport/udp_transport"
require "../src/matter/codec/message_codec"

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

      # Set up message handler
      @transport.on_message = ->(msg : Matter::Codec::MessageCodec::Message, peer : Socket::IPAddress) do
        handle_matter_message(msg, peer)
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

      Signal::INT.trap do
        shutdown
        exit(0)
      end

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

    def handle_matter_message(msg : Matter::Codec::MessageCodec::Message, peer : Socket::IPAddress)
      puts ""
      puts "═" * 70
      puts "📨 Received Matter Message from #{peer.address}:#{peer.port}"
      puts "═" * 70
      puts ""

      # Packet Header
      puts "📦 Packet Header:"
      puts "   Session ID: 0x#{msg.packet_header.session_id.to_s(16).rjust(4, '0')}"
      puts "   Session Type: #{msg.packet_header.session_type}"
      puts "   Message ID: 0x#{msg.packet_header.message_id.to_s(16).rjust(8, '0')}"
      puts "   Source Node: #{msg.packet_header.source_node_id || "none"}"
      puts "   Dest Node: #{msg.packet_header.destination_node_id || "none"}"
      puts ""

      # Payload Header
      puts "📤 Payload Header:"
      puts "   Exchange ID: 0x#{msg.payload_header.exchange_id.to_s(16).rjust(4, '0')}"
      puts "   Protocol ID: 0x#{msg.payload_header.protocol_id.to_s(16).rjust(4, '0')} (#{protocol_name(msg.payload_header.protocol_id)})"
      puts "   Message Type: 0x#{msg.payload_header.message_type.to_s(16).rjust(2, '0')} (#{message_type_name(msg.payload_header.protocol_id, msg.payload_header.message_type)})"
      puts "   Initiator: #{msg.payload_header.initiator_message?}"
      puts "   Requires ACK: #{msg.payload_header.requires_acknowledge?}"
      puts ""

      # Payload
      puts "📄 Payload: #{msg.payload.size} bytes"
      if msg.payload.size > 0
        puts "   Hex: #{msg.payload.hexstring}"
        if msg.payload.size <= 64
          puts "   Bytes: #{msg.payload.to_a.inspect}"
        end
      end
      puts ""

      # Try to decode protocol-specific messages
      decode_protocol_message(msg)

      puts "═" * 70
      puts ""
    end

    def protocol_name(protocol_id : UInt16) : String
      case protocol_id
      when 0x0000 then "Secure Channel"
      when 0x0001 then "Interaction Model"
      when 0x0002 then "BDX"
      when 0x0003 then "User Directed Commissioning"
      else             "Unknown"
      end
    end

    def message_type_name(protocol_id : UInt16, message_type : UInt8) : String
      case protocol_id
      when 0x0000 # Secure Channel
        case message_type
        when 0x00 then "MsgCounterSyncReq"
        when 0x01 then "MsgCounterSyncRsp"
        when 0x10 then "MRPStandaloneAck"
        when 0x20 then "PBKDFParamRequest"
        when 0x21 then "PBKDFParamResponse"
        when 0x22 then "PASE_Pake1"
        when 0x23 then "PASE_Pake2"
        when 0x24 then "PASE_Pake3"
        when 0x30 then "CASE_Sigma1"
        when 0x31 then "CASE_Sigma2"
        when 0x32 then "CASE_Sigma3"
        when 0x40 then "StatusReport"
        else           "Unknown (0x#{message_type.to_s(16)})"
        end
      when 0x0001 # Interaction Model
        case message_type
        when 0x01 then "StatusResponse"
        when 0x02 then "ReadRequest"
        when 0x05 then "ReportData"
        when 0x06 then "WriteRequest"
        when 0x07 then "WriteResponse"
        when 0x08 then "InvokeCommandRequest"
        when 0x09 then "InvokeCommandResponse"
        when 0x03 then "SubscribeRequest"
        when 0x04 then "SubscribeResponse"
        else           "Unknown (0x#{message_type.to_s(16)})"
        end
      else
        "Unknown"
      end
    end

    def decode_protocol_message(msg : Matter::Codec::MessageCodec::Message)
      return if msg.payload.size == 0

      case msg.payload_header.protocol_id
      when 0x0000 # Secure Channel
        decode_secure_channel_message(msg)
      when 0x0001 # Interaction Model
        decode_interaction_model_message(msg)
      end
    end

    def decode_secure_channel_message(msg : Matter::Codec::MessageCodec::Message)
      puts "🔐 Secure Channel Message:"

      case msg.payload_header.message_type
      when 0x20 # PBKDFParamRequest
        puts "   Type: PBKDF Parameter Request (PASE Step 1)"
        puts "   ⚠️  PASE not yet implemented - cannot respond"
      when 0x22 # PASE_Pake1
        puts "   Type: PASE PAKE1 (PASE Step 2)"
        puts "   ⚠️  PASE not yet implemented - cannot respond"
      when 0x24 # PASE_Pake3
        puts "   Type: PASE PAKE3 (PASE Step 3)"
        puts "   ⚠️  PASE not yet implemented - cannot respond"
      end
    end

    def decode_interaction_model_message(msg : Matter::Codec::MessageCodec::Message)
      puts "💬 Interaction Model Message:"

      case msg.payload_header.message_type
      when 0x02 # ReadRequest
        puts "   Type: Read Request"
      when 0x06 # WriteRequest
        puts "   Type: Write Request"
      when 0x08 # InvokeCommandRequest
        puts "   Type: Invoke Command Request"
      when 0x03 # SubscribeRequest
        puts "   Type: Subscribe Request"
      end

      puts "   ⚠️  IM handler not yet implemented - cannot respond"
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
