require "../codec/message_codec"
require "../session/pase/pase"
require "../session/context"
require "../session/secure_message"
require "../transport/udp_transport"
require "../cluster/basic_information_cluster"
require "../cluster/general_commissioning_cluster"
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

      # Device credentials for PASE
      property setup_pin : UInt32
      property discriminator : UInt16
      property iterations : UInt32
      property salt : Bytes

      # PASE context: store request/response payloads for context hashing
      property pbkdf_request_payload : Bytes?
      property pbkdf_response_payload : Bytes?

      # PASE session IDs from PBKDF exchange
      property initiator_session_id : UInt16?
      property responder_session_id : UInt16?

      def initialize(
        @transport : Transport::UDPTransport,
        @setup_pin : UInt32,
        @discriminator : UInt16,
        @iterations : UInt32 = 1000_u32,
        @salt : Bytes = Random::Secure.random_bytes(32),
      )
        @sessions = {} of UInt16 => Session::SecureContext
        @pase_responder = nil

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
        basic_info = Cluster::BasicInformationCluster.new(
          endpoint_id: endpoint_0,
          vendor_name: "Crystal Matter",
          vendor_id: 0xFFF1_u16,
          product_name: "Matter Device",
          product_id: 0x8000_u16
        )
        @clusters[{0_u16, 0x0028_u32}] = basic_info

        # General Commissioning cluster (0x0030) - required on endpoint 0
        general_commissioning = Cluster::GeneralCommissioningCluster.new(endpoint_0)
        @clusters[{0_u16, 0x0030_u32}] = general_commissioning

        Log.info { "Initialized #{@clusters.size} clusters" }
      end

      # Main message routing entry point
      def handle_message(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
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
        when MSG_PBKDF_PARAM_REQUEST
          handle_pbkdf_param_request(msg, peer)
        when MSG_PASE_PAKE1
          handle_pase_pake1(msg, peer)
        when MSG_PASE_PAKE3
          handle_pase_pake3(msg, peer)
        when MSG_STATUS_REPORT
          handle_status_report(msg, peer)
        when MSG_CASE_SIGMA1
          Log.info { "Received CASE Sigma1 (not yet implemented)" }
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
        when 0x02_u8 # ReadRequest
          handle_read_request(msg.payload, msg, peer, session)
        when 0x06_u8 # WriteRequest
          Log.info { "WriteRequest received (not yet implemented)" }
        when 0x08_u8 # InvokeRequest
          Log.info { "InvokeRequest received (not yet implemented)" }
        else
          Log.warn { "Unknown IM message type: 0x#{msg.payload_header.message_type.to_s(16)}" }
        end
      rescue ex
        Log.error(exception: ex) { "Error handling IM message: #{ex.message}" }
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

        # Read attributes from clusters
        response = IMHandler.read_attributes(request.attribute_requests, @clusters)

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

        # Compute the flags byte for the packet header (swapping source/dest from request)
        flags = Codec::MessageCodec::Base.compute_flags(
          original_msg.packet_header.destination_node_id, # Will become source in response
          original_msg.packet_header.source_node_id,      # Will become destination in response
          nil
        )

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
          source_node_id: original_msg.packet_header.destination_node_id,
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
          source_node_id: packet_header.source_node_id,
          destination_node_id: packet_header.destination_node_id,
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

          # If this is an error during PASE, the handshake failed
          if status_report.general_status != 0
            Log.error { "PASE handshake rejected by controller - commissioning failed" }
            Log.error { "This usually means:" }
            Log.error { "  - Incorrect PIN code" }
            Log.error { "  - SPAKE2+ computation mismatch" }
            Log.error { "  - Invalid crypto parameters" }
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
    end
  end
end
