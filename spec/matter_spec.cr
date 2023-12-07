require "./spec_helper"

describe Matter do
  it "creates a memory backend storage with a context and stores a string" do
    storage = Matter::Storage::MemoryBackend.new
    storage_manager = Matter::Storage::Manager.new(storage)

    context = storage_manager.create_context("one")

    context.set("two", "three")
    context.get("two").should eq "three"
  end

  it "encodes/decodes packet and payload header into a message" do
    packet_header = Matter::Codec::MessageCodec::PacketHeader.new(session_id: 1_u16, session_type: Matter::Codec::MessageCodec::SessionType::Group, message_id: 1_u32, privacy_enhancements: false, control_message: false, message_extensions: false, source_node_id: Matter::DataType::NodeId.new(1_u64))
    payload_header = Matter::Codec::MessageCodec::PayloadHeader.new(exchange_id: 1234_u16, protocol_id: 1_u16, message_type: 2_u8, initiator_message: false, requires_acknowledge: false, acknowledged_message_id: 3123_u32)

    message = Matter::Codec::MessageCodec::Message.new(packet_header: packet_header, payload_header: payload_header, payload: Slice[1_u8, 2_u8, 3_u8, 4_u8, 5_u8])

    payload_encoded_packet = Matter::Codec::MessageCodec::Base.encode_payload(message)
    second_message = Matter::Codec::MessageCodec::Base.decode_payload(payload_encoded_packet)

    payload_header.exchange_id.should eq second_message.payload_header.exchange_id
    payload_header.protocol_id.should eq second_message.payload_header.protocol_id
    payload_header.message_type.should eq second_message.payload_header.message_type
    payload_header.initiator_message?.should eq second_message.payload_header.initiator_message?
    payload_header.requires_acknowledge?.should eq second_message.payload_header.requires_acknowledge?
    payload_header.acknowledged_message_id.should eq second_message.payload_header.acknowledged_message_id
  end

  it "encodes/decodes dns messages" do
    query = Matter::Codec::DNSCodec::Query.new(name: "www.google.com", record_type: Matter::Codec::DNSCodec::RecordType::PTR, record_class: Matter::Codec::DNSCodec::RecordClass::IN, unicast_response: false)

    queries = [
      query,
    ] of Matter::Codec::DNSCodec::Query

    answers = [
      Matter::Codec::DNSCodec::AAAARecord.new(name: "www.instagram.com", ip: "2001:0db8:85a3:0000:0000:8a2e:0370:7334"),
      Matter::Codec::DNSCodec::ARecord.new(name: "www.instagram.com", ip: "127.0.0.1"),
      Matter::Codec::DNSCodec::PtrRecord.new(name: "www.instagram.com", ptr: "instagram.com"),
      Matter::Codec::DNSCodec::TxtRecord.new(name: "www.instagram.com", entries: ["1", "2", "3", "4", "5"] of String),
      Matter::Codec::DNSCodec::SrvRecord.new(name: "www.instagram.com", srv: Matter::Codec::DNSCodec::SrvRecordValue.new(1_u16, 2_u16, 3_u16, "Hello, World!")),
    ] of Matter::Codec::DNSCodec::Record

    encoded_message = Matter::Codec::DNSCodec::Base.encode(Matter::Codec::DNSCodec::MessageType::Query, 2_u16, queries: queries, answers: answers, authorities: [] of Matter::Codec::DNSCodec::Record, additional_records: [] of Matter::Codec::DNSCodec::Record)
    decoded_message = Matter::Codec::DNSCodec::Base.decode(encoded_message)

    raise Exception.new("Decoded message was nil") if decoded_message.nil?

    decoded_message.queries.first.name.should eq queries.first.name
    decoded_message.answers.first.value.should eq "2001:db8:85a3::8a2e:370:7334" # Compressed version of IPv6
  end

  it "encodes/decodes in der codec" do
    data = Matter::Codec::DERCodec::Base.encode(Time.utc)
    node = Matter::Codec::DERCodec::Base.decode(data)

    data.[2..].should eq node.value.["_bytes"]

    public_key = "00 04 4B D6 87 AB D2 9B 59 D8 B1 2E 8C 66 14 BD 16 64 AD B2 D4 02 45 5B 6C A3 EF 4E 58 1E 3B E3 44 B8 32 12 E6 14 F2 7E A4 EE C8 F3 1C 75 74 74 38 73 9B 1D 45 1A 7E AB 3A 30 54 2A 0A 7D 18 82 A4 59".split.map(&.to_u8(16))
    signature = "00 30 46 02 21 00 80 86 1A D5 36 EF F0 1C AD 42 81 6A 81 72 F7 1B E3 E4 FD 72 30 CF 73 A4 5E 34 94 5F E8 9D 5D 72 02 21 00 87 FC 1F 47 AD B6 D1 50 58 07 06 86 5E 2E 21 E2 96 3C 9C 15 00 6B 64 DA B5 65 8B FB 98 0A 2A D3".split.map(&.to_u8(16))

    packet = {
      "request" => {
        "version"        => 0_u8.as(Matter::Codec::DERCodec::Value),
        "subject"        => { "organization" => Matter::Codec::DERCodec::OrganisationName_X520.call("CSR").as(Matter::Codec::DERCodec::Value) } of String => Matter::Codec::DERCodec::Value,
        "publicKey"      => Matter::Codec::DERCodec::PublicKeyEcPrime256v1_X962.call(Slice(UInt8).new(public_key.size) { |i| public_key[i] }),
        "endSignedBytes" => Matter::Codec::DERCodec::ContextTagged.new(0).value,
      } of String => Matter::Codec::DERCodec::Value,
      "signAlgorithm" => Matter::Codec::DERCodec::EcdsaWithSHA256_X962.call,
      "signature" => Matter::Codec::DERCodec::ByteArray.new(Slice(UInt8).new(signature.size) { |i| signature[i] }).value,
    } of String => Matter::Codec::DERCodec::Value

    encoded = "30 81 cb 30 71 02 01 00 30 0e 31 0c 30 0a 06 03 55 04 0a 0c 03 43 53 52 30 5a 30 13 06 07 2a 86 48 ce 3d 02 01 06 08 2a 86 48 ce 3d 03 01 07 03 43 00 00 04 4b d6 87 ab d2 9b 59 d8 b1 2e 8c 66 14 bd 16 64 ad b2 d4 02 45 5b 6c a3 ef 4e 58 1e 3b e3 44 b8 32 12 e6 14 f2 7e a4 ee c8 f3 1c 75 74 74 38 73 9b 1d 45 1a 7e ab 3a 30 54 2a 0a 7d 18 82 a4 59 a0 00 30 0a 06 08 2a 86 48 ce 3d 04 03 02 03 4a 00 00 30 46 02 21 00 80 86 1a d5 36 ef f0 1c ad 42 81 6a 81 72 f7 1b e3 e4 fd 72 30 cf 73 a4 5e 34 94 5f e8 9d 5d 72 02 21 00 87 fc 1f 47 ad b6 d1 50 58 07 06 86 5e 2e 21 e2 96 3c 9c 15 00 6b 64 da b5 65 8b fb 98 0a 2a d3".split.map(&.to_u8(16))

    crafted = Matter::Codec::DERCodec::Base.encode(packet)
    original = Slice(UInt8).new(encoded.size) { |i| encoded[i] }

    crafted.hexstring.should eq original.hexstring
  end
end
