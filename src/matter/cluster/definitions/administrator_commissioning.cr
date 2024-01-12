module Matter
  module Cluster
    module Definitions
      module AdministratorCommissioning
        enum CommissioningWindowStatus : UInt8
          # Commissioning window not open
          WindowNotOpen = 0

          # An Enhanced Commissioning Method window is open
          EnhancedWindowOpen = 1

          # A Basic Commissioning Method window is open
          BasicWindowOpen = 2
        end

        enum StatusCode
          # Could not be completed because another commissioning is in progress
          Busy = 2

          # Provided PAKE parameters were incorrectly formatted or otherwise invalid
          PakeParameterError = 3

          # No commissioning window was currently open
          WindowNotOpen = 4
        end

        # Input to the AdministratorCommissioning openCommissioningWindow command
        struct OpenCommissioningWindowRequest
          include TLV::Serializable

          # This field shall specify the time in seconds during which commissioning session establishment is allowed by
          # the Node. This is known as Open Commissioning Window (OCW). This timeout value shall follow guidance as
          # specified in Announcement Duration. The CommissioningTimeout applies only to cessation of any announcements
          # and to accepting of new commissioning sessions; it does not apply to abortion of connections, i.e., a
          # commissioning session SHOULD NOT abort prematurely upon expiration of this timeout.
          @[TLV::Field(tag: 0)]
          property commissioning_timeout : UInt16

          # This field shall specify an ephemeral PAKE passcode verifier (see Section 3.10, “Password-Authenticated Key
          # Exchange (PAKE)”) computed by the existing Administrator to be used for this commissioning. The field is
          # concatenation of two values (w0 || L) shall be (CRYPTO_GROUP_SIZE_BYTES +
          # CRYPTO_PUBLIC_KEY_SIZE_BYTES)-octets long as detailed in Crypto_PAKEValues_Responder. It shall be derived
          # from an ephemeral passcode (See PAKE). It shall be deleted by the Node at the end of commissioning or
          # expiration of OCW, and shall be deleted by the existing Administrator after sending it to the Node(s).
          @[TLV::Field(tag: 1)]
          property pake_passcode_verifier : Slice(UInt8)

          # This field shall be used by the Node as the long discriminator for DNS-SD advertisement (see Commissioning
          # Discriminator) for discovery by the new Administrator. The new Administrator can find and filter DNS-SD
          # records by long discriminator to locate and initiate commissioning with the appropriate Node.
          @[TLV::Field(tag: 2)]
          property discriminator : UInt16

          # This field shall be used by the Node as the PAKE iteration count associated with the ephemeral PAKE passcode
          # verifier to be used for this commissioning, which shall be sent by the Node to the new Administrator’s
          # software as response to the PBKDFParamRequest during PASE negotiation. The permitted range of values shall
          # match the range specified in Section 3.9, “Password-Based Key Derivation Function (PBKDF)”, within the
          # definition of the Crypto_PBKDFParameterSet.
          @[TLV::Field(tag: 3)]
          property iterations : UInt32

          # This field shall be used by the Node as the PAKE Salt associated with the ephemeral PAKE passcode verifier
          # to be used for this commissioning, which shall be sent by the Node to the new
          #
          # Administrator’s software as response to the PBKDFParamRequest during PASE negotiation. The constraints on
          # the value shall match those specified in Section 3.9, “Password-Based Key Derivation Function (PBKDF)”,
          # within the definition of the Crypto_PBKDFParameterSet.
          #
          # When a Node receives the Open Commissioning Window command, it shall begin advertising on DNS-SD as
          # described in Section 4.3.1, “Commissionable Node Discovery” and for a time period as described in Section
          # 11.18.8.1.1, “CommissioningTimeout Field”. When the command is received by a SED, it shall enter into active
          # mode and set its fast-polling interval to SLEEPY_ACTIVE_INTERVAL for at least the entire duration of the
          # CommissioningTimeout.
          @[TLV::Field(tag: 4)]
          property salt : Slice(UInt8)
        end

        # Input to the AdministratorCommissioning openBasicCommissioningWindow command
        struct OpenBasicCommissioningWindowRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property commissioning_timeout : UInt16
        end
      end
    end
  end
end
