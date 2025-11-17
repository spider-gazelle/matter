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
      private def self.build_cd_tlv(vendor_id : UInt16, product_id : UInt16) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Product ID array with proper type
        product_id_array = [product_id.as(TLV::Value)] of TLV::Value

        # Certification Declaration TLV structure
        data = {
          1_u8 => 1_u16,                 # formatVersion = 1
          2_u8 => vendor_id,             # vendorId
          3_u8 => product_id_array,      # productIdArray
          4_u8 => 22_u32,                # deviceTypeId = 22 (Root Node)
          5_u8 => "CSA00000SWC00000-00", # certificateId
          6_u8 => 0_u8,                  # securityLevel = 0
          7_u8 => 0_u16,                 # securityInformation = 0
          8_u8 => 1_u16,                 # versionNumber = 1
          9_u8 => 0_u8,                  # certificationType = 0 (development/test)
        } of TLV::Tag => TLV::Value

        writer.put(nil, data)
        io.rewind.to_slice
      end

      # Build PKCS#7 SignedData ASN.1 structure
      # Uses the DERCodec helpers for proper encoding
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

        # Build PKCS#7 SignedData structure
        # Based on RFC 5652 (CMS) and Matter spec requirements
        signer_info = {
          "version"            => 3_u8,                                                        # Signer info version 3
          "sid"                => Codec::DERCodec::ContextTaggedSlice.new(0, ski_bytes).value, # Subject Key ID
          "digestAlgorithm"    => Codec::DERCodec::SHA256_CMS.call,                            # SHA-256
          "signatureAlgorithm" => Codec::DERCodec::EcdsaWithSHA256_X962.call,                  # ECDSA with SHA-256
          "signature"          => signature,                                                   # ECDSA signature
        } of String => Codec::DERCodec::Value

        signer_infos = [signer_info.as(Codec::DERCodec::Value)] of Codec::DERCodec::Value

        signed_data = {
          "version"          => 3_u8,                                                         # CMS version 3
          "digestAlgorithms" => [Codec::DERCodec::SHA256_CMS.call] of Codec::DERCodec::Value, # SHA-256
          "encapContentInfo" => {
            "eContentType" => Codec::DERCodec::Pkcs7Data.call(content), # Encapsulated content
          } of String => Codec::DERCodec::Value,
          "signerInfos" => signer_infos,
        } of String => Codec::DERCodec::Value

        # Encode as DER
        pkcs7 = Codec::DERCodec::Pkcs7SignedData.call(signed_data)
        Codec::DERCodec::Base.encode(pkcs7)
      end
    end
  end
end
