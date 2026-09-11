require "../spec_helper"

require "../../src/matter/cluster/on_off"
require "../../src/matter/codec/message_codec"
require "../../src/matter/crypto/crypto"
require "../../src/matter/datatype/node_id"
require "../../src/matter/protocol/message_handler"
require "../../src/matter/session/secure_message"
require "../../src/matter/transport/udp_transport"

# Captures outbound packets without actually sending them.
class CaptureTransport < Matter::Transport::UDPTransport
  getter sent_packets : Array(Tuple(Bytes, Socket::IPAddress)) = [] of Tuple(Bytes, Socket::IPAddress)

  # Avoid binding OS UDP sockets in the spec environment.
  def self.new_for_spec : self
    transport = allocate
    transport.initialize_for_spec
    transport
  end

  protected def initialize_for_spec : Nil
    @sent_packets = [] of Tuple(Bytes, Socket::IPAddress)
  end

  def send_raw(data : Bytes | Slice(UInt8), peer_address : Socket::IPAddress) : Nil
    slice = data.to_slice
    buf = Bytes.new(slice.size)
    buf.copy_from(slice)
    @sent_packets << {buf, peer_address}
  end
end

# Spec helper: allow deterministic exchange IDs without changing production code.
class Matter::Protocol::MessageHandler
  def __set_next_exchange_id_for_spec(value : UInt16) : Nil
    @next_exchange_id = value
  end
end

describe "Subscription report exchange regression" do
  it "sends subscription ReportData on a new exchange (initiator=true)" do
    transport = CaptureTransport.new_for_spec
    storage = Matter::Storage::Memory.new
    fabric_table = Matter::FabricTable.new(storage)

    handler = Matter::Protocol::MessageHandler.new(
      transport: transport,
      setup_pin: 20202021_u32,
      discriminator: 3840_u16,
      fabric_table: fabric_table
    )

    endpoint = Matter::DataType::EndpointNumber.new(1_u16)
    on_off = Matter::Cluster::OnOff.new(endpoint, on_off: false)
    handler.clusters[{1_u16, Matter::Cluster::OnOff::CLUSTER_ID}] = on_off

    session = Matter::Session::SecureContext.new(
      session_id: 1_u16,
      peer_session_id: 2_u16,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: Bytes.new(16, 0x11_u8),
      decryption_key: Bytes.new(16, 0x22_u8),
      initiator: false,
      peer_node_id: Matter::DataType::NodeId.new(0x2222_u64),
      local_node_id: Matter::DataType::NodeId.new(0x1111_u64),
      case_session: true,
      fabric_index: 1_u8
    )

    subscription_exchange_id = 0x1234_u16
    subscription = Matter::Protocol::MessageHandler::ActiveSubscription.new(
      subscription_id: 1_u32,
      min_interval: 0_u16,
      max_interval: 60_u16,
      peer: Socket::IPAddress.new("127.0.0.1", 5540),
      session: session,
      attribute_paths: [
        Matter::InteractionModel::AttributePath.new(
          endpoint: 1_u16,
          cluster: Matter::Cluster::OnOff::CLUSTER_ID,
          attribute: Matter::Cluster::OnOff::ATTR_ON_OFF
        ),
      ],
      exchange_id: subscription_exchange_id
    )
    handler.active_subscriptions[subscription.subscription_id] = subscription

    update_exchange_id = 0xBEEF_u16
    handler.__set_next_exchange_id_for_spec(update_exchange_id)

    # Trigger a subscription update send.
    handler.notify_subscriptions(1_u16, Matter::Cluster::OnOff::CLUSTER_ID, Matter::Cluster::OnOff::ATTR_ON_OFF)

    transport.sent_packets.size.should be >= 1
    packet_bytes, _peer = transport.sent_packets.last

    packet = Matter::Codec::MessageCodec::Base.decode_packet(packet_bytes)
    header_len = packet_bytes.size - packet.payload.size
    packet_header_bytes = packet_bytes[0, header_len]

    # Decrypt the encrypted application payload to inspect the PayloadHeader fields.
    crypto = Matter::Crypto::StandardCrypto.new
    message_counter = packet.header.message_id
    security_flags = packet_header_bytes[3]
    nonce = Matter::Session::SecureMessage.build_nonce(session.local_node_id.as(Matter::DataType::NodeId).id, message_counter, security_flags)
    decrypted = crypto.decrypt(session.encryption_key, packet.payload, nonce, packet_header_bytes)

    decrypted_packet = Matter::Codec::MessageCodec::Packet.new(packet.header, decrypted)
    message = Matter::Codec::MessageCodec::Base.decode_payload(decrypted_packet)

    message.payload_header.protocol_id.should eq(0x0001_u16) # Interaction Model
    message.payload_header.message_type.should eq(0x05_u8)   # ReportData
    message.payload_header.exchange_id.should eq(update_exchange_id)
    message.payload_header.initiator_message?.should be_true
  end
end
