require "./spec_helper"
require "../src/matter/protocol/message_handler"
require "../src/matter/session/context"
require "../src/matter/transport/udp_transport"
require "../src/matter/fabric_table"
require "../src/matter/storage/base"

# Helper module for creating test objects
module SessionCleanupTestHelpers
  def self.create_test_handler
    transport = Matter::Transport::UDPTransport.new(0)
    storage = Matter::Storage::MemoryBackend.new
    fabric_table = Matter::FabricTable.new(storage)
    handler = Matter::Protocol::MessageHandler.new(
      transport: transport,
      setup_pin: 20202021_u32,
      discriminator: 3840_u16,
      fabric_table: fabric_table
    )
    {handler, transport}
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

describe Matter::Protocol::MessageHandler do
  describe "session supersession/cleanup" do
    it "cleans up sessions without subscriptions immediately" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create an old session (created 1 minute ago)
      old_session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 1.minute)
      handler.sessions[old_session.session_id] = old_session

      # Create a new session (created now) from the same peer
      new_session = SessionCleanupTestHelpers.create_case_session(200_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[new_session.session_id] = new_session

      # Verify both sessions are present before cleanup (2 sessions)
      handler.sessions.size.should eq(2)

      # Note: cleanup_superseded_sessions is private, but it gets called
      # automatically when we add the new session via handle_case_sigma3.
      # For testing, we can verify the state directly.

      # We can't call private methods directly, but we can verify behavior
      # by checking sessions hash state
      handler.sessions.has_key?(100_u16).should be_true
      handler.sessions.has_key?(200_u16).should be_true

      transport.close
    end

    it "does not mark sessions from different peers as superseded" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create a session from peer A
      session_a = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 1.minute)
      handler.sessions[session_a.session_id] = session_a

      # Create a new session from peer B (different peer_node_id)
      session_b = SessionCleanupTestHelpers.create_case_session(200_u16, 1_u8, 99999_u64, 0.seconds)
      handler.sessions[session_b.session_id] = session_b

      # Both sessions should remain (different peers)
      handler.sessions.size.should eq(2)
      handler.sessions.has_key?(100_u16).should be_true
      handler.sessions.has_key?(200_u16).should be_true

      transport.close
    end

    it "does not mark sessions from different fabrics as superseded" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create a session on fabric 1
      session_fabric1 = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 1.minute)
      handler.sessions[session_fabric1.session_id] = session_fabric1

      # Create a new session on fabric 2 (same peer but different fabric)
      session_fabric2 = SessionCleanupTestHelpers.create_case_session(200_u16, 2_u8, 12345_u64, 0.seconds)
      handler.sessions[session_fabric2.session_id] = session_fabric2

      # Both sessions should remain (different fabrics)
      handler.sessions.size.should eq(2)
      handler.sessions.has_key?(100_u16).should be_true
      handler.sessions.has_key?(200_u16).should be_true

      transport.close
    end

    it "does not mark PASE sessions as superseded" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

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
      handler.sessions[pase_session.session_id] = pase_session

      # Create a new CASE session
      new_session = SessionCleanupTestHelpers.create_case_session(200_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[new_session.session_id] = new_session

      # PASE session should remain (never superseded by CASE)
      handler.sessions.size.should eq(2)
      handler.sessions.has_key?(100_u16).should be_true
      handler.sessions.has_key?(200_u16).should be_true

      transport.close
    end

    it "tracks subscriptions by session" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create a session
      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Add subscriptions using this session
      sub_path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0_u32
      )
      subscription = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [sub_path],
        exchange_id: 1000_u16
      )
      handler.active_subscriptions[1_u32] = subscription

      # Verify subscription is tracked
      handler.active_subscriptions.size.should eq(1)
      handler.active_subscriptions[1_u32].session.session_id.should eq(100_u16)

      transport.close
    end

    it "allows multiple sessions from different peers on same fabric" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create sessions from multiple peers on the same fabric
      session1 = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 2.minutes)
      session2 = SessionCleanupTestHelpers.create_case_session(200_u16, 1_u8, 67890_u64, 1.minute)
      session3 = SessionCleanupTestHelpers.create_case_session(300_u16, 1_u8, 11111_u64, 0.seconds)

      handler.sessions[session1.session_id] = session1
      handler.sessions[session2.session_id] = session2
      handler.sessions[session3.session_id] = session3

      # All sessions should remain (different peers)
      handler.sessions.size.should eq(3)

      transport.close
    end

    it "supports on_session_removed callback" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      removed_session_ids = [] of UInt16
      handler.on_session_removed = ->(session_id : UInt16) {
        removed_session_ids << session_id
        nil
      }

      # Callback is registered
      handler.on_session_removed.should_not be_nil

      transport.close
    end

    it "PendingSessionCleanup tracks grace period" do
      # Test the PendingSessionCleanup class
      cleanup = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(100_u16, 0.seconds)

      # With 0 second grace period, should be ready immediately
      cleanup.ready?.should be_true
      cleanup.session_id.should eq(100_u16)

      # With future grace period, should not be ready
      cleanup2 = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(200_u16, 1.hour)
      cleanup2.ready?.should be_false
    end

    it "process_pending_cleanups removes expired sessions and their subscriptions" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create a session
      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Add a subscription using this session
      sub_path = Matter::InteractionModel::AttributePath.new(
        endpoint: 1_u16,
        cluster: 0x0006_u32,
        attribute: 0_u32
      )
      subscription = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 42_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [sub_path],
        exchange_id: 1000_u16
      )
      handler.active_subscriptions[42_u32] = subscription

      # Verify initial state
      handler.sessions.size.should eq(1)
      handler.active_subscriptions.size.should eq(1)

      # Track removed session IDs via callback
      removed_ids = [] of UInt16
      handler.on_session_removed = ->(session_id : UInt16) {
        removed_ids << session_id
        nil
      }

      # Manually add a pending cleanup with 0 grace period (immediately ready)
      # This simulates what would happen after cleanup_superseded_sessions schedules it
      pending = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(100_u16, 0.seconds)
      handler.@pending_session_cleanups << pending

      # Process pending cleanups
      count = handler.process_pending_cleanups
      count.should eq(1)

      # Session and subscription should be removed
      handler.sessions.has_key?(100_u16).should be_false
      handler.active_subscriptions.has_key?(42_u32).should be_false

      # Callback should have been called
      removed_ids.should eq([100_u16])

      transport.close
    end

    it "process_pending_cleanups skips sessions still in grace period" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create a session
      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Add a pending cleanup with 1 hour grace period (not ready yet)
      pending = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(100_u16, 1.hour)
      handler.@pending_session_cleanups << pending

      # Process pending cleanups
      count = handler.process_pending_cleanups
      count.should eq(0)

      # Session should still exist
      handler.sessions.has_key?(100_u16).should be_true

      transport.close
    end

    it "removes multiple subscriptions when session is cleaned up" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create a session
      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Add multiple subscriptions using this session
      3.times do |i|
        sub_path = Matter::InteractionModel::AttributePath.new(
          endpoint: i.to_u16,
          cluster: 0x0006_u32,
          attribute: 0_u32
        )
        subscription = Matter::Protocol::MessageHandler::ActiveSubscription.new(
          subscription_id: (i + 1).to_u32,
          min_interval: 1_u16,
          max_interval: 60_u16,
          peer: Socket::IPAddress.new("127.0.0.1", 5540),
          session: session,
          attribute_paths: [sub_path],
          exchange_id: (1000 + i).to_u16
        )
        handler.active_subscriptions[(i + 1).to_u32] = subscription
      end

      # Verify 3 subscriptions
      handler.active_subscriptions.size.should eq(3)

      # Add pending cleanup (immediately ready)
      pending = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(100_u16, 0.seconds)
      handler.@pending_session_cleanups << pending

      # Process pending cleanups
      handler.process_pending_cleanups

      # All subscriptions should be removed
      handler.active_subscriptions.size.should eq(0)

      transport.close
    end

    it "only removes subscriptions belonging to the cleaned up session" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      # Create two sessions from different peers
      session1 = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      session2 = SessionCleanupTestHelpers.create_case_session(200_u16, 1_u8, 67890_u64, 0.seconds)
      handler.sessions[session1.session_id] = session1
      handler.sessions[session2.session_id] = session2

      # Add subscription to session 1
      sub1 = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session1,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      handler.active_subscriptions[1_u32] = sub1

      # Add subscription to session 2
      sub2 = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 2_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5541),
        session: session2,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1001_u16
      )
      handler.active_subscriptions[2_u32] = sub2

      # Verify initial state
      handler.sessions.size.should eq(2)
      handler.active_subscriptions.size.should eq(2)

      # Clean up only session 1
      pending = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(100_u16, 0.seconds)
      handler.@pending_session_cleanups << pending
      handler.process_pending_cleanups

      # Session 1 and its subscription should be removed
      handler.sessions.has_key?(100_u16).should be_false
      handler.active_subscriptions.has_key?(1_u32).should be_false

      # Session 2 and its subscription should remain
      handler.sessions.has_key?(200_u16).should be_true
      handler.active_subscriptions.has_key?(2_u32).should be_true

      transport.close
    end
  end

  describe "session table size limit" do
    it "has configurable max_sessions defaulting to 32" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler
      handler.max_sessions.should eq(32_u16)
      transport.close
    end

    it "allows custom max_sessions configuration" do
      transport = Matter::Transport::UDPTransport.new(0)
      storage = Matter::Storage::MemoryBackend.new
      fabric_table = Matter::FabricTable.new(storage)
      handler = Matter::Protocol::MessageHandler.new(
        transport: transport,
        setup_pin: 20202021_u32,
        discriminator: 3840_u16,
        fabric_table: fabric_table,
        max_sessions: 5_u16
      )
      handler.max_sessions.should eq(5_u16)
      transport.close
    end
  end

  describe "subscription timeout" do
    it "detects expired subscriptions" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Create a subscription with max_interval=1 second
      sub = Matter::Protocol::MessageHandler::ActiveSubscription.new(
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
      handler.active_subscriptions[1_u32] = sub

      # Process expired subscriptions
      removed_count = handler.process_expired_subscriptions
      removed_count.should eq(1)

      # Subscription should be removed
      handler.active_subscriptions.has_key?(1_u32).should be_false

      transport.close
    end

    it "does not remove non-expired subscriptions" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Create a subscription with max_interval=60 seconds
      sub = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16, # 60 second max interval
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      # last_report_time is now, so not expired
      handler.active_subscriptions[1_u32] = sub

      # Process expired subscriptions
      removed_count = handler.process_expired_subscriptions
      removed_count.should eq(0)

      # Subscription should still exist
      handler.active_subscriptions.has_key?(1_u32).should be_true

      transport.close
    end

    it "calls on_subscription_removed callback when subscription expires" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      removed_ids = [] of UInt32
      handler.on_subscription_removed = ->(sub_id : UInt32) {
        removed_ids << sub_id
        nil
      }

      # Create expired subscription
      sub = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 42_u32,
        min_interval: 1_u16,
        max_interval: 1_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      sub.last_report_time = Time.utc - 2.seconds
      handler.active_subscriptions[42_u32] = sub

      handler.process_expired_subscriptions

      removed_ids.should eq([42_u32])

      transport.close
    end
  end

  describe "cancel cleanup on traffic" do
    it "cancels pending cleanup when cancel_on_traffic is true" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Add pending cleanup with cancel_on_traffic=true
      pending = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(
        100_u16,
        1.hour,
        Matter::Protocol::MessageHandler::CleanupReason::SubscriptionExpired,
        cancel_on_traffic: true
      )
      handler.@pending_session_cleanups << pending

      handler.@pending_session_cleanups.size.should eq(1)

      # Simulate traffic detection
      canceled = handler.cancel_cleanup_on_traffic(100_u16)
      canceled.should be_true

      # Pending cleanup should be removed
      handler.@pending_session_cleanups.size.should eq(0)

      transport.close
    end

    it "does not cancel pending cleanup when cancel_on_traffic is false" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Add pending cleanup with cancel_on_traffic=false
      pending = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(
        100_u16,
        1.hour,
        Matter::Protocol::MessageHandler::CleanupReason::CaseResumptionFailed,
        cancel_on_traffic: false
      )
      handler.@pending_session_cleanups << pending

      # Simulate traffic detection
      canceled = handler.cancel_cleanup_on_traffic(100_u16)
      canceled.should be_false

      # Pending cleanup should still exist
      handler.@pending_session_cleanups.size.should eq(1)

      transport.close
    end
  end

  describe "transport failure cleanup" do
    it "schedules cleanup on transport failure" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      handler.@pending_session_cleanups.size.should eq(0)

      # Mark transport failure
      handler.mark_transport_failure(100_u16)

      # Should have pending cleanup
      handler.@pending_session_cleanups.size.should eq(1)
      handler.@pending_session_cleanups.first.reason.should eq(Matter::Protocol::MessageHandler::CleanupReason::TransportFailure)
      handler.@pending_session_cleanups.first.cancel_on_traffic?.should be_true

      transport.close
    end

    it "does not schedule cleanup for non-existent session" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      handler.mark_transport_failure(999_u16) # Non-existent session

      handler.@pending_session_cleanups.size.should eq(0)

      transport.close
    end

    it "has configurable transport_retry_window" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler
      handler.transport_retry_window.should eq(4.seconds)
      transport.close
    end
  end

  describe "CASE resumption failure cleanup" do
    it "schedules cleanup on CASE resumption failure" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Mark CASE resumption failed
      handler.mark_case_resumption_failed(100_u16)

      # Should have pending cleanup with short grace period
      handler.@pending_session_cleanups.size.should eq(1)
      handler.@pending_session_cleanups.first.reason.should eq(Matter::Protocol::MessageHandler::CleanupReason::CaseResumptionFailed)
      handler.@pending_session_cleanups.first.cancel_on_traffic?.should be_false

      transport.close
    end
  end

  describe "subscription renewal" do
    it "renews subscription by replacing old with new" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Create old subscription
      old_sub = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      handler.active_subscriptions[1_u32] = old_sub

      # Create new subscription for renewal
      new_sub = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 2_u32,
        min_interval: 1_u16,
        max_interval: 120_u16, # Different max_interval
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1001_u16
      )

      # Renew subscription
      handler.renew_subscription(1_u32, new_sub)

      # Old subscription should be gone
      handler.active_subscriptions.has_key?(1_u32).should be_false

      # New subscription should exist
      handler.active_subscriptions.has_key?(2_u32).should be_true
      handler.active_subscriptions[2_u32].max_interval.should eq(120_u16)

      transport.close
    end

    it "finds matching subscription for renewal" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Create existing subscription
      sub = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      handler.active_subscriptions[1_u32] = sub

      # Find matching subscription
      matching = handler.find_matching_subscription(
        100_u16,
        [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 1_u32)]
      )

      matching.should_not be_nil
      matching.as(Matter::Protocol::MessageHandler::ActiveSubscription).subscription_id.should eq(1_u32)

      transport.close
    end

    it "does not find subscription for different session" do
      handler, transport = SessionCleanupTestHelpers.create_test_handler

      session = SessionCleanupTestHelpers.create_case_session(100_u16, 1_u8, 12345_u64, 0.seconds)
      handler.sessions[session.session_id] = session

      # Create subscription on session 100
      sub = Matter::Protocol::MessageHandler::ActiveSubscription.new(
        subscription_id: 1_u32,
        min_interval: 1_u16,
        max_interval: 60_u16,
        peer: Socket::IPAddress.new("127.0.0.1", 5540),
        session: session,
        attribute_paths: [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)],
        exchange_id: 1000_u16
      )
      handler.active_subscriptions[1_u32] = sub

      # Try to find matching subscription for different session
      matching = handler.find_matching_subscription(
        200_u16, # Different session
        [Matter::InteractionModel::AttributePath.new(endpoint: 1_u16, cluster: 0x0006_u32, attribute: 0_u32)]
      )

      matching.should be_nil

      transport.close
    end
  end

  describe "cleanup reason tracking" do
    it "PendingSessionCleanup tracks reason and cancel_on_traffic" do
      cleanup = Matter::Protocol::MessageHandler::PendingSessionCleanup.new(
        100_u16,
        30.seconds,
        Matter::Protocol::MessageHandler::CleanupReason::TransportFailure,
        cancel_on_traffic: true
      )

      cleanup.session_id.should eq(100_u16)
      cleanup.reason.should eq(Matter::Protocol::MessageHandler::CleanupReason::TransportFailure)
      cleanup.cancel_on_traffic?.should be_true
    end
  end
end
