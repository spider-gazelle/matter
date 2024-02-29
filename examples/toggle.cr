require "../src/matter"

require "socket"

Log.setup(:debug)

module Toggle
  DUMMY_QNAME = "a.b.c.d"
  DUMMY_IP    = "1.2.3.4"

  PORT = 1234_u16

  alias Configuration = Matter::Cluster::Definitions::BasicInformation::Configuration

  alias Interface = Socket::IPAddress
  alias DNSCodec = Matter::Codec::DNSCodec

  server = Matter::MDNS::Server.new

  server.add_records_generator(port: PORT, type: Matter::MDNS::AnnouncementType::Commissionable, generator: ->(interface : Interface) {
    [
      DNSCodec::PtrRecord.new(DUMMY_QNAME, "abcd"),
      DNSCodec::SrvRecord.new(DUMMY_QNAME, DNSCodec::SrvRecordValue.new(0_u16, 0_u16, PORT, "abcd.local")),
      DNSCodec::TxtRecord.new(DUMMY_QNAME, ["A=1", "B=2"]),
      DNSCodec::ARecord.new("abcd.local", DUMMY_IP)
    ] of Matter::Codec::DNSCodec::Record
  })

  # Query message
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

  address = Matter::Network::Constants::MDNS_ADDRESS_IPv4

  socket = UDPSocket.new address.family
  socket.reuse_address = true
  socket.reuse_port = true
  socket.bind(Socket::IPAddress::UNSPECIFIED, address.port)

  # socket.multicast_interface Matter::Network::Constants::DEFAULT_INTERFACE_IPV4
  socket.join_group address

  puts "... SENDING ..."

  socket.send(encoded_message, to: Matter::Network::Constants::MDNS_ADDRESS_IPv4)
end

sleep
