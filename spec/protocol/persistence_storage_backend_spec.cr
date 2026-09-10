require "../spec_helper"
require "../../src/matter/protocol/persistence"

private SESSIONS      = Matter::Storage::Collections::SESSIONS
private SUBSCRIPTIONS = Matter::Storage::Collections::SUBSCRIPTIONS
private DEVICE        = Matter::Storage::Collections::DEVICE

private def build_fabric(fabric_index : UInt8) : Matter::Fabric
  Matter::Fabric.new(
    fabric_id: fabric_index.to_u64,
    fabric_index: fabric_index,
    node_id: 0x1_u64,
    root_public_key: Random::Secure.random_bytes(65),
    operational_cert: Random::Secure.random_bytes(200),
    operational_key: Matter::Crypto::Key.generate_key_pair,
    ipk: Random::Secure.random_bytes(16)
  )
end

private def case_session(session_id : UInt16, fabric_index : UInt8) : Matter::Session::SecureContext
  Matter::Session::SecureContext.new(
    session_id: session_id,
    peer_session_id: session_id &+ 1_u16,
    session_type: Matter::Session::SessionType::Unicast,
    encryption_key: Bytes.new(16, 1_u8),
    decryption_key: Bytes.new(16, 2_u8),
    initiator: false,
    peer_node_id: Matter::DataType::NodeId.new(0x1234_u64),
    attestation_challenge: Bytes.new(16, 3_u8),
    case_session: true,
    fabric_index: fabric_index
  )
end

private def build_handler(storage : Matter::Storage::Backend, fabric_table : Matter::FabricTable) : Matter::Protocol::MessageHandler
  # Avoid binding sockets in the spec environment.
  transport = Matter::Transport::UDPTransport.allocate

  Matter::Protocol::MessageHandler.new(
    transport: transport,
    setup_pin: 20202021_u32,
    discriminator: 3840_u16,
    fabric_table: fabric_table,
    persistence: Matter::Protocol::Persistence::StorageBackend.new(storage)
  )
end

private def build_subscription(id : UInt32, session : Matter::Session::SecureContext) : Matter::Protocol::MessageHandler::ActiveSubscription
  Matter::Protocol::MessageHandler::ActiveSubscription.new(
    subscription_id: id,
    min_interval: 1_u16,
    max_interval: 60_u16,
    peer: Socket::IPAddress.new("192.168.1.20", 5540),
    session: session,
    attribute_paths: [
      Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 6_u32, attribute: 0_u32),
      Matter::InteractionModel::AttributePath.new,
    ],
    exchange_id: 7_u16
  )
end

describe Matter::Protocol::Persistence::StorageBackend do
  describe "sessions" do
    it "writes established CASE sessions as documents and skips PASE sessions" do
      storage = Matter::Storage::Memory.new
      handler = build_handler(storage, Matter::FabricTable.new(storage))
      backend = Matter::Protocol::Persistence::StorageBackend.new(storage)

      session = case_session(111_u16, 1_u8)
      backend.session_established(handler, session)
      document = storage.read(SESSIONS, "111").as(Matter::Storage::Document)
      document["encryption_key"].should eq(Bytes.new(16, 1_u8))
      document["fabric_index"].should eq(1_i64)
      document["session_type"].should eq("Unicast")

      pase = case_session(222_u16, 1_u8)
      pase.case_session = false
      backend.session_established(handler, pase)
      storage.ids(SESSIONS).should eq(["111"])
    end

    it "removes the session document" do
      storage = Matter::Storage::Memory.new
      handler = build_handler(storage, Matter::FabricTable.new(storage))
      backend = Matter::Protocol::Persistence::StorageBackend.new(storage)

      backend.session_established(handler, case_session(111_u16, 1_u8))
      backend.session_removed(handler, 111_u16)
      storage.ids(SESSIONS).should be_empty
    end

    it "defers session updates to the debouncer and drops them for removed sessions" do
      storage = Matter::Storage::Memory.new
      handler = build_handler(storage, Matter::FabricTable.new(storage))
      backend = Matter::Protocol::Persistence::StorageBackend.new(storage)
      debouncer = Matter::Debouncer.new(1.hour) { }
      backend.write_debouncer = debouncer

      session = case_session(111_u16, 1_u8)
      backend.session_established(handler, session)
      session.local_message_counter = 42_u32
      backend.session_updated(handler, session)
      debouncer.pending?.should be_true
      storage.read(SESSIONS, "111").as(Matter::Storage::Document)["local_message_counter"].should_not eq(42_i64)

      backend.flush_pending_writes
      storage.read(SESSIONS, "111").as(Matter::Storage::Document)["local_message_counter"].should eq(42_i64)

      backend.session_updated(handler, session)
      backend.session_removed(handler, 111_u16)
      backend.flush_pending_writes
      storage.ids(SESSIONS).should be_empty
      debouncer.cancel
    end

    it "restores CASE sessions for known fabrics" do
      storage = Matter::Storage::Memory.new
      fabric_table = Matter::FabricTable.new(storage)
      fabric_table.add_fabric(build_fabric(1_u8))

      session = case_session(111_u16, 1_u8)
      session.local_message_counter = 99_u32
      session.peer_message_counter = 7_u32
      storage.write(SESSIONS, "111", session.to_record.to_document)

      handler = build_handler(storage, fabric_table)
      restored = handler.sessions[111_u16]
      restored.local_message_counter.should eq(99_u32)
      restored.peer_message_counter.should eq(7_u32)
      restored.peer_node_id.should eq(Matter::DataType::NodeId.new(0x1234_u64))
      restored.attestation_challenge.should eq(Bytes.new(16, 3_u8))
      restored.fabric_index.should eq(1_u8)
    end

    it "does not restore CASE sessions for missing fabrics (and prunes them)" do
      storage = Matter::Storage::Memory.new
      fabric_table = Matter::FabricTable.new(storage)

      # Persist a CASE session referencing fabric 1, but do not create that fabric.
      storage.write(SESSIONS, "111", case_session(111_u16, 1_u8).to_record.to_document)

      handler = build_handler(storage, fabric_table)
      handler.sessions.has_key?(111_u16).should be_false
      storage.ids(SESSIONS).should be_empty
    end

    it "prunes undecodable session documents" do
      storage = Matter::Storage::Memory.new
      fabric_table = Matter::FabricTable.new(storage)
      storage.write(SESSIONS, "5", Matter::Storage::Document{"session_id" => "bogus"})

      handler = build_handler(storage, fabric_table)
      handler.sessions.should be_empty
      storage.ids(SESSIONS).should be_empty
    end
  end

  describe "subscriptions" do
    it "writes the subscription document and the next subscription id" do
      storage = Matter::Storage::Memory.new
      handler = build_handler(storage, Matter::FabricTable.new(storage))
      backend = Matter::Protocol::Persistence::StorageBackend.new(storage)
      handler.next_subscription_id = 11_u32

      backend.subscription_established(handler, build_subscription(10_u32, case_session(111_u16, 1_u8)))

      document = storage.read(SUBSCRIPTIONS, "10").as(Matter::Storage::Document)
      document["session_id"].should eq(111_i64)
      document["peer_address"].should eq("192.168.1.20")
      document["peer_port"].should eq(5540_i64)
      paths = document["attribute_paths"].as(Array(Matter::Storage::Type))
      paths.size.should eq(2)
      paths[0].should eq(Matter::Storage::Document{"endpoint" => 1_i64, "cluster" => 6_i64, "attribute" => 0_i64})
      paths[1].should eq(Matter::Storage::Document.new)

      counters = storage.read(DEVICE, Matter::Protocol::Persistence::StorageBackend::COUNTERS_ID).as(Matter::Storage::Document)
      counters[Matter::Protocol::Persistence::StorageBackend::NEXT_SUBSCRIPTION_ID_KEY].should eq(11_i64)

      backend.subscription_removed(handler, 10_u32)
      storage.ids(SUBSCRIPTIONS).should be_empty
    end

    it "restores subscriptions whose session exists and prunes the rest" do
      storage = Matter::Storage::Memory.new
      fabric_table = Matter::FabricTable.new(storage)
      fabric_table.add_fabric(build_fabric(1_u8))

      session = case_session(111_u16, 1_u8)
      storage.write(SESSIONS, "111", session.to_record.to_document)
      storage.write(SUBSCRIPTIONS, "10", build_subscription(10_u32, session).to_record.to_document)
      storage.write(SUBSCRIPTIONS, "20", build_subscription(20_u32, case_session(222_u16, 1_u8)).to_record.to_document)
      storage.write(DEVICE, Matter::Protocol::Persistence::StorageBackend::COUNTERS_ID,
        Matter::Storage::Document{Matter::Protocol::Persistence::StorageBackend::NEXT_SUBSCRIPTION_ID_KEY => 50_i64})

      handler = build_handler(storage, fabric_table)

      handler.active_subscriptions.keys.should eq([10_u32])
      subscription = handler.active_subscriptions[10_u32]
      subscription.session.should be(handler.sessions[111_u16])
      subscription.peer.should eq(Socket::IPAddress.new("192.168.1.20", 5540))
      subscription.exchange_id.should eq(7_u16)
      subscription.attribute_paths.size.should eq(2)
      subscription.attribute_paths[0].endpoint.should eq(1_u16)
      subscription.attribute_paths[1].cluster.should be_nil
      handler.next_subscription_id.should eq(50_u32)
      storage.ids(SUBSCRIPTIONS).should eq(["10"])
    end
  end
end
