require "../spec_helper"
require "../../src/matter/protocol/persistence"

describe Matter::Protocol::Persistence::StorageBackend do
  it "does not restore CASE sessions for missing fabrics (and prunes them)" do
    storage = Matter::Storage::MemoryBackend.new
    fabric_table = Matter::FabricTable.new(storage)

    # Persist a CASE session referencing fabric 1, but do not create that fabric.
    session = Matter::Session::SecureContext.new(
      session_id: 111_u16,
      peer_session_id: 222_u16,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: Bytes.new(16, 1_u8),
      decryption_key: Bytes.new(16, 2_u8),
      is_initiator: false,
      is_case: true,
      fabric_index: 1_u8
    )

    sessions_json = {session.session_id.to_s => session.to_h}.to_json
    storage.set(["protocol"], "case_sessions", sessions_json)

    # Avoid binding sockets in the spec environment.
    transport = Matter::Transport::UDPTransport.allocate

    handler = Matter::Protocol::MessageHandler.new(
      transport: transport,
      setup_pin: 20202021_u32,
      discriminator: 3840_u16,
      fabric_table: fabric_table,
      persistence: Matter::Protocol::Persistence::StorageBackend.new(storage)
    )

    handler.sessions.has_key?(111_u16).should be_false

    # Ensure persisted session data was pruned
    stored = storage.get(["protocol"], "case_sessions")
    stored.should be_a(String)
    Hash(String, Hash(String, JSON::Any)).from_json(stored.as(String)).should be_empty
  end
end
