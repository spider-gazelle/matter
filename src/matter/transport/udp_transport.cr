require "socket"
require "log"
require "../codec/message_codec"
require "./message_counter"
require "./exchange"

module Matter
  module Transport
    # UDP transport layer for Matter protocol
    #
    # Handles:
    # - Sending and receiving Matter messages over UDP
    # - Message deduplication
    # - Automatic retransmission with exponential backoff
    # - Exchange management (request/response correlation)
    class UDPTransport
      # Matter default port
      MATTER_PORT = 5540

      Log = ::Log.for("matter.transport.udp")

      getter socket_ipv4 : UDPSocket
      getter socket_ipv6 : UDPSocket
      getter port : Int32
      getter message_counter : MessageCounter # Kept for backward compatibility (uses session_id=0)
      getter exchange_manager : ExchangeManager

      # Per-session message counters (key = session_id)
      @session_counters : Hash(UInt16, MessageCounter)

      # Per-source-node message counters for unsecured messages (session_id=0)
      # Key is the source_node_id (UInt64), value is the MessageCounter
      # This allows different nodes to have independent message counter windows
      @unsecured_counters : Hash(UInt64, MessageCounter)

      # Callback for received messages
      # Signature: (message : Codec::MessageCodec::Message, peer_address : Socket::IPAddress) -> Nil
      property on_message : Proc(Codec::MessageCodec::Message, Socket::IPAddress, Nil)?

      @running : Bool
      @receive_fiber_ipv4 : Fiber?
      @receive_fiber_ipv6 : Fiber?

      def initialize(@port : Int32 = MATTER_PORT, @interface_ipv4 : String = "0.0.0.0", @interface_ipv6 : String = "::")
        # Create separate IPv4 and IPv6 sockets for dual-stack support
        @socket_ipv4 = UDPSocket.new(Socket::Family::INET)
        @socket_ipv4.reuse_address = true
        @socket_ipv4.reuse_port = true
        @socket_ipv4.bind(@interface_ipv4, @port)
        @socket_ipv4.read_timeout = 100.milliseconds

        @socket_ipv6 = UDPSocket.new(Socket::Family::INET6)
        @socket_ipv6.reuse_address = true
        @socket_ipv6.reuse_port = true
        @socket_ipv6.bind(@interface_ipv6, @port)
        @socket_ipv6.read_timeout = 100.milliseconds

        # Initialize per-session counters hash
        @session_counters = Hash(UInt16, MessageCounter).new
        # For backward compatibility, @message_counter points to session_id=0's counter
        @message_counter = @session_counters[0_u16] = MessageCounter.new
        # Initialize per-source-node counters for unsecured messages
        @unsecured_counters = Hash(UInt64, MessageCounter).new
        @exchange_manager = ExchangeManager.new
        @running = false
        @receive_fiber_ipv4 = nil
        @receive_fiber_ipv6 = nil
        Log.info { "UDP transport bound: ipv4=[#{@interface_ipv4}]:#{@port} ipv6=[#{@interface_ipv6}]:#{@port}" }
      end

      # Start receiving messages in background
      def start : Nil
        return if @running

        @running = true
        @receive_fiber_ipv4 = spawn do
          receive_loop_ipv4
        end
        @receive_fiber_ipv6 = spawn do
          receive_loop_ipv6
        end
      end

      # Stop receiving messages
      def stop : Nil
        @running = false
        # Give fibers time to exit on next loop iteration
        sleep 200.milliseconds if @receive_fiber_ipv4 || @receive_fiber_ipv6
        @receive_fiber_ipv4 = nil
        @receive_fiber_ipv6 = nil
      end

      # Close transport and release resources
      def close : Nil
        stop
        @socket_ipv4.close unless @socket_ipv4.closed?
        @socket_ipv6.close unless @socket_ipv6.closed?
      end

      # Send a Matter message
      def send_message(
        message : Codec::MessageCodec::Message,
        peer_address : Socket::IPAddress,
        exchange : Exchange? = nil,
      ) : Nil
        # Update message ID if not set
        if message.packet_header.message_id == 0
          updated_header = Codec::MessageCodec::PacketHeader.new(
            session_id: message.packet_header.session_id,
            session_type: message.packet_header.session_type,
            message_id: @message_counter.next,
            privacy_enhancements: message.packet_header.privacy_enhancements?,
            control_message: message.packet_header.control_message?,
            message_extensions: message.packet_header.message_extensions?,
            flags: message.packet_header.flags,
            security_flags: message.packet_header.security_flags,
            source_node_id: message.packet_header.source_node_id,
            destination_node_id: message.packet_header.destination_node_id,
            destination_group_id: message.packet_header.destination_group_id
          )

          message = Codec::MessageCodec::Message.new(
            packet_header: updated_header,
            payload_header: message.payload_header,
            payload: message.payload
          )
        end

        # Store for potential retransmission if requires ACK
        if message.payload_header.requires_acknowledge? && exchange
          exchange.set_pending_message(message)
        end

        # Encode and send
        packet = Codec::MessageCodec::Base.encode_payload(message)
        data = Codec::MessageCodec::Base.encode_packet(packet)

        Log.trace do
          "Sending UDP packet: bytes=#{data.size} peer=#{peer_address.address}:#{peer_address.port} " \
          "protocol=0x#{message.payload_header.protocol_id.to_s(16)} " \
          "type=0x#{message.payload_header.message_type.to_s(16)} msg_id=#{message.packet_header.message_id}"
        end

        # Choose socket based on peer address family
        socket = peer_address.family.inet6? ? @socket_ipv6 : @socket_ipv4
        socket.send(data, peer_address)
      end

      # Send raw packet (for testing)
      def send_raw(data : Bytes | Slice(UInt8), peer_address : Socket::IPAddress) : Nil
        # Choose socket based on peer address family
        socket = peer_address.family.inet6? ? @socket_ipv6 : @socket_ipv4
        socket.send(data, peer_address)
      end

      # Create and send a message on a new exchange
      def send_request(
        protocol_id : UInt16,
        message_type : UInt8,
        payload : Bytes | Slice(UInt8),
        session_id : UInt16,
        peer_address : Socket::IPAddress,
        peer_node_id : DataType::NodeId? = nil,
        source_node_id : DataType::NodeId? = nil,
        requires_ack : Bool = true,
      ) : Exchange
        # Create new exchange
        exchange = @exchange_manager.create_exchange(
          protocol_id: protocol_id,
          session_id: session_id,
          peer_address: peer_address,
          peer_node_id: peer_node_id
        )

        # Build security flags byte for outgoing message
        security_flags = 0_u8
        security_flags |= Codec::MessageCodec::SessionType::Unicast.value # Bits 1-0

        # Compute the flags byte for the packet header
        flags = Codec::MessageCodec::Base.compute_flags(source_node_id, peer_node_id, nil)

        # Build message
        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: session_id,
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: 0_u32, # Will be set by send_message
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          flags: flags,
          security_flags: security_flags,
          source_node_id: source_node_id,
          destination_node_id: peer_node_id
        )

        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: exchange.exchange_id,
          protocol_id: protocol_id,
          message_type: message_type,
          initiator_message: true,
          requires_acknowledge: requires_ack
        )

        message = Codec::MessageCodec::Message.new(
          packet_header: packet_header,
          payload_header: payload_header,
          payload: payload.to_slice
        )

        send_message(message, peer_address, exchange)
        exchange
      end

      # Process retransmissions
      # Should be called periodically (e.g., every 50ms)
      def process_retransmissions : Nil
        candidates = @exchange_manager.get_retransmit_candidates

        candidates.each do |exchange_id, message|
          if exchange = @exchange_manager.get_exchange(exchange_id)
            if peer_address = exchange.peer_address
              send_message(message, peer_address, exchange)
            end
          end
        end

        @exchange_manager.cleanup_stale_exchanges
      end

      private def receive_loop_ipv4 : Nil
        Log.debug { "IPv4 UDP receive loop started (port=#{@port})" }
        buffer = Bytes.new(1280) # Matter MTU
        packet_count = 0
        peer_address : Socket::IPAddress? = nil
        bytes_read = 0
        data : Bytes? = nil

        while @running
          begin
            bytes_read, peer_address = @socket_ipv4.receive(buffer)
            next if bytes_read == 0

            packet_count += 1
            Log.trace { "Received IPv4 UDP packet ##{packet_count}: bytes=#{bytes_read} peer=#{peer_address.address}:#{peer_address.port}" }

            data = buffer[0, bytes_read]
            handle_received_data(data, peer_address)
          rescue ex : IO::TimeoutError
            # Normal - just continue
          rescue ex : Exception
            # Log error but keep running
            peer = peer_address ? "#{peer_address.address}:#{peer_address.port}" : "unknown"
            Log.error(exception: ex) { "IPv4 transport receive error (peer=#{peer} bytes=#{bytes_read} data_hex=#{data.try(&.hexstring) || "nil"})" }
          end
        end

        Log.debug { "IPv4 UDP receive loop stopped" }
      end

      private def receive_loop_ipv6 : Nil
        Log.debug { "IPv6 UDP receive loop started (port=#{@port})" }
        buffer = Bytes.new(1280) # Matter MTU
        packet_count = 0
        peer_address : Socket::IPAddress? = nil
        bytes_read = 0
        data : Bytes? = nil

        while @running
          begin
            bytes_read, peer_address = @socket_ipv6.receive(buffer)
            next if bytes_read == 0

            packet_count += 1
            Log.trace { "Received IPv6 UDP packet ##{packet_count}: bytes=#{bytes_read} peer=#{peer_address.address}:#{peer_address.port}" }

            data = buffer[0, bytes_read]
            handle_received_data(data, peer_address)
          rescue ex : IO::TimeoutError
            # Normal - just continue
          rescue ex : Exception
            # Log error but keep running
            peer = peer_address ? "#{peer_address.address}:#{peer_address.port}" : "unknown"
            Log.error(exception: ex) { "IPv6 transport receive error (peer=#{peer} bytes=#{bytes_read} data_hex=#{data.try(&.hexstring) || "nil"})" }
          end
        end

        Log.debug { "IPv6 UDP receive loop stopped" }
      end

      private def handle_received_data(data : Bytes, peer_address : Socket::IPAddress) : Nil
        # Validate minimum packet size
        # Minimum Matter packet: 8 bytes (flags + session_id + security_flags + message_id)
        if data.size < 8
          Log.warn { "Packet too small (#{data.size} bytes, minimum 8); ignoring malformed packet" }
          return
        end

        Log.trace { "Decoding packet: bytes=#{data.size} peer=#{peer_address.address}:#{peer_address.port}" }

        # For encrypted messages, dump packet header bytes to debug source_node_id parsing
        if data.size > 8
          session_id_offset = 1 # After flags byte
          session_id_bytes = data[session_id_offset, 2]
          session_id = IO::ByteFormat::LittleEndian.decode(UInt16, session_id_bytes)

          if session_id != 0
            Log.trace do
              "Encrypted packet header: first24=#{data[0, [24, data.size].min].hexstring} " \
              "flags=0x#{data[0].to_s(16).rjust(2, '0')} " \
              "has_source_node_id=#{(data[0] & 0x04) != 0} has_dest_node_id=#{(data[0] & 0x01) != 0} " \
              "session_id=#{session_id}"
            end
          end
        end

        # Decode packet
        packet = Codec::MessageCodec::Base.decode_packet(data)
        Log.trace do
          "Packet decoded: session_id=#{packet.header.session_id} message_id=#{packet.header.message_id} " \
          "source_node_id=#{packet.header.source_node_id.inspect} dest_node_id=#{packet.header.destination_node_id.inspect}"
        end

        # Check for duplicate messages
        session_id = packet.header.session_id
        if session_id == 0
          # For unsecured messages (session_id=0), track per source_node_id
          # This allows different nodes (e.g., different CASE initiators) to have
          # independent message counter windows
          source_node_id = packet.header.source_node_id.try(&.id) || 0_u64
          counter = @unsecured_counters[source_node_id] ||= MessageCounter.new
          unless counter.valid?(packet.header.message_id)
            # Duplicate message - ignore
            Log.warn { "Duplicate message ignored (unsecured): session_id=#{session_id}, source=#{source_node_id}, message_id=#{packet.header.message_id}" }
            return
          end
        else
          # For secured messages, track per session_id as before
          counter = @session_counters[session_id] ||= MessageCounter.new
          case counter.check(packet.header.message_id)
          when MessageCounter::CheckResult::Accept
            # Continue
          when MessageCounter::CheckResult::Duplicate
            # MRP retransmission - do not drop; the protocol layer may resend a cached response.
            Log.warn { "Duplicate message received (MRP retransmit): session_id=#{session_id}, message_id=#{packet.header.message_id}" }
          when MessageCounter::CheckResult::Stale
            Log.debug { "Stale message counter ignored: session_id=#{session_id}, message_id=#{packet.header.message_id}" }
            return
          end
        end

        # For encrypted messages (session_id != 0), do NOT decode the payload yet
        # The payload is encrypted and needs to be decrypted first by the message handler
        # For unencrypted messages (session_id == 0), decode the payload normally
        message = if session_id == 0
                    # Unencrypted message - decode payload now
                    decoded = Codec::MessageCodec::Base.decode_payload(packet)
                    Log.trace { "Message decoded: protocol=0x#{decoded.payload_header.protocol_id.to_s(16)}, type=0x#{decoded.payload_header.message_type.to_s(16)}" }
                    decoded
                  else
                    # Encrypted message - create Message with raw encrypted payload
                    # The payload_header will be decoded AFTER decryption by the message handler
                    Log.trace do
                      "Encrypted message detected: session_id=#{session_id} payload_bytes=#{packet.payload.size} " \
                      "payload_hex=#{packet.payload.hexstring}"
                    end

                    # Create a dummy payload header - it will be ignored and replaced after decryption
                    dummy_payload_header = Codec::MessageCodec::PayloadHeader.new(
                      exchange_id: 0_u16,
                      protocol_id: 0_u16,
                      message_type: 0_u8,
                      initiator_message: false,
                      requires_acknowledge: false
                    )

                    Codec::MessageCodec::Message.new(
                      packet_header: packet.header,
                      payload_header: dummy_payload_header,
                      payload: packet.payload # Keep the encrypted payload as-is
                    )
                  end

        # For encrypted messages, skip exchange management - the message handler will do this after decryption
        # For unencrypted messages, handle exchanges and acknowledgments here
        if session_id == 0
          # Get or create exchange
          exchange = @exchange_manager.get_or_create_exchange(
            exchange_id: message.payload_header.exchange_id,
            protocol_id: message.payload_header.protocol_id,
            session_id: packet.header.session_id,
            peer_address: peer_address,
            peer_node_id: packet.header.source_node_id,
            initiator: !message.payload_header.initiator_message?
          )

          # Handle acknowledgments
          if ack_msg_id = message.payload_header.acknowledged_message_id
            # This message acknowledges a previous message
            exchange.clear_pending_message
          end

          # Send acknowledgment if required
          if message.payload_header.requires_acknowledge?
            Log.trace { "Sending acknowledgment for message #{packet.header.message_id}" }
            send_acknowledgment(message, peer_address, exchange)
          end
        end

        # Deliver to application
        if callback = @on_message
          Log.trace { "Dispatching on_message callback" }
          callback.call(message, peer_address)
        else
          Log.warn { "No on_message callback registered" }
        end
      rescue ex : Exception
        # Log decode/processing errors
        Log.error(exception: ex) { "Error handling received data (peer=#{peer_address.address}:#{peer_address.port} bytes=#{data.size} data_hex=#{data.hexstring})" }
      end

      private def send_acknowledgment(
        original_message : Codec::MessageCodec::Message,
        peer_address : Socket::IPAddress,
        exchange : Exchange,
      ) : Nil
        # Build security flags byte - copy from original message
        security_flags = original_message.packet_header.security_flags

        # Compute the flags byte for the ACK packet header (swapping source/dest from request)
        flags = Codec::MessageCodec::Base.compute_flags(
          original_message.packet_header.destination_node_id, # Will become source in ACK
          original_message.packet_header.source_node_id,      # Will become destination in ACK
          nil
        )

        # Build ACK message (empty payload)
        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: original_message.packet_header.session_id,
          session_type: original_message.packet_header.session_type,
          message_id: 0_u32, # Will be set by send_message
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          flags: flags,
          security_flags: security_flags,
          source_node_id: original_message.packet_header.destination_node_id,
          destination_node_id: original_message.packet_header.source_node_id
        )

        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: exchange.exchange_id,
          protocol_id: original_message.payload_header.protocol_id,
          message_type: 0x10_u8, # MRP Standalone Acknowledgement
          initiator_message: !original_message.payload_header.initiator_message?,
          requires_acknowledge: false,
          acknowledged_message_id: original_message.packet_header.message_id
        )

        ack_message = Codec::MessageCodec::Message.new(
          packet_header: packet_header,
          payload_header: payload_header,
          payload: Bytes.new(0)
        )

        send_message(ack_message, peer_address, nil) # ACKs don't need retransmission
      end
    end
  end
end
