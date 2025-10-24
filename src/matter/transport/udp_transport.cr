require "socket"
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

      getter socket : UDPSocket
      getter port : Int32
      getter message_counter : MessageCounter
      getter exchange_manager : ExchangeManager

      # Callback for received messages
      # Signature: (message : Codec::MessageCodec::Message, peer_address : Socket::IPAddress) -> Nil
      property on_message : Proc(Codec::MessageCodec::Message, Socket::IPAddress, Nil)?

      @running : Bool
      @receive_fiber : Fiber?

      def initialize(@port : Int32 = MATTER_PORT, @interface : String = "0.0.0.0")
        @socket = UDPSocket.new
        @socket.reuse_address = true
        @socket.reuse_port = true
        @socket.bind(@interface, @port)
        @socket.read_timeout = 100.milliseconds # 100ms timeout for receive operations

        @message_counter = MessageCounter.new
        @exchange_manager = ExchangeManager.new
        @running = false
        @receive_fiber = nil
      end

      # Start receiving messages in background
      def start : Nil
        return if @running

        @running = true
        @receive_fiber = spawn do
          receive_loop
        end
      end

      # Stop receiving messages
      def stop : Nil
        @running = false
        # Give fiber time to exit on next loop iteration
        sleep 200.milliseconds if @receive_fiber
        @receive_fiber = nil
      end

      # Close transport and release resources
      def close : Nil
        stop
        @socket.close unless @socket.closed?
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
        @socket.send(data, peer_address)
      end

      # Send raw packet (for testing)
      def send_raw(data : Bytes | Slice(UInt8), peer_address : Socket::IPAddress) : Nil
        @socket.send(data, peer_address)
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

        # Build message
        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: session_id,
          session_type: Codec::MessageCodec::SessionType::Unicast,
          message_id: 0_u32, # Will be set by send_message
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
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

      private def receive_loop : Nil
        buffer = Bytes.new(1280) # Matter MTU

        while @running
          begin
            bytes_read, peer_address = @socket.receive(buffer)
            next if bytes_read == 0

            data = buffer[0, bytes_read]
            handle_received_data(data, peer_address)
          rescue ex : IO::TimeoutError
            # Normal - just continue
          rescue ex : Exception
            # Log error but keep running
            puts "Transport receive error: #{ex.message}"
          end
        end
      end

      private def handle_received_data(data : Bytes, peer_address : Socket::IPAddress) : Nil
        # Decode packet
        packet = Codec::MessageCodec::Base.decode_packet(data)

        # Check for duplicate messages
        unless @message_counter.valid?(packet.header.message_id)
          # Duplicate message - ignore
          return
        end

        # Decode full message
        message = Codec::MessageCodec::Base.decode_payload(packet)

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
          send_acknowledgment(message, peer_address, exchange)
        end

        # Deliver to application
        if callback = @on_message
          callback.call(message, peer_address)
        end
      rescue ex : Exception
        # Log decode/processing errors
        puts "Error handling received data: #{ex.message}"
      end

      private def send_acknowledgment(
        original_message : Codec::MessageCodec::Message,
        peer_address : Socket::IPAddress,
        exchange : Exchange,
      ) : Nil
        # Build ACK message (empty payload)
        packet_header = Codec::MessageCodec::PacketHeader.new(
          session_id: original_message.packet_header.session_id,
          session_type: original_message.packet_header.session_type,
          message_id: 0_u32, # Will be set by send_message
          privacy_enhancements: false,
          control_message: false,
          message_extensions: false,
          source_node_id: original_message.packet_header.destination_node_id,
          destination_node_id: original_message.packet_header.source_node_id
        )

        payload_header = Codec::MessageCodec::PayloadHeader.new(
          exchange_id: exchange.exchange_id,
          protocol_id: original_message.payload_header.protocol_id,
          message_type: original_message.payload_header.message_type,
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
