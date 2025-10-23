require "openssl"
require "openssl_ext"
require "spake2_plus"

module Matter
  module Crypto
    # SPAKE2+ implementation for Matter protocol
    # Based on https://datatracker.ietf.org/doc/html/draft-bar-cfrg-spake2plus
    #
    # SPAKE2+ is a password-authenticated key exchange protocol used during Matter commissioning
    # This is a wrapper around the spake2_plus library configured for Matter's requirements
    class Spake2p
      # Delegate to the underlying SPAKE2Plus::Protocol instance
      @protocol : SPAKE2Plus::Protocol
      # M and N constants for P-256 curve
      # From SPAKE2+ specification
      M_HEX = "02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f"
      N_HEX = "03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49"

      CRYPTO_GROUP_SIZE_BYTES = 32
      CRYPTO_W_SIZE_BYTES     = CRYPTO_GROUP_SIZE_BYTES + 8 # 40 bytes

      struct PbkdfParameters
        property iterations : Int32
        property salt : Bytes

        def initialize(@iterations, @salt)
        end
      end

      struct W0L
        property w0 : BigInt
        property l : Bytes

        def initialize(@w0, @l)
        end
      end

      struct W0W1
        property w0 : BigInt
        property w1 : BigInt

        def initialize(@w0, @w1)
        end
      end

      struct SecretAndVerifiers
        property ke : Bytes
        property h_ay : Bytes
        property h_bx : Bytes

        def initialize(@ke, @h_ay, @h_bx)
        end
      end

      getter context : Bytes
      getter random : BigInt
      getter w0 : BigInt

      # Compute w0 and w1 from PIN using PBKDF2
      def self.compute_w0_w1(crypto : CryptoBase, params : PbkdfParameters, pin : UInt32) : W0W1
        # Encode PIN as little-endian 32-bit integer
        pin_bytes = IO::Memory.new
        pin_bytes.write_bytes(pin, IO::ByteFormat::LittleEndian)

        # Derive 80 bytes using PBKDF2
        ws = crypto.create_pbkdf2_key(
          pin_bytes.to_slice,
          params.salt,
          params.iterations,
          CRYPTO_W_SIZE_BYTES * 2
        )

        # Split into w0 and w1 and reduce modulo curve order
        w0_bytes = ws[0, 40]
        w1_bytes = ws[40, 40]

        # Convert to BigInt and reduce modulo P-256 curve order
        # P-256 order: 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
        curve_order = BigInt.new("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", 16)

        w0 = BigInt.new(w0_bytes.hexstring, 16) % curve_order
        w1 = BigInt.new(w1_bytes.hexstring, 16) % curve_order

        W0W1.new(w0, w1)
      end

      # Compute w0 and L from PIN
      # L = w1 * G (where G is the generator point)
      def self.compute_w0_l(crypto : CryptoBase, params : PbkdfParameters, pin : UInt32) : W0L
        w0_w1 = compute_w0_w1(crypto, params, pin)

        # Compute L = w1 * G using the SPAKE2Plus library
        algorithm = SPAKE2Plus::MATTER_DEFAULT
        l = algorithm.generator_point.mul(w0_w1.w1).to_slice

        W0L.new(w0_w1.w0, l)
      end

      # Create SPAKE2+ instance with context and w0
      def self.create(crypto : CryptoBase, context : Bytes, w0 : BigInt) : Spake2p
        # Create using the SPAKE2Plus library with Matter defaults (P256 + SHA256 + HMAC)
        protocol = SPAKE2Plus.new(context, w0, SPAKE2Plus::MATTER_DEFAULT)
        new(protocol)
      end

      # Constructor for integration with SPAKE2Plus library
      def initialize(@protocol : SPAKE2Plus::Protocol)
      end

      # Alternative constructor for testing with specific random values
      # This allows test vectors to specify exact random values for reproducibility
      def initialize(crypto : CryptoBase, context : Bytes, random : BigInt, w0 : BigInt)
        algorithm = SPAKE2Plus::MATTER_DEFAULT
        @protocol = SPAKE2Plus::Protocol.new(algorithm, context, random, w0)
      end

      # Expose protocol properties
      getter context : Bytes { @protocol.context }
      getter random : BigInt { @protocol.random }
      getter w0 : BigInt { @protocol.w0 }

      # Compute X = x*G + w0*M (prover computes this)
      def compute_x : Bytes
        @protocol.compute_x
      end

      # Compute Y = y*G + w0*N (verifier computes this)
      def compute_y : Bytes
        @protocol.compute_y
      end

      # Compute shared secret and verifiers from Y (prover side)
      def compute_secret_and_verifiers_from_y(w1 : BigInt, x : Bytes, y : Bytes) : SecretAndVerifiers
        ke, h_ay, h_bx = @protocol.compute_secret_and_verifiers_from_y(w1, x, y)
        SecretAndVerifiers.new(ke, h_ay, h_bx)
      end

      # Compute shared secret and verifiers from X (verifier side)
      def compute_secret_and_verifiers_from_x(l : Bytes, x : Bytes, y : Bytes) : SecretAndVerifiers
        ke, h_ay, h_bx = @protocol.compute_secret_and_verifiers_from_x(l, x, y)
        SecretAndVerifiers.new(ke, h_ay, h_bx)
      end
    end
  end
end
