require "../crypto/crypto"
require "../codec/message_codec"
require "./context"

module Matter
  module Session
    # Secure message encoder/decoder for Matter protocol
    # Uses AES-128-CCM for authenticated encryption
    module SecureMessage
      extend self

      # Nonce size for AES-CCM in Matter (13 bytes)
      NONCE_LENGTH = 13

      # Privacy nonce for unencrypted header (13 bytes)
      PRIVACY_NONCE_LENGTH = 13

      # MIC (Message Integrity Check) length in bytes
      MIC_LENGTH = 16

      # Build nonce for AES-CCM encryption/decryption
      # Matter spec format: security_flags (1 byte) | message_counter (4 bytes LE) | source_node_id (8 bytes LE)
      def build_nonce(source_node_id : UInt64, message_counter : UInt32, security_flags : UInt8 = 0_u8) : Bytes
        io = IO::Memory.new(NONCE_LENGTH)

        # Write security flags (1 byte)
        io.write_byte(security_flags)

        # Write message counter (4 bytes, little-endian)
        IO::ByteFormat::LittleEndian.encode(message_counter, io)

        # Write source node ID (8 bytes, little-endian)
        IO::ByteFormat::LittleEndian.encode(source_node_id, io)

        io.to_slice
      end

      # Build Additional Authenticated Data (AAD) for AES-CCM
      # AAD = packet header (unencrypted portion)
      def build_aad(packet_header_bytes : Bytes) : Bytes
        # The AAD is the unencrypted packet header
        # This ensures the packet header can't be modified without detection
        packet_header_bytes
      end

      # Encrypt a message payload using session context
      def encrypt(
        context : SecureContext,
        payload : Bytes,
        packet_header : Codec::MessageCodec::PacketHeader,
        crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
      ) : Bytes
        # Get the next message counter
        message_counter = context.next_message_counter

        # Build nonce from source node ID and message counter
        # Use local_node_id if set, otherwise use node_id=0 for PASE
        source_node_id = if context.local_node_id
                           context.local_node_id.not_nil!.id
                         else
                           # During PASE, use node_id=0 (UNSPECIFIED) in nonce
                           # This matches matter.js behavior (NodeId.UNSPECIFIED_NODE_ID)
                           # The PASE temporary IDs (0xFFFFFFFB00000001/0xFFFFFFFB00000002)
                           # are only used in packet headers, not in AES-CCM nonces
                           0_u64
                         end
        security_flags = 0_u8
        security_flags |= 0x80 if packet_header.privacy_enhancements?
        security_flags |= 0x40 if packet_header.control_message?
        security_flags |= 0x20 if packet_header.message_extensions?

        nonce = build_nonce(source_node_id, message_counter, security_flags)

        # Build AAD from packet header
        # AAD = flags (1 byte) || session_id (2 bytes LE) || security_flags (1 byte) || message_counter (4 bytes LE)
        # Per matter.js: AAD is the entire packet header (bytes 0-7 for PASE without node IDs)
        aad_io = IO::Memory.new

        # Byte 0: flags
        aad_io.write_byte(packet_header.flags)
        # Bytes 1-2: session_id (LE)
        IO::ByteFormat::LittleEndian.encode(packet_header.session_id, aad_io)
        # Byte 3: security_flags
        aad_io.write_byte(security_flags)
        # Bytes 4-7: message_counter (LE)
        IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
        aad = aad_io.to_slice

        # Encrypt using AES-128-CCM
        encrypted = crypto.encrypt(context.encryption_key, payload, nonce, aad)

        encrypted
      end

      # Decrypt a message payload using session context
      def decrypt(
        context : SecureContext,
        encrypted_payload : Bytes,
        message_counter : UInt32,
        packet_header : Codec::MessageCodec::PacketHeader,
        crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
      ) : Bytes
        # Validate message counter to prevent replay attacks
        unless context.validate_message_counter(message_counter)
          last = context.peer_message_counter
          expected = last.nil? ? "any (first message)" : "> #{last}"
          raise "Invalid message counter - possible replay attack (received: #{message_counter}, expected #{expected})"
        end

        # Build nonce from peer node ID and message counter
        # Priority order for node ID:
        # 1. peer_node_id from context (real node ID after commissioning)
        # 2. source_node_id from packet header (if included in encrypted message)
        # 3. Node ID = 0 (UNSPECIFIED) for PASE sessions
        #
        # Note: Per matter.js implementation and testing, PASE encrypted messages use
        # node_id=0 (UNSPECIFIED_NODE_ID) in the nonce, NOT the PASE temporary IDs
        # (0xFFFFFFFB00000001/0xFFFFFFFB00000002) which are only used in packet headers
        peer_node_id = if context.peer_node_id
                         context.peer_node_id.not_nil!.id
                       elsif packet_header.source_node_id
                         packet_header.source_node_id.not_nil!.id
                       else
                         # During PASE, use node_id=0 (UNSPECIFIED) in nonce
                         # This matches matter.js behavior (NodeId.UNSPECIFIED_NODE_ID)
                         0_u64
                       end

        source = if context.peer_node_id
                   "context.peer_node_id"
                 elsif packet_header.source_node_id
                   "packet header"
                 else
                   "node_id=0 (PASE UNSPECIFIED)"
                 end

        puts "🔐 Decryption details:"
        puts "   peer_node_id: #{peer_node_id} (from #{source})"
        puts "   message_counter: #{message_counter}"
        puts "   session_id: #{packet_header.session_id}"
        puts "   peer_session_id: #{context.peer_session_id}"

        # Use the raw security_flags byte from the packet header (byte 3)
        # This is CRITICAL for AES-CCM nonce construction!
        # matter.js does: const securityFlags = headerBytes[3]
        security_flags = packet_header.security_flags

        nonce = build_nonce(peer_node_id, message_counter, security_flags)
        puts "   security_flags: 0x#{security_flags.to_s(16).rjust(2, '0')}"
        puts "   nonce: #{nonce.hexstring}"

        # Build AAD from packet header
        # AAD = flags (1 byte) || session_id (2 bytes LE) || security_flags (1 byte) || message_counter (4 bytes LE)
        # Per matter.js: AAD is the entire packet header (bytes 0-7 for PASE without node IDs)
        aad_io = IO::Memory.new

        # Byte 0: flags
        aad_io.write_byte(packet_header.flags)
        # Bytes 1-2: session_id (LE)
        IO::ByteFormat::LittleEndian.encode(packet_header.session_id, aad_io)
        # Byte 3: security_flags
        aad_io.write_byte(security_flags)
        # Bytes 4-7: message_counter (LE)
        IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
        aad = aad_io.to_slice
        puts "   aad (full packet header): #{aad.hexstring}"
        puts "   encrypted_payload size: #{encrypted_payload.size} bytes"
        puts "   encrypted_payload (first 32 bytes): #{encrypted_payload[0, [32, encrypted_payload.size].min].hexstring}"
        puts "   decryption_key: #{context.decryption_key.hexstring}"

        # Decrypt using AES-128-CCM
        decrypted = crypto.decrypt(context.decryption_key, encrypted_payload, nonce, aad)

        decrypted
      end

      # Encrypt with explicit parameters (for testing)
      def encrypt_with_params(
        key : Bytes,
        payload : Bytes,
        source_node_id : UInt64,
        message_counter : UInt32,
        session_id : UInt16,
        security_flags : UInt8 = 0_u8,
        flags : UInt8 = 0_u8,
        crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
      ) : Bytes
        nonce = build_nonce(source_node_id, message_counter, security_flags)

        # AAD = flags (1 byte) || session_id (2 bytes LE) || security_flags (1 byte) || message_counter (4 bytes LE)
        aad_io = IO::Memory.new
        aad_io.write_byte(flags)
        IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
        aad_io.write_byte(security_flags)
        IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
        aad = aad_io.to_slice

        crypto.encrypt(key, payload, nonce, aad)
      end

      # Decrypt with explicit parameters (for testing)
      def decrypt_with_params(
        key : Bytes,
        encrypted_payload : Bytes,
        source_node_id : UInt64,
        message_counter : UInt32,
        session_id : UInt16,
        security_flags : UInt8 = 0_u8,
        flags : UInt8 = 0_u8,
        crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
      ) : Bytes
        nonce = build_nonce(source_node_id, message_counter, security_flags)

        # AAD = flags (1 byte) || session_id (2 bytes LE) || security_flags (1 byte) || message_counter (4 bytes LE)
        aad_io = IO::Memory.new
        aad_io.write_byte(flags)
        IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
        aad_io.write_byte(security_flags)
        IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
        aad = aad_io.to_slice

        crypto.decrypt(key, encrypted_payload, nonce, aad)
      end
    end
  end
end
