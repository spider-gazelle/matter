require "../crypto/crypto"
require "../codec/message_codec"
require "./context"
require "log"

module Matter
  module Session
    # Secure message encoder/decoder for Matter protocol
    # Uses AES-128-CCM for authenticated encryption
    module SecureMessage
      extend self

      Log = ::Log.for("matter.session.secure_message")

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
        # CRITICAL: The node_id in the nonce MUST match the source_node_id in the packet header!
        # Use packet_header.source_node_id if present, otherwise fall back to context.local_node_id or 0
        source_node_id = if packet_header.source_node_id
                           packet_header.source_node_id.as(DataType::NodeId).id
                         elsif context.local_node_id
                           context.local_node_id.as(DataType::NodeId).id
                         else
                           # During PASE without source_node_id in header, use node_id=0 (UNSPECIFIED)
                           # This matches matter.js behavior (NodeId.UNSPECIFIED_NODE_ID)
                           0_u64
                         end

        # CRITICAL: Use the security_flags from packet_header, NOT rebuilt from individual flags
        # The security_flags byte includes session_type (bottom 2 bits) which we were missing!
        # This was causing AAD mismatch - the AAD had 0x00 but the packet header had 0x00 (Unicast) or 0x01 (Group)
        security_flags = packet_header.security_flags

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

        Log.trace do
          "Encrypt: source_node_id=#{source_node_id} " \
          "message_counter=#{message_counter} session_id=#{packet_header.session_id} " \
          "security_flags=#{Hex.u8(security_flags)} " \
          "nonce=#{nonce.hexstring} aad=#{aad.hexstring} " \
          "key=#{context.encryption_key.hexstring} payload_bytes=#{payload.size}"
        end

        # Encrypt using AES-128-CCM
        encrypted = crypto.encrypt(context.encryption_key, payload, nonce, aad)

        Log.trace do
          "Encrypt: encrypted_bytes=#{encrypted.size} (payload + #{MIC_LENGTH}-byte MIC) " \
          "encrypted_first32=#{encrypted[0, [32, encrypted.size].min].hexstring}"
        end

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
          raise Matter::SessionError.new("Invalid message counter - possible replay attack (received: #{message_counter}, expected #{expected})")
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
                         context.peer_node_id.as(DataType::NodeId).id
                       elsif packet_header.source_node_id
                         packet_header.source_node_id.as(DataType::NodeId).id
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

        Log.trace do
          "Decrypt: peer_node_id=#{peer_node_id} (from #{source}) " \
          "message_counter=#{message_counter} session_id=#{packet_header.session_id} peer_session_id=#{context.peer_session_id}"
        end

        # Use the raw security_flags byte from the packet header (the byte at
        # Codec::MessageCodec::SECURITY_FLAGS_OFFSET). This is CRITICAL for
        # AES-CCM nonce construction! matter.js does the same:
        # const securityFlags = headerBytes[3]
        security_flags = packet_header.security_flags

        nonce = build_nonce(peer_node_id, message_counter, security_flags)
        Log.trace { "Decrypt: security_flags=#{Hex.u8(security_flags)} nonce=#{nonce.hexstring}" }

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
        Log.trace do
          "Decrypt: aad=#{aad.hexstring} encrypted_payload_bytes=#{encrypted_payload.size} " \
          "encrypted_payload_first32=#{encrypted_payload[0, [32, encrypted_payload.size].min].hexstring} " \
          "key=#{context.decryption_key.hexstring}"
        end

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
