require "./spec_helper"

describe Matter do
  it "creates a memory backend storage with a context and stores a string" do
    storage = Matter::Storage::MemoryBackend.new
    storage.set(["one"], "two", "three")
    storage.get(["one"], "two").should eq "three"
  end

  it "encodes/decodes packet and payload header into a message" do
    source_node_id = Matter::DataType::NodeId.new(1_u64)
    # Compute flags with HasSourceNodeId flag set
    flags = Matter::Codec::MessageCodec::Base.compute_flags(source_node_id, nil, nil)
    packet_header = Matter::Codec::MessageCodec::PacketHeader.new(session_id: 1_u16, session_type: Matter::Codec::MessageCodec::SessionType::Group, message_id: 1_u32, privacy_enhancements: false, control_message: false, message_extensions: false, flags: flags, security_flags: 1_u8, source_node_id: source_node_id)
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

  it "encodes/decodes in der codec" do
    data = Matter::Codec::DERCodec::Base.encode(Time.utc)
    node = Matter::Codec::DERCodec::Base.decode(data)

    data.[2..].should eq node.value.["_bytes"]

    original = "3081cb3071020100300e310c300a060355040a0c03435352305a301306072a8648ce3d020106082a8648ce3d03010703430000044bd687abd29b59d8b12e8c6614bd1664adb2d402455b6ca3ef4e581e3be344b83212e614f27ea4eec8f31c75747438739b1d451a7eab3a30542a0a7d1882a459a000300a06082a8648ce3d040302034a0000304602210080861ad536eff01cad42816a8172f71be3e4fd7230cf73a45e34945fe89d5d7202210087fc1f47adb6d150580706865e2e21e2963c9c15006b64dab5658bfb980a2ad3".hexbytes

    public_key = "00044BD687ABD29B59D8B12E8C6614BD1664ADB2D402455B6CA3EF4E581E3BE344B83212E614F27EA4EEC8F31C75747438739B1D451A7EAB3A30542A0A7D1882A459".hexbytes
    signature = "00304602210080861AD536EFF01CAD42816A8172F71BE3E4FD7230CF73A45E34945FE89D5D7202210087FC1F47ADB6D150580706865E2E21E2963C9C15006B64DAB5658BFB980A2AD3".hexbytes

    packet = {
      "request" => {
        "version"        => 0_u8.as(Matter::Codec::DERCodec::Value),
        "subject"        => {"organization" => Matter::Codec::DERCodec::OrganisationName_X520.call("CSR").as(Matter::Codec::DERCodec::Value)} of String => Matter::Codec::DERCodec::Value,
        "publicKey"      => Matter::Codec::DERCodec::PublicKeyEcPrime256v1_X962.call(Slice(UInt8).new(public_key.size) { |i| public_key[i] }),
        "endSignedBytes" => Matter::Codec::DERCodec::ContextTagged.new(0).value,
      } of String => Matter::Codec::DERCodec::Value,
      "signAlgorithm" => Matter::Codec::DERCodec::EcdsaWithSHA256_X962.call,
      "signature"     => Matter::Codec::DERCodec::ByteArray.new(Slice(UInt8).new(signature.size) { |i| signature[i] }).value,
    } of String => Matter::Codec::DERCodec::Value

    crafted = Matter::Codec::DERCodec::Base.encode(packet)

    crafted.hexstring.should eq original.hexstring
  end
end
