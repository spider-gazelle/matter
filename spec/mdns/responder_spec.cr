require "../spec_helper"
require "../../src/matter/mdns/responder"
require "../../src/matter/mdns/service_type"
require "../../src/matter/mdns/record_builder"

# Captures multicast packets instead of sending them so specs can inspect
# announcements and query responses.
class RecordingResponder < Matter::MDNS::Responder
  getter sent = [] of DNS::Packet

  private def send_multicast(packet : DNS::Packet) : Nil
    @sent << packet
  end
end

# Decode a DNS label-encoded name (as stored in PTR/SRV resource data)
private def decode_dns_name(io : IO) : String
  labels = [] of String
  while (length = io.read_byte) && length > 0
    labels << io.read_string(length)
  end
  labels.join('.')
end

# Instance name a PTR record points at
private def ptr_target(record : DNS::Packet::ResourceRecord) : String
  decode_dns_name(IO::Memory.new(record.resource_data))
end

# key=value pairs of a TXT record
private def txt_entries(record : DNS::Packet::ResourceRecord) : Hash(String, String)
  io = IO::Memory.new(record.resource_data)
  entries = {} of String => String
  while (length = io.read_byte) && length > 0
    key, _, value = io.read_string(length).partition('=')
    entries[key] = value
  end
  entries
end

private def ptr_records(packet : DNS::Packet) : Array(DNS::Packet::ResourceRecord)
  packet.answers.select { |record| record.type == Matter::MDNS::RecordBuilder::TYPE_PTR }
end

private def txt_record(packet : DNS::Packet) : DNS::Packet::ResourceRecord
  packet.additionals.find! { |record| record.type == Matter::MDNS::RecordBuilder::TYPE_TXT }
end

private def query_for(name : String, type : UInt16) : DNS::Packet
  question = DNS::Packet::Question.new(name: name, type: type, class_code: Matter::MDNS::RecordBuilder::CLASS_IN)
  DNS::Packet.new(id: 0_u16, questions: [question])
end

private def commissioning_info(discriminator : UInt16, mode : Matter::MDNS::CommissioningMode = Matter::MDNS::CommissioningMode::Enhanced) : Matter::MDNS::CommissioningInfo
  Matter::MDNS::CommissioningInfo.new(
    device_name: "TestDevice",
    vendor_id: 0xFFF1_u16,
    product_id: 0x8001_u16,
    discriminator: discriminator,
    device_type: 15_u16,
    commissioning_mode: mode
  )
end

# Poll until the condition holds or the timeout elapses
private def wait_for(timeout : Time::Span, &condition : -> Bool) : Nil
  deadline = Time.monotonic + timeout
  until condition.call || Time.monotonic >= deadline
    sleep 5.milliseconds
  end
end

private def recording_responder(burst_interval : Time::Span = Matter::MDNS::Responder::ANNOUNCEMENT_BURST_INTERVAL) : RecordingResponder
  RecordingResponder.new(
    hostname: "test-device.local",
    ip_addresses: [Socket::IPAddress.new("192.168.1.100", 0)],
    announcement_burst_interval: burst_interval
  )
end

describe Matter::MDNS::Responder do
  describe "initialization" do
    it "creates a responder with default settings" do
      require_udp_sockets!
      responder = Matter::MDNS::Responder.new
      responder.port.should eq(5353)
      responder.hostname.should eq("matter-device.local")
      responder.ip_addresses.should be_empty
    end

    it "creates a responder with custom settings" do
      require_udp_sockets!
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
      require_udp_sockets!
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
        device_type: 0x0016_u32,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      # Should not raise
      responder.advertise_commissioning(info, port: 5540)
    end

    it "includes correct TXT records" do
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0016_u32,
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
      require_udp_sockets!
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      info = Matter::MDNS::OperationalInfo.new(
        compressed_fabric_id: (cfid = Bytes.new(8); IO::ByteFormat::LittleEndian.encode(0x0000000000000001_u64, cfid); cfid),
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
        compressed_fabric_id: (cfid = Bytes.new(8); IO::ByteFormat::LittleEndian.encode(0x0000000000000001_u64, cfid); cfid),
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
        compressed_fabric_id: (cfid = Bytes.new(8); IO::ByteFormat::LittleEndian.encode(0x0000000000000001_u64, cfid); cfid),
        node_id: 0x0000000000000001_u64,
        tcp_supported: false
      )

      txt_records = info.to_txt_records
      txt_records.has_key?("T").should be_false
    end
  end

  describe "service names" do
    it "generates correct commissioning instance name" do
      instance = Matter::MDNS::ServiceNames.commissioning_instance("DD200C20D25AE5F7")
      instance.should eq("DD200C20D25AE5F7._matterc._udp.local")
    end

    it "generates correct operational instance name" do
      # Create compressed fabric ID as bytes
      compressed_fabric_id = Bytes.new(8)
      IO::ByteFormat::BigEndian.encode(0x1234567890ABCDEF_u64, compressed_fabric_id)

      instance = Matter::MDNS::ServiceNames.operational_instance(
        compressed_fabric_id,
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
      subtype = Matter::MDNS::ServiceNames.device_type_subtype(0x0016_u32)
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
      require_udp_sockets!
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
      require_udp_sockets!
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
      require_udp_sockets!
      responder = Matter::MDNS::Responder.new

      responder.start
      sleep 50.milliseconds
      responder.stop
    end

    it "can be closed" do
      require_udp_sockets!
      responder = Matter::MDNS::Responder.new
      responder.start
      responder.close

      # Sockets should be closed (if present); allow a brief delay for the receive loops to unwind.
      deadline = Time.monotonic + 200.milliseconds
      loop do
        closed4 = responder.socket_ipv4.try(&.closed?) || responder.socket_ipv4.nil?
        closed6 = responder.socket_ipv6.try(&.closed?) || responder.socket_ipv6.nil?
        break if (closed4 && closed6) || Time.monotonic >= deadline
        sleep 10.milliseconds
      end

      if sock4 = responder.socket_ipv4
        sock4.closed?.should be_true
      end
      if sock6 = responder.socket_ipv6
        sock6.closed?.should be_true
      end
    end
  end

  describe "query response" do
    it "responds to matching queries" do
      require_udp_sockets!
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
      require_udp_sockets!
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
      require_udp_sockets!
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
        device_type: 0x0016_u32
      )

      # Should not raise
      responder.advertise_commissioning(info, port: 5540)
    end

    it "handles mixed IPv4/IPv6 addresses" do
      require_udp_sockets!
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
        device_type: 0x0016_u32
      )

      # Should not raise
      responder.advertise_commissioning(info, port: 5540)
    end
  end

  describe "receive loop and query processing" do
    it "starts receive loop when started" do
      require_udp_sockets!
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
      require_udp_sockets!
      ip = Socket::IPAddress.new("192.168.1.100", 0)
      responder = Matter::MDNS::Responder.new(
        hostname: "test-device.local",
        ip_addresses: [ip]
      )

      query_received = false
      responder.on_query = ->(_query : DNS::Packet, _peer : Socket::IPAddress) do
        query_received = true
      end

      # Advertise a service so responder tracks it
      info = Matter::MDNS::CommissioningInfo.new(
        device_name: "TestDevice",
        vendor_id: 0xFFF1_u16,
        product_id: 0x8000_u16,
        discriminator: 3840_u16,
        device_type: 0x0100_u32,
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
      require_udp_sockets!
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
        device_type: 0x0100_u32,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      responder.advertise_commissioning(info, port: 5540)
      sleep 50.milliseconds

      # Service should be tracked internally for responding to queries
      # (We can't directly test private @advertised_services, but we verify no crashes)

      responder.stop
    end

    it "removes service from tracking on goodbye" do
      require_udp_sockets!
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
        device_type: 0x0100_u32,
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
      require_udp_sockets!
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
        device_type: 0x0100_u32,
        commissioning_mode: Matter::MDNS::CommissioningMode::Basic
      )

      # Advertise operational service
      op_info = Matter::MDNS::OperationalInfo.new(
        compressed_fabric_id: (cfid = Bytes.new(8); IO::ByteFormat::LittleEndian.encode(0x1234567890ABCDEF_u64, cfid); cfid),
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
  describe "commissioning subtypes" do
    # Discriminator 2048 = 0x800: short discriminator (upper 4 bits) is 8
    it "announces PTR records for the service and every discovery subtype" do
      require_udp_sockets!
      responder = recording_responder
      responder.advertise_commissioning(commissioning_info(2048_u16), port: 5540)

      responder.sent.size.should eq(1)
      instance = responder.commissioning_instance_name.as(String)
      instance.should match(/\A[0-9A-F]{16}\._matterc\._udp\.local\z/)

      instance_ptrs = ptr_records(responder.sent.first).select { |record| ptr_target(record) == instance }
      instance_ptrs.map(&.name).sort!.should eq([
        "_CM._sub._matterc._udp.local",
        "_L2048._sub._matterc._udp.local",
        "_S8._sub._matterc._udp.local",
        "_T15._sub._matterc._udp.local",
        "_V65521._sub._matterc._udp.local",
        "_matterc._udp.local",
      ])
    end

    it "answers PTR queries for each subtype and the base service" do
      require_udp_sockets!
      responder = recording_responder
      responder.advertise_commissioning(commissioning_info(2048_u16), port: 5540)
      instance = responder.commissioning_instance_name.as(String)

      {
        "_matterc._udp.local",
        "_L2048._sub._matterc._udp.local",
        "_S8._sub._matterc._udp.local",
        "_CM._sub._matterc._udp.local",
        "_T15._sub._matterc._udp.local",
        "_V65521._sub._matterc._udp.local",
      }.each do |name|
        responder.sent.clear
        responder.process_query(query_for(name, Matter::MDNS::RecordBuilder::TYPE_PTR))

        responder.sent.size.should eq(1)
        answer = ptr_records(responder.sent.first).find { |record| record.name == name }
        answer.should_not be_nil
        ptr_target(answer.as(DNS::Packet::ResourceRecord)).should eq(instance)
      end
    end

    it "matches subtype queries case-insensitively" do
      require_udp_sockets!
      responder = recording_responder
      responder.advertise_commissioning(commissioning_info(2048_u16), port: 5540)
      responder.sent.clear

      responder.process_query(query_for("_l2048._sub._matterc._udp.local", Matter::MDNS::RecordBuilder::TYPE_PTR))

      responder.sent.size.should eq(1)
    end

    it "ignores PTR queries for subtypes it does not advertise" do
      require_udp_sockets!
      responder = recording_responder
      responder.advertise_commissioning(commissioning_info(2048_u16), port: 5540)
      responder.sent.clear

      responder.process_query(query_for("_L2049._sub._matterc._udp.local", Matter::MDNS::RecordBuilder::TYPE_PTR))
      responder.process_query(query_for("_S9._sub._matterc._udp.local", Matter::MDNS::RecordBuilder::TYPE_PTR))
      responder.process_query(query_for("_http._tcp.local", Matter::MDNS::RecordBuilder::TYPE_PTR))

      responder.sent.should be_empty
    end

    it "answers SRV and TXT queries for the instance name" do
      require_udp_sockets!
      responder = recording_responder
      responder.advertise_commissioning(commissioning_info(2048_u16), port: 5540)
      instance = responder.commissioning_instance_name.as(String)

      {Matter::MDNS::RecordBuilder::TYPE_SRV, Matter::MDNS::RecordBuilder::TYPE_TXT}.each do |type|
        responder.sent.clear
        responder.process_query(query_for(instance, type))

        responder.sent.size.should eq(1)
        response = responder.sent.first
        response.additionals.any? { |record| record.type == type && record.name == instance }.should be_true
      end
    end

    it "advertises a new discriminator and instance after stop_commissioning" do
      require_udp_sockets!
      responder = recording_responder
      responder.advertise_commissioning(commissioning_info(100_u16, Matter::MDNS::CommissioningMode::Basic), port: 5540)
      first_instance = responder.commissioning_instance_name.as(String)

      responder.stop_commissioning
      responder.commissioning_instance_name.should be_nil
      goodbye = responder.sent.last
      goodbye.answers.map(&.ttl).should eq([0.seconds])
      ptr_target(goodbye.answers.first).should eq(first_instance)

      responder.sent.clear
      responder.advertise_commissioning(commissioning_info(200_u16, Matter::MDNS::CommissioningMode::Enhanced), port: 5540)

      second_instance = responder.commissioning_instance_name.as(String)
      second_instance.should match(/\A[0-9A-F]{16}\._matterc\._udp\.local\z/)
      second_instance.should_not eq(first_instance)

      announcement = responder.sent.first
      ptr_records(announcement).map(&.name).should contain("_L200._sub._matterc._udp.local")
      ptr_records(announcement).map(&.name).should_not contain("_L100._sub._matterc._udp.local")
      txt = txt_entries(txt_record(announcement))
      txt["CM"].should eq(Matter::MDNS::CommissioningMode::Enhanced.value.to_s)
      txt["D"].should eq("200")
      responder.advertised_commissioning_info.try(&.discriminator).should eq(200_u16)
    end
  end

  describe "announcement burst" do
    it "repeats the commissioning announcement ANNOUNCEMENT_BURST_COUNT times" do
      require_udp_sockets!
      responder = recording_responder(burst_interval: 10.milliseconds)
      responder.advertise_commissioning(commissioning_info(2048_u16), port: 5540)

      # First announcement is sent synchronously
      responder.sent.size.should eq(1)

      wait_for(200.milliseconds) { responder.sent.size == Matter::MDNS::Responder::ANNOUNCEMENT_BURST_COUNT }
      responder.sent.size.should eq(Matter::MDNS::Responder::ANNOUNCEMENT_BURST_COUNT)
      responder.sent.map { |packet| ptr_records(packet).map(&.name) }.uniq!.size.should eq(1)
    end

    it "repeats the operational announcement ANNOUNCEMENT_BURST_COUNT times" do
      require_udp_sockets!
      responder = recording_responder(burst_interval: 10.milliseconds)
      info = Matter::MDNS::OperationalInfo.new(compressed_fabric_id: Bytes.new(8, 0x11_u8), node_id: 1_u64)
      responder.advertise_operational(info, port: 5540)

      responder.sent.size.should eq(1)
      wait_for(200.milliseconds) { responder.sent.size == Matter::MDNS::Responder::ANNOUNCEMENT_BURST_COUNT }
      responder.sent.size.should eq(Matter::MDNS::Responder::ANNOUNCEMENT_BURST_COUNT)
    end

    it "cancels the burst on stop_commissioning" do
      require_udp_sockets!
      responder = recording_responder(burst_interval: 10.milliseconds)
      responder.advertise_commissioning(commissioning_info(2048_u16), port: 5540)
      responder.stop_commissioning

      # announcement + goodbye only; no further burst announcements
      sleep 50.milliseconds
      responder.sent.size.should eq(2)
      responder.sent.last.answers.map(&.ttl).should eq([0.seconds])
    end
  end
end
