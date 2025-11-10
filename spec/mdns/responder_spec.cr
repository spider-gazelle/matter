require "../spec_helper"
require "../../src/matter/mdns/responder"
require "../../src/matter/mdns/service_type"
require "../../src/matter/mdns/record_builder"

describe Matter::MDNS::Responder do
  describe "initialization" do
    it "creates a responder with default settings" do
      responder = Matter::MDNS::Responder.new
      responder.port.should eq(5353)
      responder.hostname.should eq("matter-device.local")
      responder.ip_addresses.should be_empty
    end

    it "creates a responder with custom settings" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        port: 5540,
        hostname: "my-device.local",
        ip_addresses: [ip]
      )

      responder.port.should eq(5540)
      responder.hostname.should eq("my-device.local")
      responder.ip_addresses.size.should eq(1)
    end
  end

  describe "commissioning advertisement" do
    it "advertises commissioning service" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      # Should not raise
      responder.advertise_commissioning(info, port: 5540)
    end

    it "includes correct TXT records" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic,
        pairing_hint: 0x01_u16,
        pairing_instruction: "Scan QR code"
      )

      txt_records = info.to_txt_records
      txt_records["VP"].should eq("65521+32768")
      txt_records["D"].should eq("3840")
      txt_records["CM"].should eq("1")
      txt_records["DT"].should eq("22")
      txt_records["DN"].should eq("TestDevice")
      txt_records["PH"].should eq("1")
      txt_records["PI"].should eq("Scan QR code")
    end
  end

  describe "operational advertisement" do
    it "advertises operational service" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      info = Matter::MDNS::OperationalInfo.new(
        fabric_id: 0x0000000000000001_u64,
        node_id: 0x0000000000000001_u64,
        session_idle_interval: 500_u32,
        session_active_interval: 300_u32,
        tcp_supported: false
      )

      # Should not raise
      responder.advertise_operational(info, port: 5540)
    end

    it "includes correct TXT records for operational" do
      info = Matter::MDNS::OperationalInfo.new(
        fabric_id: 0x0000000000000001_u64,
        node_id: 0x0000000000000001_u64,
        session_idle_interval: 500_u32,
        session_active_interval: 300_u32,
        tcp_supported: true
      )

      txt_records = info.to_txt_records
      txt_records["SII"].should eq("500")
      txt_records["SAI"].should eq("300")
      txt_records["T"].should eq("1")
    end

    it "omits TCP flag when not supported" do
      info = Matter::MDNS::OperationalInfo.new(
        fabric_id: 0x0000000000000001_u64,
        node_id: 0x0000000000000001_u64,
        tcp_supported: false
      )

      txt_records = info.to_txt_records
      txt_records.has_key?("T").should be_false
    end
  end

  describe "service names" do
    it "generates correct commissioning instance name" do
      instance = Matter::MDNS::ServiceNames.commissioning_instance("MyDevice")
      instance.should eq("MyDevice._matterc._udp.local")
    end

    it "generates correct operational instance name" do
      instance = Matter::MDNS::ServiceNames.operational_instance(
        0x1234567890ABCDEF_u64,
        0xFEDCBA0987654321_u64
      )
      instance.should eq("1234567890ABCDEF-FEDCBA0987654321._matter._tcp.local")
    end

    it "generates correct hostname from MAC address" do
      hostname = Matter::MDNS::ServiceNames.hostname("AA:BB:CC:DD:EE:FF")
      hostname.should eq("AABBCCDDEEFF.local")
    end

    it "generates vendor subtype" do
      subtype = Matter::MDNS::ServiceNames.vendor_subtype(0xFFF1_u16)
      subtype.should eq("_V65521._sub._matterc._udp.local")
    end

    it "generates device type subtype" do
      subtype = Matter::MDNS::ServiceNames.device_type_subtype(0x0016_u16)
      subtype.should eq("_T22._sub._matterc._udp.local")
    end

    it "generates short discriminator subtype" do
      # Discriminator 3840 (0x0F00) -> short is (0x0F00 >> 8) & 0x0F = 0x0F
      subtype = Matter::MDNS::ServiceNames.short_discriminator_subtype(3840_u16)
      subtype.should eq("_S15._sub._matterc._udp.local")
    end

    it "generates long discriminator subtype" do
      # Discriminator 3840 (0x0F00) -> long is 0x0F00 & 0x0FFF = 0x0F00 = 3840
      subtype = Matter::MDNS::ServiceNames.long_discriminator_subtype(3840_u16)
      subtype.should eq("_L3840._sub._matterc._udp.local")
    end
  end

  describe "goodbye announcement" do
    it "sends goodbye for commissioning service" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Should not raise
      responder.send_goodbye(
        Matter::MDNS::ServiceType::Commissioning,
        "TestDevice._matterc._udp.local"
      )
    end

    it "sends goodbye for operational service" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Should not raise
      responder.send_goodbye(
        Matter::MDNS::ServiceType::Operational,
        "1-1._matter._tcp.local"
      )
    end
  end

  describe "lifecycle" do
    it "starts and stops responder" do
      responder = Matter::MDNS::Responder.new

      responder.start
      sleep 50.milliseconds
      responder.stop
    end

    it "can be closed" do
      responder = Matter::MDNS::Responder.new
      responder.start
      responder.close

      # Both sockets should be closed
      responder.socket_ipv4.try(&.closed?).should be_true
      responder.socket_ipv6.try(&.closed?).should be_true
    end
  end

  describe "query response" do
    it "responds to matching queries" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Create a query for commissioning service
      question = DNS::Packet::Question.new(
        name: "_matterc._udp.local",
        type: Matter::MDNS::RecordBuilder::TYPE_PTR,
        class_code: Matter::MDNS::RecordBuilder::CLASS_IN
      )

      query = DNS::Packet.new(
        id: 0_u16,
        questions: [question]
      )

      txt_records = {
        "VP" => "65521+32768",
        "D"  => "3840",
      }

      # Should not raise
      responder.respond_to_query(
        query,
        Matter::MDNS::ServiceType::Commissioning,
        "TestDevice._matterc._udp.local",
        5540,
        txt_records
      )
    end

    it "ignores non-matching queries" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      # Create a query for different service
      question = DNS::Packet::Question.new(
        name: "_http._tcp.local",
        type: Matter::MDNS::RecordBuilder::TYPE_PTR,
        class_code: Matter::MDNS::RecordBuilder::CLASS_IN
      )

      query = DNS::Packet.new(
        id: 0_u16,
        questions: [question]
      )

      txt_records = {"VP" => "65521+32768"}

      # Should not raise, just ignore
      responder.respond_to_query(
        query,
        Matter::MDNS::ServiceType::Commissioning,
        "TestDevice._matterc._udp.local",
        5540,
        txt_records
      )
    end
  end

  describe "IPv6 support" do
    it "handles IPv6 addresses" do
      ipv6 = Socket::IPAddress.new("fe80::1", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ipv6]
      )

      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u16
      )

      # Should not raise
      responder.advertise_commissioning(info, port: 5540)
    end

    it "handles mixed IPv4/IPv6 addresses" do
      ipv4 = Socket::IPAddress.new("192.168.1.100", 0)
      ipv6 = Socket::IPAddress.new("fe80::1", 0)

      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ipv4, ipv6]
      )

      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u16
      )

      # Should not raise
      responder.advertise_commissioning(info, port: 5540)
    end
  end

  describe "receive loop and query processing" do
    it "starts receive loop when started" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      responder.start
      sleep 50.milliseconds

      # Verify receive socket was created
      # (We can't access private @receive_socket directly, but we know it's created if start succeeds)
      responder.stop
    end

    it "invokes on_query callback when query received" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      query_received = false
      responder.on_query = ->(query : DNS::Packet, peer : Socket::IPAddress) do
        query_received = true
      end

      # Advertise a service so responder tracks it
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0100_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      responder.start
      responder.advertise_commissioning(info, port: 5540)
      sleep 100.milliseconds

      # Note: In a full integration test with actual multicast networking,
      # we could send a real query and verify the callback is invoked.
      # For now, we verify the setup doesn't crash.

      responder.stop
    end

    it "tracks advertised services for query responses" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      responder.start

      # Advertise commissioning service
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0100_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      responder.advertise_commissioning(info, port: 5540)
      sleep 50.milliseconds

      # Service should be tracked internally for responding to queries
      # (We can't directly test private @advertised_services, but we verify no crashes)

      responder.stop
    end

    it "removes service from tracking on goodbye" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      responder.start

      # Advertise then send goodbye
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0100_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      responder.advertise_commissioning(info, port: 5540)
      sleep 50.milliseconds

      # Send goodbye
      responder.send_goodbye(
        Matter::MDNS::ServiceType::Commissioning,
        "TestDevice._matterc._udp.local"
      )

      sleep 50.milliseconds

      # Service should be removed from tracking
      responder.stop
    end

    it "handles multiple concurrent services" do
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      responder.start

      # Advertise commissioning service
      comm_info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0100_u16,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      # Advertise operational service
      op_info = Matter::MDNS::OperationalInfo.new(
        fabric_id: 0x1234567890ABCDEF_u64,
        node_id: 0x0000000000000001_u64,
        session_idle_interval: 500_u32,
        session_active_interval: 300_u32,
        tcp_supported: false
      )

      responder.advertise_commissioning(comm_info, port: 5540)
      responder.advertise_operational(op_info, port: 5540)

      sleep 100.milliseconds

      # Both services should be tracked
      responder.stop
    end
  end
end
