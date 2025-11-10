require "../codec/message_codec"
require "../session/pase/pase"
require "../session/context"
require "../transport/udp_transport"

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

        # Set ourselves as the message handler
        @transport.on_message = ->(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) do
          handle_message(msg, peer)
        end
      end

      # Main message routing entry point
      def handle_message(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
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

      # Handle Secure Channel protocol (PASE, CASE, etc.)
      private def handle_secure_channel(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        case msg.payload_header.message_type
        when MSG_PBKDF_PARAM_REQUEST
          handle_pbkdf_param_request(msg, peer)
        when MSG_PASE_PAKE1
          handle_pase_pake1(msg, peer)
        when MSG_PASE_PAKE3
          handle_pase_pake3(msg, peer)
        when MSG_CASE_SIGMA1
          Log.info { "Received CASE Sigma1 (not yet implemented)" }
        else
          Log.warn { "Unsupported Secure Channel message type: 0x#{msg.payload_header.message_type.to_s(16)}" }
        end
      end

      # Handle Interaction Model protocol (Read, Write, Invoke, etc.)
      private def handle_interaction_model(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Received Interaction Model message (not yet implemented)" }
        # TODO: Implement IM message handling
        # - Check if session is secured
        # - Decrypt payload if needed
        # - Route to endpoint/cluster based on paths
        # - Execute operation and send response
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

        # Decode Pake1 message - manually parse TLV to extract pA
        reader = TLV::Reader.new(msg.payload)
        tlv_data = reader.get
        Log.debug { "  Pake1 TLV keys: #{tlv_data.as(Hash).keys.inspect}" }

        # Unwrap the structure
        wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
        struct_data = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

        # Extract pA from tag 1
        p_a = struct_data[1_u8].as(Bytes)
        Log.debug { "  Received pA: #{p_a.size} bytes" }
        Log.debug { "  pA hex: #{p_a.hexstring}" }

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
        Log.debug { "  Derived decryption key: #{keys[:decryption].size} bytes" }

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
