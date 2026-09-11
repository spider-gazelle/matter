require "../spec_helper"
require "../support/session_registry_helpers"

# What makes the registry schedule, cancel or record a session cleanup:
# subscription timeout and renewal, inbound traffic, transport failure and CASE
# resumption failure. Supersession itself lives in
# `session_registry_supersession_spec.cr`.
describe Matter::Protocol::SessionRegistry do
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
