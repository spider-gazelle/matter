require "../codec/message_codec"
require "../session/pase/pase"
require "../session/case/case"
require "../session/case/definitions"
require "../session/context"
require "../session/secure_message"
require "../transport/udp_transport"
require "../cluster/basic_information_cluster"
require "../cluster/general_commissioning_cluster"
require "../cluster/operational_credentials_cluster"
require "../fabric_table"
require "../interaction_model/paths"
require "../interaction_model/status_code"
require "../interaction_model/tlv_messages"
require "./im_handler"
require "./persistence"
require "./session_manager"
require "tlv"

module Matter
  module Protocol
    # Protocol message handler that routes incoming messages to appropriate handlers
    #
    # Handles:
    # - Secure Channel protocol (0x0000) - PASE, CASE, etc.
    # - Interaction Model protocol (0x0001) - Read, Write, Invoke, Subscribe
    class MessageHandler
      include SessionManager
      Log = ::Log.for("matter.protocol.message_handler")

      # Protocol IDs
      PROTOCOL_SECURE_CHANNEL     = 0x0000_u16
      PROTOCOL_INTERACTION_MODEL  = 0x0001_u16
      PROTOCOL_BDX                = 0x0002_u16
      PROTOCOL_USER_DIRECTED_COMM = 0x0003_u16

      # Session management defaults
      DEFAULT_MAX_SESSIONS              = 32_u16     # Maximum sessions per device
      DEFAULT_SUBSCRIPTION_GRACE_PERIOD = 30.seconds # Grace period after subscription expiry
      DEFAULT_TRANSPORT_RETRY_WINDOW    = 4.seconds  # Retry window before transport failure cleanup
      DEFAULT_SESSION_CLEANUP_INTERVAL  = 5.seconds  # How often to check for expired sessions

      # Keep a short-lived cache of encrypted responses keyed by the incoming
      # message counter. This allows us to handle MRP retransmissions from
      # controllers (notably iOS) without re-invoking cluster logic.
      MRP_DUPLICATE_RESPONSE_TTL         = 10.seconds
      MRP_DUPLICATE_RESPONSE_MAX_ENTRIES = 512

      MSG_REPORT_DATA = 0x05_u8

      # Secure Channel Message Types
      MSG_STANDALONE_ACK       = 0x10_u8
      MSG_PBKDF_PARAM_REQUEST  = 0x20_u8
      MSG_PBKDF_PARAM_RESPONSE = 0x21_u8
      MSG_PASE_PAKE1           = 0x22_u8
      MSG_PASE_PAKE2           = 0x23_u8
      MSG_PASE_PAKE3           = 0x24_u8
      MSG_CASE_SIGMA1          = 0x30_u8
      MSG_CASE_SIGMA2          = 0x31_u8
      MSG_CASE_SIGMA3          = 0x32_u8
      MSG_STATUS_REPORT        = 0x40_u8

      getter transport : Transport::UDPTransport
      getter pase_responder : Session::Pase::PaseResponder?
      getter sessions : Hash(UInt16, Session::SecureContext)
      getter clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base)
      getter fabric_table : FabricTable
      getter operational_credentials_cluster : Cluster::OperationalCredentialsCluster?
      getter persistence : Persistence::Base?

      # Device credentials for PASE
      property setup_pin : UInt32
      property discriminator : UInt16
      property iterations : UInt32
      property salt : Bytes
      property vendor_id : UInt16
      property product_id : UInt16

      # If set, PASE responder will use a pre-computed passcode verifier (w0||L)
      # instead of deriving it from the setup pin (used for enhanced commissioning windows).
      property pase_passcode_verifier : Bytes?

      @default_setup_pin : UInt32 = 0_u32
      @default_iterations : UInt32 = 0_u32
      @default_salt : Bytes = Bytes.new(0)

      # PASE context: store request/response payloads for context hashing
      property pbkdf_request_payload : Bytes?
      property pbkdf_response_payload : Bytes?

      # PASE session IDs from PBKDF exchange
      property initiator_session_id : UInt16?
      property responder_session_id : UInt16?

      # CASE support
      property case_responder : Session::Case::CaseResponder?
      property case_initiator_session_id : UInt16?
      property case_responder_session_id : UInt16?
      property case_fabric : Fabric?

      # Subscription support
      property next_subscription_id : UInt32 = 1_u32

      private struct CachedMrpResponse
        getter udp_packet : Bytes
        getter created_at : Time::Instant

        def initialize(@udp_packet : Bytes, @created_at : Time::Instant = Time.instant)
        end
      end

      # Pending subscription responses - keyed by exchange_id
      # After sending ReportData, we wait for StatusResponse before sending SubscribeResponse
      # Supports chunked responses - remaining_chunks stores chunks yet to be sent
      class PendingSubscription
        property subscription_id : UInt32
        property min_interval : UInt16
        property max_interval : UInt16
        property peer : Socket::IPAddress
        property session : Session::SecureContext
        property original_msg : Codec::MessageCodec::Message
        property remaining_chunks : Array(Tuple(Bytes, Bool))
        property attribute_paths : Array(InteractionModel::AttributePath)

        def initialize(@subscription_id, @min_interval, @max_interval, @peer, @session, @original_msg, @attribute_paths, @remaining_chunks = [] of Tuple(Bytes, Bool))
        end
      end

      @pending_subscriptions : Hash(UInt16, PendingSubscription) = {} of UInt16 => PendingSubscription

      # Pending read responses - keyed by exchange_id
      # For chunked ReadResponses, we wait for StatusResponse/ACK before sending next chunk
      class PendingReadResponse
        property peer : Socket::IPAddress
        property session : Session::SecureContext
        property original_msg : Codec::MessageCodec::Message
        property remaining_chunks : Array(Tuple(Bytes, Bool))

        def initialize(@peer, @session, @original_msg, @remaining_chunks = [] of Tuple(Bytes, Bool))
        end
      end

      @pending_read_responses : Hash(UInt16, PendingReadResponse) = {} of UInt16 => PendingReadResponse

      # Reason for pending session cleanup
      enum CleanupReason
        Superseded           # New session from same peer superseded this one
        SubscriptionExpired  # All subscriptions on session expired
        TransportFailure     # Transport reported unreachable
        CaseResumptionFailed # CASE resumption failed
      end

      # Session pending cleanup (with grace period for subscription migration)
      # When a new CASE session supersedes an old one, we don't immediately remove the old
      # session if it has active subscriptions - we give subscribers time to migrate.
      class PendingSessionCleanup
        property session_id : UInt16
        property cleanup_at : Time
        property reason : CleanupReason
        property? cancel_on_traffic : Bool

        def initialize(
          @session_id,
          grace_period : Time::Span = 30.seconds,
          @reason : CleanupReason = CleanupReason::Superseded,
          @cancel_on_traffic : Bool = false,
        )
          @cleanup_at = Time.utc + grace_period
        end

        def ready? : Bool
          Time.utc >= @cleanup_at
        end
      end

      @pending_session_cleanups : Array(PendingSessionCleanup) = [] of PendingSessionCleanup

      # Active subscriptions - keyed by subscription_id
      # After SubscribeResponse is sent, subscriptions are moved here for ongoing updates
      class ActiveSubscription
        property subscription_id : UInt32
        property min_interval : UInt16
        property max_interval : UInt16
        property peer : Socket::IPAddress
        property session : Session::SecureContext
        property attribute_paths : Array(InteractionModel::AttributePath)
        property last_report_time : Time
        property exchange_id : UInt16

        def initialize(
          @subscription_id,
          @min_interval,
          @max_interval,
          @peer,
          @session,
          @attribute_paths,
          @exchange_id,
        )
          @last_report_time = Time.utc
        end

        # Check if a path matches any subscribed paths (including wildcards)
        def matches?(endpoint_id : UInt16, cluster_id : UInt32, attribute_id : UInt32) : Bool
          @attribute_paths.any? do |path|
            endpoint_match = path.endpoint.nil? || path.endpoint == endpoint_id
            cluster_match = path.cluster.nil? || path.cluster == cluster_id
            attribute_match = path.attribute.nil? || path.attribute == attribute_id
            endpoint_match && cluster_match && attribute_match
          end
        end

        # One subscribed attribute path in its persisted form.
        struct AttributePathRecord
          include Storage::Record

          getter endpoint : UInt16?
          getter cluster : UInt32?
          getter attribute : UInt32?
          getter list_index : UInt16?

          def initialize(@endpoint : UInt16?, @cluster : UInt32?, @attribute : UInt32?, @list_index : UInt16?)
          end

          def self.from_path(path : InteractionModel::AttributePath) : AttributePathRecord
            new(path.endpoint, path.cluster, path.attribute, path.list_index)
          end

          def to_path : InteractionModel::AttributePath
            InteractionModel::AttributePath.new(endpoint: @endpoint, cluster: @cluster, attribute: @attribute, list_index: @list_index)
          end
        end

        # The persisted form of a subscription (`subscriptions/<subscription_id>`).
        # The session is referenced by id and resolved on restore.
        struct SubscriptionRecord
          include Storage::Record

          getter subscription_id : UInt32
          getter min_interval : UInt16
          getter max_interval : UInt16
          getter peer_address : String
          getter peer_port : UInt16
          getter session_id : UInt16
          getter exchange_id : UInt16
          getter last_report_at : Time
          getter attribute_paths : Array(AttributePathRecord)

          def initialize(
            @subscription_id : UInt32,
            @min_interval : UInt16,
            @max_interval : UInt16,
            @peer_address : String,
            @peer_port : UInt16,
            @session_id : UInt16,
            @exchange_id : UInt16,
            @last_report_at : Time,
            @attribute_paths : Array(AttributePathRecord),
          )
          end
        end

        def to_record : SubscriptionRecord
          SubscriptionRecord.new(
            subscription_id: @subscription_id,
            min_interval: @min_interval,
            max_interval: @max_interval,
            peer_address: @peer.address,
            peer_port: @peer.port.to_u16,
            session_id: @session.session_id,
            exchange_id: @exchange_id,
            last_report_at: @last_report_time,
            attribute_paths: @attribute_paths.map { |path| AttributePathRecord.from_path(path) }
          )
        end

        # Rebuilds a subscription from its record and the resolved *session*.
        def self.from_record(record : SubscriptionRecord, session : Session::SecureContext) : ActiveSubscription
          subscription = new(
            subscription_id: record.subscription_id,
            min_interval: record.min_interval,
            max_interval: record.max_interval,
            peer: Socket::IPAddress.new(record.peer_address, record.peer_port.to_i),
            session: session,
            attribute_paths: record.attribute_paths.map(&.to_path),
            exchange_id: record.exchange_id
          )
          subscription.last_report_time = record.last_report_at
          subscription
        end
      end

      @active_subscriptions : Hash(UInt32, ActiveSubscription) = {} of UInt32 => ActiveSubscription

      # Public getter for active subscriptions (for persistence)
      getter active_subscriptions

      # Persist all active CASE sessions to storage
      # Call this periodically (e.g., every 30s) or before graceful shutdown
      # to ensure message counters and other session state are up to date
      def persist_all_sessions : Nil
        return unless persistence = @persistence

        persisted = 0
        @sessions.each_value do |session|
          next unless session.case_session?
          begin
            persistence.session_updated(self, session)
            persisted += 1
          rescue ex
            Log.error(exception: ex) do
              "Failed to persist session #{session.session_id} " \
              "(fabric_index=#{session.fabric_index.inspect} peer_node_id=#{session.peer_node_id.try(&.id).inspect} " \
              "peer_session_id=#{session.peer_session_id})"
            end
          end
        end
        Log.debug { "Persisted #{persisted} CASE session(s)" } if persisted > 0
      end

      # Cached encrypted responses keyed by (session_id, incoming_message_counter)
      @mrp_response_cache : Hash(Tuple(UInt16, UInt32), CachedMrpResponse) = {} of Tuple(UInt16, UInt32) => CachedMrpResponse

      # Timed Interaction support (IM TimedRequest message type 0x0A).
      #
      # Keyed by (session_id, exchange_id) to scope to a secure session.
      @timed_request_deadlines : Hash(Tuple(UInt16, UInt16), Time::Instant) = {} of Tuple(UInt16, UInt16) => Time::Instant

      # Fabric access callback - set by the device implementation
      # This allows the message handler to access fabric data for CASE
      property on_get_fabric : Proc(Fabric?)?

      # Commissioning callback - called when a fabric is successfully added (AddNOC complete)
      # The device should use this to switch from commissioning to operational mDNS advertisement
      property on_commissioned : Proc(Fabric, Nil)?

      # Session established callback - called when a new secure session is established (CASE or PASE)
      # The device can use this to persist sessions for reconnection after restart
      property on_session_established : Proc(Session::SecureContext, Nil)?

      # Subscription established callback - called when a new subscription becomes active
      # The device can use this to persist subscriptions for reconnection after restart
      property on_subscription_established : Proc(ActiveSubscription, Nil)?

      # Mutex to ensure message processing is serialized
      # iPhone and other controllers may send multiple messages back-to-back,
      # and without synchronization, responses could get interleaved or state corrupted
      @message_mutex : Mutex = Mutex.new

      # Session management configuration
      property max_sessions : UInt16
      property subscription_grace_period : Time::Span
      property transport_retry_window : Time::Span

      # Background cleanup fiber control
      @session_cleanup_fiber_running : Bool = false
      @subscription_cleanup_fiber_running : Bool = false

      # Exchange ID counter for initiating new exchanges (e.g., subscription updates)
      # Start at a random value to avoid conflicts with controller-initiated exchanges
      @next_exchange_id : UInt16 = Random.rand(UInt16).to_u16

      def initialize(
        @transport : Transport::UDPTransport,
        @setup_pin : UInt32,
        @discriminator : UInt16,
        @fabric_table : FabricTable,
        @iterations : UInt32 = 1000_u32,
        @salt : Bytes = Random::Secure.random_bytes(32),
        @vendor_id : UInt16 = 0xFFF1_u16,
        @product_id : UInt16 = 0x8001_u16,
        @max_sessions : UInt16 = DEFAULT_MAX_SESSIONS,
        @subscription_grace_period : Time::Span = DEFAULT_SUBSCRIPTION_GRACE_PERIOD,
        @transport_retry_window : Time::Span = DEFAULT_TRANSPORT_RETRY_WINDOW,
        @persistence : Persistence::Base? = nil,
      )
        @sessions = {} of UInt16 => Session::SecureContext
        @pase_responder = nil
        @case_responder = nil
        @case_initiator_session_id = nil
        @case_responder_session_id = nil
        @case_fabric = nil
        @on_get_fabric = nil
        # Note: @case_fabric is now a property with type Fabric?
        @on_commissioned = nil
        @operational_credentials_cluster = nil
        @mrp_response_cache.clear

        # Initialize clusters
        @clusters = {} of Tuple(UInt16, UInt32) => Cluster::Base
        initialize_clusters

        # Set ourselves as the message handler
        @transport.on_message = ->(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) do
          handle_message(msg, peer)
        end

        # Restore persisted protocol state (CASE sessions + subscriptions)
        if persistence = @persistence
          begin
            persistence.restore(self)
          rescue ex
            Log.error(exception: ex) { "Failed to restore protocol persistence (persistence=#{persistence.class})" }
          end
        end

        # Start background cleanup fibers
        spawn_subscription_cleanup_fiber
      end

      private def prune_mrp_response_cache(now : Time::Instant = Time.instant) : Nil
        @mrp_response_cache.reject! do |_, entry|
          now - entry.created_at > MRP_DUPLICATE_RESPONSE_TTL
        end

        if @mrp_response_cache.size > MRP_DUPLICATE_RESPONSE_MAX_ENTRIES
          @mrp_response_cache = @mrp_response_cache
            .to_a
            .sort_by { |(_, entry)| entry.created_at }
            .last(MRP_DUPLICATE_RESPONSE_MAX_ENTRIES)
            .to_h
        end
      end

      # Answers a duplicate request with the cached MRP response so the peer's
      # retransmission still gets its ACK.
      #
      # Only counters the receive window classifies as `Duplicate` reach here: a
      # retransmit older than `Transport::MessageCounter::WINDOW_SIZE` is `Stale`
      # and dropped rather than resent. Within `MRP_DUPLICATE_RESPONSE_TTL` a
      # peer cannot advance the counter that far, so that path is unreachable
      # in practice.
      private def resend_cached_mrp_response?(session_id : UInt16, incoming_counter : UInt32, peer : Socket::IPAddress) : Bool
        now = Time.instant
        if cached = @mrp_response_cache[{session_id, incoming_counter}]?
          if now - cached.created_at <= MRP_DUPLICATE_RESPONSE_TTL
            Log.warn { "MRP duplicate detected: session_id=#{session_id}, message_counter=#{incoming_counter} - resending cached response" }
            @transport.send_raw(cached.udp_packet, peer)
            return true
          else
            @mrp_response_cache.delete({session_id, incoming_counter})
          end
        end
        false
      end

      private def cache_mrp_response(session_id : UInt16, incoming_counter : UInt32, udp_packet : Bytes) : Nil
        prune_mrp_response_cache
        @mrp_response_cache[{session_id, incoming_counter}] = CachedMrpResponse.new(udp_packet)
      end

      private def clear_mrp_response_cache_for_session(session_id : UInt16) : Nil
        @mrp_response_cache.reject! { |(sid, _), _| sid == session_id }
      end

      # Initialize device clusters (called during construction)
      private def initialize_clusters : Nil
        # Endpoint 0 - Root Node endpoint (required)
        endpoint_0 = DataType::EndpointNumber.new(0_u16)

        # Descriptor cluster (0x001D) - REQUIRED on all endpoints per Matter spec
        descriptor = Cluster::DescriptorCluster.new(endpoint_0)
        @clusters[{0_u16, 0x001D_u32}] = descriptor

        # Basic Information cluster (0x0028) - required on endpoint 0
        # Use the device's vendor_id and product_id to ensure consistency
        # with DAC certificates and Certification Declaration
        basic_info = Cluster::BasicInformationCluster.new(
          endpoint_id: endpoint_0,
          vendor_name: "Crystal Matter",
          vendor_id: @vendor_id,
          product_name: "Matter Device",
          product_id: @product_id
        )
        @clusters[{0_u16, 0x0028_u32}] = basic_info

        # General Commissioning cluster (0x0030) - required on endpoint 0
        general_commissioning = Cluster::GeneralCommissioningCluster.new(endpoint_0)
        @clusters[{0_u16, 0x0030_u32}] = general_commissioning

        # Operational Credentials cluster (0x003E) - required on endpoint 0 for commissioning
        # NOTE: We do NOT call set_attestation_from_manager here because:
        # 1. The device application should set up its own attestation credentials
        # 2. Calling it here AND in the device causes double DAC keypair generation
        # 3. The device example overwrites these clusters anyway
        # The device application must call set_attestation_from_manager or set_attestation_credentials
        operational_creds = Cluster::OperationalCredentialsCluster.new(@fabric_table, endpoint_0)

        # Set up session_lookup callback so the cluster can get attestation challenge from sessions
        # This is CRITICAL for attestation signature verification - per Matter spec,
        # attestation signature must be over (attestation_elements || attestation_challenge)
        operational_creds.session_lookup = ->(session_id : UInt64) : Bytes? do
          # Look up session by ID and return its attestation challenge
          session = @sessions[session_id.to_u16]?
          if session
            Log.trace { "session_lookup: session_id=#{session_id} found, returning attestation_challenge" }
            session.attestation_challenge
          else
            Log.trace { "session_lookup: session_id=#{session_id} not found" }
            nil
          end
        end

        # Set up on_fabric_added callback to forward to on_commissioned
        # This allows the device to switch from commissioning to operational mDNS advertisement
        operational_creds.on_fabric_added = ->(fabric : Fabric) do
          Log.info { "Fabric added: fabric_id=#{fabric.fabric_id}, node_id=#{fabric.node_id}, compressed_fabric_id=#{fabric.compressed_fabric_id.hexstring.upcase}" }
          if callback = @on_commissioned
            callback.call(fabric)
          end
        end

        @clusters[{0_u16, 0x003E_u32}] = operational_creds
        @operational_credentials_cluster = operational_creds

        @pase_passcode_verifier = nil
        @default_setup_pin = @setup_pin
        @default_iterations = @iterations
        @default_salt = @salt.dup

        Log.debug { "MessageHandler initialized with #{@clusters.size} default clusters (device may add more)" }
      end

      # Configure PASE server parameters for an enhanced commissioning window.
      # The passcode verifier is the pre-computed w0||L (97 bytes) used by SPAKE2+.
      def configure_pase_server(passcode_verifier : Bytes, iterations : UInt32, salt : Bytes) : Nil
        @pase_passcode_verifier = passcode_verifier.dup
        @iterations = iterations
        @salt = salt.dup
        reset_pase_exchange_state
      end

      # Configure PASE server parameters for a basic commissioning window.
      def configure_pase_pin(pin : UInt32, iterations : UInt32, salt : Bytes) : Nil
        @pase_passcode_verifier = nil
        @setup_pin = pin
        @iterations = iterations
        @salt = salt.dup
        reset_pase_exchange_state
      end

      # Restore default PASE parameters and clear any enhanced verifier.
      def reset_pase_server : Nil
        @pase_passcode_verifier = nil
        @setup_pin = @default_setup_pin
        @iterations = @default_iterations
        @salt = @default_salt.dup
        reset_pase_exchange_state
      end

      private def reset_pase_exchange_state : Nil
        @pase_responder = nil
        @pbkdf_request_payload = nil
        @pbkdf_response_payload = nil
        @initiator_session_id = nil
        @responder_session_id = nil
      end

      # Wire up attribute change notification callbacks for all clusters
      # This should be called after all clusters have been added to the clusters hash
      # It enables automatic subscription updates when attributes change
      def setup_cluster_notifications
        @clusters.each do |_key, cluster|
          cluster.on_attribute_changed = ->(ep : UInt16, cl : UInt32, attr : UInt32) do
            notify_subscriptions(ep, cl, attr)
          end
        end
        Log.debug { "Set up attribute change notifications for #{@clusters.size} cluster(s)" }
      end

      # Handle attribute change and send updates to matching subscriptions
      # This is called by clusters when their attributes change
      def notify_subscriptions(endpoint_id : UInt16, cluster_id : UInt32, attribute_id : UInt32)
        notify_subscriptions_batched([{endpoint_id, cluster_id, attribute_id}])
      end

      # Batch multiple attribute changes into a single subscription update
      # This is important to avoid overwhelming controllers (especially iOS) with rapid-fire updates.
      # Each tuple is (endpoint_id, cluster_id, attribute_id).
      def notify_subscriptions_batched(attributes : Array(Tuple(UInt16, UInt32, UInt32)))
        Log.debug { "notify_subscriptions_batched: #{attributes.size} attribute(s), active=#{@active_subscriptions.size}" }
        return if @active_subscriptions.empty? || attributes.empty?

        # For each subscription, collect all matching attribute reports and send as one ReportData
        @active_subscriptions.each do |sub_id, subscription|
          attribute_reports = [] of InteractionModel::AttributeReportIB

          attributes.each do |(endpoint_id, cluster_id, attribute_id)|
            matches = subscription.matches?(endpoint_id, cluster_id, attribute_id)
            next unless matches

            # Read the current attribute value
            cluster = @clusters[{endpoint_id, cluster_id}]?
            unless cluster
              Log.warn { "Subscription update skipped: cluster not found (endpoint=#{endpoint_id}, cluster=0x#{cluster_id.to_s(16)})" }
              next
            end

            # Build attribute report for this attribute
            value = cluster.read_attribute(attribute_id, subscription.session.fabric_index)
            case value
            when TLV::Any
              attr_path = InteractionModel::AttributePath.new(
                endpoint: endpoint_id,
                cluster: cluster_id,
                attribute: attribute_id
              )

              attr_data = InteractionModel::AttributeDataIB.new(
                path: attr_path,
                data: value,
                data_version: cluster.data_version
              )

              attribute_reports << InteractionModel::AttributeReportIB.new(attribute_data: attr_data)
            else
              Log.warn { "Subscription update skipped: read_attribute returned #{value.class} (endpoint=#{endpoint_id}, cluster=0x#{cluster_id.to_s(16)}, attr=0x#{attribute_id.to_s(16)})" }
            end
          end

          # Send batched update if we have any reports
          if attribute_reports.size > 0
            Log.debug { "Sending batched subscription update: subscription_id=#{sub_id}, peer=#{subscription.peer}, reports=#{attribute_reports.size}" }

            report_data = IMHandler.encode_report_data(attribute_reports, subscription.subscription_id)
            Log.trace { "Subscription update ReportData TLV (#{report_data.size} bytes): #{report_data.hexstring}" }

            send_subscription_update(subscription, report_data)
            subscription.last_report_time = Time.utc
          end
        end
      end

      # Send a subscription update (ReportData) to a subscriber
      private def send_subscription_update(subscription : ActiveSubscription, payload : Bytes)
        session = subscription.session
        new_exchange_id = @next_exchange_id
        @next_exchange_id = @next_exchange_id &+ 1
        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: new_exchange_id,
          protocol_id: PROTOCOL_INTERACTION_MODEL,
          message_type: MSG_REPORT_DATA,
          initiator_message: true,
          requires_acknowledge: true
        )
        udp_packet, _ = Session::SecureMessage.encode(session, payload_header, payload,
          source_node_id: session.local_node_id)
        @transport.send_raw(udp_packet, subscription.peer)
      end

      # Main message routing entry point
      def handle_message(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        # Serialize all message processing to prevent race conditions
        # iPhone and other controllers may send multiple messages back-to-back,
        # and without synchronization, responses could get interleaved or state corrupted
        @message_mutex.synchronize do
          session_id = msg.packet_header.session_id

          # Decrypt encrypted messages (session_id != 0) BEFORE routing
          if session_id != 0
            Log.trace { "Message is encrypted (session_id=#{session_id}), decrypting" }

            # Get secure session context
            session = @sessions[session_id]?
            unless session
              Log.warn { "Dropping encrypted message: no session found (session_id=#{session_id})" }
              return
            end

            message_counter = msg.packet_header.message_id
            case session.check_peer_message_counter(message_counter)
            when Transport::MessageCounter::CheckResult::Duplicate
              unless resend_cached_mrp_response?(session_id, message_counter, peer)
                Log.trace { "Dropping duplicate message with no cached response: session_id=#{session_id}, counter=#{message_counter}" }
              end
              return
            when Transport::MessageCounter::CheckResult::Stale
              Log.trace { "Dropping stale message outside the receive window: session_id=#{session_id}, counter=#{message_counter}" }
              return
            end

            msg = decrypt_message(msg, session)
            cancel_cleanup_on_traffic(session_id)
          end

          Log.debug { "Received message: protocol=0x#{msg.payload_header.protocol_id.to_s(16)}, type=0x#{msg.payload_header.message_type.to_s(16)}" }

          case msg.payload_header.protocol_id
          when PROTOCOL_SECURE_CHANNEL
            handle_secure_channel(msg, peer)
          when PROTOCOL_INTERACTION_MODEL
            handle_interaction_model(msg, peer)
          else
            Log.warn { "Unsupported protocol: 0x#{msg.payload_header.protocol_id.to_s(16)}" }
          end
        end
      rescue ex
        Log.debug(exception: ex) do
          "Error handling message: peer=#{peer.address}:#{peer.port} session_id=#{msg.packet_header.session_id} " \
          "msg_id=#{msg.packet_header.message_id} protocol=0x#{msg.payload_header.protocol_id.to_s(16)} " \
          "type=0x#{msg.payload_header.message_type.to_s(16)} exchange=#{msg.payload_header.exchange_id} " \
          "payload_bytes=#{msg.payload.size}"
        end
      end

      # Decrypt an encrypted message and re-parse the payload header
      private def decrypt_message(
        msg : Codec::MessageCodec::Message,
        session : Session::SecureContext,
      ) : Codec::MessageCodec::Message
        decrypted = Session::SecureMessage.decode(session,
          Codec::MessageCodec::Packet.new(msg.packet_header, msg.payload, msg.header_bytes))

        # Some controllers (notably iOS) may omit or otherwise vary the peer identity
        # we can extract during CASE establishment; however encrypted packet headers
        # may still carry the source NodeId. Populate it so ACL checks have a stable
        # subject for CASE interactions.
        if session.case_session?
          if session.peer_node_id.nil?
            if source = msg.packet_header.source_node_id
              session.peer_node_id = source
              Log.debug { "Populated CASE peer_node_id from packet header: 0x#{source.id.to_s(16)} (session_id=#{session.session_id})" }
            end
          end

          if session.peer_subject_ids.empty?
            if peer = session.peer_node_id
              session.peer_subject_ids = [peer.id]
            end
          end
        end

        decrypted
      end

      # Handle Secure Channel protocol (PASE, CASE, etc.)
      private def handle_secure_channel(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        case msg.payload_header.message_type
        when MSG_STANDALONE_ACK
          handle_standalone_ack(msg, peer)
        when MSG_PBKDF_PARAM_REQUEST
          handle_pbkdf_param_request(msg, peer)
        when MSG_PASE_PAKE1
          handle_pase_pake1(msg, peer)
        when MSG_PASE_PAKE3
          handle_pase_pake3(msg, peer)
        when MSG_STATUS_REPORT
          handle_status_report(msg, peer)
        when MSG_CASE_SIGMA1
          handle_case_sigma1(msg, peer)
        when MSG_CASE_SIGMA3
          handle_case_sigma3(msg, peer)
        else
          Log.warn { "Unsupported Secure Channel message type: 0x#{msg.payload_header.message_type.to_s(16)}" }
        end
      end

      # Handle Interaction Model protocol (Read, Write, Invoke, etc.)
      private def handle_interaction_model(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.debug { "InteractionModel message: type=0x#{msg.payload_header.message_type.to_s(16)}, exchange=#{msg.payload_header.exchange_id}, requires_ack=#{msg.payload_header.requires_acknowledge?}, initiator=#{msg.payload_header.initiator_message?}" }

        # Get secure session context (needed for sending response)
        session_id = msg.packet_header.session_id
        session = @sessions[session_id]?
        unless session
          Log.warn { "Dropping IM message: no session found (session_id=#{session_id})" }
          return
        end

        # Per Matter spec 4.11.8: Don't send standalone ACK if we respond immediately
        # The ReadResponse with acknowledged_message_id serves as the ACK
        # (Standalone ACKs are only sent if response takes longer than MRP_STANDALONE_ACK_TIMEOUT)

        # Message is already decrypted, payload contains TLV data
        # Parse IM message based on message type
        case msg.payload_header.message_type
        when InteractionModel::MessageType::StatusResponse.value
          handle_status_response(msg.payload, msg, peer, session)
        when InteractionModel::MessageType::ReadRequest.value
          handle_read_request(msg.payload, msg, peer, session)
        when InteractionModel::MessageType::SubscribeRequest.value
          handle_subscribe_request(msg.payload, msg, peer, session)
        when InteractionModel::MessageType::WriteRequest.value
          handle_write_request(msg.payload, msg, peer, session)
        when InteractionModel::MessageType::InvokeRequest.value
          handle_invoke_request(msg.payload, msg, peer, session)
        when InteractionModel::MessageType::TimedRequest.value
          handle_timed_request(msg.payload, msg, peer, session)
        else
          Log.warn { "Unknown IM message type: 0x#{msg.payload_header.message_type.to_s(16)}" }
        end
      rescue ex
        Log.error(exception: ex) do
          "Error handling IM message: peer=#{peer.address}:#{peer.port} session_id=#{msg.packet_header.session_id} " \
          "msg_id=#{msg.packet_header.message_id} exchange=#{msg.payload_header.exchange_id} " \
          "type=0x#{msg.payload_header.message_type.to_s(16)} payload_hex=#{msg.payload.hexstring}"
        end
      end

      private def record_timed_request(session_id : UInt16, exchange_id : UInt16, timeout_ms : UInt16) : Nil
        # Spec-defined max is UInt16 ms, so this is at most ~65s.
        deadline = Time.instant + timeout_ms.milliseconds
        @timed_request_deadlines[{session_id, exchange_id}] = deadline
      end

      private def consume_timed_request?(session_id : UInt16, exchange_id : UInt16) : Bool
        key = {session_id, exchange_id}
        if deadline = @timed_request_deadlines[key]?
          if Time.instant <= deadline
            @timed_request_deadlines.delete(key)
            return true
          end
          @timed_request_deadlines.delete(key)
        end
        false
      end

      private def handle_timed_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        exchange_id = original_msg.payload_header.exchange_id

        timeout_ms = 0_u16
        begin
          timeout_ms = InteractionModel::TimedRequestMessage.from_slice(decrypted).timeout
        rescue ex
          Log.error(exception: ex) do
            "TimedRequest: failed to parse request (session_id=#{session.session_id} exchange=#{exchange_id} bytes=#{decrypted.hexstring})"
          end
          timeout_ms = 0_u16
        end

        # Record deadline for the follow-up Invoke/Write on this exchange. Even if parsing
        # fails, respond SUCCESS so controllers can proceed (some stacks are strict about
        # receiving a StatusResponse here).
        record_timed_request(session.session_id, exchange_id, timeout_ms)
        Log.info { "TimedRequest: timeout_ms=#{timeout_ms} (session_id=#{session.session_id} exchange=#{exchange_id})" }

        status = InteractionModel::StatusResponseMessage.new(status: InteractionModel::StatusCode::Success.value)
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: InteractionModel::MessageType::StatusResponse.value,
          payload: status.to_slice,
          cache_for_mrp: true
        )
      end

      # Handle StatusResponse - acknowledgment from controller
      #
      # This may be a response to:
      # - ReportData (part of subscription flow) - we need to send SubscribeResponse
      # - Other messages - just an acknowledgment
      private def handle_status_response(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.debug { "Handling StatusResponse (exchange=#{original_msg.payload_header.exchange_id})" }

        # Parse StatusResponse TLV
        status_code = InteractionModel::StatusCode::Success.value
        begin
          status_code = InteractionModel::StatusResponseMessage.from_slice(decrypted).status

          if status_code == InteractionModel::StatusCode::Success.value
            Log.debug { "StatusResponse: SUCCESS" }
          else
            Log.warn { "StatusResponse: status=0x#{status_code.to_s(16)}" }
          end
        rescue ex
          Log.error(exception: ex) { "Failed to parse StatusResponse (#{decrypted.size} bytes): #{decrypted.hexstring}" }
        end

        # Check if this StatusResponse is for a pending subscription
        exchange_id = original_msg.payload_header.exchange_id
        if pending = @pending_subscriptions.delete(exchange_id)
          if status_code == InteractionModel::StatusCode::Success.value
            # Success - check if there are more chunks to send
            if !pending.remaining_chunks.empty?
              # Send next chunk
              next_chunk, _ = pending.remaining_chunks.shift
              Log.debug { "StatusResponse for subscription #{pending.subscription_id}: sending next chunk (#{pending.remaining_chunks.size} remaining)" }

              # Send next ReportData chunk
              send_im_response(
                original_msg: original_msg,
                peer: pending.peer,
                session: pending.session,
                message_type: InteractionModel::MessageType::ReportData.value,
                payload: next_chunk
              )

              # Put pending subscription back to wait for next StatusResponse
              @pending_subscriptions[exchange_id] = pending
              Log.debug { "Sent ReportData chunk, waiting for StatusResponse (subscription #{pending.subscription_id})" }
            else
              # All chunks sent - send SubscribeResponse to complete the subscription
              Log.debug { "All ReportData chunks sent for subscription #{pending.subscription_id}; sending SubscribeResponse" }

              # Encode SubscribeResponse as TLV
              subscribe_response_tlv = IMHandler.encode_subscribe_response(pending.subscription_id, pending.max_interval)
              Log.trace { "Encoded SubscribeResponse TLV (#{subscribe_response_tlv.size} bytes): #{subscribe_response_tlv.hexstring}" }

              # Send SubscribeResponse
              send_im_response(
                original_msg: original_msg,
                peer: pending.peer,
                session: pending.session,
                message_type: InteractionModel::MessageType::SubscribeResponse.value,
                payload: subscribe_response_tlv
              )

              # Move subscription to active subscriptions for ongoing updates
              active_sub = ActiveSubscription.new(
                subscription_id: pending.subscription_id,
                min_interval: pending.min_interval,
                max_interval: pending.max_interval,
                peer: pending.peer,
                session: pending.session,
                attribute_paths: pending.attribute_paths,
                exchange_id: exchange_id
              )
              @active_subscriptions[pending.subscription_id] = active_sub

              Log.info { "Subscription #{pending.subscription_id} is now active (watching #{pending.attribute_paths.size} path(s))" }

              # Notify device about new subscription for persistence
              if persistence = @persistence
                begin
                  persistence.subscription_established(self, active_sub)
                rescue ex
                  Log.error(exception: ex) do
                    "Failed persisting subscription #{active_sub.subscription_id} " \
                    "(peer=#{active_sub.peer} exchange=#{active_sub.exchange_id} session_id=#{active_sub.session.session_id} paths=#{active_sub.attribute_paths.size})"
                  end
                end
              end
              if callback = @on_subscription_established
                callback.call(active_sub)
              end
            end
          else
            # Error - subscription failed
            Log.warn { "StatusResponse error for subscription #{pending.subscription_id}, aborting subscription" }
          end
          # Check if this StatusResponse is for a pending read response
        elsif pending_read = @pending_read_responses.delete(exchange_id)
          if status_code == InteractionModel::StatusCode::Success.value
            # Success - check if there are more chunks to send
            if !pending_read.remaining_chunks.empty?
              # Send next chunk
              next_chunk, _ = pending_read.remaining_chunks.shift
              Log.debug { "StatusResponse for read response: sending next chunk (#{pending_read.remaining_chunks.size} remaining)" }

              # Send next ReportData chunk
              send_im_response(
                original_msg: original_msg,
                peer: pending_read.peer,
                session: pending_read.session,
                message_type: InteractionModel::MessageType::ReportData.value,
                payload: next_chunk
              )

              # Put pending read back to wait for next StatusResponse
              if !pending_read.remaining_chunks.empty?
                @pending_read_responses[exchange_id] = pending_read
                Log.debug { "Sent ReportData chunk, waiting for StatusResponse (read response)" }
              else
                Log.debug { "Sent final ReportData chunk for read response" }
              end
            else
              # All chunks already sent - nothing more to do for read responses
              Log.debug { "StatusResponse received for read response, all chunks already sent" }
            end
          else
            # Error - read failed
            Log.warn { "StatusResponse error for read response, aborting" }
          end
        else
          # This StatusResponse is not for a pending subscription or read -
          # it's likely an acknowledgment for a subscription update we sent.
          # We still need to send an ACK back if required.
          if original_msg.payload_header.requires_acknowledge?
            Log.trace { "StatusResponse requires ACK, sending standalone ACK" }
            send_encrypted_ack(original_msg, peer, session)
          end
        end
      end

      # Send a standalone ACK for an encrypted message
      # Used when we receive a message that requires acknowledgment but we don't have another response to send
      private def send_encrypted_ack(
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: original_msg.payload_header.exchange_id,
          protocol_id: PROTOCOL_SECURE_CHANNEL,
          message_type: MSG_STANDALONE_ACK,
          initiator_message: !original_msg.payload_header.initiator_message?,
          requires_acknowledge: false,
          acknowledged_message_id: original_msg.packet_header.message_id
        )
        udp_packet, _ = Session::SecureMessage.encode(session, payload_header, Bytes.empty,
          source_node_id: session.local_node_id, destination_node_id: session.peer_node_id)
        @transport.send_raw(udp_packet, peer)
      end

      # Handle ReadRequest - parse, read attributes, encode response, encrypt and send
      # Uses chunking for large responses to stay within UDP MTU limits
      private def handle_read_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.debug { "Handling ReadRequest" }

        # Parse ReadRequest using IMHandler
        request = IMHandler.parse_read_request(decrypted)
        unless request
          Log.error { "Failed to parse ReadRequest" }
          return
        end

        attribute_requests = request.attribute_requests || [] of InteractionModel::AttributePath
        Log.info { "ReadRequest: #{attribute_requests.size} attribute(s) requested" }

        # Read attributes from clusters (pass fabric_index for fabric-scoped attributes)
        attribute_reports = IMHandler.read_attributes(
          request.attribute_requests,
          @clusters,
          session.fabric_index,
          session.case_session?,
          session.peer_subject_ids.empty? ? nil : session.peer_subject_ids
        )

        Log.debug { "ReadResponse: #{attribute_reports.size} report(s)" }

        # Encode ReadResponse as TLV with chunking (no subscription_id for regular reads)
        chunks = IMHandler.encode_chunked_report_data(attribute_reports, nil)
        Log.debug { "Chunked ReadResponse into #{chunks.size} chunk(s)" }

        # Get first chunk to send
        first_chunk, is_last = chunks.first
        remaining_chunks = chunks.size > 1 ? chunks[1..] : [] of Tuple(Bytes, Bool)

        Log.debug { "Sending first chunk (#{first_chunk.size} bytes), #{remaining_chunks.size} remaining, is_last=#{is_last}" }

        # Send first ReportData chunk
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: InteractionModel::MessageType::ReportData.value,
          payload: first_chunk,
          cache_for_mrp: true
        )

        Log.debug { "Sent ReadResponse chunk 1/#{chunks.size}" }

        # If there are more chunks, store pending read response
        if !remaining_chunks.empty?
          exchange_id = original_msg.payload_header.exchange_id
          @pending_read_responses[exchange_id] = PendingReadResponse.new(
            peer: peer,
            session: session,
            original_msg: original_msg,
            remaining_chunks: remaining_chunks
          )
          Log.debug { "Waiting for StatusResponse/ACK on exchange #{exchange_id} (#{remaining_chunks.size} chunks remaining)" }
        end
      rescue ex
        Log.error(exception: ex) do
          "Error handling ReadRequest: peer=#{peer.address}:#{peer.port} session_id=#{session.session_id} " \
          "exchange=#{original_msg.payload_header.exchange_id} msg_id=#{original_msg.packet_header.message_id} " \
          "payload_hex=#{decrypted.hexstring}"
        end
      end

      # Handle SubscribeRequest - parse, read attributes, send ReportData, wait for StatusResponse, then SubscribeResponse
      #
      # Matter spec subscription flow:
      # 1. Controller sends SubscribeRequest
      # 2. Device sends ReportData (with SubscriptionId)
      # 3. Controller sends StatusResponse (acknowledging receipt)
      # 4. Device sends SubscribeResponse
      private def handle_subscribe_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.debug { "Handling SubscribeRequest" }

        # Parse SubscribeRequest using IMHandler
        request = IMHandler.parse_subscribe_request(decrypted)
        unless request
          Log.error { "Failed to parse SubscribeRequest" }
          return
        end

        attribute_requests = request.attribute_requests || [] of InteractionModel::AttributePath
        Log.info { "SubscribeRequest: #{attribute_requests.size} attribute(s), min=#{request.min_interval_floor}s, max=#{request.max_interval_ceiling}s" }

        # Log what attributes are being subscribed to
        attribute_requests.each_with_index do |path, idx|
          endpoint = path.endpoint.try(&.to_s) || "*"
          cluster = path.cluster.try { |cluster_id| "0x#{cluster_id.to_s(16)}" } || "*"
          attribute = path.attribute.try { |attr_id| "0x#{attr_id.to_s(16)}" } || "*"
          Log.debug { "  Subscribe #{idx}: endpoint=#{endpoint} cluster=#{cluster} attr=#{attribute}" }
        end

        # Generate subscription ID
        subscription_id = @next_subscription_id
        @next_subscription_id += 1

        Log.info { "Created subscription #{subscription_id}" }

        # Read attributes from clusters (same as ReadRequest, pass fabric_index for fabric-scoped attributes)
        attribute_reports = IMHandler.read_attributes(
          request.attribute_requests,
          @clusters,
          session.fabric_index,
          session.case_session?,
          session.peer_subject_ids.empty? ? nil : session.peer_subject_ids
        )

        Log.debug { "Initial ReportData: #{attribute_reports.size} report(s)" }

        # Encode ReportData with subscription ID as TLV, chunked to fit MTU
        chunks = IMHandler.encode_chunked_report_data(attribute_reports, subscription_id)
        Log.debug { "Chunked ReportData into #{chunks.size} chunk(s)" }

        # Get first chunk to send
        first_chunk, _ = chunks.first
        remaining_chunks = chunks.size > 1 ? chunks[1..] : [] of Tuple(Bytes, Bool)

        Log.debug { "Sending first chunk (#{first_chunk.size} bytes), #{remaining_chunks.size} remaining" }

        # Send first ReportData chunk
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: InteractionModel::MessageType::ReportData.value,
          payload: first_chunk,
          cache_for_mrp: true
        )

        Log.debug { "Sent initial ReportData chunk for subscription #{subscription_id}" }

        # Calculate actual intervals (we honor the requested values)
        min_interval = request.min_interval_floor
        max_interval = request.max_interval_ceiling

        # Convert attribute requests to AttributePath for subscription tracking
        attribute_paths = attribute_requests.map do |req|
          InteractionModel::AttributePath.new(
            endpoint: req.endpoint,
            cluster: req.cluster,
            attribute: req.attribute
          )
        end

        # Store pending subscription - we'll send more chunks or SubscribeResponse after receiving StatusResponse
        # The exchange_id is used to correlate the StatusResponse with this subscription
        exchange_id = original_msg.payload_header.exchange_id
        @pending_subscriptions[exchange_id] = PendingSubscription.new(
          subscription_id: subscription_id,
          min_interval: min_interval,
          max_interval: max_interval,
          peer: peer,
          session: session,
          original_msg: original_msg,
          attribute_paths: attribute_paths,
          remaining_chunks: remaining_chunks
        )

        Log.debug { "Waiting for StatusResponse on exchange #{exchange_id} (#{remaining_chunks.size} chunks remaining)" }
      rescue ex
        Log.error(exception: ex) do
          "Error handling SubscribeRequest: peer=#{peer.address}:#{peer.port} session_id=#{session.session_id} " \
          "exchange=#{original_msg.payload_header.exchange_id} msg_id=#{original_msg.packet_header.message_id} " \
          "payload_hex=#{decrypted.hexstring}"
        end
      end

      # Handle WriteRequest - parse, write attributes, encode response, encrypt and send
      private def handle_write_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.debug { "Handling WriteRequest" }

        # Parse WriteRequest using IMHandler
        request = IMHandler.parse_write_request(decrypted)
        unless request
          Log.error { "Failed to parse WriteRequest" }
          return
        end

        if request.timed_request
          unless consume_timed_request?(session.session_id, original_msg.payload_header.exchange_id)
            Log.warn do
              "WriteRequest rejected: missing/expired TimedRequest " \
              "(session_id=#{session.session_id} exchange=#{original_msg.payload_header.exchange_id} peer=#{peer.address}:#{peer.port})"
            end
            status = InteractionModel::StatusResponseMessage.new(status: InteractionModel::StatusCode::Timeout.value)
            send_im_response(
              original_msg: original_msg,
              peer: peer,
              session: session,
              message_type: InteractionModel::MessageType::StatusResponse.value,
              payload: status.to_slice,
              cache_for_mrp: true
            )
            return
          end
        end

        write_requests = request.write_requests || [] of InteractionModel::AttributeDataIB
        Log.info { "WriteRequest: #{write_requests.size} attribute(s) to write" }

        # Write attributes to clusters
        write_responses = IMHandler.write_attributes(
          request.write_requests,
          @clusters,
          session_id: session.session_id,
          is_case_session: session.case_session?,
          fabric_index: session.fabric_index,
          peer_subject_ids: session.peer_subject_ids.empty? ? nil : session.peer_subject_ids
        )

        Log.debug { "WriteResponse: #{write_responses.size} status(es)" }

        # Check if response should be suppressed
        if request.suppress_response && write_responses.all? { |write_status| write_status.status.status == InteractionModel::StatusCode::Success.value }
          Log.info { "Response suppressed per suppressResponse flag (all writes succeeded)" }
          return
        end

        # Encode WriteResponse as TLV
        response_tlv = IMHandler.encode_write_response(write_responses)
        Log.debug { "Encoded WriteResponse TLV (#{response_tlv.size} bytes): #{response_tlv.hexstring}" }

        # Send encrypted IM response
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: InteractionModel::MessageType::WriteResponse.value,
          payload: response_tlv,
          cache_for_mrp: true
        )

        Log.debug { "Sent WriteResponse" }
      rescue ex
        Log.error(exception: ex) do
          "Error handling WriteRequest: peer=#{peer.address}:#{peer.port} session_id=#{session.session_id} " \
          "exchange=#{original_msg.payload_header.exchange_id} msg_id=#{original_msg.packet_header.message_id} " \
          "payload_hex=#{decrypted.hexstring}"
        end
      end

      # Handle InvokeRequest - parse, execute commands, encode response, encrypt and send
      private def handle_invoke_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.debug { "Handling InvokeRequest" }

        # Parse InvokeRequest using IMHandler
        request = IMHandler.parse_invoke_request(decrypted)
        unless request
          Log.error { "Failed to parse InvokeRequest" }
          return
        end

        if request.timed_request
          unless consume_timed_request?(session.session_id, original_msg.payload_header.exchange_id)
            Log.warn do
              "InvokeRequest rejected: missing/expired TimedRequest " \
              "(session_id=#{session.session_id} exchange=#{original_msg.payload_header.exchange_id} peer=#{peer.address}:#{peer.port})"
            end
            status = InteractionModel::StatusResponseMessage.new(status: InteractionModel::StatusCode::Timeout.value)
            send_im_response(
              original_msg: original_msg,
              peer: peer,
              session: session,
              message_type: InteractionModel::MessageType::StatusResponse.value,
              payload: status.to_slice,
              cache_for_mrp: true
            )
            return
          end
        end

        Log.info { "InvokeRequest: #{request.invoke_requests.size} command(s) requested" }

        # Execute commands on clusters (pass session info for attestation)
        invoke_responses = IMHandler.invoke_commands(
          request.invoke_requests,
          @clusters,
          session.session_id.to_u64,
          session.case_session?,
          session.fabric_index,
          session.peer_subject_ids.empty? ? nil : session.peer_subject_ids
        )

        # Count status-only responses (errors)
        status_count = invoke_responses.count { |resp| resp.command_status != nil }
        Log.info { "InvokeResponse: #{invoke_responses.size} response(s), #{status_count} status(es)" }

        # Check if response should be suppressed (only if all succeeded)
        if request.suppress_response && status_count == 0
          Log.info { "Response suppressed per suppressResponse flag" }
          return
        end

        # Encode InvokeResponse as TLV
        response_tlv = IMHandler.encode_invoke_response(invoke_responses, suppress_response: request.suppress_response || false)
        Log.debug { "Encoded InvokeResponse TLV (#{response_tlv.size} bytes): #{response_tlv.hexstring}" }

        # Send encrypted IM response
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: InteractionModel::MessageType::InvokeResponse.value,
          payload: response_tlv,
          cache_for_mrp: true
        )

        Log.info { "Sent InvokeResponse" }
      rescue ex
        Log.error(exception: ex) do
          "Error handling InvokeRequest: peer=#{peer.address}:#{peer.port} session_id=#{session.session_id} " \
          "exchange=#{original_msg.payload_header.exchange_id} msg_id=#{original_msg.packet_header.message_id} " \
          "payload_hex=#{decrypted.hexstring}"
        end
      end

      # Encrypt and send an Interaction Model response
      private def send_im_response(
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
        message_type : UInt8,
        payload : Bytes,
        cache_for_mrp : Bool = false,
      ) : Nil
        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: original_msg.payload_header.exchange_id,
          protocol_id: PROTOCOL_INTERACTION_MODEL,
          message_type: message_type,
          initiator_message: !original_msg.payload_header.initiator_message?,
          requires_acknowledge: true,
          acknowledged_message_id: original_msg.payload_header.requires_acknowledge? ? original_msg.packet_header.message_id : nil
        )
        udp_packet, _ = Session::SecureMessage.encode(session, payload_header, payload,
          source_node_id: original_msg.packet_header.destination_node_id || session.local_node_id,
          destination_node_id: original_msg.packet_header.source_node_id)
        if cache_for_mrp && original_msg.packet_header.session_id != 0
          cache_mrp_response(original_msg.packet_header.session_id, original_msg.packet_header.message_id, udp_packet.dup)
        end
        @transport.send_raw(udp_packet, peer)
      end

      # Handle PBKDF Parameter Request (first step of PASE)
      private def handle_pbkdf_param_request(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling PBKDFParamRequest" }

        # Debug: dump payload bytes
        Log.trace { "PBKDF Request payload (#{msg.payload.size} bytes): #{msg.payload.hexstring}" }

        # Store request payload for context hashing (needed for SPAKE2+ context)
        @pbkdf_request_payload = msg.payload.dup

        # Decode request (TLV::Serializable provides constructor that takes Bytes)
        request = Session::Pase::Definitions::PbkdfParamRequest.from_slice(msg.payload)
        Log.debug { "  Initiator session ID: #{request.initiator_session_id || "none"}" }

        # Store initiator session ID for later use in secure session creation
        @initiator_session_id = request.initiator_session_id

        # Extract initiator_random from request (32 bytes)
        initiator_random = request.initiator_random
        unless initiator_random
          Log.error { "PBKDFParamRequest missing initiator_random" }
          return
        end
        Log.debug { "  Initiator random: #{initiator_random.size} bytes" }

        # Generate responder random (32 bytes)
        responder_random = Random::Secure.random_bytes(32)

        # Generate responder session ID
        responder_session_id = Random::Secure.rand(UInt16)

        # Store responder session ID for later use in secure session creation
        @responder_session_id = responder_session_id

        # Build response
        response = Session::Pase::Definitions::PbkdfParamResponse.new(
          initiator_random: initiator_random,
          responder_random: responder_random,
          responder_session_id: responder_session_id,
          iterations: @iterations,
          salt: @salt
        )

        # Store response payload for context hashing (needed for SPAKE2+ context)
        pbkdf_response_payload = response.to_slice
        @pbkdf_response_payload = pbkdf_response_payload
        Log.debug { "PBKDF Response payload (#{pbkdf_response_payload.size} bytes): #{pbkdf_response_payload.hexstring}" }

        # Send response
        send_secure_channel_response(
          msg: msg,
          peer: peer,
          message_type: MSG_PBKDF_PARAM_RESPONSE,
          payload: pbkdf_response_payload
        )

        Log.info { "Sent PBKDFParamResponse with session ID: #{responder_session_id}" }

        # Compute SPAKE2+ context hash: SHA256(SPAKE_CONTEXT || requestPayload || responsePayload)
        # This matches matter.js implementation in PasePairingTest.ts line 48
        spake_context = "CHIP PAKE V1 Commissioning"
        digest = OpenSSL::Digest.new("SHA256")
        digest.update(spake_context.to_slice)
        digest.update(@pbkdf_request_payload.as(Bytes))
        digest.update(pbkdf_response_payload)
        context_hash = digest.final

        Log.debug { "  SPAKE2+ context hash: #{context_hash.hexstring}" }

        # Create PBKDF parameters and PaseResponder with proper context
        pbkdf_params = Session::Pase::PbkdfParameters.new(@iterations.to_i32, @salt)
        crypto = Crypto::StandardCrypto.new
        if verifier = @pase_passcode_verifier
          Log.debug { "Creating PaseResponder using passcode verifier (bytes=#{verifier.size})" }
          @pase_responder = Session::Pase::PaseResponder.from_passcode_verifier(verifier, pbkdf_params, crypto, context_hash)
        else
          @pase_responder = Session::Pase::PaseResponder.new(@setup_pin, pbkdf_params, crypto, context_hash)
        end

        Log.debug { "Created PaseResponder with hashed context" }
      end

      # Handle PASE Pake1 (second step of PASE)
      private def handle_pase_pake1(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling PASE Pake1" }

        # Decode Pake1 message - TLV library now correctly extracts the EC point
        pake1 = Session::Pase::Definitions::Pake1.from_slice(msg.payload)
        p_a = pake1.x # Now correctly contains just the 65-byte EC point

        Log.debug { "  Received pA: #{p_a.size} bytes" }
        Log.trace { "  pA hex: #{p_a.hexstring}" }
        Log.trace { "  pA first byte: #{Hex.u8(p_a[0])}" } if p_a.size > 0

        # Get or create PASE responder
        responder = @pase_responder
        unless responder
          Log.error { "PASE responder not initialized - PBKDF request must come first" }
          return
        end

        # Process pA and generate pB (device's public key)
        # This also computes the shared secret and confirmation values
        p_b = responder.process_pake1(p_a)
        Log.debug { "  Generated pB: #{p_b.size} bytes" }

        # Generate our confirmation value (cB, h_bx)
        c_b = responder.generate_pake3
        Log.debug { "  Generated cB: #{c_b.size} bytes" }

        # Build Pake2 response
        pake2 = Session::Pase::Definitions::Pake2.new(
          y: p_b,
          verifier: c_b
        )

        # Send Pake2 response
        send_secure_channel_response(
          msg: msg,
          peer: peer,
          message_type: MSG_PASE_PAKE2,
          payload: pake2.to_slice
        )

        Log.info { "Sent PASE Pake2 (pB + cB)" }
      rescue ex
        Log.error(exception: ex) do
          "Error handling PASE Pake1: peer=#{peer.address}:#{peer.port} msg_id=#{msg.packet_header.message_id} " \
          "exchange=#{msg.payload_header.exchange_id} payload_hex=#{msg.payload.hexstring}"
        end
      end

      # Handle PASE Pake3 (third/final step of PASE)
      private def handle_pase_pake3(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling PASE Pake3" }

        c_a = Session::Pase::Definitions::Pake3.from_slice(msg.payload).verifier
        Log.debug { "  Received cA: #{c_a.size} bytes" }
        Log.trace { "  cA hex: #{c_a.hexstring}" }

        # Get PASE responder
        responder = @pase_responder
        unless responder
          Log.error { "PASE responder not initialized" }
          return
        end

        # Verify commissioner's confirmation (cA should match our computed h_ay)
        # The responder has already computed this during process_pake1
        sav = responder.secret_and_verifiers
        unless sav
          Log.error { "Shared secret not computed - Pake1 must be processed first" }
          return
        end

        # Verify cA matches our computed h_ay
        Log.trace { "  Expected h_ay: #{sav.h_ay.hexstring}" }
        if c_a != sav.h_ay
          Log.error { "PASE confirmation failed - cA doesn't match h_ay" }
          Log.error { "  Expected: #{sav.h_ay.hexstring}" }
          Log.error { "  Received: #{c_a.hexstring}" }
          # TODO: Send status report with error
          return
        end

        Log.debug { "PASE confirmation successful" }

        # Derive session keys from the shared secret
        keys = responder.derive_session_keys
        Log.debug { "  Derived encryption key: #{keys[:encryption].size} bytes" }
        Log.trace { "  Encryption key (R2I): #{keys[:encryption].hexstring}" }
        Log.debug { "  Derived decryption key: #{keys[:decryption].size} bytes" }
        Log.trace { "  Decryption key (I2R): #{keys[:decryption].hexstring}" }
        Log.debug { "  Attestation challenge: #{keys[:attestation_challenge].size} bytes" }
        Log.trace { "  Attestation challenge: #{keys[:attestation_challenge].hexstring}" }

        # Create secure session context using stored session IDs from PBKDF exchange
        # We are the responder, so our session_id is responder_session_id
        # The peer (initiator) uses initiator_session_id as their session_id
        session_id = @responder_session_id
        peer_session_id = @initiator_session_id

        unless session_id && peer_session_id
          Log.error { "Missing session IDs - PBKDF exchange must complete first" }
          return
        end

        secure_context = Session::SecureContext.new(
          session_id: session_id,
          peer_session_id: peer_session_id,
          session_type: Session::SessionType::Unicast,
          encryption_key: keys[:encryption],
          decryption_key: keys[:decryption],
          attestation_challenge: keys[:attestation_challenge],
          initiator: false # We're the responder
        )

        # Enforce session table size limit before adding new session
        enforce_session_limit

        # Store session for future encrypted communication
        @sessions[session_id] = secure_context

        Log.info { "PASE secure session established (session_id=#{session_id}, peer_session_id=#{peer_session_id})" }

        # Send StatusReport to confirm session establishment
        # StatusReport is still sent unsecured (session_id=0) as part of the PASE handshake
        # The secure session only becomes active AFTER StatusReport is acknowledged
        send_status_report_success(msg, peer)
      rescue ex
        Log.error(exception: ex) do
          "Error handling PASE Pake3: peer=#{peer.address}:#{peer.port} msg_id=#{msg.packet_header.message_id} " \
          "exchange=#{msg.payload_header.exchange_id} payload_hex=#{msg.payload.hexstring}"
        end
      end

      # Send a Secure Channel protocol response
      private def send_secure_channel_response(
        msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        message_type : UInt8,
        payload : Bytes | Slice(UInt8),
        session_id : UInt16? = nil,
      ) : Nil
        # Build response packet header
        response_session_id = session_id || msg.packet_header.session_id

        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: response_session_id,
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: 0_u32, # Will be set by transport
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          source_node_id: msg.packet_header.destination_node_id,
          destination_node_id: msg.packet_header.source_node_id
        )

        # Build response payload header
        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: msg.payload_header.exchange_id,
          protocol_id: PROTOCOL_SECURE_CHANNEL,
          message_type: message_type,
          initiator_message: !msg.payload_header.initiator_message?,
          requires_acknowledge: false
        )

        # Build and send message
        response = Codec::MessageCodec::Message.new(
          packet_header: packet_header,
          payload_header: payload_header,
          payload: payload.to_slice
        )

        @transport.send_message(response, peer)
      end

      # Send a StatusReport with success status
      # Handle Standalone ACK messages
      # These are sent when a peer wants to acknowledge a message but has no other data to send
      # For chunked ReportData, iPhone may send StandaloneAck instead of StatusResponse between chunks
      private def handle_standalone_ack(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.debug { "Received StandaloneAck" }

        # If the ACK includes an acknowledged message ID, log it
        if ack_msg_id = msg.payload_header.acknowledged_message_id
          Log.debug { "  Acknowledging message ID: #{ack_msg_id}" }
        end

        exchange_id = msg.payload_header.exchange_id

        # Check if this ACK is for a pending subscription with remaining chunks
        # iPhone sends StandaloneAck (instead of StatusResponse) to acknowledge intermediate ReportData chunks
        if pending = @pending_subscriptions[exchange_id]?
          if !pending.remaining_chunks.empty?
            # Send next chunk
            next_chunk, _ = pending.remaining_chunks.shift
            Log.debug { "StandaloneAck for subscription #{pending.subscription_id}: sending next chunk (#{pending.remaining_chunks.size} remaining)" }

            # Send next ReportData chunk
            send_im_response(
              original_msg: pending.original_msg,
              peer: pending.peer,
              session: pending.session,
              message_type: InteractionModel::MessageType::ReportData.value,
              payload: next_chunk
            )

            # If there are more chunks, keep waiting
            if !pending.remaining_chunks.empty?
              Log.debug { "Sent ReportData chunk, waiting for ACK/StatusResponse (subscription #{pending.subscription_id})" }
            else
              # Last chunk sent, wait for StatusResponse to send SubscribeResponse
              Log.debug { "Sent final ReportData chunk, waiting for StatusResponse to complete subscription (subscription #{pending.subscription_id})" }
            end
          elsif pending.remaining_chunks.empty?
            # All chunks were sent, this ACK might be for the final chunk
            # Now we need to send SubscribeResponse
            Log.debug { "StandaloneAck after final chunk: sending SubscribeResponse for subscription #{pending.subscription_id}" }

            # Remove from pending
            @pending_subscriptions.delete(exchange_id)

            # Encode and send SubscribeResponse
            subscribe_response_tlv = IMHandler.encode_subscribe_response(pending.subscription_id, pending.max_interval)
            Log.trace { "Encoded SubscribeResponse TLV (#{subscribe_response_tlv.size} bytes): #{subscribe_response_tlv.hexstring}" }

            send_im_response(
              original_msg: pending.original_msg,
              peer: pending.peer,
              session: pending.session,
              message_type: InteractionModel::MessageType::SubscribeResponse.value,
              payload: subscribe_response_tlv
            )

            # Move subscription to active subscriptions for ongoing updates
            active_sub = ActiveSubscription.new(
              subscription_id: pending.subscription_id,
              min_interval: pending.min_interval,
              max_interval: pending.max_interval,
              peer: pending.peer,
              session: pending.session,
              attribute_paths: pending.attribute_paths,
              exchange_id: exchange_id
            )
            @active_subscriptions[pending.subscription_id] = active_sub

            Log.info { "Subscription #{pending.subscription_id} is now active (watching #{pending.attribute_paths.size} path(s))" }

            # Notify device about new subscription for persistence
            if callback = @on_subscription_established
              callback.call(active_sub)
            end
          end
          # Check if this ACK is for a pending read response with remaining chunks
        elsif pending_read = @pending_read_responses[exchange_id]?
          if !pending_read.remaining_chunks.empty?
            # Send next chunk
            next_chunk, _ = pending_read.remaining_chunks.shift
            Log.debug { "StandaloneAck for read response: sending next chunk (#{pending_read.remaining_chunks.size} remaining)" }

            # Send next ReportData chunk
            send_im_response(
              original_msg: pending_read.original_msg,
              peer: pending_read.peer,
              session: pending_read.session,
              message_type: InteractionModel::MessageType::ReportData.value,
              payload: next_chunk
            )

            # If there are more chunks, keep waiting
            if pending_read.remaining_chunks.empty?
              # Last chunk sent, remove from pending
              @pending_read_responses.delete(exchange_id)
              Log.debug { "Sent final ReportData chunk for read response" }
            else
              Log.debug { "Sent ReportData chunk, waiting for ACK/StatusResponse (read response)" }
            end
          else
            # All chunks were sent, remove from pending
            @pending_read_responses.delete(exchange_id)
            Log.debug { "StandaloneAck received after final chunk for read response" }
          end
        end
      end

      # Handle StatusReport messages (sent by controllers to indicate errors or status)
      private def handle_status_report(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        # Parse StatusReport from binary payload (NOT TLV!)
        status_report = Session::Pase::Definitions::StatusReport.from_bytes(msg.payload)

        general = status_report.general_status
        protocol = status_report.protocol_status

        if general == 0 && protocol == 0
          Log.debug { "StatusReport: SUCCESS (peer=#{peer})" }
          return
        end

        Log.warn { "StatusReport: general=#{Hex.u16(general)}, protocol=#{Hex.u16(protocol)} (peer=#{peer})" }

        # If this is an error, provide context-specific help
        return if general == 0

        if @case_responder
          Log.debug do
            "StatusReport during CASE: protocol=#{Hex.u16(protocol)} " \
            "(e.g. 0x0002 NO_SHARED_TRUST_ROOTS; check ICAC/root trust)"
          end
        else
          Log.debug { "StatusReport during PASE: check PIN, SPAKE2+, and crypto parameter compatibility" }
        end
      rescue ex
        Log.error(exception: ex) { "Failed to parse StatusReport (#{msg.payload.size} bytes): #{msg.payload.hexstring}" }
      end

      private def send_status_report_success(
        msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
      ) : Nil
        # Build StatusReport with success status
        # Only 2 fields: general_status and protocol_status (both 0 for SUCCESS)
        status_report = Session::Pase::Definitions::StatusReport.new(
          general_status: 0_u16,  # SUCCESS
          protocol_status: 0_u16, # SUCCESS
        )

        Log.info { "Sending StatusReport (SUCCESS) to confirm PASE session" }
        Log.info { "  StatusReport sent unsecured (session_id=0) as part of PASE handshake" }

        # Send via secure channel protocol
        # StatusReport uses session_id=0 (unsecured) - secure session becomes active after acknowledgment
        send_secure_channel_response(
          msg: msg,
          peer: peer,
          message_type: MSG_STATUS_REPORT,
          payload: status_report.to_bytes
        )
      end

      # Handle CASE Sigma1 (first step of CASE - operational session establishment)
      private def handle_case_sigma1(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling CASE Sigma1" }

        # Decode Sigma1 message
        begin
          sigma1 = Session::Case::Definitions::Sigma1.from_slice(msg.payload)

          Log.info { "  Initiator session ID: #{sigma1.initiator_session_id}" }
          Log.info { "  Initiator ephemeral public key: #{sigma1.initiator_eph_pub_key.size} bytes" }
          Log.debug { "  Initiator eph pub key hex: #{sigma1.initiator_eph_pub_key.hexstring}" }
          Log.debug { "  Destination ID: #{sigma1.destination_id.hexstring}" }

          # Store initiator session ID
          @case_initiator_session_id = sigma1.initiator_session_id

          # Find the fabric matching the destination_id from Sigma1
          # The destination_id is computed by the initiator as:
          #   HMAC-SHA256(IPK, initiatorRandom || rootPublicKey || fabricId || nodeId)
          # We need to check each fabric to find which one matches
          fabric : Fabric? = nil

          # First try fabric_table (preferred)
          if @fabric_table.size > 0
            Log.debug { "Searching #{@fabric_table.size} fabrics for destination_id match" }
            @fabric_table.all_fabrics.each do |fabric_entry|
              expected_dest_id = fabric_entry.compute_destination_id(sigma1.initiator_random)
              Log.debug { "  Fabric #{fabric_entry.fabric_id.to_s(16)}: expected=#{expected_dest_id.hexstring}" }
              Log.debug { "  Fabric #{fabric_entry.fabric_id.to_s(16)}: received=#{sigma1.destination_id.hexstring}" }
              if expected_dest_id == sigma1.destination_id
                fabric = fabric_entry
                Log.info { "  Matched fabric by destination_id: #{fabric_entry.fabric_id.to_s(16)}" }
                break
              end
            end
          end

          # Fall back to callback if no match in fabric_table
          if fabric.nil?
            fabric_callback = @on_get_fabric
            if fabric_callback
              fabric = fabric_callback.call
              if fabric
                # Log warning - we're using callback without destination_id matching
                expected_dest_id = fabric.compute_destination_id(sigma1.initiator_random)
                if expected_dest_id != sigma1.destination_id
                  Log.warn { "Fabric from callback doesn't match destination_id!" }
                  Log.warn { "  Expected: #{expected_dest_id.hexstring}" }
                  Log.warn { "  Received: #{sigma1.destination_id.hexstring}" }
                end
              end
            end
          end

          unless fabric
            Log.error { "No fabric found matching destination_id: #{sigma1.destination_id.hexstring}" }
            Log.error { "Device may not be commissioned or destination_id computation differs" }
            return
          end

          Log.info { "Using fabric: #{fabric.fabric_id.to_s(16)}" }
          Log.info { "  NOC size: #{fabric.operational_cert.size} bytes" }
          Log.info { "  ICAC present: #{fabric.intermediate_cert != nil}" }
          if icac = fabric.intermediate_cert
            Log.info { "  ICAC size: #{icac.size} bytes" }
          else
            Log.warn { "  NO ICAC in fabric - CASE may fail if controller expects 3-tier PKI" }
          end

          # Create CaseResponder with fabric's operational certificates and IPK
          cert_chain = Session::Case::OperationalCertChain.new(
            noc: fabric.operational_cert,
            icac: fabric.intermediate_cert,
            root: nil # Root certificate not needed for responder
          )

          crypto = Crypto::StandardCrypto.new
          responder = Session::Case::CaseResponder.new(
            cert_chain: cert_chain,
            operational_key: fabric.operational_key,
            fabric_id: fabric.fabric_id,
            node_id: fabric.node_id,
            ipk: fabric.derived_ipk, # Use derived IPK with "GroupKey v1.0" info string
            crypto: crypto
          )

          # Store responder and fabric for Sigma3 processing
          @case_responder = responder
          @case_fabric = fabric

          # Process Sigma1 and generate Sigma2 response
          # Pass the raw Sigma1 bytes for key derivation
          sigma2_data = responder.process_sigma1(
            peer_ephemeral_public_key: sigma1.initiator_eph_pub_key,
            peer_random: sigma1.initiator_random,
            peer_session_id: sigma1.initiator_session_id,
            sigma1_bytes: msg.payload
          )

          # Store responder session ID
          @case_responder_session_id = sigma2_data[:session_id]

          Log.info { "  Generated Sigma2 response" }
          Log.info { "  Responder session ID: #{sigma2_data[:session_id]}" }
          Log.debug { "  Responder ephemeral public key: #{sigma2_data[:ephemeral_public_key].size} bytes" }
          Log.debug { "  Encrypted cert: #{sigma2_data[:encrypted_cert].size} bytes" }

          # Build Sigma2 message
          sigma2 = Session::Case::Definitions::Sigma2.new(
            responder_random: sigma2_data[:random],
            responder_session_id: sigma2_data[:session_id],
            responder_eph_pub_key: sigma2_data[:ephemeral_public_key],
            encrypted2: sigma2_data[:encrypted_cert]
          )

          # Send Sigma2 response
          send_secure_channel_response(
            msg: msg,
            peer: peer,
            message_type: MSG_CASE_SIGMA2,
            payload: sigma2.to_slice
          )

          Log.info { "Sent CASE Sigma2" }
        rescue ex
          Log.error(exception: ex) do
            "Error handling CASE Sigma1: peer=#{peer.address}:#{peer.port} session_id=#{msg.packet_header.session_id} " \
            "msg_id=#{msg.packet_header.message_id} exchange=#{msg.payload_header.exchange_id} payload_hex=#{msg.payload.hexstring}"
          end
        end
      end

      # ========================================================================
      # Session Cleanup - Superseded Session Management
      # ========================================================================
      #
      # When a new CASE session is established from the same peer (same fabric_index
      # and peer_node_id), the old session is considered "superseded". The old session
      # should be cleaned up, but with a grace period if it has active subscriptions
      # to allow subscription migration.
      #
      # Matter spec section 4.13.2.5 states that when a new session is established
      # that supersedes an existing session, the node SHOULD close the old session.

      # Find sessions that are superseded by a new session
      # A session is superseded if:
      # - It has the same fabric_index as the new session
      # - It has the same peer_node_id as the new session
      # - It has a lower session_id than the new session (new > old)
      # - It is a CASE session (not PASE)
      private def find_superseded_sessions(new_session : Session::SecureContext) : Array(Session::SecureContext)
        return [] of Session::SecureContext unless new_session.case_session?
        return [] of Session::SecureContext unless new_session.fabric_index

        new_fabric = new_session.fabric_index.as(UInt8)
        new_peer_node = new_session.peer_node_id

        @sessions.values.select do |session|
          next false unless session.case_session?                        # Only CASE sessions
          next false unless session.fabric_index == new_fabric           # Same fabric
          next false unless session.session_id != new_session.session_id # Not the new session itself
          next false if new_peer_node.nil? || session.peer_node_id.nil?  # Both must have peer_node_id

                        # Check same peer node
          same_peer = session.peer_node_id.as(DataType::NodeId).id == new_peer_node.as(DataType::NodeId).id

          # For supersession, typically the new session ID > old session ID
          # However, session IDs can wrap around, so we compare creation time as tiebreaker
          older_session = session.creation_time < new_session.creation_time

          same_peer && older_session
        end
      end

      # Find the newest session that supersedes the given session
      # This is the inverse of find_superseded_sessions - given an old session,
      # find the newest active session for the same fabric/peer that can take over
      private def find_superseding_session(old_session_id : UInt16) : Session::SecureContext?
        old_session = @sessions[old_session_id]?
        return unless old_session
        return unless old_session.case_session?
        return unless old_session.fabric_index

        old_fabric = old_session.fabric_index.as(UInt8)
        old_peer_node = old_session.peer_node_id
        return if old_peer_node.nil?

        # Find all newer sessions for the same fabric/peer
        candidates = @sessions.values.select do |session|
          next false unless session.case_session?
          next false unless session.fabric_index == old_fabric
          next false unless session.session_id != old_session_id
          next false if session.peer_node_id.nil?

          same_peer = session.peer_node_id.as(DataType::NodeId).id == old_peer_node.as(DataType::NodeId).id
          newer_session = session.creation_time > old_session.creation_time

          same_peer && newer_session
        end

        # Return the newest candidate (most recently created)
        candidates.max_by?(&.creation_time)
      end

      # Check if a session has any active subscriptions
      private def session_has_subscriptions?(session_id : UInt16) : Bool
        @active_subscriptions.values.any? { |sub| sub.session.session_id == session_id }
      end

      # Get all subscriptions for a session
      private def get_session_subscriptions(session_id : UInt16) : Array(ActiveSubscription)
        @active_subscriptions.values.select { |sub| sub.session.session_id == session_id }
      end

      # Clean up superseded sessions after a new CASE session is established
      #
      # Sessions with active subscriptions have their subscriptions MIGRATED to the
      # new session before the old session is removed. This ensures subscription
      # continuity when controllers re-establish CASE sessions.
      private def cleanup_superseded_sessions(new_session : Session::SecureContext) : Nil
        superseded = find_superseded_sessions(new_session)
        return if superseded.empty?

        Log.info { "Found #{superseded.size} superseded session(s) to clean up" }

        superseded.each do |old_session|
          session_id = old_session.session_id

          # Migrate subscriptions to new session before removing old session
          migrate_subscriptions_to_new_session(session_id, new_session)

          # Remove old session (subscriptions already migrated, not deleted)
          remove_session_only(session_id)
        end
      end

      # Migrate subscriptions from an old session to a new session
      # This preserves subscription continuity when controllers re-establish CASE
      private def migrate_subscriptions_to_new_session(old_session_id : UInt16, new_session : Session::SecureContext) : Nil
        subs_to_migrate = @active_subscriptions.select { |_, sub| sub.session.session_id == old_session_id }

        if subs_to_migrate.empty?
          Log.info { "No subscriptions to migrate from session #{old_session_id}" }
          return
        end

        Log.info { "Migrating #{subs_to_migrate.size} subscription(s) from session #{old_session_id} to session #{new_session.session_id}" }

        subs_to_migrate.each do |sub_id, subscription|
          # Update the subscription's session reference to the new session
          subscription.session = new_session

          Log.info { "Migrated subscription #{sub_id} to new session #{new_session.session_id}" }

          # Persist the updated subscription
          if persistence = @persistence
            begin
              persistence.subscription_established(self, subscription)
            rescue ex
              Log.error(exception: ex) do
                "Failed persisting migrated subscription #{sub_id} " \
                "(old_session_id=#{old_session_id} new_session_id=#{new_session.session_id} peer=#{subscription.peer} paths=#{subscription.attribute_paths.size})"
              end
            end
          end
        end
      end

      # Remove a session WITHOUT removing its subscriptions (used after migration)
      private def remove_session_only(session_id : UInt16) : Nil
        clear_mrp_response_cache_for_session(session_id)

        # Remove the session from pending cleanups if present
        @pending_session_cleanups.reject! { |pending| pending.session_id == session_id }

        # Remove the session
        if session = @sessions.delete(session_id)
          if persistence = @persistence
            begin
              persistence.session_removed(self, session_id)
            rescue ex
              Log.error(exception: ex) do
                "Failed removing persisted session #{session_id} " \
                "(fabric_index=#{session.fabric_index.inspect} peer_node_id=#{session.peer_node_id.try(&.id).inspect})"
              end
            end
          end
          Log.info { "Removed superseded session #{session_id} (fabric=#{session.fabric_index}, peer=#{session.peer_node_id.try(&.id)})" }
        end
      end

      # Remove a session and all its associated subscriptions
      private def remove_session_and_subscriptions(session_id : UInt16) : Nil
        clear_mrp_response_cache_for_session(session_id)

        # Remove subscriptions first
        subs_to_remove = @active_subscriptions.select { |_, sub| sub.session.session_id == session_id }
        subs_to_remove.each do |sub_id, _|
          @active_subscriptions.delete(sub_id)
          if persistence = @persistence
            begin
              persistence.subscription_removed(self, sub_id)
            rescue ex
              Log.error(exception: ex) do
                "Failed removing persisted subscription #{sub_id} " \
                "(session_id=#{session_id})"
              end
            end
          end
          Log.info { "Removed subscription #{sub_id} (from superseded session #{session_id})" }
        end

        # Remove the session
        if session = @sessions.delete(session_id)
          if persistence = @persistence
            begin
              persistence.session_removed(self, session_id)
            rescue ex
              Log.error(exception: ex) do
                "Failed removing persisted session #{session_id} " \
                "(fabric_index=#{session.fabric_index.inspect} peer_node_id=#{session.peer_node_id.try(&.id).inspect})"
              end
            end
          end
          Log.info { "Removed superseded session #{session_id} (fabric=#{session.fabric_index}, peer=#{session.peer_node_id.try(&.id)})" }
        end
      end

      # Remove a session (and its subscriptions) from application code.
      #
      # This updates internal state and triggers persistence hooks, then calls
      # `on_session_removed` if configured.
      def delete_session(session_id : UInt16) : Bool
        existed = @sessions.has_key?(session_id)
        remove_session_and_subscriptions(session_id)
        if existed
          if callback = @on_session_removed
            callback.call(session_id)
          end
        end
        existed
      end

      # Remove an active subscription from application code.
      #
      # This updates internal state and triggers persistence hooks, then calls
      # `on_subscription_removed` if configured.
      def delete_subscription(subscription_id : UInt32) : Bool
        removed_subscription = @active_subscriptions.delete(subscription_id)
        removed = !removed_subscription.nil?
        if sub = removed_subscription
          if persistence = @persistence
            begin
              persistence.subscription_removed(self, subscription_id)
            rescue ex
              Log.error(exception: ex) do
                "Failed removing persisted subscription #{subscription_id} " \
                "(session_id=#{sub.session.session_id} peer=#{sub.peer} paths=#{sub.attribute_paths.size})"
              end
            end
          end
          if callback = @on_subscription_removed
            callback.call(subscription_id)
          end
        end
        removed
      end

      # Callback fired when a superseded session is cleaned up
      # Device can use this to remove session from persistent storage
      property on_session_removed : Proc(UInt16, Nil)?

      # Spawn a fiber to process pending session cleanups
      # This runs in the background and checks periodically for sessions
      # whose grace period has expired
      @cleanup_fiber_running : Bool = false

      private def spawn_cleanup_fiber : Nil
        return if @cleanup_fiber_running
        @cleanup_fiber_running = true

        spawn do
          while !@pending_session_cleanups.empty?
            # Find cleanups that are ready
            ready = @pending_session_cleanups.select(&.ready?)

            ready.each do |pending|
              @pending_session_cleanups.delete(pending)
              Log.info { "Grace period expired for session #{pending.session_id} - cleaning up" }
              remove_session_and_subscriptions(pending.session_id)

              # Notify device to update persistent storage
              if callback = @on_session_removed
                callback.call(pending.session_id)
              end
            end

            # Sleep before checking again
            sleep(5.seconds) unless @pending_session_cleanups.empty?
          end

          @cleanup_fiber_running = false
        end
      end

      # Manually trigger cleanup of expired pending sessions (useful for testing)
      def process_pending_cleanups : Int32
        count = 0
        ready = @pending_session_cleanups.select(&.ready?)

        ready.each do |pending|
          @pending_session_cleanups.delete(pending)
          Log.info { "Processing pending cleanup for session #{pending.session_id} (reason: #{pending.reason})" }

          # Check if there's a newer superseding session that can take over subscriptions
          if session_has_subscriptions?(pending.session_id)
            if superseding = find_superseding_session(pending.session_id)
              Log.info { "Found superseding session #{superseding.session_id} for pending cleanup of #{pending.session_id}" }
              migrate_subscriptions_to_new_session(pending.session_id, superseding)
              remove_session_only(pending.session_id)
            else
              # No superseding session - subscriptions must be removed with session
              remove_session_and_subscriptions(pending.session_id)
            end
          else
            # No subscriptions to worry about
            remove_session_and_subscriptions(pending.session_id)
          end

          # Notify device
          if callback = @on_session_removed
            callback.call(pending.session_id)
          end
          count += 1
        end

        count
      end

      # ========================================================================
      # Session Table Size Management
      # ========================================================================

      # Enforce session table size limit by evicting oldest sessions
      # Called before adding a new session to ensure we don't exceed max_sessions
      private def enforce_session_limit : Nil
        return if @sessions.size < @max_sessions

        # Find oldest sessions to evict (PASE sessions first, then oldest CASE)
        sessions_to_evict = @sessions.values.sort_by! do |session|
          # PASE sessions get higher priority for eviction (lower sort value)
          # Then sort by creation time (oldest first)
          pase_priority = session.case_session? ? 1 : 0
          {pase_priority, session.creation_time}
        end

        # Evict oldest sessions until we're under the limit
        while @sessions.size >= @max_sessions && !sessions_to_evict.empty?
          session = sessions_to_evict.shift
          Log.info { "Evicting oldest session #{session.session_id} to stay under limit of #{@max_sessions}" }

          # Check if there's a newer superseding session that can take over subscriptions
          if session_has_subscriptions?(session.session_id)
            if superseding = find_superseding_session(session.session_id)
              Log.info { "Found superseding session #{superseding.session_id} for eviction of #{session.session_id}" }
              migrate_subscriptions_to_new_session(session.session_id, superseding)
              remove_session_only(session.session_id)
            else
              remove_session_and_subscriptions(session.session_id)
            end
          else
            remove_session_and_subscriptions(session.session_id)
          end

          # Notify device
          if callback = @on_session_removed
            callback.call(session.session_id)
          end
        end
      end

      # ========================================================================
      # Subscription Timeout Management
      # ========================================================================

      # Callback fired when a subscription is removed (expired or renewed)
      property on_subscription_removed : Proc(UInt32, Nil)?

      # Check if a subscription has expired
      # Subscription expires when: current_time > last_report_time + max_interval
      private def subscription_expired?(subscription : ActiveSubscription) : Bool
        expiry_time = subscription.last_report_time + subscription.max_interval.seconds
        Time.utc > expiry_time
      end

      # Process expired subscriptions and schedule session cleanup if needed
      def process_expired_subscriptions : Int32
        count = 0
        expired_subs = @active_subscriptions.values.select { |sub| subscription_expired?(sub) }

        expired_subs.each do |sub|
          session_id = sub.session.session_id
          Log.info { "Subscription #{sub.subscription_id} expired (session #{session_id})" }

          # Remove the subscription
          @active_subscriptions.delete(sub.subscription_id)
          count += 1

          # Notify device
          if persistence = @persistence
            begin
              persistence.subscription_removed(self, sub.subscription_id)
            rescue ex
              Log.error(exception: ex) do
                "Failed removing persisted subscription #{sub.subscription_id} " \
                "(session_id=#{session_id} peer=#{sub.peer})"
              end
            end
          end
          if callback = @on_subscription_removed
            callback.call(sub.subscription_id)
          end

          # Check if session should be scheduled for cleanup
          # If no subscriptions remain and no traffic for grace period, cleanup session
          unless session_has_subscriptions?(session_id)
            # Schedule session for cleanup with grace period
            # Use cancel_on_traffic=true so new traffic cancels the cleanup
            already_pending = @pending_session_cleanups.any? { |pending| pending.session_id == session_id }
            unless already_pending
              Log.info { "Session #{session_id} has no more subscriptions - scheduling cleanup with #{@subscription_grace_period} grace period" }
              @pending_session_cleanups << PendingSessionCleanup.new(
                session_id,
                @subscription_grace_period,
                CleanupReason::SubscriptionExpired,
                cancel_on_traffic: true
              )
              spawn_cleanup_fiber
            end
          end
        end

        count
      end

      # Spawn background fiber to periodically check for expired subscriptions
      # Also persists session state every 30 seconds (6 intervals)
      private def spawn_subscription_cleanup_fiber : Nil
        return if @subscription_cleanup_fiber_running
        @subscription_cleanup_fiber_running = true

        spawn do
          persist_counter = 0
          loop do
            sleep(DEFAULT_SESSION_CLEANUP_INTERVAL)
            process_expired_subscriptions
            process_pending_cleanups

            # Persist session state every 6 intervals (30 seconds)
            persist_counter += 1
            if persist_counter >= 6
              persist_all_sessions
              persist_counter = 0
            end
          end
        rescue ex
          Log.error(exception: ex) do
            "Subscription cleanup fiber crashed " \
            "(active_subscriptions=#{@active_subscriptions.size} sessions=#{@sessions.size} pending_cleanups=#{@pending_session_cleanups.size})"
          end
          @subscription_cleanup_fiber_running = false
        end
      end

      # Handle subscription renewal - called when a new SubscribeRequest comes in
      # for the same attribute paths from the same session
      def renew_subscription(old_subscription_id : UInt32, new_subscription : ActiveSubscription) : Nil
        if @active_subscriptions.delete(old_subscription_id)
          Log.info { "Renewed subscription #{old_subscription_id} -> #{new_subscription.subscription_id}" }

          # Notify device about old subscription removal
          if persistence = @persistence
            begin
              persistence.subscription_removed(self, old_subscription_id)
            rescue ex
              Log.error(exception: ex) do
                "Failed removing persisted subscription #{old_subscription_id} " \
                "(renew_to=#{new_subscription.subscription_id} session_id=#{new_subscription.session.session_id} peer=#{new_subscription.peer})"
              end
            end
          end
          if callback = @on_subscription_removed
            callback.call(old_subscription_id)
          end
        end

        # Add new subscription
        @active_subscriptions[new_subscription.subscription_id] = new_subscription
      end

      # Find existing subscription that matches a new subscription request
      # (same session, overlapping paths)
      def find_matching_subscription(session_id : UInt16, paths : Array(InteractionModel::AttributePath)) : ActiveSubscription?
        @active_subscriptions.values.find do |sub|
          next false unless sub.session.session_id == session_id

          # Check if paths overlap significantly (same endpoint/cluster combinations)
          paths.any? do |new_path|
            sub.attribute_paths.any? do |existing_path|
              new_path.endpoint == existing_path.endpoint &&
                new_path.cluster == existing_path.cluster
            end
          end
        end
      end

      # ========================================================================
      # Traffic-Based Cleanup Cancellation
      # ========================================================================

      # Cancel pending cleanup for a session if traffic is detected
      # Called when we receive a message on a session that has cancel_on_traffic=true
      def cancel_cleanup_on_traffic(session_id : UInt16) : Bool
        canceled = false
        @pending_session_cleanups.reject! do |pending|
          if pending.session_id == session_id && pending.cancel_on_traffic?
            Log.info { "Canceling pending cleanup for session #{session_id} - traffic detected" }
            canceled = true
            true # Remove from array
          else
            false
          end
        end
        canceled
      end

      # ========================================================================
      # Transport Failure Cleanup
      # ========================================================================

      # Mark a session as having transport failure and schedule cleanup
      # Called when transport reports the peer is unreachable after retries
      def mark_transport_failure(session_id : UInt16) : Nil
        return unless @sessions.has_key?(session_id)

        # Check if already pending cleanup
        already_pending = @pending_session_cleanups.any? { |pending| pending.session_id == session_id }
        return if already_pending

        Log.warn { "Transport failure for session #{session_id} - scheduling cleanup after #{@transport_retry_window}" }

        @pending_session_cleanups << PendingSessionCleanup.new(
          session_id,
          @transport_retry_window,
          CleanupReason::TransportFailure,
          cancel_on_traffic: true # Cancel if peer becomes reachable again
        )

        spawn_cleanup_fiber
      end

      # ========================================================================
      # CASE Resumption Failure Cleanup
      # ========================================================================

      # Mark a session for cleanup due to CASE resumption failure
      # Called when CASE resumption is attempted but fails
      def mark_case_resumption_failed(session_id : UInt16) : Nil
        return unless @sessions.has_key?(session_id)

        # Check if already pending cleanup
        already_pending = @pending_session_cleanups.any? { |pending| pending.session_id == session_id }
        return if already_pending

        Log.warn { "CASE resumption failed for session #{session_id} - scheduling cleanup" }

        # Short grace period for resumption failure (peer will re-establish if needed)
        @pending_session_cleanups << PendingSessionCleanup.new(
          session_id,
          5.seconds,
          CleanupReason::CaseResumptionFailed,
          cancel_on_traffic: false # Don't cancel - resumption already failed
        )

        spawn_cleanup_fiber
      end

      # Handle CASE Sigma3 (final step of CASE)
      private def handle_case_sigma3(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling CASE Sigma3" }

        begin
          # Decode Sigma3 message
          sigma3 = Session::Case::Definitions::Sigma3.from_slice(msg.payload)

          Log.debug { "  Encrypted cert: #{sigma3.encrypted3.size} bytes" }

          # Get CASE responder
          responder = @case_responder
          unless responder
            Log.error { "CASE responder not initialized - Sigma1 must come first" }
            return
          end

          # Get the raw Sigma3 bytes for key derivation
          sigma3_bytes = msg.payload

          # Process Sigma3 and verify
          # Note: Sigma3 includes encrypted initiator certificate
          # The CaseResponder will decrypt and verify it
          unless responder.process_sigma3(sigma3.encrypted3, sigma3_bytes)
            Log.error { "CASE Sigma3 verification failed" }
            return
          end

          Log.debug { "CASE Sigma3 verified successfully" }

          # Derive session keys from the shared secret
          # Pass sigma3_bytes for session key salt calculation
          keys = responder.derive_session_keys(sigma3_bytes)

          Log.trace { "  Derived encryption key (R2I): #{keys[:encryption].hexstring}" }
          Log.trace { "  Derived decryption key (I2R): #{keys[:decryption].hexstring}" }
          Log.trace { "  Derived attestation challenge: #{keys[:attestation_challenge].hexstring}" }

          # Create secure session context using stored session IDs from Sigma1/Sigma2 exchange
          session_id = @case_responder_session_id
          peer_session_id = @case_initiator_session_id

          unless session_id && peer_session_id
            Log.error { "Missing session IDs - Sigma1/Sigma2 exchange must complete first" }
            return
          end

          # Use the fabric matched during Sigma1 (stored in @case_fabric)
          # This is critical - we must use the exact fabric that was matched by destination_id
          # Using on_get_fabric callback here would return wrong fabric in multi-fabric scenarios
          fabric = @case_fabric
          unless fabric
            Log.error { "No CASE fabric available - Sigma1 must complete first" }
            return
          end
          Log.debug { "Using CASE fabric from Sigma1: fabric_id=0x#{fabric.fabric_id.to_s(16)}, index=#{fabric.fabric_index}" }

          # Get the peer's node ID extracted from their NOC in Sigma3
          # This is critical for proper nonce construction in encrypted messages
          peer_node_id_value = responder.peer_node_id
          if peer_node_id_value
            Log.debug { "Using peer node ID from Sigma3: #{peer_node_id_value}" }
          else
            Log.warn { "No peer node ID extracted from Sigma3; falling back to nil" }
          end

          secure_context = Session::SecureContext.new(
            session_id: session_id,
            peer_session_id: peer_session_id,
            session_type: Session::SessionType::Unicast,
            encryption_key: keys[:encryption],
            decryption_key: keys[:decryption],
            attestation_challenge: keys[:attestation_challenge], # CRITICAL for attestation signatures
            initiator: false,                                    # We're the responder
            local_node_id: DataType::NodeId.new(fabric.node_id),
            peer_node_id: peer_node_id_value ? DataType::NodeId.new(peer_node_id_value) : nil,
            case_session: true,
            fabric_index: fabric.fabric_index
          )

          # Populate the peer Subject IDs (NodeId + CATs) for ACL checks.
          # iOS commonly installs ACL entries using CATs as subjects.
          secure_context.peer_subject_ids = responder.peer_subject_ids.dup
          if secure_context.peer_subject_ids.empty?
            if peer_node = secure_context.peer_node_id
              secure_context.peer_subject_ids = [peer_node.id]
            end
          end
          Log.debug do
            subjects = secure_context.peer_subject_ids.map { |id| "0x#{id.to_s(16)}" }.join(",")
            "CASE peer subjects: [#{subjects}] (session_id=#{secure_context.session_id} fabric_index=#{secure_context.fabric_index})"
          end

          # Enforce session table size limit before adding new session
          enforce_session_limit

          # Store session for future encrypted communication
          @sessions[session_id] = secure_context

          Log.info { "CASE secure session established (session_id=#{session_id}, peer_session_id=#{peer_session_id}, fabric_index=#{fabric.fabric_index})" }

          # Clean up any superseded sessions (same fabric, same peer, older)
          # This is done AFTER storing the new session so the cleanup logic
          # correctly identifies the new session as the replacement
          cleanup_superseded_sessions(secure_context)

          # Notify device of new session (for persistence)
          if persistence = @persistence
            begin
              persistence.session_established(self, secure_context)
            rescue ex
              Log.error(exception: ex) do
                "Failed persisting session #{secure_context.session_id} " \
                "(fabric_index=#{secure_context.fabric_index.inspect} peer_node_id=#{secure_context.peer_node_id.try(&.id).inspect})"
              end
            end
          end
          if callback = @on_session_established
            callback.call(secure_context)
          end

          # Send StatusReport to confirm session establishment
          # Like PASE, this is sent unsecured as part of the CASE handshake
          send_status_report_success(msg, peer)
        rescue ex
          Log.error(exception: ex) do
            "Error handling CASE Sigma3: peer=#{peer.address}:#{peer.port} session_id=#{msg.packet_header.session_id} " \
            "msg_id=#{msg.packet_header.message_id} exchange=#{msg.payload_header.exchange_id} payload_hex=#{msg.payload.hexstring}"
          end
        end
      end
    end
  end
end
