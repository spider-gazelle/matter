require "../fabric"
require "../fabric_table"
require "../crypto/key"
require "base64"

module Matter
  module Clusters
    # Operational Credentials Cluster (0x003E)
    #
    # This cluster is used to manage device operational certificates and fabrics.
    # It is critical for commissioning and managing multi-admin fabrics.
    #
    # Matter Specification: Core 1.4 § 11.17 - Operational Credentials Cluster
    #
    # Commands:
    # - AttestationRequest (0x00): Request device attestation
    # - CertificateChainRequest (0x02): Request DAC/PAI certificate
    # - CSRRequest (0x04): Request Certificate Signing Request for NOC
    # - AddNOC (0x06): Add a Node Operational Certificate
    # - UpdateNOC (0x07): Update existing NOC
    # - UpdateFabricLabel (0x09): Update fabric label
    # - RemoveFabric (0x0A): Remove a fabric
    # - AddTrustedRootCertificate (0x0B): Add trusted root CA cert
    #
    # Attributes:
    # - NOCs (0x00): List of NOC certificates
    # - Fabrics (0x01): List of fabric descriptors
    # - SupportedFabrics (0x02): Maximum supported fabrics
    # - CommissionedFabrics (0x03): Current number of fabrics
    # - TrustedRootCertificates (0x04): List of trusted root certs
    # - CurrentFabricIndex (0x05): Fabric index of current session
    class OperationalCredentials
      CLUSTER_ID = 0x003E_u16

      # NodeOperationalCertStatus Enum
      # Status codes returned by NOC-related commands
      enum NodeOperationalCertStatus : UInt8
        Ok                  =  0 # Operation successful
        InvalidPublicKey    =  1 # Public key in NOC doesn't match CSR
        InvalidNodeOpId     =  2 # Node Operational ID in NOC is invalid
        InvalidNoc          =  3 # NOC certificate validation failed
        MissingCsr          =  4 # CSR not found for this session
        TableFull           =  5 # Fabric table is at capacity
        InvalidAdminSubject =  6 # CaseAdminSubject is invalid
        FabricConflict      =  9 # Fabric with same ID already exists
        LabelConflict       = 10 # Label already in use by another fabric
        InvalidFabricIndex  = 11 # Specified fabric index doesn't exist
      end

      # NOCStruct - Node Operational Certificate structure
      # Returned in NOCs attribute
      struct NOCStruct
        property noc : Bytes   # Max 400 bytes TLV-encoded certificate
        property icac : Bytes? # Optional Intermediate CA cert (max 400 bytes)
        property fabric_index : UInt8

        def initialize(@noc : Bytes, @icac : Bytes?, @fabric_index : UInt8)
        end
      end

      # AttestationRequest command (0x00)
      struct AttestationRequestCommand
        property attestation_nonce : Bytes # Must be exactly 32 bytes

        def initialize(@attestation_nonce : Bytes)
          raise ArgumentError.new("attestation_nonce must be 32 bytes") if @attestation_nonce.size != 32
        end
      end

      # AttestationResponse
      struct AttestationResponse
        property attestation_elements : Bytes
        property attestation_signature : Bytes

        def initialize(@attestation_elements : Bytes, @attestation_signature : Bytes)
        end
      end

      # CertificateChainRequest command (0x02)
      enum CertificateChainType : UInt8
        DACCertificate = 1 # Device Attestation Certificate
        PAICertificate = 2 # Product Attestation Intermediate
      end

      struct CertificateChainRequestCommand
        property certificate_type : CertificateChainType

        def initialize(@certificate_type : CertificateChainType)
        end
      end

      # CertificateChainResponse
      struct CertificateChainResponse
        property certificate : Bytes # Max 600 bytes

        def initialize(@certificate : Bytes)
        end
      end

      # CSRRequest command (0x04)
      struct CSRRequestCommand
        property csr_nonce : Bytes         # Must be exactly 32 bytes
        property is_for_update_noc : Bool? # Optional, default false

        def initialize(@csr_nonce : Bytes, @is_for_update_noc : Bool? = false)
          raise ArgumentError.new("csr_nonce must be 32 bytes") if @csr_nonce.size != 32
        end
      end

      # CSRResponse
      struct CSRResponse
        property nocsr_elements : Bytes
        property attestation_signature : Bytes

        def initialize(@nocsr_elements : Bytes, @attestation_signature : Bytes)
        end
      end

      # AddTrustedRootCertificate command (0x0B)
      struct AddTrustedRootCertificateCommand
        property root_ca_certificate : Bytes # Max 400 bytes DER-encoded

        def initialize(@root_ca_certificate : Bytes)
        end
      end

      # AddNOC command (0x06)
      struct AddNOCCommand
        property noc_value : Bytes           # Max 400 bytes
        property icac_value : Bytes?         # Optional, max 400 bytes
        property ipk_value : Bytes           # Must be 16 bytes (IPK)
        property case_admin_subject : UInt64 # Node ID of admin
        property admin_vendor_id : UInt16    # Vendor ID of admin

        def initialize(
          @noc_value : Bytes,
          @icac_value : Bytes?,
          @ipk_value : Bytes,
          @case_admin_subject : UInt64,
          @admin_vendor_id : UInt16,
        )
          raise ArgumentError.new("ipk_value must be 16 bytes") if @ipk_value.size != 16
        end
      end

      # UpdateNOC command (0x07)
      struct UpdateNOCCommand
        property noc_value : Bytes   # Max 400 bytes
        property icac_value : Bytes? # Optional, max 400 bytes

        def initialize(@noc_value : Bytes, @icac_value : Bytes?)
        end
      end

      # UpdateFabricLabel command (0x09)
      struct UpdateFabricLabelCommand
        property label : String # Max 32 characters

        def initialize(@label : String)
          raise ArgumentError.new("label must be <= 32 characters") if @label.size > 32
        end
      end

      # RemoveFabric command (0x0A)
      struct RemoveFabricCommand
        property fabric_index : UInt8

        def initialize(@fabric_index : UInt8)
        end
      end

      # NOCResponse - Generic response for AddNOC, UpdateNOC, UpdateFabricLabel, RemoveFabric
      struct NOCResponse
        property status_code : NodeOperationalCertStatus
        property fabric_index : UInt8? # Present on success
        property debug_text : String?  # Optional debug info

        def initialize(
          @status_code : NodeOperationalCertStatus,
          @fabric_index : UInt8? = nil,
          @debug_text : String? = nil,
        )
        end

        def success?
          @status_code == NodeOperationalCertStatus::Ok
        end
      end

      # Failsafe context state for tracking CSR and root cert operations
      class FailsafeContext
        property csr_session_id : UInt64?
        property is_for_update_noc : Bool
        property root_cert_set : Bool
        property noc_added_or_updated : Bool

        def initialize
          @csr_session_id = nil
          @is_for_update_noc = false
          @root_cert_set = false
          @noc_added_or_updated = false
        end

        def reset
          @csr_session_id = nil
          @is_for_update_noc = false
          @root_cert_set = false
          @noc_added_or_updated = false
        end

        def csr_exists?(session_id : UInt64) : Bool
          @csr_session_id == session_id
        end

        def set_csr(session_id : UInt64, is_for_update : Bool)
          @csr_session_id = session_id
          @is_for_update_noc = is_for_update
        end
      end

      # The Operational Credentials cluster server
      @fabric_table : FabricTable
      @failsafe_context : FailsafeContext
      @dac : Bytes?                   # Device Attestation Certificate
      @pai : Bytes?                   # Product Attestation Intermediate
      @attestation_key : Crypto::Key? # Device Attestation private key
      @pending_noc_key : Crypto::Key? # Pending operational key from CSR
      @trusted_root_certs : Array(Bytes)

      getter fabric_table : FabricTable

      def initialize(@fabric_table : FabricTable)
        @failsafe_context = FailsafeContext.new
        @dac = nil
        @pai = nil
        @attestation_key = nil
        @pending_noc_key = nil
        @trusted_root_certs = [] of Bytes
      end

      # Configure device attestation credentials
      # Should be called during device initialization with factory credentials
      def set_attestation_credentials(
        dac : Bytes,
        pai : Bytes,
        attestation_key : Crypto::Key,
      )
        @dac = dac
        @pai = pai
        @attestation_key = attestation_key
      end

      # Attributes

      # NOCs attribute (0x00) - Fabric-scoped list of NOC certificates
      def nocs(fabric_index : UInt8) : Array(NOCStruct)
        fabric = @fabric_table.get_fabric(fabric_index)
        return [] of NOCStruct unless fabric

        [NOCStruct.new(
          noc: fabric.operational_cert,
          icac: fabric.intermediate_cert,
          fabric_index: fabric.fabric_index
        )]
      end

      # Fabrics attribute (0x01) - List of all fabric descriptors
      def fabrics : Array(FabricDescriptor)
        @fabric_table.fabric_descriptors
      end

      # SupportedFabrics attribute (0x02) - Maximum supported fabrics (fixed)
      def supported_fabrics : UInt8
        @fabric_table.max_fabrics
      end

      # CommissionedFabrics attribute (0x03) - Current number of fabrics
      def commissioned_fabrics : UInt8
        @fabric_table.size.to_u8
      end

      # TrustedRootCertificates attribute (0x04) - List of trusted root certs
      def trusted_root_certificates : Array(Bytes)
        @trusted_root_certs
      end

      # CurrentFabricIndex attribute (0x05) - Fabric index from session context
      def current_fabric_index(session_fabric_index : UInt8?) : UInt8
        session_fabric_index || 0_u8
      end

      # Commands

      # AttestationRequest command (0x00)
      # Request device attestation during commissioning
      def handle_attestation_request(
        cmd : AttestationRequestCommand,
        session_id : UInt64,
      ) : AttestationResponse
        # Validate nonce is exactly 32 bytes (enforced by struct initializer)

        # Build attestation elements (TLV structure containing certification declaration, nonce, timestamp)
        # For now, simplified implementation
        attestation_elements = build_attestation_elements(cmd.attestation_nonce)

        # Sign with attestation key
        attestation_signature = sign_attestation(attestation_elements)

        AttestationResponse.new(
          attestation_elements: attestation_elements,
          attestation_signature: attestation_signature
        )
      end

      # CertificateChainRequest command (0x02)
      # Request DAC or PAI certificate
      def handle_certificate_chain_request(
        cmd : CertificateChainRequestCommand,
      ) : CertificateChainResponse
        certificate = case cmd.certificate_type
                      when CertificateChainType::DACCertificate
                        @dac
                      when CertificateChainType::PAICertificate
                        @pai
                      else
                        nil
                      end

        raise "Certificate not available" unless certificate

        CertificateChainResponse.new(certificate: certificate)
      end

      # CSRRequest command (0x04)
      # Generate a Certificate Signing Request for NOC
      def handle_csr_request(
        cmd : CSRRequestCommand,
        session_id : UInt64,
        is_pase_session : Bool,
        failsafe_armed : Bool,
      ) : CSRResponse?
        # Validate failsafe is armed
        return nil unless failsafe_armed

        # Cannot update NOC on PASE session
        if cmd.is_for_update_noc == true && is_pase_session
          return nil
        end

        # Cannot call CSR after AddNOC/UpdateNOC in same failsafe
        if @failsafe_context.noc_added_or_updated
          return nil
        end

        # Generate new operational key pair
        @pending_noc_key = Crypto::Key.generate_key_pair

        # Build CSR elements (TLV structure with public key and nonce)
        csr_elements = build_csr_elements(cmd.csr_nonce, @pending_noc_key.not_nil!)

        # Sign CSR with attestation key
        csr_signature = sign_attestation(csr_elements)

        # Store CSR context in failsafe
        @failsafe_context.set_csr(session_id, cmd.is_for_update_noc || false)

        CSRResponse.new(
          nocsr_elements: csr_elements,
          attestation_signature: csr_signature
        )
      end

      # AddTrustedRootCertificate command (0x0B)
      # Add a trusted root CA certificate
      def handle_add_trusted_root_certificate(
        cmd : AddTrustedRootCertificateCommand,
        failsafe_armed : Bool,
      ) : NOCResponse?
        # Must have armed failsafe
        return nil unless failsafe_armed

        # Cannot set root cert twice in same failsafe
        if @failsafe_context.root_cert_set
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Root certificate already set in this failsafe context"
          )
        end

        # Cannot set root cert after AddNOC/UpdateNOC
        if @failsafe_context.noc_added_or_updated
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Cannot set root certificate after AddNOC/UpdateNOC"
          )
        end

        # Validate certificate (basic validation - should be enhanced)
        # TODO: Proper X.509 validation

        # Store root certificate
        @trusted_root_certs << cmd.root_ca_certificate
        @failsafe_context.root_cert_set = true

        # No response for this command (TlvNoResponse in Matter spec)
        nil
      end

      # AddNOC command (0x06)
      # Add a Node Operational Certificate (commission into a fabric)
      def handle_add_noc(
        cmd : AddNOCCommand,
        session_id : UInt64,
        failsafe_armed : Bool,
      ) : NOCResponse
        # Must have armed failsafe
        unless failsafe_armed
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Failsafe not armed"
          )
        end

        # Cannot call AddNOC twice in same failsafe
        if @failsafe_context.noc_added_or_updated
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "AddNOC/UpdateNOC already called in this failsafe"
          )
        end

        # Must have CSR from this session
        unless @failsafe_context.csr_exists?(session_id)
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::MissingCsr,
            debug_text: "CSR not found for this session"
          )
        end

        # Must have root certificate set
        unless @failsafe_context.root_cert_set
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Root certificate not set"
          )
        end

        # Check if table is full
        if @fabric_table.full?
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::TableFull,
            debug_text: "Fabric table is full"
          )
        end

        # Parse NOC to extract fabric_id and node_id
        # TODO: Implement proper Matter certificate parsing
        # For now, use placeholder values
        fabric_id = extract_fabric_id_from_noc(cmd.noc_value)
        node_id = extract_node_id_from_noc(cmd.noc_value)

        # Check for fabric conflict (same fabric_id already exists)
        if @fabric_table.find_by_fabric_id(fabric_id)
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::FabricConflict,
            debug_text: "Fabric with this ID already exists"
          )
        end

        # Add fabric to table
        fabric = @fabric_table.add_fabric_auto_index(
          fabric_id: fabric_id,
          node_id: node_id,
          root_public_key: @trusted_root_certs.last,
          operational_cert: cmd.noc_value,
          operational_key: @pending_noc_key.not_nil!,
          ipk: cmd.ipk_value,
          vendor_id: cmd.admin_vendor_id,
          label: "",
          intermediate_cert: cmd.icac_value
        )

        unless fabric
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::TableFull,
            debug_text: "Failed to add fabric"
          )
        end

        # Mark NOC operation completed
        @failsafe_context.noc_added_or_updated = true

        # TODO: Create default ACL entry for case_admin_subject

        NOCResponse.new(
          status_code: NodeOperationalCertStatus::Ok,
          fabric_index: fabric.fabric_index
        )
      end

      # UpdateNOC command (0x07)
      # Update an existing NOC certificate
      def handle_update_noc(
        cmd : UpdateNOCCommand,
        session_id : UInt64,
        session_fabric_index : UInt8,
        failsafe_armed : Bool,
      ) : NOCResponse
        # Must have armed failsafe
        unless failsafe_armed
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Failsafe not armed"
          )
        end

        # Cannot call UpdateNOC after AddNOC in same failsafe
        if @failsafe_context.noc_added_or_updated
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "AddNOC/UpdateNOC already called in this failsafe"
          )
        end

        # Must have CSR from this session with is_for_update_noc=true
        unless @failsafe_context.csr_exists?(session_id) && @failsafe_context.is_for_update_noc
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::MissingCsr,
            debug_text: "CSR for update not found"
          )
        end

        # Root certificate cannot be set for updates
        if @failsafe_context.root_cert_set
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Cannot set root certificate for NOC update"
          )
        end

        # Get current fabric
        fabric = @fabric_table.get_fabric(session_fabric_index)
        unless fabric
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidFabricIndex,
            debug_text: "Session fabric not found"
          )
        end

        # Parse new NOC to verify fabric_id matches
        new_fabric_id = extract_fabric_id_from_noc(cmd.noc_value)
        if new_fabric_id != fabric.fabric_id
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Fabric ID mismatch"
          )
        end

        # Update fabric with new NOC
        fabric.operational_cert = cmd.noc_value
        fabric.intermediate_cert = cmd.icac_value
        fabric.operational_key = @pending_noc_key.not_nil!

        @fabric_table.update_fabric(fabric)

        # Mark NOC operation completed
        @failsafe_context.noc_added_or_updated = true

        NOCResponse.new(
          status_code: NodeOperationalCertStatus::Ok,
          fabric_index: fabric.fabric_index
        )
      end

      # UpdateFabricLabel command (0x09)
      # Update the label of a fabric
      def handle_update_fabric_label(
        cmd : UpdateFabricLabelCommand,
        session_fabric_index : UInt8,
      ) : NOCResponse
        # Get fabric
        fabric = @fabric_table.get_fabric(session_fabric_index)
        unless fabric
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidFabricIndex,
            debug_text: "Fabric not found"
          )
        end

        # Check for label conflict
        @fabric_table.all_fabrics.each do |f|
          if f.fabric_index != session_fabric_index && f.label == cmd.label
            return NOCResponse.new(
              status_code: NodeOperationalCertStatus::LabelConflict,
              debug_text: "Label already in use"
            )
          end
        end

        # Update label
        fabric.label = cmd.label
        @fabric_table.update_fabric(fabric)

        NOCResponse.new(
          status_code: NodeOperationalCertStatus::Ok,
          fabric_index: fabric.fabric_index
        )
      end

      # RemoveFabric command (0x0A)
      # Remove a fabric from the device
      def handle_remove_fabric(
        cmd : RemoveFabricCommand,
      ) : NOCResponse
        # Check if fabric exists
        unless @fabric_table.get_fabric(cmd.fabric_index)
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidFabricIndex,
            debug_text: "Fabric not found"
          )
        end

        # Remove fabric
        if @fabric_table.remove_fabric(cmd.fabric_index)
          # TODO: Remove all fabric-scoped data (ACLs, bindings, etc.)
          NOCResponse.new(
            status_code: NodeOperationalCertStatus::Ok,
            fabric_index: cmd.fabric_index
          )
        else
          NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidFabricIndex,
            debug_text: "Failed to remove fabric"
          )
        end
      end

      # Failsafe timer expired - reset context
      def on_failsafe_expired
        @failsafe_context.reset
        @pending_noc_key = nil
      end

      # Failsafe timer disarmed successfully - commit changes
      def on_failsafe_success
        @failsafe_context.reset
        @pending_noc_key = nil
      end

      # Helper methods for certificate parsing
      # TODO: Implement proper Matter certificate TLV parsing

      private def build_attestation_elements(nonce : Bytes) : Bytes
        # Placeholder: Should build TLV structure with certification declaration, nonce, timestamp
        # For now, return nonce as-is for testing
        nonce
      end

      private def sign_attestation(data : Bytes) : Bytes
        # Placeholder: Should sign with attestation key
        # For now, return dummy signature
        Bytes.new(64, 0_u8)
      end

      private def build_csr_elements(nonce : Bytes, key : Crypto::Key) : Bytes
        # Placeholder: Should build TLV CSR structure
        # For now, return nonce as-is for testing
        nonce
      end

      private def extract_fabric_id_from_noc(noc : Bytes) : UInt64
        # Placeholder: Should parse Matter certificate TLV
        # For now, return dummy value
        0x1234567890_u64
      end

      private def extract_node_id_from_noc(noc : Bytes) : UInt64
        # Placeholder: Should parse Matter certificate TLV
        # For now, return dummy value
        0xABCDEF_u64
      end
    end
  end
end
