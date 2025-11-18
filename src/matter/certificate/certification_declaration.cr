require "openssl_ext"
require "../codec/der_codec"
require "../crypto/crypto"
require "../crypto/key"
require "tlv"

module Matter
  module Certificate
    # Generates Certification Declaration (CD) for Matter devices
    # The CD is a PKCS#7 SignedData structure containing device certification info
    # Used during commissioning to prove device compliance
    class CertificationDeclaration
      # Test CMS Signer Private Key from Matter 1.1 Core Spec Appendix F
      # This is the well-known test key that chip-tool trusts
      TEST_CMS_SIGNER_PRIVATE_KEY = "AEF3484116E9481EC57BE0472DF41BF499064E5024AD869ECA5E889802D48075"

      # Subject Key Identifier for the test CMS signer certificate
      TEST_CMS_SIGNER_SKI = "62FA823359ACFAA9963E1CFA140ADDF504F37160"

      # Generate a Certification Declaration for a device
      def self.generate(vendor_id : UInt16, product_id : UInt16) : Bytes
        # Build CD content as TLV
        cd_content = build_cd_tlv(vendor_id, product_id)

        # Sign with test CMS key using PKCS#7 SignedData format
        build_pkcs7_signed_data(cd_content)
      end

      # Build the CD TLV structure
      # Based on Matter Core Spec section 6.3.1
      # Note: Matter spec uses 0-based field tags (0-8), not 1-based
      # Note: Matter spec requires specific integer sizes - must use force_size
      private def self.build_cd_tlv(vendor_id : UInt16, product_id : UInt16) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Start structure (anonymous)
        writer.start_structure(nil)

        # Field 0: formatVersion (uint8)
        writer.put_unsigned_int(0_u8, 1_u8)

        # Field 1: vendorId (uint16)
        writer.put_unsigned_int(1_u8, vendor_id, force_size: 2)

        # Field 2: productIdArray (array of uint16)
        writer.start_array(2_u8)
        writer.put_unsigned_int(nil, product_id, force_size: 2)
        writer.end_container

        # Field 3: deviceTypeId (uint32 - MUST be 4 bytes)
        writer.put_unsigned_int(3_u8, 22_u32, force_size: 4)

        # Field 4: certificateId (string)
        writer.put_string(4_u8, "CSA00000SWC00000-00")

        # Field 5: securityLevel (uint8)
        writer.put_unsigned_int(5_u8, 0_u8)

        # Field 6: securityInformation (uint16 - MUST be 2 bytes)
        writer.put_unsigned_int(6_u8, 0_u16, force_size: 2)

        # Field 7: versionNumber (uint16 - MUST be 2 bytes)
        writer.put_unsigned_int(7_u8, 1_u16, force_size: 2)

        # Field 8: certificationType (uint8)
        writer.put_unsigned_int(8_u8, 0_u8)

        # End structure
        writer.end_container

        io.rewind.to_slice
      end

      # Build PKCS#7 SignedData ASN.1 structure
      # Manually builds DER bytes in correct RFC 5652 field order
      private def self.build_pkcs7_signed_data(content : Bytes) : Bytes
        # Load the test private key
        key_bytes = Bytes.new(TEST_CMS_SIGNER_PRIVATE_KEY.hexbytes.size)
        TEST_CMS_SIGNER_PRIVATE_KEY.hexbytes.to_a.each_with_index do |b, i|
          key_bytes[i] = b
        end

        # Derive public key from private key using OpenSSL
        ec_key = OpenSSL::PKey::EC.from_private_bytes(key_bytes, "P-256")
        public_key_bytes = ec_key.public_key_bytes

        # Create Key with both private and public keys
        key_pair = Crypto::BinaryKeyPair.new(public_key_bytes, key_bytes)
        key = Crypto.private_key(key_pair)

        # Sign the content with ECDSA (DER format for PKCS#7)
        signature = Crypto.sign_ecdsa(key, content, "der")

        # Subject Key Identifier as bytes
        ski_bytes = Bytes.new(TEST_CMS_SIGNER_SKI.hexbytes.size)
        TEST_CMS_SIGNER_SKI.hexbytes.to_a.each_with_index do |b, i|
          ski_bytes[i] = b
        end

        # Build SignerInfo SEQUENCE manually in RFC 5652 order:
        # version, sid, digestAlgorithm, signatureAlgorithm, signature
        signer_info_fields = [] of Bytes
        signer_info_fields << Codec::DERCodec::Base.encode(3_u8) # version

        # Build SubjectKeyIdentifier as context-specific [0] primitive (just raw bytes)
        ski_io = IO::Memory.new
        ski_io.write_byte(0x80_u8) # Context-specific [0] (primitive)
        ski_length_bytes = Codec::DERCodec::Base.encode_length_bytes(ski_bytes.size)
        ski_io.write(ski_length_bytes)
        ski_io.write(ski_bytes)
        signer_info_fields << ski_io.to_slice # sid

        signer_info_fields << Codec::DERCodec::Base.encode(Codec::DERCodec::SHA256_CMS.call)           # digestAlgorithm
        signer_info_fields << Codec::DERCodec::Base.encode(Codec::DERCodec::EcdsaWithSHA256_X962.call) # signatureAlgorithm
        signer_info_fields << Codec::DERCodec::Base.encode(signature)                                  # signature
        signer_info_seq = Codec::DERCodec::Base.encode_sequence(Slice(UInt8).join(signer_info_fields))

        # Build SET OF SignerInfo (tag 0x31 = SET | CONSTRUCTED)
        io = IO::Memory.new
        io.write_byte(0x31_u8) # SET | CONSTRUCTED
        length_bytes = Codec::DERCodec::Base.encode_length_bytes(signer_info_seq.size)
        io.write(length_bytes)
        io.write(signer_info_seq)
        signer_infos_set = io.to_slice

        # Build digestAlgorithms SET (tag 0x31)
        digest_alg_encoded = Codec::DERCodec::Base.encode(Codec::DERCodec::SHA256_CMS.call)
        io2 = IO::Memory.new
        io2.write_byte(0x31_u8) # SET | CONSTRUCTED
        length_bytes2 = Codec::DERCodec::Base.encode_length_bytes(digest_alg_encoded.size)
        io2.write(length_bytes2)
        io2.write(digest_alg_encoded)
        digest_algs_set = io2.to_slice

        # Build SignedData SEQUENCE in RFC 5652 order:
        # version, digestAlgorithms, encapContentInfo, signerInfos
        signed_data_fields = [] of Bytes
        signed_data_fields << Codec::DERCodec::Base.encode(3_u8)                                     # version
        signed_data_fields << digest_algs_set                                                        # digestAlgorithms SET
        signed_data_fields << Codec::DERCodec::Base.encode(Codec::DERCodec::Pkcs7Data.call(content)) # encapContentInfo
        signed_data_fields << signer_infos_set                                                       # signerInfos SET
        signed_data_seq = Codec::DERCodec::Base.encode_sequence(Slice(UInt8).join(signed_data_fields))

        # Wrap in PKCS#7 SignedData OID manually to avoid double-encoding
        # Structure: SEQUENCE { OID(pkcs7-signedData), [0] EXPLICIT <raw SignedData bytes> }

        # Build context tag [0] EXPLICIT (CONSTRUCTED) with raw SignedData bytes
        ctx_io = IO::Memory.new
        ctx_io.write_byte(0xA0_u8) # Context [0] | CONSTRUCTED
        ctx_length = Codec::DERCodec::Base.encode_length_bytes(signed_data_seq.size)
        ctx_io.write(ctx_length)
        ctx_io.write(signed_data_seq)
        context_tagged = ctx_io.to_slice

        # Build PKCS#7 OID
        pkcs7_oid = Codec::DERCodec::Base.encode(Codec::DERCodec::ObjectId.new("2a864886f70d010702").value)

        # Combine OID + context-tagged SignedData in a SEQUENCE
        Codec::DERCodec::Base.encode_sequence(Slice(UInt8).join([pkcs7_oid, context_tagged]))
      end
    end
  end
end
