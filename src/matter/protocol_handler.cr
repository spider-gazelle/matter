require "./transport/udp_transport"
require "./session/context"
require "./session/secure_message"
require "./codec/message_codec"
require "./interaction_model/messages"
require "./cluster/on_off_cluster"
require "./cluster/basic_information_cluster"
require "./crypto/crypto"
require "./crypto/spake2p"

module Matter
  # Protocol handler for Matter devices
  #
  # Integrates:
  # - UDP transport layer
  # - Session management (PASE/CASE)
  # - Interaction Model routing
  # - Cluster command/attribute handling
  class ProtocolHandler
    getter transport : Transport::UDPTransport
    getter sessions : Hash(UInt16, Session::SecureContext)
    getter unsecured_session : Session::UnsecuredContext
    getter crypto : Crypto::StandardCrypto

    # Cluster storage (endpoint => cluster_id => cluster)
    getter clusters : Hash(UInt16, Hash(UInt32, Cluster::OnOffCluster | Cluster::BasicInformationCluster))

    # PASE session establishment
    property setup_pin : UInt32
    property? commissioning_mode : Bool = true

    # Callbacks
    property on_commissioned : Proc(Nil)?

    def initialize(@setup_pin : UInt32, port : Int32 = 5540)
      @transport = Transport::UDPTransport.new(port: port)
      @sessions = {} of UInt16 => Session::SecureContext
      @unsecured_session = Session::UnsecuredContext.new
      @crypto = Crypto::StandardCrypto.new
      @clusters = {} of UInt16 => Hash(UInt32, Cluster::OnOffCluster | Cluster::BasicInformationCluster)

      # Set up message handler
      @transport.on_message = ->(msg : Codec::MessageCodec::Message, peer : Socket::IPAddress) do
        handle_message(msg, peer)
      end
    end

    # Add a cluster to an endpoint
    def add_cluster(endpoint : UInt16, cluster : Cluster::OnOffCluster | Cluster::BasicInformationCluster)
      @clusters[endpoint] ||= {} of UInt32 => (Cluster::OnOffCluster | Cluster::BasicInformationCluster)
      @clusters[endpoint][cluster.cluster_id.value] = cluster
    end

    # Start listening for messages
    def start
      @transport.start
      puts "   Protocol handler listening on port #{@transport.port}"
    end

    # Stop handler
    def stop
      @transport.close
    end

    private def handle_message(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      puts "📨 Received message from #{peer_address.address}:#{peer_address.port}"
      puts "   Session ID: #{msg.packet_header.session_id}"
      puts "   Protocol: #{msg.payload_header.protocol_id}"
      puts "   Message Type: #{msg.payload_header.message_type}"

      # Determine if message is secured or unsecured
      if msg.packet_header.session_type.unsecured?
        handle_unsecured_message(msg, peer_address)
      else
        handle_secured_message(msg, peer_address)
      end
    rescue ex
      puts "❌ Error handling message: #{ex.message}"
      puts ex.backtrace.join("\n")
    end

    private def handle_unsecured_message(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      case msg.payload_header.protocol_id
      when 0x0000 # Secure Channel protocol
        handle_secure_channel_message(msg, peer_address)
      else
        puts "   ⚠️  Unsupported protocol on unsecured session: #{msg.payload_header.protocol_id}"
      end
    end

    private def handle_secured_message(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      session = @sessions[msg.packet_header.session_id]?
      unless session
        puts "   ⚠️  No session found for ID #{msg.packet_header.session_id}"
        return
      end

      # Decrypt payload
      # TODO: Implement secure message decryption using session keys
      puts "   🔐 Secured message (decryption not yet implemented)"
    end

    private def handle_secure_channel_message(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      case msg.payload_header.message_type
      when 0x20 # PBKDFParamRequest (PASE Step 1)
        handle_pase_pbkdf_request(msg, peer_address)
      when 0x22 # PASE_Pake1 (PASE Step 2)
        handle_pase_pake1(msg, peer_address)
      when 0x24 # PASE_Pake3 (PASE Step 3)
        handle_pase_pake3(msg, peer_address)
      when 0x30 # StatusReport
        handle_status_report(msg, peer_address)
      else
        puts "   ⚠️  Unsupported Secure Channel message: 0x#{msg.payload_header.message_type.to_s(16)}"
      end
    end

    private def handle_pase_pbkdf_request(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      puts "   🔐 PASE: Received PBKDFParamRequest"

      # Parse request (simplified - would use TLV in real impl)
      # For now, just send back PBKDF params

      # TODO: Parse TLV request and send proper response
      puts "   ⚠️  PASE PBKDF handling not fully implemented"
    end

    private def handle_pase_pake1(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      puts "   🔐 PASE: Received PAKE1"

      # TODO: Implement full PASE responder flow
      puts "   ⚠️  PASE PAKE1 handling not fully implemented"
    end

    private def handle_pase_pake3(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      puts "   🔐 PASE: Received PAKE3"

      # TODO: Verify PAKE3 and establish session
      puts "   ⚠️  PASE PAKE3 handling not fully implemented"
    end

    private def handle_status_report(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress)
      puts "   📊 StatusReport received"
      # Parse status from payload
      # TODO: Handle status reports properly
    end

    private def handle_interaction_model_message(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress, session : Session::SecureContext)
      case msg.payload_header.message_type
      when 0x02 # ReadRequest
        handle_read_request(msg, peer_address, session)
      when 0x06 # WriteRequest
        handle_write_request(msg, peer_address, session)
      when 0x08 # InvokeCommandRequest
        handle_invoke_request(msg, peer_address, session)
      when 0x03 # SubscribeRequest
        handle_subscribe_request(msg, peer_address, session)
      else
        puts "   ⚠️  Unsupported IM message type: 0x#{msg.payload_header.message_type.to_s(16)}"
      end
    end

    private def handle_read_request(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress, session : Session::SecureContext)
      puts "   📖 ReadRequest"

      # TODO: Parse ReadRequest TLV
      # TODO: Read from clusters
      # TODO: Send ReadResponse
      puts "   ⚠️  ReadRequest handling not fully implemented"
    end

    private def handle_write_request(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress, session : Session::SecureContext)
      puts "   ✏️  WriteRequest"

      # TODO: Parse WriteRequest TLV
      # TODO: Write to clusters
      # TODO: Send WriteResponse
      puts "   ⚠️  WriteRequest handling not fully implemented"
    end

    private def handle_invoke_request(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress, session : Session::SecureContext)
      puts "   ⚙️  InvokeCommandRequest"

      # TODO: Parse InvokeRequest TLV
      # TODO: Execute command on cluster
      # TODO: Send InvokeResponse
      puts "   ⚠️  InvokeRequest handling not fully implemented"
    end

    private def handle_subscribe_request(msg : Codec::MessageCodec::Message, peer_address : Socket::IPAddress, session : Session::SecureContext)
      puts "   📡 SubscribeRequest"

      # TODO: Set up subscription
      # TODO: Send SubscribeResponse and periodic reports
      puts "   ⚠️  SubscribeRequest handling not fully implemented"
    end
  end
end
