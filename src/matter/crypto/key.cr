require "openssl"
require "openssl_ext"
require "base64"

module Matter
  module Crypto
    # ECDSA P-256 constants (prime256v1)
    CRYPTO_EC_CURVE        = "prime256v1"
    CRYPTO_EC_KEY_BYTES    = 32
    CRYPTO_AUTH_TAG_LENGTH = 16

    enum KeyType
      EC
      RSA
      Oct
    end

    enum CurveType
      P256 = 1
      P384
      P521
    end

    # Binary key pair structure
    struct BinaryKeyPair
      property public_key : Bytes
      property private_key : Bytes

      def initialize(@public_key, @private_key)
      end
    end

    # Represents a cryptographic key
    # Models keys similar to JSON Web Key (JWK) format for compatibility
    class Key
      property type : KeyType
      property curve : CurveType?
      property algorithm : String?
      property operations : Array(String)?
      property extractable : Bool

      # Private key material (d in JWK)
      @private_bits : Bytes?
      # Public key x coordinate
      @x_bits : Bytes?
      # Public key y coordinate
      @y_bits : Bytes?

      def initialize(
        @type : KeyType = KeyType::EC,
        @curve : CurveType? = CurveType::P256,
        @extractable : Bool = true,
      )
        @operations = ["sign", "verify"]
      end

      # Get/set private key bytes
      def private_bits : Bytes?
        @private_bits
      end

      def private_bits=(value : Bytes?)
        @private_bits = value
        # If we have a private key and EC type, compute public key
        derive_public_from_private if value && @type == KeyType::EC && !@x_bits
      end

      # Get/set public key x coordinate
      def x_bits : Bytes?
        @x_bits
      end

      def x_bits=(value : Bytes?)
        @x_bits = value
      end

      # Get/set public key y coordinate
      def y_bits : Bytes?
        @y_bits
      end

      def y_bits=(value : Bytes?)
        @y_bits = value
      end

      # Import/export public key in SEC1/SPKI format (0x04 || x || y)
      def public_bits : Bytes?
        return nil unless @x_bits && @y_bits

        io = IO::Memory.new
        io.write_byte(0x04_u8) # Uncompressed point indicator
        io.write(@x_bits.not_nil!)
        io.write(@y_bits.not_nil!)
        io.to_slice
      end

      def public_bits=(value : Bytes)
        return if value.size.even?

        case value[0]
        when 0x02, 0x03
          raise ArgumentError.new("Unsupported public key compression")
        when 0x04
          # Uncompressed format
        when 0x05
          raise ArgumentError.new("Illegal public key format specifier")
        else
          raise ArgumentError.new("Invalid public key format")
        end

        coordinate_length = (value.size - 1) // 2
        infer_curve(coordinate_length)

        @type = KeyType::EC
        @x_bits = value[1, coordinate_length]
        @y_bits = value[coordinate_length + 1, coordinate_length]
      end

      # Import/export key pair
      def key_pair_bits : BinaryKeyPair?
        pub = public_bits
        priv = @private_bits
        return nil unless pub && priv

        BinaryKeyPair.new(pub, priv)
      end

      def key_pair_bits=(pair : BinaryKeyPair)
        self.public_bits = pair.public_key
        self.private_bits = pair.private_key
      end

      # Asserted accessors that raise if not present
      def public_key : Bytes
        public_bits || raise ArgumentError.new("Public key not defined")
      end

      def private_key : Bytes
        @private_bits || raise ArgumentError.new("Private key not defined")
      end

      def key_pair : BinaryKeyPair
        key_pair_bits || raise ArgumentError.new("Complete key pair not defined")
      end

      # Import PKCS#8 private key
      def import_pkcs8(data : Bytes)
        # PKCS#8 is a DER-encoded format
        # Try to load it via PEM format
        pem = "-----BEGIN PRIVATE KEY-----\n"
        pem += Base64.strict_encode(data).scan(/.{1,64}/).map(&.[0]).join("\n")
        pem += "\n-----END PRIVATE KEY-----\n"

        pkey = OpenSSL::PKey::EC.new(pem)

        @type = KeyType::EC
        @curve = CurveType::P256 # Assume P-256 for Matter

        # Get the SEC1 format from the loaded key
        io = IO::Memory.new
        pkey.to_der(io)
        sec1_der = io.to_slice

        # Extract private key and public key using our extraction methods
        @private_bits = Key.extract_private_key_from_der(sec1_der)

        # Get public key
        pub_io = IO::Memory.new
        pkey.public_key.to_der(pub_io)
        pub_der = pub_io.to_slice
        self.public_bits = Key.extract_public_key_from_der(pub_der)
      end

      # Import SPKI public key
      def import_spki(data : Bytes)
        # SPKI is a DER-encoded format
        # Convert to PEM and load
        pem = "-----BEGIN PUBLIC KEY-----\n"
        pem += Base64.strict_encode(data).scan(/.{1,64}/).map(&.[0]).join("\n")
        pem += "\n-----END PUBLIC KEY-----\n"

        pkey = OpenSSL::PKey::EC.new(pem)

        @type = KeyType::EC
        @curve = CurveType::P256

        # Get public key DER
        pub_io = IO::Memory.new
        pkey.to_der(pub_io)
        pub_der = pub_io.to_slice

        # Extract uncompressed public key bytes
        self.public_bits = Key.extract_public_key_from_der(pub_der)
      end

      # Import SEC1 private key
      def import_sec1(data : Bytes)
        # SEC1 is a DER-encoded EC private key format
        # Convert to PEM and load
        pem = "-----BEGIN EC PRIVATE KEY-----\n"
        pem += Base64.strict_encode(data).scan(/.{1,64}/).map(&.[0]).join("\n")
        pem += "\n-----END EC PRIVATE KEY-----\n"

        pkey = OpenSSL::PKey::EC.new(pem)

        @type = KeyType::EC
        @curve = CurveType::P256

        # Extract private key bytes using our extraction method
        io = IO::Memory.new
        pkey.to_der(io)
        priv_der = io.to_slice
        @private_bits = Key.extract_private_key_from_der(priv_der)

        # Get public key
        pub_io = IO::Memory.new
        pkey.public_key.to_der(pub_io)
        pub_der = pub_io.to_slice
        self.public_bits = Key.extract_public_key_from_der(pub_der)
      end

      # Generate a random EC key pair
      def self.generate_key_pair : Key
        pkey = OpenSSL::PKey::EC.generate_by_curve_name(CRYPTO_EC_CURVE)

        key = new(KeyType::EC, CurveType::P256)

        # Get private key DER
        priv_io = IO::Memory.new
        pkey.to_der(priv_io)
        priv_der = priv_io.to_slice

        # Get public key DER
        pub_pkey = pkey.public_key
        pub_io = IO::Memory.new
        pub_pkey.to_der(pub_io)
        pub_der = pub_io.to_slice

        # Extract raw key material from DER
        key.private_bits = extract_private_key_from_der(priv_der)
        key.public_bits = extract_public_key_from_der(pub_der)

        key
      end

      # Extract 32-byte private key from DER format
      # TODO: Make private after testing
      def self.extract_private_key_from_der(der : Bytes) : Bytes
        # EC private key DER format has the 32-byte key embedded as an OCTET STRING
        # Look for tag 0x04 (OCTET STRING) followed by length 0x20 (32 bytes)
        # Format: ... 04 20 [32 bytes of private key] ...
        (0...der.size - 2).each do |i|
          if der[i] == 0x04 && der[i + 1] == 0x20 && i + 2 + CRYPTO_EC_KEY_BYTES <= der.size
            return der[i + 2, CRYPTO_EC_KEY_BYTES]
          end
        end

        # Fallback for unexpected format
        raise ArgumentError.new("Could not find private key in DER format")
      end

      # Extract 65-byte uncompressed public key from DER format
      # TODO: Make private after testing
      def self.extract_public_key_from_der(der : Bytes) : Bytes
        # Public key DER format has the 65-byte uncompressed key (0x04 || x || y) at the end
        # Scan backwards for 0x04 marker
        (der.size - 65).downto(0) do |i|
          if der[i] == 0x04 && i + 65 <= der.size
            return der[i, 65]
          end
        end

        # Fallback
        if der.size >= 65
          der[der.size - 65, 65]
        else
          raise ArgumentError.new("Invalid DER public key size")
        end
      end

      # Compute shared secret for Diffie-Hellman
      def self.compute_shared_secret(private_key : Key, peer_public_key : Key) : Bytes
        # Use OpenSSL ECDH
        ec_key = OpenSSL::PKey::EC.generate(CRYPTO_EC_CURVE)

        # Build PEM format for the keys
        # This is a simplified implementation - production code should use proper DER encoding
        raise NotImplementedError.new("ECDH shared secret computation - needs OpenSSL bindings")
      end

      private def infer_curve(bytes : Int32)
        return if @curve

        @curve = case bytes
                 when 66 then CurveType::P521
                 when 48 then CurveType::P384
                 when 32 then CurveType::P256
                 else
                   raise ArgumentError.new("Cannot infer curve from key length #{bytes}")
                 end
      end

      private def derive_public_from_private
        return unless @type == KeyType::EC
        return unless priv = @private_bits
        return if @x_bits && @y_bits

        # For now, mark as not implemented
        # Full implementation would require reconstructing EC key from raw bytes
        # which is non-trivial with the current OpenSSL bindings
        Log.warn { "Public key derivation from private key not yet fully implemented" }
      rescue e
        Log.warn { "Could not derive public key from private: #{e.message}" }
      end
    end

    # Factory methods for convenience
    def self.private_key(private_key : Bytes | BinaryKeyPair, extractable : Bool = true) : Key
      key = Key.new(KeyType::EC, CurveType::P256, extractable: extractable)

      if private_key.is_a?(BinaryKeyPair)
        key.private_bits = private_key.private_key
        key.public_bits = private_key.public_key
      else
        key.private_bits = private_key
      end

      key
    end

    def self.public_key(public_key : Bytes, extractable : Bool = true) : Key
      key = Key.new(KeyType::EC, CurveType::P256, extractable: extractable)
      key.public_bits = public_key
      key
    end

    def self.symmetric_key(key_bytes : Bytes, extractable : Bool = true) : Key
      key = Key.new(KeyType::Oct, extractable: extractable)
      key.private_bits = key_bytes
      key
    end
  end
end
