require "openssl"
require "../crypto/crypto"
require "../crypto/key"
require "./chip_paa_authorities"

# Additional LibCrypto bindings for custom OID support
lib LibCrypto
  # openssl_ext's X509V3_CTX predates OpenSSL 3's issuer_pkey member.
  # Keep the complete ABI layout here until the shard updates its binding.
  struct MatterX509V3Context
    flags : Int32
    issuer_cert : Void*
    subject_cert : Void*
    subject_req : Void*
    crl : Void*
    db_meth : Void*
    db : Void*
    {% if compare_versions(LibCrypto::OPENSSL_VERSION, "3.0.0") >= 0 %}
      issuer_pkey : Void*
    {% end %}
  end

  fun x509_name_add_entry_by_obj = X509_NAME_add_entry_by_OBJ(name : LibCrypto::X509_NAME, obj : LibCrypto::ASN1_OBJECT, type : Int32, bytes : UInt8*, len : Int32, loc : Int32, set : Int32) : Int32
end

module Matter
  module Certificate
    # Manages generation of attestation certificates (PAA, PAI, DAC)
    # Based on matter.js AttestationCertificateManager
    #
    # Creates a complete attestation certificate chain for testing:
    # - PAA (Product Attestation Authority) - self-signed root CA
    # - PAI (Product Attestation Intermediate) - intermediate CA
    # - DAC (Device Attestation Certificate) - device certificate
    class AttestationCertificateManager
      Log = ::Log.for("matter.certificate.attestation_certificate_manager")

      # PAA key pair (persisted across instances for same vendor)
      getter paa_key_pair : Crypto::Key

      # PAI key pair (persisted across instances)
      getter pai_key_pair : Crypto::Key

      # PAA certificate (DER encoded)
      getter paa_cert : Bytes

      # PAI certificate (DER encoded)
      getter pai_cert : Bytes

      # Vendor ID for this certificate chain
      getter vendor_id : UInt16

      # Product ID (optional, for PAI scoping)
      getter product_id : UInt16?

      # Certificate serial number counter
      @next_cert_id : UInt64

      def initialize(@vendor_id : UInt16, @product_id : UInt16? = nil)
        @next_cert_id = 1_u64

        # Use official Matter Test PAA (pre-loaded in chip-tool's trust store)
        # We cannot generate our own PAA because chip-tool only trusts the official test PAAs
        @paa_key_pair = Crypto::Key.new(Crypto::KeyType::EC, Crypto::CurveType::P256)
        @paa_key_pair.private_bits = ChipPAAuthorities::TEST_CERT_PAA_NO_VID_PRIVATE_KEY
        @paa_key_pair.public_bits = ChipPAAuthorities::TEST_CERT_PAA_NO_VID_PUBLIC_KEY
        @paa_cert = ChipPAAuthorities::TEST_CERT_PAA_NO_VID_CERT

        # Generate PAI (intermediate CA)
        @pai_key_pair = Crypto::Key.generate_key_pair
        @pai_cert = generate_pai_certificate(@pai_key_pair, @vendor_id, @product_id)
      end

      # Get PAI certificate
      def pai_cert : Bytes
        @pai_cert
      end

      # Generate DAC for a specific product
      # Returns both the certificate and the key pair
      def get_dac_cert(product_id : UInt16) : {Bytes, Crypto::Key}
        dac_key_pair = Crypto::Key.generate_key_pair
        Log.debug { "Generated DAC key pair" }
        Log.trace { "DAC public key (65 bytes): #{dac_key_pair.public_key.hexstring}" }
        dac_cert = generate_dac_certificate(dac_key_pair, @vendor_id, product_id)
        Log.debug { "Generated DAC certificate: #{dac_cert.size} bytes" }
        {dac_cert, dac_key_pair}
      end

      private def generate_pai_certificate(key : Crypto::Key, vendor_id : UInt16, product_id : UInt16?) : Bytes
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = OpenSSL::BN.new(@next_cert_id)
        @next_cert_id += 1

        # Validity period
        cert.not_before = OpenSSL::ASN1::Time.days_from_now(-365)    # 1 year ago
        cert.not_after = OpenSSL::ASN1::Time.days_from_now(365 * 10) # 10 years from now

        # Issuer = PAA
        cert.issuer = build_subject_name("Matter Test PAA")

        # Subject with vendor ID (PAI should NOT include productId - it's reusable across products)
        cn = "Matter Test PAI 0x#{vendor_id.to_s(16).upcase}"
        cert.subject = build_subject_name(cn, vendor_id, nil)

        # Public key
        cert.public_key = build_ec_public_key(key.public_key)

        # Extensions
        # Basic Constraints: CA=TRUE, pathlen=0 (critical)
        cert.add_extension(create_extension("basicConstraints", "critical,CA:TRUE,pathlen:0"))

        # Key Usage: keyCertSign, cRLSign (critical)
        cert.add_extension(create_extension("keyUsage", "critical,keyCertSign,cRLSign"))

        add_key_identifiers(cert, OpenSSL::X509::Certificate.from_der(@paa_cert))

        # Note: Matter vendor/product IDs are automatically added as subject DN attributes
        # by build_subject_name() using custom OID entries per Matter spec section 6.3.5:
        # - VendorId: 1.3.6.1.4.1.37244.2.1 (encoded as 4-char hex string)
        # - ProductId: 1.3.6.1.4.1.37244.2.2 (encoded as 4-char hex string)

        # Sign with PAA private key
        paa_private_key = build_ec_private_key(@paa_key_pair.private_key)
        cert.sign(paa_private_key, OpenSSL::Digest.new("SHA256"))

        cert.to_der
      end

      private def generate_dac_certificate(key : Crypto::Key, vendor_id : UInt16, product_id : UInt16) : Bytes
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = OpenSSL::BN.new(@next_cert_id)
        @next_cert_id += 1

        # Validity period
        cert.not_before = OpenSSL::ASN1::Time.days_from_now(-365)    # 1 year ago
        cert.not_after = OpenSSL::ASN1::Time.days_from_now(365 * 10) # 10 years from now

        # Issuer = PAI (PAI never includes productId in its subject)
        pai_cn = "Matter Test PAI 0x#{vendor_id.to_s(16).upcase}"
        cert.issuer = build_subject_name(pai_cn, vendor_id, nil)

        # Subject with vendor ID and product ID
        cn = "Matter Test DAC 0x#{vendor_id.to_s(16).upcase}/0x#{product_id.to_s(16).upcase}"
        cert.subject = build_subject_name(cn, vendor_id, product_id)

        # Public key
        cert.public_key = build_ec_public_key(key.public_key)

        # Extensions
        # Basic Constraints: CA=FALSE (critical)
        cert.add_extension(create_extension("basicConstraints", "critical,CA:FALSE"))

        # Key Usage: digitalSignature (critical)
        cert.add_extension(create_extension("keyUsage", "critical,digitalSignature"))

        add_key_identifiers(cert, OpenSSL::X509::Certificate.from_der(@pai_cert))

        # Note: Matter vendor/product IDs are automatically added as subject DN attributes
        # by build_subject_name() using custom OID entries per Matter spec section 6.3.5:
        # - VendorId: 1.3.6.1.4.1.37244.2.1 (encoded as 4-char hex string)
        # - ProductId: 1.3.6.1.4.1.37244.2.2 (encoded as 4-char hex string)

        # Sign with PAI private key
        pai_private_key = build_ec_private_key(@pai_key_pair.private_key)
        cert.sign(pai_private_key, OpenSSL::Digest.new("SHA256"))

        cert.to_der
      end

      # Build X.509 Name (subject/issuer) with Matter-specific DN attributes
      # Per Matter spec section 6.3.5, vendor/product IDs are encoded as:
      # - UTF8String or PrintableString
      # - Uppercase hex, zero-padded to exactly 4 characters (2 octets * 2)
      # - Added as custom OID attributes in subject DN
      private def build_subject_name(cn : String, vendor_id : UInt16? = nil, product_id : UInt16? = nil) : OpenSSL::X509::Name
        name = OpenSSL::X509::Name.new
        name.add_entry("CN", cn)

        # Add Matter-specific OID attributes if provided
        if vendor_id
          # VendorId OID: 1.3.6.1.4.1.37244.2.1
          # Encode as 4-character uppercase hex string
          vid_str = Hex.u16_upper(vendor_id)
          add_custom_oid_entry(name, "1.3.6.1.4.1.37244.2.1", vid_str)
        end

        if product_id
          # ProductId OID: 1.3.6.1.4.1.37244.2.2
          # Encode as 4-character uppercase hex string
          pid_str = Hex.u16_upper(product_id)
          add_custom_oid_entry(name, "1.3.6.1.4.1.37244.2.2", pid_str)
        end

        name
      end

      # Add a custom OID entry to an X509::Name using low-level LibSSL API
      # This is needed because OpenSSL's high-level API doesn't support custom OIDs
      private def add_custom_oid_entry(name : OpenSSL::X509::Name, oid : String, value : String)
        # Create ASN1_OBJECT from OID string
        obj = LibCrypto.obj_txt2obj(oid, 0)
        raise Matter::CertificateError.new("Failed to create ASN1_OBJECT for OID #{oid}") if obj.null?

        # Add entry to X509_NAME with UTF8String encoding
        # MBSTRING_UTF8 = 0x1000 | 0x0001 = 0x1001
        ret = LibCrypto.x509_name_add_entry_by_obj(
          name.to_unsafe,
          obj,
          LibCrypto::MBSTRING_UTF8,
          value.to_unsafe,
          value.bytesize,
          -1, # location (-1 = append)
          0   # set (0 = new RDN)
        )

        # Free the ASN1_OBJECT
        LibCrypto.asn1_object_free(obj)

        raise Matter::CertificateError.new("Failed to add OID entry to X509_NAME") if ret == 0
      end

      # Create OpenSSL extension
      private def create_extension(name : String, value : String) : OpenSSL::X509::Extension
        OpenSSL::X509::Extension.new(name, value)
      end

      private def add_key_identifiers(cert : OpenSSL::X509::Certificate, issuer : OpenSSL::X509::Certificate) : Nil
        context = LibCrypto::MatterX509V3Context.new
        context_pointer = pointerof(context).as(LibCrypto::X509V3_CTX*)
        LibCrypto.x509v3_set_ctx(context_pointer, issuer, cert, nil, nil, 0)
        { {"subjectKeyIdentifier", "hash"}, {"authorityKeyIdentifier", "keyid:always"} }.each do |name, value|
          nid = LibCrypto.obj_sn2nid(name)
          extension = LibCrypto.x509v3_ext_conf_nid(nil, context_pointer, nid, value)
          raise Matter::CertificateError.new("Failed to create #{name} extension") if extension.null?
          begin
            cert.add_extension(OpenSSL::X509::Extension.new(extension))
          ensure
            LibCrypto.x509_extension_free(extension)
          end
        end
      end

      # Build EC public key from raw bytes
      private def build_ec_public_key(public_key_bytes : Bytes) : OpenSSL::PKey::EC
        OpenSSL::PKey::EC.from_public_bytes(public_key_bytes, Crypto::CRYPTO_EC_CURVE_NIST)
      end

      # Build EC private key from raw bytes
      private def build_ec_private_key(private_key_bytes : Bytes) : OpenSSL::PKey::EC
        OpenSSL::PKey::EC.from_private_bytes(private_key_bytes, Crypto::CRYPTO_EC_CURVE_NIST)
      end
    end
  end
end
