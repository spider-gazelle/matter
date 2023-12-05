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
      query
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
  end
end
