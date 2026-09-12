# Shared preamble for the `Matter::Protocol::SessionRegistry` specs, which are
# split into `spec/protocol/session_registry_supersession_spec.cr` and
# `spec/protocol/session_registry_cleanup_triggers_spec.cr`.
require "../../src/matter/protocol/session_registry"
require "../../src/matter/session/context"

# Helper module for creating test objects
module SessionRegistryTestHelpers
  def self.create_test_registry(
    max_sessions : UInt16 = Matter::Protocol::SessionRegistry::DEFAULT_MAX_SESSIONS,
  ) : Matter::Protocol::SessionRegistry
    Matter::Protocol::SessionRegistry.new(
      mrp_cache: Matter::Protocol::MrpCache.new(Matter::Spec::CaptureTransport.new_for_spec),
      max_sessions: max_sessions
    )
  end

  def self.create_case_session(
    session_id : UInt16,
    fabric_index : UInt8,
    peer_node_id : UInt64,
    creation_offset : Time::Span = 0.seconds,
  ) : Matter::Session::SecureContext
    ctx = Matter::Session::SecureContext.new(
      session_id: session_id,
      peer_session_id: (session_id + 1000).to_u16,
      session_type: Matter::Session::SessionType::Unicast,
      encryption_key: Random::Secure.random_bytes(16),
      decryption_key: Random::Secure.random_bytes(16),
      initiator: false,
      peer_node_id: Matter::DataType::NodeId.new(peer_node_id),
      local_node_id: Matter::DataType::NodeId.new(1_u64),
      case_session: true,
      fabric_index: fabric_index
    )
    # Adjust creation time for testing supersession order
    ctx.creation_time = Time.utc - creation_offset
    ctx
  end
end
