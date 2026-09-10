require "log"
require "socket"

require "../codec/message_codec"
require "../crypto/crypto"
require "../datatype/node_id"
require "../session/context"
require "../session/secure_message"
require "../transport/udp_transport"

module Matter
  module Controller
    class Client
      Log = ::Log.for("matter.controller.client")

      PROTOCOL_SECURE_CHANNEL    = 0x0000_u16
      PROTOCOL_INTERACTION_MODEL = 0x0001_u16

      MSG_STANDALONE_ACK = 0x10_u8

      record ReceivedMessage, message : Codec::MessageCodec::Message, peer : Socket::IPAddress

      getter transport : Transport::UDPTransport
      getter crypto : Crypto::CryptoBase

      @sessions = {} of UInt16 => Session::SecureContext
      @inbox : Channel(ReceivedMessage)
      @next_exchange_id : UInt16
      @unsecured_source_node_id : DataType::NodeId?

      def initialize(
        port : Int32 = 0,
        @crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
        unsecured_source_node_id : UInt64? = nil,
        initial_unsecured_message_counter : UInt32? = nil,
      )
        @transport = Transport::UDPTransport.new(port: port)
        @unsecured_source_node_id = unsecured_source_node_id ? DataType::NodeId.new(unsecured_source_node_id) : nil

        # Avoid re-using old unsecured message IDs across process restarts: peers may
        # keep a dedupe window for unsecured traffic (session_id=0), which can cause
        # commissioning/CASE handshakes to be ignored as duplicates/stale.
        if initial = initial_unsecured_message_counter
          @transport.message_counter.reset(initial)
        else
          @transport.message_counter.reset(Random::Secure.rand(UInt32))
        end
        @inbox = Channel(ReceivedMessage).new(256)
        @next_exchange_id = Random.rand(UInt16).to_u16

        @transport.on_message = ->(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) { handle_transport_message(msg, peer) }
        @transport.start
      end

      def close : Nil
        @transport.close
      end

      def register_session(session : Session::SecureContext) : Nil
        @sessions[session.session_id] = session
      end

      def session?(session_id : UInt16) : Session::SecureContext?
        @sessions[session_id]?
      end

      def next_exchange_id : UInt16
        id = @next_exchange_id
        @next_exchange_id = @next_exchange_id &+ 1
        id
      end

      # Send an unsecured (session_id=0) request and return the exchange id.
      def send_unsecured_request(
        peer : Socket::IPAddress,
        protocol_id : UInt16,
        message_type : UInt8,
        payload : Bytes | Slice(UInt8),
        requires_ack : Bool = true,
      ) : UInt16
        exchange = @transport.send_request(
          protocol_id: protocol_id,
          message_type: message_type,
          payload: payload,
          session_id: 0_u16,
          peer_address: peer,
          peer_node_id: nil,
          source_node_id: @unsecured_source_node_id,
          requires_ack: requires_ack
        )
        exchange.exchange_id
      end

      # Send an unsecured (session_id=0) message on an existing exchange.
      def send_unsecured_on_exchange(
        peer : Socket::IPAddress,
        exchange_id : UInt16,
        protocol_id : UInt16,
        message_type : UInt8,
        payload : Bytes | Slice(UInt8),
        initiator_message : Bool = true,
        requires_ack : Bool = true,
        acknowledged_message_id : UInt32? = nil,
      ) : Nil
        exchange = @transport.exchange_manager.get_exchange(exchange_id)
        raise Matter::ProtocolError.new("unknown exchange_id=#{exchange_id}") unless exchange

        security_flags = 0_u8
        security_flags |= Codec::MessageCodec::SessionType::Unicast.value

        flags = Codec::MessageCodec::Base.compute_flags(@unsecured_source_node_id, nil, nil)

        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: 0_u16,
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: 0_u32, # assigned by UDPTransport
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          flags: flags,
          security_flags: security_flags,
          source_node_id: @unsecured_source_node_id,
          destination_node_id: nil
        )

        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: exchange_id,
          protocol_id: protocol_id,
          message_type: message_type,
          initiator_message: initiator_message,
          requires_acknowledge: requires_ack,
          acknowledged_message_id: acknowledged_message_id
        )

        message = Codec::MessageCodec::Message.new(
          packet_header: packet_header,
          payload_header: payload_header,
          payload: payload.to_slice
        )

        @transport.send_message(message, peer, exchange)
      end

      # Send an encrypted request on an existing secure session.
      def send_encrypted_request(
        session : Session::SecureContext,
        peer : Socket::IPAddress,
        protocol_id : UInt16,
        message_type : UInt8,
        payload : Bytes | Slice(UInt8),
        exchange_id : UInt16 = next_exchange_id,
        initiator_message : Bool = true,
        requires_ack : Bool = true,
        acknowledged_message_id : UInt32? = nil,
      ) : UInt16
        message_counter = session.next_message_counter

        security_flags = 0_u8
        security_flags |= Codec::MessageCodec::SessionType::Unicast.value

        # For encrypted requests, omit node IDs from the header (device-side decrypt
        # currently uses the 8-byte header AAD).
        flags = Codec::MessageCodec::Base.compute_flags(nil, nil, nil)

        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: session.peer_session_id,
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: message_counter,
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          flags: flags,
          security_flags: security_flags,
          source_node_id: nil,
          destination_node_id: nil
        )

        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: exchange_id,
          protocol_id: protocol_id,
          message_type: message_type,
          initiator_message: initiator_message,
          requires_acknowledge: requires_ack,
          acknowledged_message_id: acknowledged_message_id
        )

        payload_header_io = IO::Memory.new
        Codec::MessageCodec::Base.encode_payload_header(payload_header, payload_header_io)
        payload_header_bytes = payload_header_io.rewind.to_slice

        packet_header_io = IO::Memory.new
        Codec::MessageCodec::Base.encode_packet_header(packet_header, packet_header_io)
        packet_header_bytes = packet_header_io.rewind.to_slice

        application_payload = Slice.join([payload_header_bytes, payload.to_slice])

        source_node_id = session.local_node_id.try(&.id) || 0_u64
        nonce = Session::SecureMessage.build_nonce(source_node_id, message_counter, packet_header.security_flags)
        encrypted = @crypto.encrypt(session.encryption_key, application_payload, nonce, packet_header_bytes)

        udp_packet = Slice.join([packet_header_bytes, encrypted])
        @transport.send_raw(udp_packet, peer)

        exchange_id
      end

      # Wait for the next message matching exchange/protocol/type.
      def wait_for(
        exchange_id : UInt16,
        protocol_id : UInt16,
        message_type : UInt8,
        timeout : Time::Span,
      ) : ReceivedMessage?
        deadline = Time.instant + timeout

        loop do
          remaining = deadline - Time.instant
          return if remaining <= 0.seconds

          select
          when rec = @inbox.receive
            ack_encrypted_if_needed(rec)
            msg = rec.message
            next unless msg.payload_header.exchange_id == exchange_id
            next unless msg.payload_header.protocol_id == protocol_id
            next unless msg.payload_header.message_type == message_type
            return rec
          when timeout(remaining)
            return
          end
        end
      end

      private def handle_transport_message(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) : Nil
        if msg.packet_header.session_id == 0
          @inbox.send(ReceivedMessage.new(msg, peer))
          return
        end

        session = @sessions[msg.packet_header.session_id]?
        unless session
          Log.debug { "Dropping encrypted message: no session found (session_id=#{msg.packet_header.session_id}, peer=#{peer})" }
          return
        end

        decrypted_message = decrypt_message(session, msg)
        @inbox.send(ReceivedMessage.new(decrypted_message, peer))
      rescue ex
        Log.error(exception: ex) { "Controller: failed handling inbound message (peer=#{peer} session_id=#{msg.packet_header.session_id} data_hex=#{msg.payload.hexstring})" }
      end

      private def decrypt_message(session : Session::SecureContext, msg : Codec::MessageCodec::Message) : Codec::MessageCodec::Message
        packet_header_io = IO::Memory.new
        Codec::MessageCodec::Base.encode_packet_header(msg.packet_header, packet_header_io)
        packet_header_bytes = packet_header_io.rewind.to_slice

        peer_node_id = session.peer_node_id.try(&.id) || msg.packet_header.source_node_id.try(&.id) || 0_u64
        nonce = Session::SecureMessage.build_nonce(peer_node_id, msg.packet_header.message_id, msg.packet_header.security_flags)

        decrypted_application_payload = @crypto.decrypt(session.decryption_key, msg.payload.to_slice, nonce, packet_header_bytes)

        packet = Codec::MessageCodec::Packet.new(header: msg.packet_header, payload: decrypted_application_payload)
        Codec::MessageCodec::Base.decode_payload(packet)
      end

      private def ack_encrypted_if_needed(rec : ReceivedMessage) : Nil
        msg = rec.message
        return unless msg.payload_header.requires_acknowledge?
        return if msg.packet_header.session_id == 0

        session = @sessions[msg.packet_header.session_id]?
        return unless session

        send_standalone_ack(session, rec.peer, msg)
      end

      private def send_standalone_ack(
        session : Session::SecureContext,
        peer : Socket::IPAddress,
        original : Codec::MessageCodec::Message,
      ) : Nil
        message_counter = session.next_message_counter

        security_flags = 0_u8
        security_flags |= Codec::MessageCodec::SessionType::Unicast.value

        flags = Codec::MessageCodec::Base.compute_flags(nil, nil, nil)

        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: session.peer_session_id,
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: message_counter,
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          flags: flags,
          security_flags: security_flags,
          source_node_id: nil,
          destination_node_id: nil
        )

        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: original.payload_header.exchange_id,
          protocol_id: PROTOCOL_SECURE_CHANNEL,
          message_type: MSG_STANDALONE_ACK,
          initiator_message: !original.payload_header.initiator_message?,
          requires_acknowledge: false,
          acknowledged_message_id: original.packet_header.message_id
        )

        payload_header_io = IO::Memory.new
        Codec::MessageCodec::Base.encode_payload_header(payload_header, payload_header_io)
        payload_header_bytes = payload_header_io.rewind.to_slice

        packet_header_io = IO::Memory.new
        Codec::MessageCodec::Base.encode_packet_header(packet_header, packet_header_io)
        packet_header_bytes = packet_header_io.rewind.to_slice

        application_payload = payload_header_bytes

        source_node_id = session.local_node_id.try(&.id) || 0_u64
        nonce = Session::SecureMessage.build_nonce(source_node_id, message_counter, packet_header.security_flags)
        encrypted = @crypto.encrypt(session.encryption_key, application_payload, nonce, packet_header_bytes)
        udp_packet = Slice.join([packet_header_bytes, encrypted])
        @transport.send_raw(udp_packet, peer)
      end
    end
  end
end
