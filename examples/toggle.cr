require "../src/matter"

require "socket"

Log.setup(:debug)

DUMMY_QNAME = "a.b.c.d"
DUMMY_IP    = "1.2.3.4"

PORT = 1234_u16

module Toggle
  alias Configuration = Matter::Cluster::Definitions::BasicInformation::Configuration

  alias Interface = Socket::IPAddress | UInt32
  alias DNSCodec = Matter::Codec::DNSCodec

  server = Matter::MDNS::Server.new

  server.add_records_generator(port: PORT, type: Matter::MDNS::AnnouncementType::Commissionable, generator: ->(interface : Interface) {
    [
      DNSCodec::PtrRecord.new(DUMMY_QNAME, "abcd"),
      DNSCodec::SrvRecord.new(DUMMY_QNAME, DNSCodec::SrvRecordValue.new(0_u16, 0_u16, PORT, "abcd.local")),
      DNSCodec::TxtRecord.new(DUMMY_QNAME, ["A=1", "B=2"]),
      DNSCodec::ARecord.new("abcd.local", DUMMY_IP),
    ] of Matter::Codec::DNSCodec::Record
  })

  # server.announce(Matter::Network::Constants::DEFAULT_INTERFACE_IPV4, PORT)

  encoded_message = DNSCodec::Base.encode(
    DNSCodec::Message.new(
      transaction_id: 0_u16,
      message_type: DNSCodec::MessageType::Query,
      queries: [
        DNSCodec::Query.new(
          name: DUMMY_QNAME,
          record_class: DNSCodec::RecordClass::IN,
          record_type: DNSCodec::RecordType::ANY),
      ] of DNSCodec::Query,
      answers: [] of DNSCodec::Record,
      authorities: [] of DNSCodec::Record,
      additional_records: [] of DNSCodec::Record
    )
  )

  server.multicast_server.socket.send(encoded_message, to: Socket::IPAddress.new(DUMMY_IP, PORT))
end

sleep
