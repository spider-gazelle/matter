require "../../crypto/crypto"
require "../../crypto/spake2p"
require "../context"
require "./definitions"

module Matter
  module Session
    module Pase
      Log = ::Log.for("matter.pase")

      # PBKDF parameters for PASE
      struct PbkdfParameters
        property iterations : Int32
        property salt : Bytes

        def initialize(@iterations : Int32, @salt : Bytes)
        end

        # Default parameters for testing
        def self.default
          new(
            iterations: 1000,
            salt: Crypto.random_bytes(32)
          )
        end
      end

      # PASE session establishment (initiator side - commissioner)
      class PaseCommissioner
        property pin_code : UInt32
        property pbkdf_params : PbkdfParameters?
        property spake : Crypto::Spake2p?
        property context : Bytes
        property crypto : Crypto::CryptoBase
        property w0_w1 : Crypto::Spake2p::W0W1?
        property p_a : Bytes?
        property secret_and_verifiers : Crypto::Spake2p::SecretAndVerifiers?

        def initialize(
          @pin_code : UInt32,
          @crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
          @context : Bytes = "CHIP PAKE V1 Commissioning".to_slice,
        )
          @w0_w1 = nil
          @p_a = nil
          @secret_and_verifiers = nil
        end

        # Step 1: Request PBKDF parameters from responder
        def create_pbkdf_param_request : Bytes
          # Create a TLV-encoded PBKDF parameter request
          # This can include optional initiator information
          request = Definitions::PbkdfParamRequest.new
          request.to_slice
        end

        # Step 2: Process PBKDF parameters from responder
        def process_pbkdf_param_response(response : Bytes)
          # Decode the TLV-encoded response to get PBKDF parameters
          resp = Definitions::PbkdfParamResponse.from_slice(response)

          # Extract iterations and salt from nested pbkdf_parameters
          if pbkdf_params = resp.pbkdf_parameters
            @pbkdf_params = PbkdfParameters.new(
              iterations: pbkdf_params.iterations.to_i32,
              salt: pbkdf_params.salt
            )

            # Compute w0 and w1 from PIN using PBKDF2
            @w0_w1 = Crypto::Spake2p.compute_w0_w1(@crypto,
              Crypto::Spake2p::PbkdfParameters.new(@pbkdf_params.not_nil!.iterations, @pbkdf_params.not_nil!.salt),
              @pin_code
            )

            # Create SPAKE2+ instance with w0
            @spake = Crypto::Spake2p.create(@crypto, @context, @w0_w1.not_nil!.w0)
          else
            raise "PBKDF parameters not found in response"
          end
        end

        # Step 3: Generate pA (our public value)
        def generate_pake1 : Bytes
          spake = @spake
          raise "SPAKE2+ not initialized" if spake.nil?

          # Compute X (commissioner/prover's public value)
          @p_a = spake.compute_x
          @p_a.not_nil!
        end

        # Step 4: Process pB (responder's public value) and compute confirmation
        def process_pake2(p_b : Bytes) : Bytes
          spake = @spake
          w0_w1 = @w0_w1
          p_a = @p_a
          raise "SPAKE2+ not initialized" if spake.nil? || w0_w1.nil? || p_a.nil?

          # Compute shared secret and verifiers from Y (responder's public value)
          # This returns ke (shared secret), h_ay, and h_bx
          @secret_and_verifiers = spake.compute_secret_and_verifiers_from_y(
            w0_w1.w1,
            p_a,
            p_b
          )

          # Return our confirmation value (h_ay)
          @secret_and_verifiers.not_nil!.h_ay
        end

        # Step 5: Verify responder's confirmation
        def process_pake3(confirmation : Bytes) : Bool
          sav = @secret_and_verifiers
          raise "Shared secret not computed" if sav.nil?

          # Verify that the responder's confirmation matches our computed h_bx
          confirmation == sav.h_bx
        end

        # Derive session keys after successful PASE
        def derive_session_keys : {encryption: Bytes, decryption: Bytes, attestation_challenge: Bytes}
          sav = @secret_and_verifiers
          raise "Shared secret not computed" if sav.nil?

          # Derive session keys from shared secret (ke) using HKDF
          # Per matter.js: SessionKeys = HKDF(ke, salt="", info="SessionKeys", length=48)
          # Returns 48 bytes: I2R (0-15) | R2I (16-31) | AttestationChallenge (32-47)
          session_keys = @crypto.create_hkdf_key(
            sav.ke,
            Bytes.new(0), # Empty salt
            "SessionKeys".to_slice,
            48 # Derive 48 bytes: I2R + R2I + AttestationChallenge
          )

          # Split keys - initiator (commissioner) uses:
          # - I2R (bytes 0-15) for encryption (initiator-to-responder)
          # - R2I (bytes 16-31) for decryption (responder-to-initiator)
          # - AttestationChallenge (bytes 32-47) for attestation signature verification
          {
            encryption:            session_keys[0, 16],  # I2R key
            decryption:            session_keys[16, 16], # R2I key
            attestation_challenge: session_keys[32, 16], # AttestationChallenge
          }
        end
      end

      # PASE session establishment (responder side - device)
      class PaseResponder
        property pin_code : UInt32
        property pbkdf_params : PbkdfParameters
        property spake : Crypto::Spake2p?
        property context : Bytes
        property crypto : Crypto::CryptoBase
        property w0_l : Crypto::Spake2p::W0L?
        property p_b : Bytes?
        property secret_and_verifiers : Crypto::Spake2p::SecretAndVerifiers?

        def initialize(
          @pin_code : UInt32,
          @pbkdf_params : PbkdfParameters = PbkdfParameters.default,
          @crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
          @context : Bytes = "CHIP PAKE V1 Commissioning".to_slice,
        )
          @w0_l = nil
          @p_b = nil
          @secret_and_verifiers = nil
        end

        # Step 1: Process PBKDF parameter request and return parameters
        def process_pbkdf_param_request(request : Bytes) : Bytes
          # Parse the TLV-encoded request (if not empty)
          initiator_random = if request.size > 0
                               req = Definitions::PbkdfParamRequest.from_slice(request)
                               req.initiator_random || Random::Secure.random_bytes(32)
                             else
                               Random::Secure.random_bytes(32)
                             end

          # Generate responder random
          responder_random = Random::Secure.random_bytes(32)
          responder_session_id = Random::Secure.rand(UInt16)

          # Create and encode the PBKDF parameter response
          response = Definitions::PbkdfParamResponse.new(
            initiator_random: initiator_random,
            responder_random: responder_random,
            responder_session_id: responder_session_id,
            iterations: @pbkdf_params.iterations.to_u32,
            salt: @pbkdf_params.salt
          )
          response.to_slice
        end

        # Step 2: Initialize SPAKE2+ with w0 and L
        def initialize_spake
          # Compute w0 and L from PIN using PBKDF2
          @w0_l = Crypto::Spake2p.compute_w0_l(@crypto,
            Crypto::Spake2p::PbkdfParameters.new(@pbkdf_params.iterations, @pbkdf_params.salt),
            @pin_code
          )

          # Create SPAKE2+ instance with w0
          @spake = Crypto::Spake2p.create(@crypto, @context, @w0_l.not_nil!.w0)
        end

        # Step 3: Process pA (initiator's public value) and generate pB
        def process_pake1(p_a : Bytes) : Bytes
          Log.debug { "PaseResponder: Processing Pake1 (pA bytes=#{p_a.size})" }
          Log.trace { "pA (first 16 bytes): #{p_a[0, [16, p_a.size].min].hexstring}" }

          initialize_spake unless @spake

          spake = @spake
          w0_l = @w0_l
          raise "SPAKE2+ not initialized" if spake.nil? || w0_l.nil?

          # Compute Y (responder/verifier's public value)
          @p_b = spake.compute_y
          Log.debug { "Generated pB (bytes=#{@p_b.not_nil!.size})" }
          Log.trace { "pB (first 16 bytes): #{@p_b.not_nil![0, 16].hexstring}" }

          # Compute shared secret and verifiers from X (initiator's public value)
          @secret_and_verifiers = spake.compute_secret_and_verifiers_from_x(
            w0_l.l,
            p_a,
            @p_b.not_nil!
          )

          Log.trace do
            sav = @secret_and_verifiers.not_nil!
            "Computed shared secret and confirmations (ke_bytes=#{sav.ke.size}, h_ay_bytes=#{sav.h_ay.size}, h_bx_bytes=#{sav.h_bx.size})"
          end

          @p_b.not_nil!
        end

        # Step 4: Generate confirmation value
        def generate_pake3 : Bytes
          sav = @secret_and_verifiers
          raise "Shared secret not computed" if sav.nil?

          # Return our confirmation value (h_bx)
          sav.h_bx
        end

        # Derive session keys after successful PASE
        def derive_session_keys : {encryption: Bytes, decryption: Bytes, attestation_challenge: Bytes}
          sav = @secret_and_verifiers
          raise "Shared secret not computed" if sav.nil?

          # Derive session keys from shared secret (ke) using HKDF
          # Per matter.js: SessionKeys = HKDF(ke, salt="", info="SessionKeys", length=48)
          # Returns 48 bytes: I2R (0-15) | R2I (16-31) | AttestationChallenge (32-47)
          session_keys = @crypto.create_hkdf_key(
            sav.ke,
            Bytes.new(0), # Empty salt
            "SessionKeys".to_slice,
            48 # Derive 48 bytes: I2R + R2I + AttestationChallenge
          )
          Log.trace { "Derived SessionKeys via HKDF (bytes=#{session_keys.size})" }

          # Split keys - responder uses:
          # - R2I (bytes 16-31) for encryption (responder-to-initiator)
          # - I2R (bytes 0-15) for decryption (initiator-to-responder)
          # - AttestationChallenge (bytes 32-47) for attestation signature generation
          {
            encryption:            session_keys[16, 16], # R2I key
            decryption:            session_keys[0, 16],  # I2R key
            attestation_challenge: session_keys[32, 16], # AttestationChallenge
          }
        end
      end

      # Helper to establish a PASE session (simplified)
      def self.establish_session(
        pin_code : UInt32,
        initiator_session_id : UInt16,
        responder_session_id : UInt16,
        crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
      ) : {initiator: SecureContext, responder: SecureContext}
        # Create commissioner and responder
        pbkdf_params = PbkdfParameters.default
        commissioner = PaseCommissioner.new(pin_code, crypto)
        responder = PaseResponder.new(pin_code, pbkdf_params, crypto)

        # Simulate PASE handshake
        # 1. Commissioner requests PBKDF params
        request = commissioner.create_pbkdf_param_request
        response = responder.process_pbkdf_param_request(request)

        # 2. Commissioner processes params (decoded from response) and generates pA
        commissioner.process_pbkdf_param_response(response)
        p_a = commissioner.generate_pake1

        # 3. Responder processes pA and generates pB
        p_b = responder.process_pake1(p_a)

        # 4. Commissioner processes pB
        commissioner.process_pake2(p_b)

        # 5. Responder generates confirmation
        confirmation = responder.generate_pake3

        # 6. Commissioner verifies confirmation
        unless commissioner.process_pake3(confirmation)
          raise "PASE confirmation failed"
        end

        # 7. Derive session keys
        commissioner_keys = commissioner.derive_session_keys
        responder_keys = responder.derive_session_keys

        # Create session contexts
        # Note: In real implementation, keys would match (i2r and r2i)
        initiator_context = SecureContext.new(
          session_id: initiator_session_id,
          peer_session_id: responder_session_id,
          session_type: SessionType::Unicast,
          encryption_key: commissioner_keys[:encryption],
          decryption_key: commissioner_keys[:decryption],
          is_initiator: true
        )

        responder_context = SecureContext.new(
          session_id: responder_session_id,
          peer_session_id: initiator_session_id,
          session_type: SessionType::Unicast,
          encryption_key: responder_keys[:encryption],
          decryption_key: responder_keys[:decryption],
          is_initiator: false
        )

        {initiator: initiator_context, responder: responder_context}
      end
    end
  end
end
