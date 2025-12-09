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
require "../interaction_model/messages"
require "../interaction_model/paths"
require "../interaction_model/status_code"
require "./im_handler"
require "tlv"

module Matter
  module Protocol
    # Protocol message handler that routes incoming messages to appropriate handlers
    #
    # Handles:
    # - Secure Channel protocol (0x0000) - PASE, CASE, etc.
    # - Interaction Model protocol (0x0001) - Read, Write, Invoke, Subscribe
    class MessageHandler
      Log = ::Log.for("matter.protocol")

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
      getter sessions : Hash(UInt16, Session::SecureContext)
      getter clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base)
      getter fabric_table : FabricTable
      getter operational_credentials_cluster : Cluster::OperationalCredentialsCluster?

      # Device credentials for PASE
      property setup_pin : UInt32
      property discriminator : UInt16
      property iterations : UInt32
      property salt : Bytes
      property vendor_id : UInt16
      property product_id : UInt16

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

      # Subscription support
      property next_subscription_id : UInt32 = 1_u32

      # Pending subscription responses - keyed by exchange_id
      # After sending ReportData, we wait for StatusResponse before sending SubscribeResponse
      # Supports chunked responses - remaining_chunks stores chunks yet to be sent
      class PendingSubscription
        property subscription_id : UInt32
        property max_interval : UInt16
        property peer : Socket::IPAddress
        property session : Session::SecureContext
        property original_msg : Codec::MessageCodec::Message
        property remaining_chunks : Array(Tuple(Bytes, Bool))

        def initialize(@subscription_id, @max_interval, @peer, @session, @original_msg, @remaining_chunks = [] of Tuple(Bytes, Bool))
        end
      end

      @pending_subscriptions : Hash(UInt16, PendingSubscription) = {} of UInt16 => PendingSubscription

      # Fabric access callback - set by the device implementation
      # This allows the message handler to access fabric data for CASE
      property on_get_fabric : Proc(Fabric?)?

      # Commissioning callback - called when a fabric is successfully added (AddNOC complete)
      # The device should use this to switch from commissioning to operational mDNS advertisement
      property on_commissioned : Proc(Fabric, Nil)?

      # Mutex to ensure message processing is serialized
      # iPhone and other controllers may send multiple messages back-to-back,
      # and without synchronization, responses could get interleaved or state corrupted
      @message_mutex : Mutex = Mutex.new

      def initialize(
        @transport : Transport::UDPTransport,
        @setup_pin : UInt32,
        @discriminator : UInt16,
        @fabric_table : FabricTable,
        @iterations : UInt32 = 1000_u32,
        @salt : Bytes = Random::Secure.random_bytes(32),
        @vendor_id : UInt16 = 0xFFF1_u16,
        @product_id : UInt16 = 0x8001_u16,
      )
        @sessions = {} of UInt16 => Session::SecureContext
        @pase_responder = nil
        @case_responder = nil
        @case_initiator_session_id = nil
        @case_responder_session_id = nil
        @on_get_fabric = nil
        @on_commissioned = nil
        @operational_credentials_cluster = nil

        # Initialize clusters
        @clusters = {} of Tuple(UInt16, UInt32) => Cluster::Base
        initialize_clusters

        # Set ourselves as the message handler
        @transport.on_message = ->(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) do
          handle_message(msg, peer)
        end
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
        operational_creds = Cluster::OperationalCredentialsCluster.new(@fabric_table, endpoint_0)
        # Set up attestation credentials from certificate manager (generates DAC/PAI)
        operational_creds.set_attestation_from_manager(@vendor_id, @product_id)

        # Set up session_lookup callback so the cluster can get attestation challenge from sessions
        # This is CRITICAL for attestation signature verification - per Matter spec,
        # attestation signature must be over (attestation_elements || attestation_challenge)
        operational_creds.session_lookup = ->(session_id : UInt64) : Bytes? do
          # Look up session by ID and return its attestation challenge
          session = @sessions[session_id.to_u16]?
          if session
            Log.debug { "session_lookup: Found session #{session_id}, returning attestation_challenge" }
            session.attestation_challenge
          else
            Log.debug { "session_lookup: Session #{session_id} not found" }
            nil
          end
        end

        # Set up on_fabric_added callback to forward to on_commissioned
        # This allows the device to switch from commissioning to operational mDNS advertisement
        operational_creds.on_fabric_added = ->(fabric : Fabric) do
          Log.info { "Fabric added: fabric_id=#{fabric.fabric_id}, node_id=#{fabric.node_id}" }
          Log.info { "  compressed_fabric_id=#{fabric.compressed_fabric_id.hexstring.upcase}" }
          if callback = @on_commissioned
            callback.call(fabric)
          end
        end

        @clusters[{0_u16, 0x003E_u32}] = operational_creds
        @operational_credentials_cluster = operational_creds

        Log.info { "Initialized #{@clusters.size} clusters" }
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
            Log.debug { "Message is encrypted (session_id=#{session_id}), decrypting..." }

            # Get secure session context
            session = @sessions[session_id]?
            unless session
              Log.error { "No session found for ID: #{session_id}" }
              return
            end

            # Decrypt the payload
            msg = decrypt_message(msg, session)
          end

          Log.info { "Received message: protocol=0x#{msg.payload_header.protocol_id.to_s(16)}, type=0x#{msg.payload_header.message_type.to_s(16)}" }

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
        Log.error(exception: ex) { "Error handling message: #{ex.message}" }
      end

      # Decrypt an encrypted message and re-parse the payload header
      private def decrypt_message(
        msg : Codec::MessageCodec::Message,
        session : Session::SecureContext,
      ) : Codec::MessageCodec::Message
        Log.debug { "Decrypting payload (#{msg.payload.size} bytes)" }
        crypto = Crypto::StandardCrypto.new

        # Use the actual message_id from the packet header as the message counter
        # (message_id IS the message counter for encrypted messages)
        message_counter = msg.packet_header.message_id

        decrypted = Session::SecureMessage.decrypt(
          context: session,
          encrypted_payload: msg.payload,
          message_counter: message_counter,
          packet_header: msg.packet_header,
          crypto: crypto
        )

        unless decrypted
          raise "Failed to decrypt message"
        end

        Log.debug { "Decrypted payload: #{decrypted.hexstring}" }

        # Create a packet with decrypted payload and decode it
        decrypted_packet = Codec::MessageCodec::Packet.new(
          header: msg.packet_header,
          payload: decrypted
        )

        # Decode the payload to get the real protocol_id and message_type
        Codec::MessageCodec::Base.decode_payload(decrypted_packet)
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
        Log.info { "Received Interaction Model message (already decrypted)" }
        Log.debug { "  Exchange ID: #{msg.payload_header.exchange_id}" }
        Log.debug { "  Requires ACK: #{msg.payload_header.requires_acknowledge?}" }
        Log.debug { "  Initiator: #{msg.payload_header.initiator_message?}" }

        # Get secure session context (needed for sending response)
        session_id = msg.packet_header.session_id
        session = @sessions[session_id]?
        unless session
          Log.error { "No session found for ID: #{session_id}" }
          return
        end

        # Per Matter spec 4.11.8: Don't send standalone ACK if we respond immediately
        # The ReadResponse with acknowledged_message_id serves as the ACK
        # (Standalone ACKs are only sent if response takes longer than MRP_STANDALONE_ACK_TIMEOUT)

        # Message is already decrypted, payload contains TLV data
        # Parse IM message based on message type
        case msg.payload_header.message_type
        when 0x01_u8 # StatusResponse
          handle_status_response(msg.payload, msg, peer, session)
        when 0x02_u8 # ReadRequest
          handle_read_request(msg.payload, msg, peer, session)
        when 0x03_u8 # SubscribeRequest
          handle_subscribe_request(msg.payload, msg, peer, session)
        when 0x06_u8 # WriteRequest
          handle_write_request(msg.payload, msg, peer, session)
        when 0x08_u8 # InvokeRequest
          handle_invoke_request(msg.payload, msg, peer, session)
        else
          Log.warn { "Unknown IM message type: 0x#{msg.payload_header.message_type.to_s(16)}" }
        end
      rescue ex
        Log.error(exception: ex) { "Error handling IM message: #{ex.message}" }
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
        Log.info { "Handling StatusResponse" }

        # Parse StatusResponse TLV
        status_code = 0_u8
        begin
          reader = TLV::Reader.new(decrypted)
          data = reader.get.as(Hash(TLV::Tag, TLV::Value))
          request_data = data["Any"].as(Hash(TLV::Tag, TLV::Value))

          # Extract status code (tag 0)
          status_value = request_data[0_u8]?
          status_code = if status_value
                          case status_value
                          when Int
                            status_value.to_u8
                          when UInt8
                            status_value
                          else
                            0_u8
                          end
                        else
                          0_u8
                        end

          if status_code == 0
            Log.info { "✅ StatusResponse: SUCCESS" }
          else
            Log.warn { "⚠️  StatusResponse: status=0x#{status_code.to_s(16)}" }
          end
        rescue ex
          Log.error { "Failed to parse StatusResponse: #{ex.message}" }
        end

        # Check if this StatusResponse is for a pending subscription
        exchange_id = original_msg.payload_header.exchange_id
        if pending = @pending_subscriptions.delete(exchange_id)
          if status_code == 0
            # Success - check if there are more chunks to send
            if !pending.remaining_chunks.empty?
              # Send next chunk
              next_chunk, is_last = pending.remaining_chunks.shift
              Log.info { "StatusResponse received for subscription #{pending.subscription_id}, sending next chunk (#{pending.remaining_chunks.size} remaining)" }

              # Send next ReportData chunk
              send_im_response(
                original_msg: original_msg,
                peer: pending.peer,
                session: pending.session,
                message_type: 0x05_u8, # ReportData
                payload: next_chunk
              )

              # Put pending subscription back to wait for next StatusResponse
              @pending_subscriptions[exchange_id] = pending
              Log.info { "Sent ReportData chunk, waiting for StatusResponse" }
            else
              # All chunks sent - send SubscribeResponse to complete the subscription
              Log.info { "StatusResponse received for subscription #{pending.subscription_id}, all chunks sent, sending SubscribeResponse" }

              # Encode SubscribeResponse as TLV
              subscribe_response_tlv = IMHandler.encode_subscribe_response(pending.subscription_id, pending.max_interval)
              Log.debug { "Encoded SubscribeResponse TLV (#{subscribe_response_tlv.size} bytes)" }

              # Send SubscribeResponse
              send_im_response(
                original_msg: original_msg,
                peer: pending.peer,
                session: pending.session,
                message_type: 0x04_u8, # SubscribeResponse
                payload: subscribe_response_tlv
              )

              Log.info { "Sent SubscribeResponse for subscription #{pending.subscription_id}, maxInterval=#{pending.max_interval}s" }
            end
          else
            # Error - subscription failed
            Log.error { "StatusResponse error for subscription #{pending.subscription_id}, aborting subscription" }
          end
        end
      end

      # Handle ReadRequest - parse, read attributes, encode response, encrypt and send
      private def handle_read_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.info { "Handling ReadRequest" }

        # Parse ReadRequest using IMHandler
        request = IMHandler.parse_read_request(decrypted)
        unless request
          Log.error { "Failed to parse ReadRequest" }
          return
        end

        Log.info { "ReadRequest: #{request.attribute_requests.size} attribute(s) requested" }

        # Read attributes from clusters (pass fabric_index for fabric-scoped attributes)
        response = IMHandler.read_attributes(request.attribute_requests, @clusters, session.fabric_index)

        Log.info { "ReadResponse: #{response.attribute_reports.size} report(s), #{response.attribute_status.size} status(es)" }

        # Encode ReadResponse as TLV
        response_tlv = IMHandler.encode_read_response(response)
        Log.debug { "Encoded ReadResponse TLV (#{response_tlv.size} bytes): #{response_tlv.hexstring}" }

        # Send encrypted IM response
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: 0x05_u8, # ReportData (ReadResponse)
          payload: response_tlv
        )

        Log.info { "Sent ReadResponse" }
      rescue ex
        Log.error(exception: ex) { "Error handling ReadRequest: #{ex.message}" }
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
        Log.info { "Handling SubscribeRequest" }

        # Parse SubscribeRequest using IMHandler
        request = IMHandler.parse_subscribe_request(decrypted)
        unless request
          Log.error { "Failed to parse SubscribeRequest" }
          return
        end

        Log.info { "SubscribeRequest: #{request.attribute_requests.size} attribute(s), min=#{request.min_interval_floor}s, max=#{request.max_interval_ceiling}s" }

        # Log what attributes are being subscribed to
        request.attribute_requests.each_with_index do |path, idx|
          endpoint = path.endpoint.try(&.to_s) || "*"
          cluster = path.cluster.try { |c| "0x#{c.to_s(16)}" } || "*"
          attribute = path.attribute.try { |a| "0x#{a.to_s(16)}" } || "*"
          Log.info { "  Subscribe #{idx}: endpoint=#{endpoint} cluster=#{cluster} attr=#{attribute}" }
        end

        # Generate subscription ID
        subscription_id = @next_subscription_id
        @next_subscription_id += 1

        Log.info { "Created subscription #{subscription_id}" }

        # Read attributes from clusters (same as ReadRequest, pass fabric_index for fabric-scoped attributes)
        response = IMHandler.read_attributes(request.attribute_requests, @clusters, session.fabric_index)

        Log.info { "Initial ReportData: #{response.attribute_reports.size} report(s), #{response.attribute_status.size} status(es)" }

        # Encode ReportData with subscription ID as TLV, chunked to fit MTU
        chunks = IMHandler.encode_chunked_report_data(response, subscription_id)
        Log.info { "Chunked ReportData into #{chunks.size} chunk(s)" }

        # Get first chunk to send
        first_chunk, _ = chunks.first
        remaining_chunks = chunks.size > 1 ? chunks[1..] : [] of Tuple(Bytes, Bool)

        Log.debug { "Sending first chunk (#{first_chunk.size} bytes), #{remaining_chunks.size} remaining" }

        # Send first ReportData chunk
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: 0x05_u8, # ReportData
          payload: first_chunk
        )

        Log.info { "Sent initial ReportData chunk for subscription #{subscription_id}" }

        # Calculate actual max interval (we honor the requested ceiling)
        max_interval = request.max_interval_ceiling

        # Store pending subscription - we'll send more chunks or SubscribeResponse after receiving StatusResponse
        # The exchange_id is used to correlate the StatusResponse with this subscription
        exchange_id = original_msg.payload_header.exchange_id
        @pending_subscriptions[exchange_id] = PendingSubscription.new(
          subscription_id: subscription_id,
          max_interval: max_interval,
          peer: peer,
          session: session,
          original_msg: original_msg,
          remaining_chunks: remaining_chunks
        )

        Log.info { "Waiting for StatusResponse on exchange #{exchange_id} (#{remaining_chunks.size} chunks remaining)" }
      rescue ex
        Log.error(exception: ex) { "Error handling SubscribeRequest: #{ex.message}" }
      end

      # Handle WriteRequest - parse, write attributes, encode response, encrypt and send
      private def handle_write_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.info { "Handling WriteRequest" }

        # Parse WriteRequest using IMHandler
        request = IMHandler.parse_write_request(decrypted)
        unless request
          Log.error { "Failed to parse WriteRequest" }
          return
        end

        Log.info { "WriteRequest: #{request.write_requests.size} attribute(s) to write" }

        # Write attributes to clusters
        response = IMHandler.write_attributes(request.write_requests, @clusters)

        Log.info { "WriteResponse: #{response.write_responses.size} status(es)" }

        # Check if response should be suppressed
        if request.suppress_response && response.write_responses.all? { |s| s.status.status == InteractionModel::StatusCode::Success }
          Log.info { "Response suppressed per suppressResponse flag (all writes succeeded)" }
          return
        end

        # Encode WriteResponse as TLV
        response_tlv = IMHandler.encode_write_response(response)
        Log.debug { "Encoded WriteResponse TLV (#{response_tlv.size} bytes): #{response_tlv.hexstring}" }

        # Send encrypted IM response
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: 0x07_u8, # WriteResponse
          payload: response_tlv
        )

        Log.info { "Sent WriteResponse" }
      rescue ex
        Log.error(exception: ex) { "Error handling WriteRequest: #{ex.message}" }
      end

      # Handle InvokeRequest - parse, execute commands, encode response, encrypt and send
      private def handle_invoke_request(
        decrypted : Bytes,
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
      ) : Nil
        Log.info { "Handling InvokeRequest" }

        # Parse InvokeRequest using IMHandler
        request = IMHandler.parse_invoke_request(decrypted)
        unless request
          Log.error { "Failed to parse InvokeRequest" }
          return
        end

        Log.info { "InvokeRequest: #{request.invoke_requests.size} command(s) requested" }

        # Execute commands on clusters (pass session info for attestation)
        response = IMHandler.invoke_commands(request.invoke_requests, @clusters, session.session_id.to_u64, session.is_case, session.fabric_index)

        Log.info { "InvokeResponse: #{response.invoke_responses.size} response(s), #{response.invoke_status.size} status(es)" }

        # Check if response should be suppressed
        if request.suppress_response && response.invoke_status.empty?
          Log.info { "Response suppressed per suppressResponse flag" }
          return
        end

        # Encode InvokeResponse as TLV
        response_tlv = IMHandler.encode_invoke_response(response)
        Log.debug { "Encoded InvokeResponse TLV (#{response_tlv.size} bytes): #{response_tlv.hexstring}" }

        # Send encrypted IM response
        send_im_response(
          original_msg: original_msg,
          peer: peer,
          session: session,
          message_type: 0x09_u8, # InvokeResponse
          payload: response_tlv
        )

        Log.info { "Sent InvokeResponse" }
      rescue ex
        Log.error(exception: ex) { "Error handling InvokeRequest: #{ex.message}" }
      end

      # Encrypt and send an Interaction Model response
      private def send_im_response(
        original_msg : Codec::MessageCodec::Message,
        peer : Socket::IPAddress,
        session : Session::SecureContext,
        message_type : UInt8,
        payload : Bytes,
      ) : Nil
        # Encrypt the payload using the session's encryption key
        crypto = Crypto::StandardCrypto.new

        # Build security flags byte for outgoing message
        # Bits 1-0: Session type (0=Unicast, 1=Group)
        # Bits 7-5: Control flags (privacy, control msg, extensions)
        security_flags = 0_u8
        security_flags |= Codec::MessageCodec::SessionType::Unicast.value # Bits 1-0

        # For PASE sessions, we must explicitly set source_node_id to NodeId(0)
        # matter.js always includes source_node_id in packet headers, using UNSPECIFIED_NODE_ID (0) for PASE
        # If we leave it as nil, the HasSourceNodeId flag won't be set and the 8-byte field won't be encoded,
        # creating a mismatch between AAD and nonce that causes chip-tool's decryption to fail
        response_source_node_id = if original_msg.packet_header.destination_node_id
                                    original_msg.packet_header.destination_node_id
                                  elsif session.local_node_id
                                    session.local_node_id
                                  else
                                    DataType::NodeId.new(0_u64) # PASE uses UNSPECIFIED_NODE_ID
                                  end

        # Compute the flags byte for the packet header (swapping source/dest from request)
        flags = Codec::MessageCodec::Base.compute_flags(
          response_source_node_id,                   # Will become source in response
          original_msg.packet_header.source_node_id, # Will become destination in response
          nil
        )
        Log.debug { "compute_flags returned: 0x#{flags.to_s(16)}, response_source_node_id=#{response_source_node_id.inspect}" }

        # Build packet header for encrypted response
        # CRITICAL: Use peer_session_id so recipient can find the session!
        # When chip-tool receives, it looks up by its own local session_id
        # which is our peer_session_id
        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: session.peer_session_id, # Use peer's session ID so they can look it up!
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: 0_u32, # Will be set by transport
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          flags: flags,
          security_flags: security_flags,
          source_node_id: response_source_node_id,
          destination_node_id: original_msg.packet_header.source_node_id
        )

        Log.debug { "Sending response on peer_session_id=#{session.peer_session_id} (received on our session_id=#{session.session_id})" }

        # Build payload header
        # If the original message required acknowledgment, embed the ACK in our response
        ack_msg_id = if original_msg.payload_header.requires_acknowledge?
                       original_msg.packet_header.message_id
                     else
                       nil
                     end

        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: original_msg.payload_header.exchange_id,
          protocol_id: PROTOCOL_INTERACTION_MODEL,
          message_type: message_type,
          initiator_message: !original_msg.payload_header.initiator_message?,
          requires_acknowledge: true, # Set to true like matter.js does
          acknowledged_message_id: ack_msg_id
        )

        Log.debug { "Response payload header: exchange=#{payload_header.exchange_id}, ack_msg=#{ack_msg_id}, initiator=#{payload_header.initiator_message?}" }

        # Encode the payload header to bytes
        payload_header_io = IO::Memory.new
        Codec::MessageCodec::Base.encode_payload_header(payload_header, payload_header_io)
        payload_header_bytes = payload_header_io.rewind.to_slice

        # Concatenate payload header + TLV payload (this is the "application payload" that gets encrypted)
        application_payload = Slice.join([payload_header_bytes, payload])

        Log.debug { "Application payload to encrypt: #{application_payload.size} bytes (#{payload_header_bytes.size} header + #{payload.size} TLV)" }

        # CRITICAL: Must encode packet header BEFORE encrypting to get the correct AAD!
        # Update packet header with the actual message counter we'll use
        message_counter = session.next_message_counter
        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: packet_header.session_id,
          session_type: packet_header.session_type,
          message_id: message_counter, # Use the actual counter!
          privacy_enhancements: packet_header.privacy_enhancements?,
          control_message: packet_header.control_message?,
          message_extensions: packet_header.message_extensions?,
          flags: packet_header.flags,
          security_flags: packet_header.security_flags,
          source_node_id: response_source_node_id,                        # Use the computed value!
          destination_node_id: original_msg.packet_header.source_node_id, # Use the original source as destination
          destination_group_id: packet_header.destination_group_id
        )

        # Encode packet header to get the exact bytes that will be sent (and used as AAD)
        packet_header_io = IO::Memory.new
        Codec::MessageCodec::Base.encode_packet_header(packet_header, packet_header_io)
        packet_header_bytes = packet_header_io.rewind.to_slice

        # Extract security_flags from the encoded header (byte 3) - like matter.js does
        security_flags = packet_header_bytes[3]

        # Determine node_id for nonce (must match source_node_id in header)
        source_node_id = if packet_header.source_node_id
                           packet_header.source_node_id.not_nil!.id
                         elsif session.local_node_id
                           session.local_node_id.not_nil!.id
                         else
                           0_u64 # PASE uses node_id=0
                         end

        # Build nonce: security_flags (1) + message_counter (4) + source_node_id (8)
        nonce = Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

        Log.info { "═══ ENCRYPTION TEST VECTOR ═══" }
        Log.info { "encryption_key: #{session.encryption_key.hexstring}" }
        Log.info { "application_payload (first 64 bytes): #{application_payload[0, [64, application_payload.size].min].hexstring}" }
        Log.info { "nonce (13 bytes): #{nonce.hexstring}" }
        Log.info { "aad (packet_header_bytes): #{packet_header_bytes.hexstring}" }
        Log.info { "Breakdown:" }
        Log.info { "  security_flags: 0x#{security_flags.to_s(16).rjust(2, '0')}" }
        Log.info { "  message_counter: #{message_counter}" }
        Log.info { "  source_node_id: #{source_node_id}" }
        Log.info { "  session_id: #{packet_header.session_id}" }

        # Encrypt using the ACTUAL packet header bytes as AAD (exactly like matter.js!)
        encrypted = crypto.encrypt(session.encryption_key, application_payload, nonce, packet_header_bytes)

        Log.info { "encrypted (first 64 bytes): #{encrypted[0, [64, encrypted.size].min].hexstring}" }
        Log.info { "═══════════════════════════════" }

        unless encrypted
          Log.error { "Failed to encrypt IM response" }
          return
        end

        Log.debug { "Encrypted application payload (#{encrypted.size} bytes)" }

        # Final UDP packet: packet_header_bytes + encrypted_application_payload
        udp_packet = Slice.join([packet_header_bytes, encrypted])

        # VERIFY: Log the actual bytes being sent on the wire
        Log.info { "📤 Sending UDP packet (#{udp_packet.size} bytes):" }
        Log.info { "   Header (AAD, 8 bytes): #{packet_header_bytes.hexstring}" }
        Log.info { "   Encrypted (first 64): #{encrypted[0, [64, encrypted.size].min].hexstring}" }

        # Send raw UDP packet
        @transport.send_raw(udp_packet, peer)
      end

      # Handle PBKDF Parameter Request (first step of PASE)
      private def handle_pbkdf_param_request(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling PBKDFParamRequest" }

        # Debug: dump payload bytes
        Log.debug { "PBKDF Request payload (#{msg.payload.size} bytes): #{msg.payload.hexstring}" }

        # Store request payload for context hashing (needed for SPAKE2+ context)
        @pbkdf_request_payload = msg.payload.dup

        # Decode request (TLV::Serializable provides constructor that takes Bytes)
        request = Session::Pase::Definitions::PbkdfParamRequest.new(msg.payload)
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
        @pbkdf_response_payload = response.to_bytes
        Log.debug { "PBKDF Response payload (#{@pbkdf_response_payload.not_nil!.size} bytes): #{@pbkdf_response_payload.not_nil!.hexstring}" }

        # Send response
        send_secure_channel_response(
          msg: msg,
          peer: peer,
          message_type: MSG_PBKDF_PARAM_RESPONSE,
          payload: @pbkdf_response_payload.not_nil!
        )

        Log.info { "Sent PBKDFParamResponse with session ID: #{responder_session_id}" }

        # Compute SPAKE2+ context hash: SHA256(SPAKE_CONTEXT || requestPayload || responsePayload)
        # This matches matter.js implementation in PasePairingTest.ts line 48
        spake_context = "CHIP PAKE V1 Commissioning"
        digest = OpenSSL::Digest.new("SHA256")
        digest.update(spake_context.to_slice)
        digest.update(@pbkdf_request_payload.not_nil!)
        digest.update(@pbkdf_response_payload.not_nil!)
        context_hash = digest.final

        Log.debug { "  SPAKE2+ context hash: #{context_hash.hexstring}" }

        # Create PBKDF parameters and PaseResponder with proper context
        pbkdf_params = Session::Pase::PbkdfParameters.new(@iterations.to_i32, @salt)
        crypto = Crypto::StandardCrypto.new
        @pase_responder = Session::Pase::PaseResponder.new(@setup_pin, pbkdf_params, crypto, context_hash)

        Log.info { "Created PaseResponder with hashed context" }
      end

      # Handle PASE Pake1 (second step of PASE)
      private def handle_pase_pake1(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling PASE Pake1" }

        # Decode Pake1 message - TLV library now correctly extracts the EC point
        pake1 = Session::Pase::Definitions::Pake1.new(msg.payload)
        p_a = pake1.x # Now correctly contains just the 65-byte EC point

        Log.info { "  Received pA: #{p_a.size} bytes" }
        Log.info { "  pA hex: #{p_a.hexstring}" }
        Log.info { "  pA first byte: 0x#{p_a[0].to_s(16).rjust(2, '0')}" } if p_a.size > 0

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
          payload: pake2.to_bytes
        )

        Log.info { "Sent PASE Pake2 (pB + cB)" }
      rescue ex
        Log.error(exception: ex) { "Error handling PASE Pake1: #{ex.message}" }
      end

      # Handle PASE Pake3 (third/final step of PASE)
      private def handle_pase_pake3(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling PASE Pake3" }

        # Decode Pake3 message - manually parse TLV to extract verifier (cA)
        Log.debug { "  Pake3 payload: #{msg.payload.hexstring}" }
        reader = TLV::Reader.new(msg.payload)
        tlv_data = reader.get
        Log.debug { "  Pake3 TLV keys: #{tlv_data.as(Hash).keys.inspect}" }

        # Unwrap the structure (same pattern as Pake1)
        wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
        struct_data = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

        # Extract cA (verifier) from tag 1
        c_a = struct_data[1_u8].as(Bytes)
        Log.debug { "  Received cA: #{c_a.size} bytes" }
        Log.debug { "  cA hex: #{c_a.hexstring}" }

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
        Log.debug { "  Expected h_ay: #{sav.h_ay.hexstring}" }
        if c_a != sav.h_ay
          Log.error { "PASE confirmation failed - cA doesn't match h_ay" }
          Log.error { "  Expected: #{sav.h_ay.hexstring}" }
          Log.error { "  Received: #{c_a.hexstring}" }
          # TODO: Send status report with error
          return
        end

        Log.info { "✅ PASE confirmation successful!" }

        # Derive session keys from the shared secret
        keys = responder.derive_session_keys
        Log.debug { "  Derived encryption key: #{keys[:encryption].size} bytes" }
        Log.debug { "  Encryption key (R2I): #{keys[:encryption].hexstring}" }
        Log.debug { "  Derived decryption key: #{keys[:decryption].size} bytes" }
        Log.debug { "  Decryption key (I2R): #{keys[:decryption].hexstring}" }
        Log.debug { "  Attestation challenge: #{keys[:attestation_challenge].size} bytes" }
        Log.debug { "  Attestation challenge: #{keys[:attestation_challenge].hexstring}" }

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
          is_initiator: false # We're the responder
        )

        # Store session for future encrypted communication
        @sessions[session_id] = secure_context

        Log.info { "✅ Secure session established! Session ID: #{session_id}" }
        Log.info { "   Commissioner can now send encrypted Interaction Model messages" }

        # Send StatusReport to confirm session establishment
        # StatusReport is still sent unsecured (session_id=0) as part of the PASE handshake
        # The secure session only becomes active AFTER StatusReport is acknowledged
        send_status_report_success(msg, peer)
      rescue ex
        Log.error(exception: ex) { "Error handling PASE Pake3: #{ex.message}" }
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

        # Build security flags byte for outgoing message
        # Bits 1-0: Session type (0=Unicast, 1=Group)
        # Bits 7-5: Control flags (privacy, control msg, extensions)
        security_flags = 0_u8
        security_flags |= Codec::MessageCodec::SessionType::Unicast.value # Bits 1-0

        # Compute the flags byte for the packet header (swapping source/dest from request)
        flags = Codec::MessageCodec::Base.compute_flags(
          msg.packet_header.destination_node_id, # Will become source in response
          msg.packet_header.source_node_id,      # Will become destination in response
          nil
        )

        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: response_session_id,
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: 0_u32, # Will be set by transport
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          flags: flags,
          security_flags: security_flags,
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
        Log.info { "✅ Received StandaloneAck" }

        # If the ACK includes an acknowledged message ID, log it
        if ack_msg_id = msg.payload_header.acknowledged_message_id
          Log.debug { "  Acknowledging message ID: #{ack_msg_id}" }
        end

        # Check if this ACK is for a pending subscription with remaining chunks
        # iPhone sends StandaloneAck (instead of StatusResponse) to acknowledge intermediate ReportData chunks
        exchange_id = msg.payload_header.exchange_id
        if pending = @pending_subscriptions[exchange_id]?
          if !pending.remaining_chunks.empty?
            # Send next chunk
            next_chunk, is_last = pending.remaining_chunks.shift
            Log.info { "StandaloneAck received for subscription #{pending.subscription_id}, sending next chunk (#{pending.remaining_chunks.size} remaining)" }

            # Send next ReportData chunk
            send_im_response(
              original_msg: pending.original_msg,
              peer: pending.peer,
              session: pending.session,
              message_type: 0x05_u8, # ReportData
              payload: next_chunk
            )

            # If there are more chunks, keep waiting
            if !pending.remaining_chunks.empty?
              Log.info { "Sent ReportData chunk, waiting for ACK/StatusResponse" }
            else
              # Last chunk sent, wait for StatusResponse to send SubscribeResponse
              Log.info { "Sent final ReportData chunk, waiting for StatusResponse to complete subscription" }
            end
          elsif pending.remaining_chunks.empty?
            # All chunks were sent, this ACK might be for the final chunk
            # Now we need to send SubscribeResponse
            Log.info { "StandaloneAck received after final chunk, sending SubscribeResponse for subscription #{pending.subscription_id}" }

            # Remove from pending
            @pending_subscriptions.delete(exchange_id)

            # Encode and send SubscribeResponse
            subscribe_response_tlv = IMHandler.encode_subscribe_response(pending.subscription_id, pending.max_interval)
            Log.debug { "Encoded SubscribeResponse TLV (#{subscribe_response_tlv.size} bytes)" }

            send_im_response(
              original_msg: pending.original_msg,
              peer: pending.peer,
              session: pending.session,
              message_type: 0x04_u8, # SubscribeResponse
              payload: subscribe_response_tlv
            )

            Log.info { "Sent SubscribeResponse for subscription #{pending.subscription_id}, maxInterval=#{pending.max_interval}s" }
          end
        end
      end

      # Handle StatusReport messages (sent by controllers to indicate errors or status)
      private def handle_status_report(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "📨 Received StatusReport" }

        begin
          # Parse StatusReport from binary payload (NOT TLV!)
          status_report = Session::Pase::Definitions::StatusReport.from_bytes(msg.payload)

          # Log the status details
          Log.info { "  General Status: 0x#{status_report.general_status.to_s(16).rjust(4, '0')}" }
          Log.info { "  Protocol Status: 0x#{status_report.protocol_status.to_s(16).rjust(4, '0')}" }

          # Interpret common status codes
          case status_report.general_status
          when 0
            Log.info { "  ✅ SUCCESS" }
          when 1
            Log.error { "  ❌ FAILURE" }
          when 2
            Log.error { "  ❌ BUSY - Device is busy, try again later" }
          else
            Log.warn { "  ⚠️  Unknown general status" }
          end

          # Log protocol-specific status if non-zero
          if status_report.protocol_status != 0
            Log.warn { "  Protocol-specific error code: #{status_report.protocol_status}" }
          end

          # If this is an error, provide context-specific help
          if status_report.general_status != 0
            # Check if we have a CASE responder active (indicating CASE session establishment)
            if @case_responder
              Log.error { "CASE session rejected by controller" }
              Log.error { "Protocol status 0x#{status_report.protocol_status.to_s(16).rjust(4, '0')} meanings:" }
              Log.error { "  0x0002 = NO_SHARED_TRUST_ROOTS - Certificate chain verification failed" }
              Log.error { "This usually means:" }
              Log.error { "  - Missing ICAC certificate in fabric" }
              Log.error { "  - NOC not signed by a trusted root" }
              Log.error { "  - Certificate chain validation failure" }
            else
              Log.error { "PASE handshake rejected by controller - commissioning failed" }
              Log.error { "This usually means:" }
              Log.error { "  - Incorrect PIN code" }
              Log.error { "  - SPAKE2+ computation mismatch" }
              Log.error { "  - Invalid crypto parameters" }
            end
          end
        rescue ex
          Log.error(exception: ex) { "Failed to parse StatusReport: #{ex.message}" }
          Log.debug { "  Payload hex: #{msg.payload.hexstring}" }
        end
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
          sigma1 = Session::Case::Definitions::Sigma1.new(msg.payload)

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
            @fabric_table.all_fabrics.each do |f|
              expected_dest_id = f.compute_destination_id(sigma1.initiator_random)
              Log.debug { "  Fabric #{f.fabric_id.to_s(16)}: expected=#{expected_dest_id.hexstring}" }
              Log.debug { "  Fabric #{f.fabric_id.to_s(16)}: received=#{sigma1.destination_id.hexstring}" }
              if expected_dest_id == sigma1.destination_id
                fabric = f
                Log.info { "  Matched fabric by destination_id: #{f.fabric_id.to_s(16)}" }
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

          # Store responder for Sigma3 processing
          @case_responder = responder

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
            payload: sigma2.to_bytes
          )

          Log.info { "Sent CASE Sigma2" }
        rescue ex
          Log.error(exception: ex) { "Error handling CASE Sigma1: #{ex.message}" }
        end
      end

      # Handle CASE Sigma3 (final step of CASE)
      private def handle_case_sigma3(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling CASE Sigma3" }

        begin
          # Decode Sigma3 message
          sigma3 = Session::Case::Definitions::Sigma3.new(msg.payload)

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

          Log.info { "✅ CASE Sigma3 verified successfully" }

          # Derive session keys from the shared secret
          # Pass sigma3_bytes for session key salt calculation
          keys = responder.derive_session_keys(sigma3_bytes)

          Log.debug { "  Derived encryption key (R2I): #{keys[:encryption].hexstring}" }
          Log.debug { "  Derived decryption key (I2R): #{keys[:decryption].hexstring}" }

          # Create secure session context using stored session IDs from Sigma1/Sigma2 exchange
          session_id = @case_responder_session_id
          peer_session_id = @case_initiator_session_id

          unless session_id && peer_session_id
            Log.error { "Missing session IDs - Sigma1/Sigma2 exchange must complete first" }
            return
          end

          # Get fabric for node IDs
          fabric_callback = @on_get_fabric
          unless fabric_callback
            Log.error { "No fabric callback set" }
            return
          end

          fabric = fabric_callback.call
          unless fabric
            Log.error { "No fabric available" }
            return
          end

          # Get the peer's node ID extracted from their NOC in Sigma3
          # This is critical for proper nonce construction in encrypted messages
          peer_node_id_value = responder.peer_node_id
          if peer_node_id_value
            Log.info { "Using peer node ID from Sigma3: #{peer_node_id_value}" }
          else
            Log.warn { "No peer node ID extracted from Sigma3 - falling back to nil" }
          end

          secure_context = Session::SecureContext.new(
            session_id: session_id,
            peer_session_id: peer_session_id,
            session_type: Session::SessionType::Unicast,
            encryption_key: keys[:encryption],
            decryption_key: keys[:decryption],
            is_initiator: false, # We're the responder
            local_node_id: DataType::NodeId.new(fabric.node_id),
            peer_node_id: peer_node_id_value ? DataType::NodeId.new(peer_node_id_value) : nil,
            is_case: true,
            fabric_index: fabric.fabric_index
          )

          # Store session for future encrypted communication
          @sessions[session_id] = secure_context

          Log.info { "✅ CASE secure session established! Session ID: #{session_id}" }
          Log.info { "   Operational messages can now be encrypted/decrypted" }

          # Send StatusReport to confirm session establishment
          # Like PASE, this is sent unsecured as part of the CASE handshake
          send_status_report_success(msg, peer)
        rescue ex
          Log.error(exception: ex) { "Error handling CASE Sigma3: #{ex.message}" }
        end
      end
    end
  end
end
