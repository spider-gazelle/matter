require "../codec/message_codec"
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
require "./secure_channel"
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

      # PBKDF parameters advertised during PASE unless a commissioning window
      # supplies its own.
      DEFAULT_PBKDF_ITERATIONS = 1000_u32
      PBKDF_SALT_LENGTH        =       32

      getter transport : Transport::UDPTransport

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
      getter discriminator : UInt16
      getter operational_credentials_cluster : Cluster::OperationalCredentials?
      getter persistence : Persistence::Base?

      property vendor_id : UInt16
      property product_id : UInt16

      # Timed Interaction support (IM TimedRequest message type 0x0A).
      #
      # Keyed by (session_id, exchange_id) to scope to a secure session.
      @timed_request_deadlines : Hash(Tuple(UInt16, UInt16), Time::Instant) = {} of Tuple(UInt16, UInt16) => Time::Instant

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

      # The PASE parameters a commissioning window configures, and the fabric
      # lookup CASE falls back on.
      delegate configure_pase_server, configure_pase_pin, reset_pase_server, to: @secure_channel
      delegate on_get_fabric, :on_get_fabric=, to: @secure_channel

      def initialize(
        @transport : Transport::UDPTransport,
        setup_pin : UInt32,
        @discriminator : UInt16,
        @fabric_table : FabricTable,
        iterations : UInt32 = DEFAULT_PBKDF_ITERATIONS,
        salt : Bytes = Random::Secure.random_bytes(PBKDF_SALT_LENGTH),
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
        @on_commissioned = nil
        @operational_credentials_cluster = nil

        # Initialize clusters
        @node = Node.new
        initialize_clusters

        @sender = ResponseSender.new(@transport, @mrp_cache)
        @subscriptions = SubscriptionManager.new(@registry, @node, @sender)
        @secure_channel = SecureChannel.new(@fabric_table, @registry, @sender, setup_pin, iterations, salt)

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

        Log.debug { "MessageHandler initialized with #{clusters.size} default clusters (device may add more)" }
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
          when ProtocolId::SecureChannel.value
            handle_secure_channel(msg, peer)
          when ProtocolId::InteractionModel.value
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

      # Routes a Secure Channel message: the handshakes belong to the secure
      # channel, a bare acknowledgement to the subscription chunk ladder.
      private def handle_secure_channel(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        if msg.payload_header.message_type == SecureChannelMessageType::StandaloneAck.value
          handle_standalone_ack(msg)
          return
        end

        unless @secure_channel.handle(msg, peer)
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

      private def handle_standalone_ack(msg : Codec::MessageCodec::Message) : Nil
        Log.debug { "Received StandaloneAck" }
        if ack_msg_id = msg.payload_header.acknowledged_message_id
          Log.debug { "  Acknowledging message ID: #{ack_msg_id}" }
        end

        # iOS acknowledges intermediate ReportData chunks with a bare MRP ACK
        # rather than a StatusResponse; both drive the same ladder.
        @subscriptions.advance(msg.payload_header.exchange_id, msg)
      end
    end
  end
end
