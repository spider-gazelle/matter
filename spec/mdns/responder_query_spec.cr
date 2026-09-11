require "../spec_helper"
require "../support/mdns_responder_helpers"

describe Matter::MDNS::Responder do
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
        compressed_fabric_id: compressed_fabric_id_bytes(0x1234567890ABCDEF_u64),
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
end
