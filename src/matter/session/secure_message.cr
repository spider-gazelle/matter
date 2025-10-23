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
      # Format: source_node_id (8 bytes) | message_counter (4 bytes) | security_flags (1 byte)
      def build_nonce(source_node_id : UInt64, message_counter : UInt32, security_flags : UInt8 = 0_u8) : Bytes
        nonce = Bytes.new(NONCE_LENGTH)

        # Write source node ID (8 bytes, little-endian)
        IO::ByteFormat::LittleEndian.encode(source_node_id, nonce[0, 8])

        # Write message counter (4 bytes, little-endian)
        IO::ByteFormat::LittleEndian.encode(message_counter, nonce[8, 4])

        # Write security flags (1 byte)
        nonce[12] = security_flags

        nonce
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
        source_node_id = context.local_node_id.try(&.id) || 0_u64
        security_flags = 0_u8
        security_flags |= 0x80 if packet_header.privacy_enhancements?
        security_flags |= 0x40 if packet_header.control_message?
        security_flags |= 0x20 if packet_header.message_extensions?

        nonce = build_nonce(source_node_id, message_counter, security_flags)

        # Build AAD from packet header
        # For now, we'll use the session_id and message_id as AAD
        aad_io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(packet_header.session_id, aad_io)
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
        peer_node_id = context.peer_node_id.try(&.id) || 0_u64
        security_flags = 0_u8
        security_flags |= 0x80 if packet_header.privacy_enhancements?
        security_flags |= 0x40 if packet_header.control_message?
        security_flags |= 0x20 if packet_header.message_extensions?

        nonce = build_nonce(peer_node_id, message_counter, security_flags)

        # Build AAD from packet header
        aad_io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(packet_header.session_id, aad_io)
        IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
        aad = aad_io.to_slice

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
        crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
      ) : Bytes
        nonce = build_nonce(source_node_id, message_counter, security_flags)

        aad_io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
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
        crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
      ) : Bytes
        nonce = build_nonce(source_node_id, message_counter, security_flags)

        aad_io = IO::Memory.new
        IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
        IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
        aad = aad_io.to_slice

        crypto.decrypt(key, encrypted_payload, nonce, aad)
      end
    end
  end
end
