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

        # Decode request (TLV::Serializable provides constructor that takes Bytes)
        request = Session::Pase::Definitions::PbkdfParamRequest.new(msg.payload)
        Log.debug { "  Initiator session ID: #{request.initiator_session_id || "none"}" }

        # Extract initiator_random from request (32 bytes)
        initiator_random = request.initiator_random
        unless initiator_random
          Log.error { "PBKDFParamRequest missing initiator_random" }
          return
        end
        Log.debug { "  Initiator random: #{initiator_random.size} bytes" }

        # Create PASE responder if not exists
        unless @pase_responder
          @pase_responder = Session::Pase::PaseResponder.new(@setup_pin)
        end

        # Generate responder random (32 bytes)
        responder_random = Random::Secure.random_bytes(32)

        # Generate responder session ID
        responder_session_id = Random::Secure.rand(UInt16)

        # Build response
        response = Session::Pase::Definitions::PbkdfParamResponse.new(
          initiator_random: initiator_random,
          responder_random: responder_random,
          responder_session_id: responder_session_id,
          iterations: @iterations,
          salt: @salt
        )

        # Send response
        send_secure_channel_response(
          msg: msg,
          peer: peer,
          message_type: MSG_PBKDF_PARAM_RESPONSE,
          payload: response.to_bytes
        )

        Log.info { "Sent PBKDFParamResponse with session ID: #{responder_session_id}" }
      end

      # Handle PASE Pake1 (second step of PASE)
      private def handle_pase_pake1(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        Log.info { "Handling PASE Pake1" }

        # Decode Pake1 message (TLV::Serializable provides constructor that takes Bytes)
        pake1 = Session::Pase::Definitions::Pake1.new(msg.payload)
        p_a = pake1.x # Commissioner's public key
        Log.debug { "  Received pA: #{p_a.size} bytes" }

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

        # Decode Pake3 message (TLV::Serializable provides constructor that takes Bytes)
        pake3 = Session::Pase::Definitions::Pake3.new(msg.payload)
        c_a = pake3.verifier # Commissioner's confirmation
        Log.debug { "  Received cA: #{c_a.size} bytes" }

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
        if c_a != sav.h_ay
          Log.error { "PASE confirmation failed - cA doesn't match h_ay" }
          # TODO: Send status report with error
          return
        end

        Log.info { "✅ PASE confirmation successful!" }

        # Derive session keys from the shared secret
        keys = responder.derive_session_keys
        Log.debug { "  Derived encryption key: #{keys[:encryption].size} bytes" }
        Log.debug { "  Derived decryption key: #{keys[:decryption].size} bytes" }

        # Create secure session context
        session_id = msg.packet_header.session_id
        peer_session_id = msg.packet_header.source_node_id.try(&.id.to_u16) || 0_u16

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

        # TODO: Send a status report to confirm session establishment

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
    end
  end
end
