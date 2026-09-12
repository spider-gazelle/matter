require "./certificate"
require "./certificate_asn1"
require "./crypto"
require "./key"

module Matter
  module Crypto
    struct MatterCertificate
      # Operational certificate chain validation.
      #
      # A CASE peer proving it holds the private key of the certificate it
      # presents says nothing about who issued that certificate. Without this,
      # any member of a fabric can mint a certificate naming any node id or
      # CASE authenticated tag and inherit the access control entries written
      # for it.
      module Validation
        extend self

        # Extensions of a Matter certificate, tag 10
        private ISSUER_KEY_IDENTIFIER  = Asn1::Extension::AuthorityKeyIdentifier.value
        private SUBJECT_KEY_IDENTIFIER = Asn1::Extension::SubjectKeyIdentifier.value
        private BASIC_CONSTRAINTS      = Asn1::Extension::BasicConstraints.value

        # Verify `certificate` against the public key of whoever issued it.
        # Raises `Matter::AuthenticationError` when it does not hold.
        def verify_signature(certificate : Bytes, issuer_public_key : Bytes) : Nil
          parsed = parse(certificate)
          signature = signature_of(parsed)
          transcript = Asn1.to_unsigned_asn1(parsed)

          key = Key.new(KeyType::EC, CurveType::P256)
          key.public_bits = issuer_public_key

          Crypto.verify_ecdsa(key, transcript, signature)
        rescue ex : Matter::AuthenticationError
          raise ex
        rescue ex
          raise Matter::AuthenticationError.new("Certificate signature could not be checked: #{ex.message}", cause: ex)
        end

        # Verify that `noc` was issued by the holder of `root_public_key`,
        # through `icac` when the peer presented one. Raises
        # `Matter::AuthenticationError` on the first link that does not hold.
        def verify_chain(noc : Bytes, icac : Bytes?, root_public_key : Bytes) : Nil
          if icac
            unless certificate_authority?(icac)
              raise Matter::AuthenticationError.new("Intermediate certificate is not a certificate authority")
            end

            verify_signature(icac, root_public_key)
            verify_issued_by(noc, icac)
            verify_signature(noc, MatterCertificate.public_key_from_tlv(icac))
          else
            verify_signature(noc, root_public_key)
          end
        end

        # The issuer a certificate names must be the subject of the certificate
        # that signed it, so a peer cannot present an unrelated pair.
        def verify_issued_by(certificate : Bytes, issuer : Bytes) : Nil
          authority = extension(certificate, ISSUER_KEY_IDENTIFIER)
          subject = extension(issuer, SUBJECT_KEY_IDENTIFIER)

          if authority.nil? || subject.nil?
            raise Matter::AuthenticationError.new("Certificate is missing a key identifier extension")
          end

          unless authority.as_bytes == subject.as_bytes
            raise Matter::AuthenticationError.new("Certificate was not issued by the certificate above it")
          end
        end

        # True when the certificate's basic constraints mark it as a CA
        def certificate_authority?(certificate : Bytes) : Bool
          constraints = extension(certificate, BASIC_CONSTRAINTS)
          return false if constraints.nil?

          is_ca = constraints.as_structure?.try(&.[Asn1::BASIC_CONSTRAINT_IS_CA]?)
          return false if is_ca.nil?

          is_ca.as_bool
        rescue ex
          Log.debug(exception: ex) { "Certificate has unreadable basic constraints" }
          false
        end

        private def extension(certificate : Bytes, tag : UInt8) : TLV::Any?
          extensions = parse(certificate).as_structure?.try(&.[Asn1::Field::Extensions.value]?)
          return if extensions.nil?

          extensions.as_list?.try(&.find { |element| element.header.ids == tag })
        end

        private def signature_of(parsed : TLV::Any) : Bytes
          signature = parsed.as_structure?.try(&.[Asn1::Field::Signature.value]?)
          raise Matter::CertificateError.new("Certificate carries no signature") if signature.nil?

          signature.as_bytes
        end

        private def parse(certificate : Bytes) : TLV::Any
          TLV::Any.from_slice(certificate)
        end
      end
    end
  end
end
