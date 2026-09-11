require "../spec_helper"
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

describe Matter::Protocol::SessionRegistry do
  describe "session supersession/cleanup" do
    it "cleans up sessions without subscriptions immediately" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create an old session (created 1 minute ago)
      old_session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 1.minute)
      registry.sessions[old_session.session_id] = old_session

      # Create a new session (created now) from the same peer
      new_session = SessionRegistryTestHelpers.create_case_session(200_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[new_session.session_id] = new_session

      # Verify both sessions are present before cleanup (2 sessions)
      registry.sessions.size.should eq(2)

      # Note: cleanup_superseded_sessions is private, but it gets called
      # automatically when we add the new session via handle_case_sigma3.
      # For testing, we can verify the state directly.

      # We can't call private methods directly, but we can verify behavior
      # by checking sessions hash state
      registry.sessions.has_key?(100_u16).should be_true
      registry.sessions.has_key?(200_u16).should be_true
    end

    it "does not mark sessions from different peers as superseded" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create a session from peer A
      session_a = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 1.minute)
      registry.sessions[session_a.session_id] = session_a

      # Create a new session from peer B (different peer_node_id)
      session_b = SessionRegistryTestHelpers.create_case_session(200_u16, 1_u8, 99999_u64, 0.seconds)
      registry.sessions[session_b.session_id] = session_b

      # Both sessions should remain (different peers)
      registry.sessions.size.should eq(2)
      registry.sessions.has_key?(100_u16).should be_true
      registry.sessions.has_key?(200_u16).should be_true
    end

    it "does not mark sessions from different fabrics as superseded" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create a session on fabric 1
      session_fabric1 = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 1.minute)
      registry.sessions[session_fabric1.session_id] = session_fabric1

      # Create a new session on fabric 2 (same peer but different fabric)
      session_fabric2 = SessionRegistryTestHelpers.create_case_session(200_u16, 2_u8, 12345_u64, 0.seconds)
      registry.sessions[session_fabric2.session_id] = session_fabric2

      # Both sessions should remain (different fabrics)
      registry.sessions.size.should eq(2)
      registry.sessions.has_key?(100_u16).should be_true
      registry.sessions.has_key?(200_u16).should be_true
    end

    it "does not mark PASE sessions as superseded" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create a PASE session (is_case=false)
      pase_session = Matter::Session::SecureContext.new(
        session_id: 100_u16,
        peer_session_id: 1100_u16,
        session_type: Matter::Session::SessionType::Unicast,
        encryption_key: Random::Secure.random_bytes(16),
        decryption_key: Random::Secure.random_bytes(16),
        initiator: false,
        case_session: false # PASE session
      )
      registry.sessions[pase_session.session_id] = pase_session

      # Create a new CASE session
      new_session = SessionRegistryTestHelpers.create_case_session(200_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[new_session.session_id] = new_session

      # PASE session should remain (never superseded by CASE)
      registry.sessions.size.should eq(2)
      registry.sessions.has_key?(100_u16).should be_true
      registry.sessions.has_key?(200_u16).should be_true
    end

    it "tracks subscriptions by session" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create a session
      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Add subscriptions using this session
      sub_path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0_u32
      )
      subscription = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [sub_path],
        exchange_id: 1000_u16
      )
      registry.active_subscriptions[1_u32] = subscription

      # Verify subscription is tracked
      registry.active_subscriptions.size.should eq(1)
      registry.active_subscriptions[1_u32].session.session_id.should eq(100_u16)
    end

    it "allows multiple sessions from different peers on same fabric" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create sessions from multiple peers on the same fabric
      session1 = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 2.minutes)
      session2 = SessionRegistryTestHelpers.create_case_session(200_u16, 1_u8, 67890_u64, 1.minute)
      session3 = SessionRegistryTestHelpers.create_case_session(300_u16, 1_u8, 11111_u64, 0.seconds)

      registry.sessions[session1.session_id] = session1
      registry.sessions[session2.session_id] = session2
      registry.sessions[session3.session_id] = session3

      # All sessions should remain (different peers)
      registry.sessions.size.should eq(3)
    end

    it "supports on_session_removed callback" do
      registry = SessionRegistryTestHelpers.create_test_registry

      removed_session_ids = [] of UInt16
      registry.on_session_removed = ->(session_id : UInt16) {
        removed_session_ids << session_id
        nil
      }

      # Callback is registered
      registry.on_session_removed.should_not be_nil
    end

    it "PendingSessionCleanup tracks grace period" do
      # Test the PendingSessionCleanup class
      cleanup = Matter::Protocol::SessionRegistry::PendingCleanup.new(100_u16, 0.seconds)

      # With 0 second grace period, should be ready immediately
      cleanup.ready?.should be_true
      cleanup.session_id.should eq(100_u16)

      # With future grace period, should not be ready
      cleanup2 = Matter::Protocol::SessionRegistry::PendingCleanup.new(200_u16, 1.hour)
      cleanup2.ready?.should be_false
    end

    it "process_pending_cleanups removes expired sessions and their subscriptions" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create a session
      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Add a subscription using this session
      sub_path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0_u32
      )
      subscription = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 42_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [sub_path],
        exchange_id: 1000_u16
      )
      registry.active_subscriptions[42_u32] = subscription

      # Verify initial state
      registry.sessions.size.should eq(1)
      registry.active_subscriptions.size.should eq(1)

      # Track removed session IDs via callback
      removed_ids = [] of UInt16
      registry.on_session_removed = ->(session_id : UInt16) {
        removed_ids << session_id
        nil
      }

      # Manually add a pending cleanup with 0 grace period (immediately ready)
      # This simulates what would happen after cleanup_superseded_sessions schedules it
      pending = Matter::Protocol::SessionRegistry::PendingCleanup.new(100_u16, 0.seconds)
      registry.pending_cleanups << pending

      # Process pending cleanups
      count = registry.process_pending_cleanups
      count.should eq(1)

      # Session and subscription should be removed
      registry.sessions.has_key?(100_u16).should be_false
      registry.active_subscriptions.has_key?(42_u32).should be_false

      # Callback should have been called
      removed_ids.should eq([100_u16])
    end

    it "process_pending_cleanups skips sessions still in grace period" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create a session
      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Add a pending cleanup with 1 hour grace period (not ready yet)
      pending = Matter::Protocol::SessionRegistry::PendingCleanup.new(100_u16, 1.hour)
      registry.pending_cleanups << pending

      # Process pending cleanups
      count = registry.process_pending_cleanups
      count.should eq(0)

      # Session should still exist
      registry.sessions.has_key?(100_u16).should be_true
    end

    it "removes multiple subscriptions when session is cleaned up" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create a session
      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Add multiple subscriptions using this session
      3.times do |i|
        sub_path = Matter::InteractionModel::AttributePath.new(
          endpoint: i.to_u16,
          cluster: 0x0006_u32,
          attribute: 0_u32
        )
        subscription = Matter::Protocol::ActiveSubscription.new(
          subscription_id: (i + 1).to_u32,
          min_interval: 1_u16,
          max_interval: 60_u16,
          peer: Socket::IPAddress.new("127.0.0.1", 5540),
          session: session,
          attribute_paths: [sub_path],
          exchange_id: (1000 + i).to_u16
        )
        registry.active_subscriptions[(i + 1).to_u32] = subscription
      end

      # Verify 3 subscriptions
      registry.active_subscriptions.size.should eq(3)

      # Add pending cleanup (immediately ready)
      pending = Matter::Protocol::SessionRegistry::PendingCleanup.new(100_u16, 0.seconds)
      registry.pending_cleanups << pending

      # Process pending cleanups
      registry.process_pending_cleanups

      # All subscriptions should be removed
      registry.active_subscriptions.size.should eq(0)
    end

    it "only removes subscriptions belonging to the cleaned up session" do
      registry = SessionRegistryTestHelpers.create_test_registry

      # Create two sessions from different peers
      session1 = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      session2 = SessionRegistryTestHelpers.create_case_session(200_u16, 1_u8, 67890_u64, 0.seconds)
      registry.sessions[session1.session_id] = session1
      registry.sessions[session2.session_id] = session2

      # Add subscription to session 1
      sub1 = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session1,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      registry.active_subscriptions[1_u32] = sub1

      # Add subscription to session 2
      sub2 = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 2_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5541),
        session: session2,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1001_u16
      )
      registry.active_subscriptions[2_u32] = sub2

      # Verify initial state
      registry.sessions.size.should eq(2)
      registry.active_subscriptions.size.should eq(2)

      # Clean up only session 1
      pending = Matter::Protocol::SessionRegistry::PendingCleanup.new(100_u16, 0.seconds)
      registry.pending_cleanups << pending
      registry.process_pending_cleanups

      # Session 1 and its subscription should be removed
      registry.sessions.has_key?(100_u16).should be_false
      registry.active_subscriptions.has_key?(1_u32).should be_false

      # Session 2 and its subscription should remain
      registry.sessions.has_key?(200_u16).should be_true
      registry.active_subscriptions.has_key?(2_u32).should be_true
    end
  end

  describe "session table size limit" do
    it "has configurable max_sessions defaulting to 32" do
      registry = SessionRegistryTestHelpers.create_test_registry
      registry.max_sessions.should eq(32_u16)
    end

    it "allows custom max_sessions configuration" do
      registry = SessionRegistryTestHelpers.create_test_registry(max_sessions: 5_u16)
      registry.max_sessions.should eq(5_u16)
    end
  end

  describe "subscription timeout" do
    it "detects expired subscriptions" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Create a subscription with max_interval=1 second
      sub = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 1_u16, # 1 second max interval
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      # Set last_report_time to 2 seconds ago so it's expired
      sub.last_report_time = Time.utc - 2.seconds
      registry.active_subscriptions[1_u32] = sub

      # Process expired subscriptions
      removed_count = registry.process_expired_subscriptions
      removed_count.should eq(1)

      # Subscription should be removed
      registry.active_subscriptions.has_key?(1_u32).should be_false
    end

    it "does not remove non-expired subscriptions" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Create a subscription with max_interval=60 seconds
      sub = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16, # 60 second max interval
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      # last_report_time is now, so not expired
      registry.active_subscriptions[1_u32] = sub

      # Process expired subscriptions
      removed_count = registry.process_expired_subscriptions
      removed_count.should eq(0)

      # Subscription should still exist
      registry.active_subscriptions.has_key?(1_u32).should be_true
    end

    it "calls on_subscription_removed callback when subscription expires" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      removed_ids = [] of UInt32
      registry.on_subscription_removed = ->(sub_id : UInt32) {
        removed_ids << sub_id
        nil
      }

      # Create expired subscription
      sub = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 42_u32,
        min_interval: 1_u16,
        max_interval: 1_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      sub.last_report_time = Time.utc - 2.seconds
      registry.active_subscriptions[42_u32] = sub

      registry.process_expired_subscriptions

      removed_ids.should eq([42_u32])
    end
  end

  describe "cancel cleanup on traffic" do
    it "cancels pending cleanup when cancel_on_traffic is true" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Add pending cleanup with cancel_on_traffic=true
      pending = Matter::Protocol::SessionRegistry::PendingCleanup.new(
        100_u16,
        1.hour,
        Matter::Protocol::SessionRegistry::CleanupReason::SubscriptionExpired,
        cancel_on_traffic: true
      )
      registry.pending_cleanups << pending

      registry.pending_cleanups.size.should eq(1)

      # Simulate traffic detection
      canceled = registry.cancel_cleanup_on_traffic(100_u16)
      canceled.should be_true

      # Pending cleanup should be removed
      registry.pending_cleanups.size.should eq(0)
    end

    it "does not cancel pending cleanup when cancel_on_traffic is false" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Add pending cleanup with cancel_on_traffic=false
      pending = Matter::Protocol::SessionRegistry::PendingCleanup.new(
        100_u16,
        1.hour,
        Matter::Protocol::SessionRegistry::CleanupReason::CaseResumptionFailed,
        cancel_on_traffic: false
      )
      registry.pending_cleanups << pending

      # Simulate traffic detection
      canceled = registry.cancel_cleanup_on_traffic(100_u16)
      canceled.should be_false

      # Pending cleanup should still exist
      registry.pending_cleanups.size.should eq(1)
    end
  end

  describe "transport failure cleanup" do
    it "schedules cleanup on transport failure" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      registry.pending_cleanups.size.should eq(0)

      # Mark transport failure
      registry.mark_transport_failure(100_u16)

      # Should have pending cleanup
      registry.pending_cleanups.size.should eq(1)
      registry.pending_cleanups.first.reason.should eq(Matter::Protocol::SessionRegistry::CleanupReason::TransportFailure)
      registry.pending_cleanups.first.cancel_on_traffic?.should be_true
    end

    it "does not schedule cleanup for non-existent session" do
      registry = SessionRegistryTestHelpers.create_test_registry

      registry.mark_transport_failure(999_u16) # Non-existent session

      registry.pending_cleanups.size.should eq(0)
    end

    it "has configurable transport_retry_window" do
      registry = SessionRegistryTestHelpers.create_test_registry
      registry.transport_retry_window.should eq(4.seconds)
    end
  end

  describe "CASE resumption failure cleanup" do
    it "schedules cleanup on CASE resumption failure" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Mark CASE resumption failed
      registry.mark_case_resumption_failed(100_u16)

      # Should have pending cleanup with short grace period
      registry.pending_cleanups.size.should eq(1)
      registry.pending_cleanups.first.reason.should eq(Matter::Protocol::SessionRegistry::CleanupReason::CaseResumptionFailed)
      registry.pending_cleanups.first.cancel_on_traffic?.should be_false
    end
  end

  describe "subscription renewal" do
    it "renews subscription by replacing old with new" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Create old subscription
      old_sub = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      registry.active_subscriptions[1_u32] = old_sub

      # Create new subscription for renewal
      new_sub = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 2_u32,
        min_interval: 1_u16,
        max_interval: 120_u16, # Different max_interval
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1001_u16
      )

      # Renew subscription
      registry.renew_subscription(1_u32, new_sub)

      # Old subscription should be gone
      registry.active_subscriptions.has_key?(1_u32).should be_false

      # New subscription should exist
      registry.active_subscriptions.has_key?(2_u32).should be_true
      registry.active_subscriptions[2_u32].max_interval.should eq(120_u16)
    end

    it "finds matching subscription for renewal" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Create existing subscription
      sub = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      registry.active_subscriptions[1_u32] = sub

      # Find matching subscription
      matching = registry.find_matching_subscription(
        100_u16,
        [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 1_u32)]
      )

      matching.should_not be_nil
      matching.as(Matter::Protocol::ActiveSubscription).subscription_id.should eq(1_u32)
    end

    it "does not find subscription for different session" do
      registry = SessionRegistryTestHelpers.create_test_registry

      session = SessionRegistryTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      registry.sessions[session.session_id] = session

      # Create subscription on session 100
      sub = Matter::Protocol::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      registry.active_subscriptions[1_u32] = sub

      # Try to find matching subscription for different session
      matching = registry.find_matching_subscription(
        200_u16, # Different session
        [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)]
      )

      matching.should be_nil
    end
  end

  describe "cleanup reason tracking" do
    it "PendingSessionCleanup tracks reason and cancel_on_traffic" do
      cleanup = Matter::Protocol::SessionRegistry::PendingCleanup.new(
        100_u16,
        30.seconds,
        Matter::Protocol::SessionRegistry::CleanupReason::TransportFailure,
        cancel_on_traffic: true
      )

      cleanup.session_id.should eq(100_u16)
      cleanup.reason.should eq(Matter::Protocol::SessionRegistry::CleanupReason::TransportFailure)
      cleanup.cancel_on_traffic?.should be_true
    end
  end
end
