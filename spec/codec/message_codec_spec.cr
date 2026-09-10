require "../spec_helper"

describe Matter::Codec::MessageCodec do
  it "encodes/decodes packet and payload header into a message" do
    source_node_id = Matter::DataType::NodeId.new(1_u64)
    # Compute flags with HasSourceNodeId flag set

    packet_header = Matter::Codec::MessageCodec::PacketHeader.new(session_id: 1_u16, session_type: Matter::Codec::MessageCodec::SessionType::Group, message_id: 1_u32, privacy_enhancements: false, control_message: false, message_extensions: false, source_node_id: source_node_id)
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
end
