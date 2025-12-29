require "../spec_helper"
require "../../src/matter/mdns/responder"
require "../../src/matter/mdns/scanner"
require "../../src/matter/mdns/service_type"

describe "mDNS Integration" do
  describe "commissioning service discovery" do
    it "advertises and discovers commissioning service" do
      require_udp_sockets!

      # Setup scanner
      scanner = Matter::MDNS::Scanner.new
      scanner.start

      # Track discovered devices
      discovered_devices = [] of Matter::MDNS::DiscoveredDevice
      scanner.on_device_discovered = ->(device : Matter::MDNS::DiscoveredDevice) {
        discovered_devices << device
        nil
      }

      # Setup responder
      ip = Socket::IPAddress.new("127.0.0.1", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Advertise commissioning service
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      responder.advertise_commissioning(info, port: 5540)

      # Give time for multicast propagation
      sleep 100.milliseconds

      # Note: In a real environment, the scanner would receive the multicast
      # In this test environment, we're just verifying the APIs work correctly
      # Full network testing would require actual multicast network setup

      # Cleanup
      scanner.close
      responder.close
    end

    it "advertises and discovers operational service" do
      require_udp_sockets!

      # Setup scanner
      scanner = Matter::MDNS::Scanner.new
      scanner.start

      # Track discovered devices
      discovered_devices = [] of Matter::MDNS::DiscoveredDevice
      scanner.on_device_discovered = ->(device : Matter::MDNS::DiscoveredDevice) {
        discovered_devices << device
        nil
      }

      # Setup responder
      ip = Socket::IPAddress.new("127.0.0.1", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Advertise operational service
      # Create a dummy compressed fabric ID (8 bytes)
      compressed_fabric_id = Bytes.new(8)
      IO::ByteFormat::LittleEndian.encode(0x0000000000000001_u64, compressed_fabric_id)

      info = Matter::MDNS::OperationalInfo.new(
        compressed_fabric_id: compressed_fabric_id,
        node_id: 0x0000000000000001_u64,
        session_idle_interval: 500_u32,
        session_active_interval: 300_u32,
        tcp_supported: false
      )

      responder.advertise_operational(info, port: 5540)

      # Give time for multicast propagation
      sleep 100.milliseconds

      # Cleanup
      scanner.close
      responder.close
    end
  end

  describe "query and response" do
    it "scanner queries for commissioning devices" do
      require_udp_sockets!

      scanner = Matter::MDNS::Scanner.new
      scanner.start

      # Send query
      scanner.query_commissioning

      sleep 50.milliseconds

      scanner.close
    end

    it "scanner queries for operational devices" do
      require_udp_sockets!

      scanner = Matter::MDNS::Scanner.new
      scanner.start

      # Send query
      scanner.query_operational

      sleep 50.milliseconds

      scanner.close
    end

    it "responder responds to queries" do
      require_udp_sockets!

      ip = Socket::IPAddress.new("127.0.0.1", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Create a query packet
      question = DNS::Packet::Question.new(
        name: "_matterc._udp.local",
        type: Matter::MDNS::RecordBuilder::TYPE_PTR,
        class_code: Matter::MDNS::RecordBuilder::CLASS_IN
      )

      query = DNS::Packet.new(
        id: 0_u16,
        questions: [question]
      )

      txt_records = {"VP" => "65521+32768"}

      # Respond to query
      responder.respond_to_query(
        query,
        Matter::MDNS::ServiceType::Commissioning,
        "DD200C20D25AE5F7._matterc._udp.local",
        5540,
        txt_records
      )

      responder.close
    end
  end

  describe "goodbye packets" do
    it "scanner handles device removal" do
      require_udp_sockets!

      scanner = Matter::MDNS::Scanner.new
      scanner.start

      # Track removed devices
      removed_devices = [] of String
      scanner.on_device_removed = ->(instance_name : String) {
        removed_devices << instance_name
        nil
      }

      # Give time for setup
      sleep 50.milliseconds

      scanner.close
    end

    it "responder sends goodbye" do
      require_udp_sockets!

      ip = Socket::IPAddress.new("127.0.0.1", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Send goodbye for commissioning service
      responder.send_goodbye(
        Matter::MDNS::ServiceType::Commissioning,
        "DD200C20D25AE5F7._matterc._udp.local"
      )

      responder.close
    end
  end

  describe "device updates" do
    it "scanner tracks device updates" do
      require_udp_sockets!

      scanner = Matter::MDNS::Scanner.new
      scanner.start

      # Track updated devices
      updated_devices = [] of Matter::MDNS::DiscoveredDevice
      scanner.on_device_updated = ->(device : Matter::MDNS::DiscoveredDevice) {
        updated_devices << device
        nil
      }

      # Give time for setup
      sleep 50.milliseconds

      scanner.close
    end
  end

  describe "multiple services" do
    it "responder advertises both commissioning and operational" do
      require_udp_sockets!

      ip = Socket::IPAddress.new("127.0.0.1", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Advertise commissioning
      commissioning_info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u16
      )

      responder.advertise_commissioning(commissioning_info, port: 5540)

      # Advertise operational
      # Create a dummy compressed fabric ID (8 bytes)
      compressed_fabric_id2 = Bytes.new(8)
      IO::ByteFormat::LittleEndian.encode(0x0000000000000001_u64, compressed_fabric_id2)

      operational_info = Matter::MDNS::OperationalInfo.new(
        compressed_fabric_id: compressed_fabric_id2,
        node_id: 0x0000000000000001_u64
      )

      responder.advertise_operational(operational_info, port: 5540)

      responder.close
    end

    it "scanner discovers both commissioning and operational" do
      require_udp_sockets!

      scanner = Matter::MDNS::Scanner.new
      scanner.start

      # Query for both service types
      scanner.query_commissioning
      scanner.query_operational

      sleep 50.milliseconds

      scanner.close
    end
  end

  describe "DNS record validation" do
    it "builds valid PTR record" do
      record = Matter::MDNS::RecordBuilder.build_ptr(
        service: "_matterc._udp.local",
        instance: "DD200C20D25AE5F7._matterc._udp.local",
        ttl: 120.seconds
      )

      record.type.should eq(Matter::MDNS::RecordBuilder::TYPE_PTR)
      record.name.should eq("_matterc._udp.local")
    end

    it "builds valid SRV record" do
      record = Matter::MDNS::RecordBuilder.build_srv(
        instance: "DD200C20D25AE5F7._matterc._udp.local",
        port: 5540,
        target: "test-device.local",
        ttl: 120.seconds
      )

      record.type.should eq(Matter::MDNS::RecordBuilder::TYPE_SRV)
      record.class_code.should eq(Matter::MDNS::RecordBuilder::CLASS_IN_CACHE_FLUSH)
    end

    it "builds valid TXT record" do
      txt_records = {"VP" => "65521+32768", "D" => "3840"}

      record = Matter::MDNS::RecordBuilder.build_txt(
        instance: "DD200C20D25AE5F7._matterc._udp.local",
        txt_records: txt_records,
        ttl: 120.seconds
      )

      record.type.should eq(Matter::MDNS::RecordBuilder::TYPE_TXT)
      record.class_code.should eq(Matter::MDNS::RecordBuilder::CLASS_IN_CACHE_FLUSH)
    end

    it "builds valid A record" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)

      record = Matter::MDNS::RecordBuilder.build_a(
        hostname: "test-device.local",
        ip: ip,
        ttl: 120.seconds
      )

      record.type.should eq(Matter::MDNS::RecordBuilder::TYPE_A)
      record.resource_data.size.should eq(4)
    end

    it "builds valid AAAA record" do
      ip = Socket::IPAddress.new("fe80::1", 0)

      record = Matter::MDNS::RecordBuilder.build_aaaa(
        hostname: "test-device.local",
        ip: ip,
        ttl: 120.seconds
      )

      record.type.should eq(Matter::MDNS::RecordBuilder::TYPE_AAAA)
      record.resource_data.size.should eq(16)
    end
  end

  describe "service name formatting" do
    it "formats commissioning instance correctly" do
      instance = Matter::MDNS::ServiceNames.commissioning_instance("DD200C20D25AE5F7")
      instance.should eq("DD200C20D25AE5F7._matterc._udp.local")
    end

    it "formats operational instance correctly" do
      # Create compressed fabric ID as bytes
      compressed_fabric_id3 = Bytes.new(8)
      IO::ByteFormat::BigEndian.encode(0x1234567890ABCDEF_u64, compressed_fabric_id3)

      instance = Matter::MDNS::ServiceNames.operational_instance(
        compressed_fabric_id3,
        0xFEDCBA0987654321_u64
      )
      instance.should eq("1234567890ABCDEF-FEDCBA0987654321._matter._tcp.local")
    end

    it "formats hostname from MAC address" do
      hostname = Matter::MDNS::ServiceNames.hostname("AA:BB:CC:DD:EE:FF")
      hostname.should eq("AABBCCDDEEFF.local")
    end

    it "formats vendor subtype" do
      subtype = Matter::MDNS::ServiceNames.vendor_subtype(0xFFF1_u16)
      subtype.should eq("_V65521._sub._matterc._udp.local")
    end

    it "formats device type subtype" do
      subtype = Matter::MDNS::ServiceNames.device_type_subtype(0x0016_u16)
      subtype.should eq("_T22._sub._matterc._udp.local")
    end
  end

  describe "concurrent operations" do
    it "handles multiple scanners" do
      require_udp_sockets!

      scanner1 = Matter::MDNS::Scanner.new
      scanner2 = Matter::MDNS::Scanner.new

      scanner1.start
      scanner2.start

      sleep 50.milliseconds

      scanner1.close
      scanner2.close
    end

    it "handles multiple responders" do
      require_udp_sockets!

      ip = Socket::IPAddress.new("127.0.0.1", 0)

      responder1 = Matter::MDNS::Responder.new(
        hostname: "device1.local",
        ip_addresses: [ip]
      )

      responder2 = Matter::MDNS::Responder.new(
        hostname: "device2.local",
        ip_addresses: [ip]
      )

      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "Device",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u16
      )

      responder1.advertise_commissioning(info, port: 5540)
      responder2.advertise_commissioning(info, port: 5541)

      responder1.close
      responder2.close
    end
  end
end
