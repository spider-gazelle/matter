require "tlv"

module Matter
  module Crypto
    # Matter Certificate TLV encoding as per Matter spec section 6.5.2
    # This represents the Matter Operational Certificate (NOC) format

    # Distinguished Name (DN) attributes for certificate subject/issuer
    # These appear as context-tagged elements within a LIST (not Structure)
    # Matter uses TLV List format for DN attributes
    @[TLV::ListFormat]
    struct DNAttributes
      include TLV::Serializable

      # Matter-specific DN attribute OIDs mapped to context tags:
      # Tag 17 (0x11): matter-node-id
      # Tag 18 (0x12): matter-firmware-signing-id
      # Tag 19 (0x13): matter-icac-id
      # Tag 20 (0x14): matter-rcac-id
      # Tag 21 (0x15): matter-fabric-id
      # Tag 22 (0x16): matter-noc-cat

      @[TLV::Field(tag: 17, optional: true)]
      property node_id : UInt64?

      @[TLV::Field(tag: 18, optional: true)]
      property firmware_signing_id : UInt64?

      @[TLV::Field(tag: 19, optional: true)]
      property icac_id : UInt64?

      @[TLV::Field(tag: 20, optional: true)]
      property rcac_id : UInt64?

      @[TLV::Field(tag: 21, optional: true)]
      property fabric_id : UInt64?

      @[TLV::Field(tag: 22, optional: true)]
      property noc_cat : UInt32?

      def initialize(
        @node_id : UInt64? = nil,
        @fabric_id : UInt64? = nil,
        @icac_id : UInt64? = nil,
        @rcac_id : UInt64? = nil,
        @firmware_signing_id : UInt64? = nil,
        @noc_cat : UInt32? = nil,
      )
      end
    end

    # Matter Certificate TLV structure
    # See Matter spec section 6.5.2 "Matter Certificate Encoding"
    struct MatterCertificate
      include TLV::Serializable

      # Tag 1: Serial number (octet string, 1-20 bytes)
      @[TLV::Field(tag: 1)]
      property serial_number : Bytes

      # Tag 2: Signature algorithm (unsigned int)
      # 1 = ECDSA with SHA256
      @[TLV::Field(tag: 2)]
      property signature_algorithm : UInt8

      # Tag 3: Issuer DN (list of DN attributes)
      @[TLV::Field(tag: 3)]
      property issuer : DNAttributes

      # Tag 4: Not Before (unsigned int, Matter epoch seconds)
      @[TLV::Field(tag: 4)]
      property not_before : UInt32

      # Tag 5: Not After (unsigned int, Matter epoch seconds)
      @[TLV::Field(tag: 5)]
      property not_after : UInt32

      # Tag 6: Subject DN (list of DN attributes)
      @[TLV::Field(tag: 6)]
      property subject : DNAttributes

      # Tag 7: Public key algorithm (unsigned int)
      # 1 = EC public key
      @[TLV::Field(tag: 7)]
      property public_key_algorithm : UInt8

      # Tag 8: Elliptic curve ID (unsigned int)
      # 1 = prime256v1 (P-256)
      @[TLV::Field(tag: 8)]
      property elliptic_curve_id : UInt8

      # Tag 9: EC public key (octet string, 65 bytes for uncompressed P-256)
      @[TLV::Field(tag: 9)]
      property ec_public_key : Bytes

      # Tag 10: Extensions (list)
      @[TLV::Field(tag: 10, optional: true)]
      property extensions : TLV::Any?

      # Tag 11: Signature (octet string, 64 bytes for P-256 ECDSA)
      @[TLV::Field(tag: 11)]
      property signature : Bytes

      def initialize(
        @serial_number : Bytes,
        @signature_algorithm : UInt8,
        @issuer : DNAttributes,
        @not_before : UInt32,
        @not_after : UInt32,
        @subject : DNAttributes,
        @public_key_algorithm : UInt8,
        @elliptic_curve_id : UInt8,
        @ec_public_key : Bytes,
        @signature : Bytes,
        @extensions : TLV::Any? = nil,
      )
      end

      # Extract fabric ID from subject DN
      def fabric_id : UInt64?
        subject.fabric_id
      end

      # Extract node ID from subject DN
      def node_id : UInt64?
        subject.node_id
      end

      # Check if this is a NOC (has both fabric_id and node_id)
      def noc? : Bool
        !subject.fabric_id.nil? && !subject.node_id.nil?
      end

      # Check if this is an ICAC (has icac_id)
      def icac? : Bool
        !subject.icac_id.nil?
      end

      # Check if this is a root CA (has rcac_id)
      def root_ca? : Bool
        !subject.rcac_id.nil?
      end
    end
  end
end
