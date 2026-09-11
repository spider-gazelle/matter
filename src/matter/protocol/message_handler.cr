require "../codec/message_codec"
require "../session/pase/pase"
require "../session/case/case"
require "../session/case/definitions"
require "../session/context"
require "../session/secure_message"
require "../transport/udp_transport"
require "../cluster/basic_information"
require "../cluster/general_commissioning"
require "../cluster/operational_credentials"
require "../fabric_table"
require "../node"
require "../interaction_model/paths"
require "../interaction_model/status_code"
require "../interaction_model/tlv_messages"
require "./im_handler"
require "./mrp_cache"
require "./response_sender"
require "./subscription_manager"
require "./persistence"
require "./session_registry"
require "tlv"

module Matter
  module Protocol
    # Protocol message handler that routes incoming messages to appropriate handlers
    #
    # Handles:
    # - Secure Channel protocol (0x0000) - PASE, CASE, etc.
    # - Interaction Model protocol (0x0001) - Read, Write, Invoke, Subscribe
    class MessageHandler
      Log = ::Log.for("matter.protocol.message_handler")

      # Protocol IDs
      PROTOCOL_SECURE_CHANNEL     = 0x0000_u16
      PROTOCOL_INTERACTION_MODEL  = 0x0001_u16
      PROTOCOL_BDX                = 0x0002_u16
      PROTOCOL_USER_DIRECTED_COMM = 0x0003_u16

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

      # Sessions, subscriptions and the lock every protocol fiber shares.
      getter registry : SessionRegistry

      # The subscription handshakes and report fan-out.
      getter subscriptions : SubscriptionManager

      # Encrypts and sends everything the node puts on the wire.
      getter sender : ResponseSender

      # The data model this handler serves: endpoints, their clusters and the
      # flat index the Interaction Model resolves paths against.
      getter node : Node

      getter fabric_table : FabricTable
      getter operational_credentials_cluster : Cluster::OperationalCredentials?
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

      # The session and subscription state, and the callbacks the device hooks
      # into, live in the registry; these delegate so the rest of the library
      # and the specs address one object.
      delegate sessions, active_subscriptions, to: @registry
      delegate next_subscription_id, :next_subscription_id=, to: @registry
      delegate max_sessions, :max_sessions=, to: @registry
      delegate subscription_grace_period, :subscription_grace_period=, to: @registry
      delegate transport_retry_window, :transport_retry_window=, to: @registry
      delegate on_session_established, :on_session_established=, to: @registry
      delegate on_session_removed, :on_session_removed=, to: @registry
      delegate on_subscription_established, :on_subscription_established=, to: @registry
      delegate on_subscription_removed, :on_subscription_removed=, to: @registry
      delegate delete_session, persist_all_sessions, to: @registry
      delegate process_pending_cleanups, process_expired_subscriptions, to: @registry
      delegate cancel_cleanup_on_traffic, mark_transport_failure, mark_case_resumption_failed, to: @registry
      delegate renew_subscription, find_matching_subscription, to: @registry

      def initialize(
        @transport : Transport::UDPTransport,
        @setup_pin : UInt32,
        @discriminator : UInt16,
        @fabric_table : FabricTable,
        @iterations : UInt32 = 1000_u32,
        @salt : Bytes = Random::Secure.random_bytes(32),
        @vendor_id : UInt16 = 0xFFF1_u16,
        @product_id : UInt16 = 0x8001_u16,
        max_sessions : UInt16 = SessionRegistry::DEFAULT_MAX_SESSIONS,
        subscription_grace_period : Time::Span = SessionRegistry::DEFAULT_SUBSCRIPTION_GRACE_PERIOD,
        transport_retry_window : Time::Span = SessionRegistry::DEFAULT_TRANSPORT_RETRY_WINDOW,
        @persistence : Persistence::Base? = nil,
      )
        @mrp_cache = MrpCache.new(@transport)
        @registry = SessionRegistry.new(
          mrp_cache: @mrp_cache,
          persistence: @persistence,
          max_sessions: max_sessions,
          subscription_grace_period: subscription_grace_period,
          transport_retry_window: transport_retry_window
        )
        @pase_responder = nil
        @case_responder = nil
        @case_initiator_session_id = nil
        @case_responder_session_id = nil
        @case_fabric = nil
        @on_get_fabric = nil
        # Note: @case_fabric is now a property with type Fabric?
        @on_commissioned = nil
        @operational_credentials_cluster = nil

        # Initialize clusters
        @node = Node.new
        initialize_clusters

        @sender = ResponseSender.new(@transport, @mrp_cache)
        @subscriptions = SubscriptionManager.new(@registry, @node, @sender)

        # Set ourselves as the message handler
        @transport.on_message = ->(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) do
          handle_message(msg, peer)
        end

        # Restore persisted protocol state (CASE sessions + subscriptions)
        if persistence = @persistence
          begin
            persistence.restore(@registry, @fabric_table)
          rescue ex
            Log.error(exception: ex) { "Failed to restore protocol persistence (persistence=#{persistence.class})" }
          end
        end

        @registry.start
      end

      # Stops the registry background sweep. The transport is closed by its
      # owner; this releases what the handler itself started.
      def close : Nil
        @registry.close
      end

      # The clusters of the node, keyed by `{endpoint, cluster}`.
      #
      # Inserting into this hash registers a cluster without an endpoint; it is
      # the escape hatch the protocol specs use. Devices build endpoints
      # through `node` instead.
      def clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base)
        @node.clusters
      end

      # Initialize device clusters (called during construction)
      #
      # These are placeholders that let a bare handler answer a read before a
      # device has been built on top of it; `Device::Base` replaces the root
      # endpoint wholesale with the real clusters. The endpoint carries no
      # device type, so it is not held to the Root Node conformance a device
      # must satisfy.
      private def initialize_clusters : Nil
        # Endpoint 0 - Root Node endpoint (required)
        endpoint_0 = DataType::EndpointNumber.new(0_u16)
        root = Endpoint.new(endpoint_0)

        # Basic Information cluster (0x0028) - required on endpoint 0
        # Use the device's vendor_id and product_id to ensure consistency
        # with DAC certificates and Certification Declaration
        root.add_cluster(Cluster::BasicInformation.new(
          endpoint_id: endpoint_0,
          vendor_name: "Crystal Matter",
          vendor_id: @vendor_id,
          product_name: "Matter Device",
          product_id: @product_id
        ))

        # General Commissioning cluster (0x0030) - required on endpoint 0
        root.add_cluster(Cluster::GeneralCommissioning.new(endpoint_0))

        # Operational Credentials cluster (0x003E) - required on endpoint 0 for commissioning
        # NOTE: We do NOT call set_attestation_from_manager here because:
        # 1. The device application should set up its own attestation credentials
        # 2. Calling it here AND in the device causes double DAC keypair generation
        # 3. The device example overwrites these clusters anyway
        # The device application must call set_attestation_from_manager or set_attestation_credentials
        operational_creds = Cluster::OperationalCredentials.new(@fabric_table, endpoint_0)

        # Set up session_lookup callback so the cluster can get attestation challenge from sessions
        # This is CRITICAL for attestation signature verification - per Matter spec,
        # attestation signature must be over (attestation_elements || attestation_challenge)
        operational_creds.session_lookup = ->(session_id : UInt64) : Bytes? do
          # Look up session by ID and return its attestation challenge
          session = @registry.sessions[session_id.to_u16]?
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

        root.add_cluster(operational_creds)
        @operational_credentials_cluster = operational_creds

        # The Descriptor cluster (0x001D), required on every endpoint per the
        # Matter spec, is injected and populated by `Node#add_endpoint`.
        @node.add_endpoint(root)

        @pase_passcode_verifier = nil
        @default_setup_pin = @setup_pin
        @default_iterations = @iterations
        @default_salt = @salt.dup

        Log.debug { "MessageHandler initialized with #{clusters.size} default clusters (device may add more)" }
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
        @node.on_attribute_changed = ->(ep : UInt16, cl : UInt32, attr : UInt32) do
          @subscriptions.notify(ep, cl, attr)
        end
        Log.debug { "Set up attribute change notifications for #{clusters.size} cluster(s)" }
      end

      # Reports one changed attribute to every subscription watching it.
      def notify_subscriptions(endpoint_id : UInt16, cluster_id : UInt32, attribute_id : UInt32) : Nil
        @subscriptions.notify(endpoint_id, cluster_id, attribute_id)
      end

      # Reports a batch of changed attributes, one ReportData per subscription.
      def notify_subscriptions_batched(attributes : Array(Tuple(UInt16, UInt32, UInt32))) : Nil
        @subscriptions.notify_batched(attributes)
      end

      # Main message routing entry point
      def handle_message(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        # Serialize all message processing to prevent race conditions
        # iPhone and other controllers may send multiple messages back-to-back,
        # and without synchronization, responses could get interleaved or state corrupted
        @registry.synchronize do
          session_id = msg.packet_header.session_id

          # Decrypt encrypted messages (session_id != 0) BEFORE routing
          if session_id != 0
            Log.trace { "Message is encrypted (session_id=#{session_id}), decrypting" }

            # Get secure session context
            session = @registry.sessions[session_id]?
            unless session
              Log.warn { "Dropping encrypted message: no session found (session_id=#{session_id})" }
              return
            end

            message_counter = msg.packet_header.message_id
            case session.check_peer_message_counter(message_counter)
            when Transport::MessageCounter::CheckResult::Duplicate
              unless @mrp_cache.resend?(session_id, message_counter, peer)
                Log.trace { "Dropping duplicate message with no cached response: session_id=#{session_id}, counter=#{message_counter}" }
              end
              return
            when Transport::MessageCounter::CheckResult::Stale
              Log.trace { "Dropping stale message outside the receive window: session_id=#{session_id}, counter=#{message_counter}" }
              return
            end

            msg = decrypt_message(msg, session)
            @registry.cancel_cleanup_on_traffic(session_id)
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
        session = @registry.sessions[session_id]?
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
        @sender.send_im_response(
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

        # A StatusResponse either acknowledges a ReportData chunk of ours, or
        # is a bare acknowledgement we owe an ACK for.
        success = status_code == InteractionModel::StatusCode::Success.value
        return if @subscriptions.advance(original_msg.payload_header.exchange_id, original_msg, success)

        if original_msg.payload_header.requires_acknowledge?
          Log.trace { "StatusResponse requires ACK, sending standalone ACK" }
          @sender.send_encrypted_ack(original_msg, peer, session)
        end
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
          clusters,
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
        remaining_chunks = chunks[1..].map(&.[0])

        Log.debug { "Sending first chunk (#{first_chunk.size} bytes), #{remaining_chunks.size} remaining, is_last=#{is_last}" }

        # Send first ReportData chunk
        @sender.send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: InteractionModel::MessageType::ReportData.value,
          payload: first_chunk,
          cache_for_mrp: true
        )

        Log.debug { "Sent ReadResponse chunk 1/#{chunks.size}" }

        # If there are more chunks, wait for the controller to acknowledge this one
        unless remaining_chunks.empty?
          exchange_id = original_msg.payload_header.exchange_id
          @subscriptions.await_read(exchange_id, SubscriptionManager::PendingRead.new(
            peer: peer,
            session: session,
            remaining_chunks: remaining_chunks
          ))
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
        subscription_id = @registry.allocate_subscription_id

        Log.info { "Created subscription #{subscription_id}" }

        # Read attributes from clusters (same as ReadRequest, pass fabric_index for fabric-scoped attributes)
        attribute_reports = IMHandler.read_attributes(
          request.attribute_requests,
          clusters,
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
        remaining_chunks = chunks[1..].map(&.[0])

        Log.debug { "Sending first chunk (#{first_chunk.size} bytes), #{remaining_chunks.size} remaining" }

        # Send first ReportData chunk
        @sender.send_im_response(
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
        @subscriptions.await_subscription(exchange_id, SubscriptionManager::PendingSubscription.new(
          subscription_id: subscription_id,
          min_interval: min_interval,
          max_interval: max_interval,
          peer: peer,
          session: session,
          attribute_paths: attribute_paths,
          remaining_chunks: remaining_chunks
        ))

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
            @sender.send_im_response(
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
          clusters,
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
        @sender.send_im_response(
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
            @sender.send_im_response(
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
          clusters,
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
        @sender.send_im_response(
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

        @registry.establish_session(secure_context)

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
      private def handle_standalone_ack(msg : Codec::MessageCodec::Message, _peer : Socket::IPAddress) : Nil
        Log.debug { "Received StandaloneAck" }
        if ack_msg_id = msg.payload_header.acknowledged_message_id
          Log.debug { "  Acknowledging message ID: #{ack_msg_id}" }
        end

        # iOS acknowledges intermediate ReportData chunks with a bare MRP ACK
        # rather than a StatusResponse; both drive the same ladder.
        @subscriptions.advance(msg.payload_header.exchange_id, msg)
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

          @registry.establish_session(secure_context)

          Log.info { "CASE secure session established (session_id=#{session_id}, peer_session_id=#{peer_session_id}, fabric_index=#{fabric.fabric_index})" }

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
