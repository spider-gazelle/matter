require "./cluster"
require "./definitions/operational_credentials"
require "../fabric"
require "../fabric_table"
require "../crypto/key"
require "../crypto/crypto"
require "../storage/memory_backend"
require "../certificate/attestation_certificate_manager"
require "../certificate/certification_declaration"

module Matter
  module Cluster
    # Operational Credentials Cluster (0x003E)
    #
    # Functionality to manage operational certificates and fabric membership.
    # This cluster is required for Matter commissioning and fabric management.
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
    class OperationalCredentialsCluster < Base
      CLUSTER_ID = 0x003E_u32

      # Certificate Chain Type
      enum CertificateChainType : UInt8
        DACCertificate = 1 # Device Attestation Certificate
        PAICertificate = 2 # Product Attestation Intermediate Certificate
      end

      # Node Operational Certificate Status Codes
      enum NodeOperationalCertStatus : UInt8
        Ok                    =  0 # Operation successful
        InvalidPublicKey      =  1 # Public key in NOC doesn't match CSR
        InvalidNodeOpId       =  2 # Node Operational ID in NOC is invalid
        InvalidNoc            =  3 # NOC certificate validation failed
        MissingCsr            =  4 # CSR not found for this session
        TableFull             =  5 # Fabric table is at capacity
        InvalidAdminSubject   =  6 # CaseAdminSubject is invalid
        InsufficientPrivilege =  8 # Insufficient privilege
        FabricConflict        =  9 # Fabric with same ID already exists
        LabelConflict         = 10 # Label already in use by another fabric
        InvalidFabricIndex    = 11 # Specified fabric index doesn't exist

        # Aliases for backward compatibility
        OK         = Ok
        InvalidNOC = InvalidNoc
      end

      # Attributes
      ATTR_NOCS                      = 0x0000_u32
      ATTR_FABRICS                   = 0x0001_u32
      ATTR_SUPPORTED_FABRICS         = 0x0002_u32
      ATTR_COMMISSIONED_FABRICS      = 0x0003_u32
      ATTR_TRUSTED_ROOT_CERTIFICATES = 0x0004_u32
      ATTR_CURRENT_FABRIC_INDEX      = 0x0005_u32

      # Commands
      CMD_ATTESTATION_REQUEST          = 0x00_u32
      CMD_ATTESTATION_RESPONSE         = 0x01_u32
      CMD_CERTIFICATE_CHAIN_REQUEST    = 0x02_u32
      CMD_CERTIFICATE_CHAIN_RESPONSE   = 0x03_u32
      CMD_CSR_REQUEST                  = 0x04_u32
      CMD_CSR_RESPONSE                 = 0x05_u32
      CMD_ADD_NOC                      = 0x06_u32
      CMD_UPDATE_NOC                   = 0x07_u32
      CMD_NOC_RESPONSE                 = 0x08_u32
      CMD_UPDATE_FABRIC_LABEL          = 0x09_u32
      CMD_REMOVE_FABRIC                = 0x0A_u32
      CMD_ADD_TRUSTED_ROOT_CERTIFICATE = 0x0B_u32

      # NOC Struct
      struct NOCStruct
        property noc : Bytes          # Node Operational Certificate (DER encoded)
        property icac : Bytes?        # Intermediate CA Certificate (DER encoded, optional)
        property fabric_index : UInt8 # Index of the fabric

        def initialize(@noc : Bytes, @icac : Bytes?, @fabric_index : UInt8)
        end
      end

      # Fabric Descriptor Struct
      struct FabricDescriptorStruct
        property root_public_key : Bytes # Root public key (65 bytes - uncompressed P-256)
        property vendor_id : UInt16      # Vendor ID
        property fabric_id : UInt64      # Fabric ID
        property node_id : UInt64        # Node ID
        property label : String          # Fabric label
        property fabric_index : UInt8    # Index of the fabric

        def initialize(@root_public_key : Bytes, @vendor_id : UInt16,
                       @fabric_id : UInt64, @node_id : UInt64,
                       @label : String, @fabric_index : UInt8)
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

      # Instance variables
      @fabric_table : FabricTable
      @failsafe_context : FailsafeContext
      @dac : Bytes?                                                           # Device Attestation Certificate
      @pai : Bytes?                                                           # Product Attestation Intermediate
      @attestation_key : Crypto::Key?                                         # Device Attestation private key
      @pending_noc_key : Crypto::Key?                                         # Pending operational key from CSR
      @vendor_id : UInt16                                                     # Vendor ID for attestation
      @product_id : UInt16                                                    # Product ID for attestation
      @attestation_cert_manager : Certificate::AttestationCertificateManager? # Certificate manager
      @trusted_root_certs : Array(Bytes)
      @access_control_cluster : AccessControlCluster? # Optional ACL cluster reference
      @current_fabric_index_value : UInt8 = 0_u8

      # Session context for command handling
      # NOTE: These should be set by the protocol layer (InteractionModel/Exchange)
      # For testing, they default to sensible values
      @session_id : UInt64? = nil
      @session_fabric_index : UInt8? = nil
      @failsafe_armed : Bool = true # Default to true for testing

      getter fabric_table : FabricTable
      property current_fabric_index : UInt8
      property session_id : UInt64?
      property session_fabric_index : UInt8?
      property failsafe_armed : Bool

      # CurrentFabricIndex helper method (returns passed value or stored value)
      def current_fabric_index(session_fabric_index : UInt8?) : UInt8
        session_fabric_index || @current_fabric_index
      end

      def initialize(
        @fabric_table : FabricTable,
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        @access_control_cluster : AccessControlCluster? = nil,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @failsafe_context = FailsafeContext.new
        @dac = nil
        @pai = nil
        # Generate a default attestation key for testing
        @attestation_key = Crypto::Key.generate_key_pair
        @pending_noc_key = nil
        @trusted_root_certs = [] of Bytes
        @current_fabric_index = 0_u8
        # Default test vendor/product IDs (typically set via set_attestation_credentials)
        @vendor_id = 0xFFF1_u16  # Test vendor ID
        @product_id = 0x8000_u16 # Test product ID
        @attestation_cert_manager = nil
      end

      # Overload for tests that pass fabric_table and acl_cluster directly
      def initialize(
        fabric_table : FabricTable,
        access_control_cluster : AccessControlCluster,
      )
        initialize(
          fabric_table,
          DataType::EndpointNumber.new(0_u16),
          access_control_cluster
        )
      end

      # Overload for tests that pass only endpoint_id (creates default fabric table)
      def initialize(endpoint_id : DataType::EndpointNumber)
        storage = Storage::MemoryBackend.new
        fabric_table = FabricTable.new(storage)
        initialize(fabric_table, endpoint_id, nil)
      end

      def name : String
        "OperationalCredentials"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_NOCS),
            "NOCs",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_FABRICS),
            "Fabrics",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SUPPORTED_FABRICS),
            "SupportedFabrics",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COMMISSIONED_FABRICS),
            "CommissionedFabrics",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_TRUSTED_ROOT_CERTIFICATES),
            "TrustedRootCertificates",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CURRENT_FABRIC_INDEX),
            "CurrentFabricIndex",
            :uint8,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_ATTESTATION_REQUEST),
            "AttestationRequest"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_CERTIFICATE_CHAIN_REQUEST),
            "CertificateChainRequest"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_CSR_REQUEST),
            "CSRRequest"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_ADD_NOC),
            "AddNOC"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_UPDATE_NOC),
            "UpdateNOC"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_UPDATE_FABRIC_LABEL),
            "UpdateFabricLabel"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_REMOVE_FABRIC),
            "RemoveFabric"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_ADD_TRUSTED_ROOT_CERTIFICATE),
            "AddTrustedRootCertificate"
          ),
        ]
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

      # Initialize attestation from certificate manager
      # Generates DAC and PAI certificates for the specified vendor/product
      def set_attestation_from_manager(
        vendor_id : UInt16,
        product_id : UInt16,
      )
        # Create or reuse certificate manager
        @vendor_id = vendor_id
        @product_id = product_id

        # Generate certificate manager if not already present
        cert_manager = @attestation_cert_manager || Certificate::AttestationCertificateManager.new(vendor_id, product_id)
        @attestation_cert_manager = cert_manager

        # Get DAC certificate and key
        dac_cert, dac_key = cert_manager.get_dac_cert(product_id)

        # Get PAI certificate
        pai_cert = cert_manager.get_pai_cert

        # Set the credentials
        @dac = dac_cert
        @pai = pai_cert
        @attestation_key = dac_key
      end

      # Attribute accessors using fabric_table

      # NOCs attribute (0x00) - Fabric-scoped list of NOC certificates
      # NOCs attribute for specific fabric (0x00)
      def nocs(fabric_index : UInt8) : Array(NOCStruct)
        fabric = @fabric_table.get_fabric(fabric_index)
        return [] of NOCStruct unless fabric

        [NOCStruct.new(
          noc: fabric.operational_cert,
          icac: fabric.intermediate_cert,
          fabric_index: fabric.fabric_index
        )]
      end

      # Get all NOCs from all fabrics (for tests)
      def nocs : Array(NOCStruct)
        result = [] of NOCStruct
        @fabric_table.all_fabrics.each do |fabric|
          result << NOCStruct.new(
            noc: fabric.operational_cert,
            icac: fabric.intermediate_cert,
            fabric_index: fabric.fabric_index
          )
        end
        result
      end

      # Fabrics attribute (0x01) - List of all fabric descriptors
      def fabrics : Array(FabricDescriptor)
        @fabric_table.fabric_descriptors
      end

      # Get fabric descriptor by index (for tests)
      def get_fabric_by_index(index : UInt8) : FabricDescriptor?
        fabrics.find { |f| f.fabric_index == index }
      end

      # Check if there's capacity for more fabrics (for tests)
      def has_fabric_capacity? : Bool
        !@fabric_table.full?
      end

      # Get NOC by fabric index (for tests)
      def get_noc_by_fabric_index(index : UInt8) : NOCStruct?
        nocs.find { |n| n.fabric_index == index }
      end

      # SupportedFabrics attribute (0x02) - Maximum supported fabrics
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
      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_NOCS
          encode_noc_list
        when ATTR_FABRICS
          encode_fabric_list
        when ATTR_SUPPORTED_FABRICS
          encode_uint8(supported_fabrics)
        when ATTR_COMMISSIONED_FABRICS
          encode_uint8(commissioned_fabrics)
        when ATTR_TRUSTED_ROOT_CERTIFICATES
          encode_certificate_list
        when ATTR_CURRENT_FABRIC_INDEX
          encode_uint8(current_fabric_index)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only
        super
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_ATTESTATION_REQUEST
          Cluster::CommandResponse.new(CMD_ATTESTATION_RESPONSE, handle_attestation_request(fields))
        when CMD_CERTIFICATE_CHAIN_REQUEST
          Cluster::CommandResponse.new(CMD_CERTIFICATE_CHAIN_RESPONSE, handle_certificate_chain_request(fields))
        when CMD_CSR_REQUEST
          Cluster::CommandResponse.new(CMD_CSR_RESPONSE, handle_csr_request(fields))
        when CMD_ADD_NOC
          Cluster::CommandResponse.new(CMD_NOC_RESPONSE, handle_add_noc(fields))
        when CMD_UPDATE_NOC
          Cluster::CommandResponse.new(CMD_NOC_RESPONSE, handle_update_noc(fields))
        when CMD_UPDATE_FABRIC_LABEL
          Cluster::CommandResponse.new(CMD_NOC_RESPONSE, handle_update_fabric_label(fields))
        when CMD_REMOVE_FABRIC
          Cluster::CommandResponse.new(CMD_NOC_RESPONSE, handle_remove_fabric(fields))
        when CMD_ADD_TRUSTED_ROOT_CERTIFICATE
          # AddTrustedRootCertificate has no response - return success status
          handle_add_trusted_root_certificate(fields)
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # Command Handlers

      private def handle_attestation_request(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::AttestationRequest.new(fields)

        # Build attestation elements (TLV structure containing certification declaration, nonce, timestamp)
        attestation_elements = build_attestation_elements(request.attestation_nonce)

        # Sign with attestation key
        attestation_signature = sign_attestation(attestation_elements)

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => attestation_elements,
          1_u8 => attestation_signature,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_certificate_chain_request(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::CertificateChainRequest.new(fields)

        # Get the appropriate certificate
        certificate = case request.certificate_type
                      when Definitions::OperationalCredentials::CertificateChainType::DacCertificate
                        @dac
                      when Definitions::OperationalCredentials::CertificateChainType::PaiCertificate
                        @pai
                      else
                        nil
                      end

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => certificate || Bytes.new(0),
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_csr_request(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::CsrRequest.new(fields)

        # Validate failsafe is armed
        # NOTE: @failsafe_armed should be set by protocol layer, defaults to true for testing
        unless @failsafe_armed
          return encode_error_response("Failsafe not armed")
        end

        # Check if NOC already added/updated in current failsafe
        if @failsafe_context.noc_added_or_updated
          # Return error - cannot call CSR after AddNOC/UpdateNOC
          return encode_error_response("Cannot generate CSR after AddNOC/UpdateNOC")
        end

        # Generate new operational key pair
        @pending_noc_key = Crypto::Key.generate_key_pair

        # Build CSR elements (TLV structure with public key and nonce)
        csr_elements = build_csr_elements(request.csr_nonce, @pending_noc_key.not_nil!)

        # Sign CSR with attestation key
        csr_signature = sign_attestation(csr_elements)

        # Store CSR context in failsafe
        # NOTE: @session_id should be set by protocol layer, defaults to 0 for testing
        session_id = @session_id || 0_u64
        is_for_update = request.is_for_update_noc || false
        @failsafe_context.set_csr(session_id, is_for_update)

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => csr_elements,
          1_u8 => csr_signature,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_add_noc(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::AddNocRequest.new(fields)

        # Validate failsafe is armed
        # NOTE: @failsafe_armed should be set by protocol layer, defaults to true for testing
        unless @failsafe_armed
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "Failsafe not armed")
        end

        # Cannot call AddNOC twice in same failsafe
        if @failsafe_context.noc_added_or_updated
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "AddNOC/UpdateNOC already called in this failsafe")
        end

        # Must have CSR from this session
        # NOTE: @session_id should be set by protocol layer, defaults to 0 for testing
        session_id = @session_id || 0_u64
        unless @failsafe_context.csr_exists?(session_id)
          return encode_noc_response(NodeOperationalCertStatus::MissingCsr, nil, "CSR not found for this session")
        end

        # Must have root certificate set
        unless @failsafe_context.root_cert_set
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "Root certificate not set")
        end

        # Check if table is full
        if @fabric_table.full?
          return encode_noc_response(NodeOperationalCertStatus::TableFull, nil, "Fabric table is full")
        end

        # Parse NOC to extract fabric_id and node_id
        begin
          fabric_id = extract_fabric_id_from_noc(request.noc_value)
          node_id = extract_node_id_from_noc(request.noc_value)
        rescue ex
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "Failed to parse NOC: #{ex.message}")
        end

        # Check for fabric conflict (same fabric_id already exists)
        if @fabric_table.find_by_fabric_id(fabric_id)
          return encode_noc_response(NodeOperationalCertStatus::FabricConflict, nil, "Fabric with this ID already exists")
        end

        # Add fabric to table
        fabric = @fabric_table.add_fabric_auto_index(
          fabric_id: fabric_id,
          node_id: node_id,
          root_public_key: @trusted_root_certs.last,
          operational_cert: request.noc_value,
          operational_key: @pending_noc_key.not_nil!,
          ipk: request.ipk_value,
          vendor_id: request.admin_vendor_id.id,
          label: "",
          intermediate_cert: request.icac_value
        )

        unless fabric
          return encode_noc_response(NodeOperationalCertStatus::TableFull, nil, "Failed to add fabric")
        end

        # Mark NOC operation completed
        @failsafe_context.noc_added_or_updated = true

        # Create default ACL entry for case_admin_subject
        # Matter spec requires creating an ACL entry that grants Administer privilege
        # to the commissioning administrator (case_admin_subject)
        if acl_cluster = @access_control_cluster
          default_acl = AccessControlCluster::AccessControlEntry.new(
            privilege: AccessControlCluster::AccessControlEntryPrivilege::Administer,
            auth_mode: AccessControlCluster::AccessControlEntryAuthMode::CASE,
            subjects: [request.case_admin_subject.id],
            targets: nil, # nil means all targets
            fabric_index: fabric.fabric_index
          )
          acl_cluster.acl << default_acl
          acl_cluster.increment_version
        end

        encode_noc_response(NodeOperationalCertStatus::Ok, fabric.fabric_index)
      end

      private def handle_update_noc(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::UpdateNocRequest.new(fields)

        # Validate failsafe is armed
        # NOTE: @failsafe_armed should be set by protocol layer, defaults to true for testing
        unless @failsafe_armed
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "Failsafe not armed")
        end

        # Get session fabric index from instance variable or request
        # NOTE: @session_fabric_index should be set by protocol layer
        session_fabric_index = @session_fabric_index || request.fabric_index.index || 0_u8

        # Cannot call UpdateNOC after AddNOC in same failsafe
        if @failsafe_context.noc_added_or_updated
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "AddNOC/UpdateNOC already called in this failsafe")
        end

        # Must have CSR from this session with is_for_update_noc=true
        # NOTE: @session_id should be set by protocol layer, defaults to 0 for testing
        session_id = @session_id || 0_u64
        unless @failsafe_context.csr_exists?(session_id) && @failsafe_context.is_for_update_noc
          return encode_noc_response(NodeOperationalCertStatus::MissingCsr, nil, "CSR for update not found")
        end

        # Root certificate cannot be set for updates
        if @failsafe_context.root_cert_set
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "Cannot set root certificate for NOC update")
        end

        # Get current fabric
        fabric = @fabric_table.get_fabric(session_fabric_index)
        unless fabric
          return encode_noc_response(NodeOperationalCertStatus::InvalidFabricIndex, nil, "Session fabric not found")
        end

        # Parse new NOC to verify fabric_id matches and extract node_id
        begin
          new_fabric_id = extract_fabric_id_from_noc(request.noc_value)
          if new_fabric_id != fabric.fabric_id
            return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "Fabric ID mismatch")
          end

          # Extract new node_id from the updated NOC
          new_node_id = extract_node_id_from_noc(request.noc_value)
        rescue ex
          return encode_noc_response(NodeOperationalCertStatus::InvalidNoc, nil, "Failed to parse NOC: #{ex.message}")
        end

        # Update fabric with new NOC, node_id, and operational key
        fabric.operational_cert = request.noc_value
        fabric.intermediate_cert = request.icac_value
        fabric.operational_key = @pending_noc_key.not_nil!
        fabric.node_id = new_node_id

        @fabric_table.update_fabric(fabric)

        # Mark NOC operation completed
        @failsafe_context.noc_added_or_updated = true

        encode_noc_response(NodeOperationalCertStatus::Ok, fabric.fabric_index)
      end

      private def handle_update_fabric_label(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::UpdateFabricLabelRequest.new(fields)

        # Get session fabric index from instance variable or request
        # NOTE: @session_fabric_index should be set by protocol layer
        fabric_idx = @session_fabric_index || request.fabric_index.index

        unless fabric_idx
          return encode_noc_response(NodeOperationalCertStatus::InvalidFabricIndex, nil, "Invalid fabric index")
        end

        # Get fabric
        fabric = @fabric_table.get_fabric(fabric_idx)
        unless fabric
          return encode_noc_response(NodeOperationalCertStatus::InvalidFabricIndex, nil, "Fabric not found")
        end

        # Check for label conflict
        @fabric_table.all_fabrics.each do |f|
          if f.fabric_index != fabric_idx && f.label == request.label
            return encode_noc_response(NodeOperationalCertStatus::LabelConflict, nil, "Label already in use")
          end
        end

        # Update label
        fabric.label = request.label
        @fabric_table.update_fabric(fabric)
        increment_version

        encode_noc_response(NodeOperationalCertStatus::Ok, fabric.fabric_index)
      end

      private def handle_remove_fabric(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::RemoveFabricRequest.new(fields)

        fabric_idx = request.fabric_index.index

        unless fabric_idx
          return encode_noc_response(NodeOperationalCertStatus::InvalidFabricIndex, nil, "Invalid fabric index")
        end

        # Check if fabric exists
        unless @fabric_table.get_fabric(fabric_idx)
          return encode_noc_response(NodeOperationalCertStatus::InvalidFabricIndex, nil, "Fabric not found")
        end

        # Remove fabric
        if @fabric_table.remove_fabric(fabric_idx)
          # Remove all fabric-scoped data
          # According to Matter spec, when a fabric is removed, all fabric-scoped
          # data must also be removed, including ACL entries, bindings, etc.

          # Remove ACL entries for this fabric
          if acl_cluster = @access_control_cluster
            acl_cluster.remove_fabric_acl(fabric_idx)
          end

          increment_version

          encode_noc_response(NodeOperationalCertStatus::Ok, fabric_idx)
        else
          encode_noc_response(NodeOperationalCertStatus::InvalidFabricIndex, nil, "Failed to remove fabric")
        end
      end

      private def handle_add_trusted_root_certificate(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::AddTrustedRootCertificateRequest.new(fields)

        # Validate failsafe is armed
        # NOTE: @failsafe_armed should be set by protocol layer, defaults to true for testing
        # NOTE: This command has no response according to Matter spec, but we return empty
        # bytes to indicate completion (success or failure cannot be distinguished)
        unless @failsafe_armed
          return Bytes.new(0)
        end

        # Cannot set root cert twice in same failsafe
        if @failsafe_context.root_cert_set
          return Bytes.new(0)
        end

        # Cannot set root cert after AddNOC/UpdateNOC
        if @failsafe_context.noc_added_or_updated
          return Bytes.new(0)
        end

        # Validate certificate format
        unless validate_certificate_format(request.root_certificate)
          return Bytes.new(0)
        end

        # Store root certificate
        @trusted_root_certs << request.root_certificate
        @failsafe_context.root_cert_set = true
        increment_version

        # This command has no response (returns empty bytes on success)
        Bytes.new(0)
      end

      # Failsafe management

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

      # Public command handlers that accept command structs
      # These are used by tests and provide a structured interface

      # AttestationRequest command (0x00)
      # Request device attestation during commissioning
      def handle_attestation_request(
        cmd : AttestationRequestCommand,
        session_id : UInt64,
      ) : AttestationResponse
        # Validate nonce is exactly 32 bytes (enforced by struct initializer)

        # Build attestation elements (TLV structure containing certification declaration, nonce, timestamp)
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

        # Validate certificate format
        unless validate_certificate_format(cmd.root_ca_certificate)
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Invalid root certificate format"
          )
        end

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

        # Create default ACL entry for case_admin_subject
        # Matter spec requires creating an ACL entry that grants Administer privilege
        # to the commissioning administrator (case_admin_subject)
        if acl_cluster = @access_control_cluster
          default_acl = AccessControlCluster::AccessControlEntry.new(
            privilege: AccessControlCluster::AccessControlEntryPrivilege::Administer,
            auth_mode: AccessControlCluster::AccessControlEntryAuthMode::CASE,
            subjects: [cmd.case_admin_subject],
            targets: nil, # nil means all targets
            fabric_index: fabric.fabric_index
          )
          acl_cluster.acl << default_acl
          acl_cluster.increment_version
        end

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

        # Parse new NOC to verify fabric_id matches and extract node_id
        new_fabric_id = extract_fabric_id_from_noc(cmd.noc_value)
        if new_fabric_id != fabric.fabric_id
          return NOCResponse.new(
            status_code: NodeOperationalCertStatus::InvalidNoc,
            debug_text: "Fabric ID mismatch"
          )
        end

        # Extract new node_id from the updated NOC
        new_node_id = extract_node_id_from_noc(cmd.noc_value)

        # Update fabric with new NOC, node_id, and operational key
        fabric.operational_cert = cmd.noc_value
        fabric.intermediate_cert = cmd.icac_value
        fabric.operational_key = @pending_noc_key.not_nil!
        fabric.node_id = new_node_id

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
          # Remove all fabric-scoped data
          # According to Matter spec, when a fabric is removed, all fabric-scoped
          # data must also be removed, including ACL entries, bindings, etc.

          # Remove ACL entries for this fabric
          if acl_cluster = @access_control_cluster
            acl_cluster.remove_fabric_acl(cmd.fabric_index)
          end

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

      # Helper methods for certificate operations

      private def build_attestation_elements(nonce : Bytes) : Bytes
        # Build TLV structure for attestation elements
        # TLV structure: {
        #   1 => declaration (bytes - PKCS#7 SignedData)
        #   2 => attestationNonce (32 bytes)
        #   3 => timestamp (UInt32)
        # }
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Generate Certification Declaration using our certificate manager
        declaration = Certificate::CertificationDeclaration.generate(@vendor_id, @product_id)
        timestamp = Time.utc.to_unix.to_u32

        data = {
          1_u8 => declaration,
          2_u8 => nonce,
          3_u8 => timestamp,
        } of TLV::Tag => TLV::Value

        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def sign_attestation(data : Bytes) : Bytes
        # Sign with attestation key using ECDSA
        unless key = @attestation_key
          raise "Attestation key not configured"
        end

        # Sign with ECDSA in IEEE P1363 format (r||s, 64 bytes for P-256)
        Crypto.sign_ecdsa(key, data, "ieee-p1363")
      end

      private def build_csr_elements(nonce : Bytes, key : Crypto::Key) : Bytes
        # Build TLV structure for CSR elements
        # TLV structure: {
        #   1 => certSigningRequest (bytes - DER-encoded CSR)
        #   2 => csrNonce (32 bytes)
        # }

        # Create a DER-encoded CSR with the public key
        csr = build_csr_der(key)

        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        data = {
          1_u8 => csr,
          2_u8 => nonce,
        } of TLV::Tag => TLV::Value

        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def build_csr_der(key : Crypto::Key) : Bytes
        # Build a simplified DER-encoded Certificate Signing Request
        # This is a basic CSR containing just the public key
        # Format based on PKCS#10 / RFC 2986

        # Get public key bytes
        pub_key = key.public_key

        # Build CSR info structure (version, subject, public key)
        csr_info_io = IO::Memory.new

        # Version (INTEGER 0)
        csr_info_io.write Bytes[0x02, 0x01, 0x00]

        # Subject (empty SEQUENCE for CSR)
        # SEQUENCE { SET { SEQUENCE { OID, UTF8String "CSR" } } }
        # Simplified: just use empty subject
        csr_info_io.write Bytes[0x30, 0x00] # Empty SEQUENCE

        # SubjectPublicKeyInfo (SPKI format)
        # Use the crypto module's DER building capability
        spki = Crypto::StandardCrypto.new.build_ec_public_key_der(pub_key)
        csr_info_io.write spki

        # Context tag [0] for attributes (empty)
        csr_info_io.write Bytes[0xa0, 0x00]

        csr_info = csr_info_io.to_slice

        # Sign the CSR info with the key
        unless attestation_key = @attestation_key
          raise "Attestation key required for CSR"
        end
        signature = Crypto.sign_ecdsa(attestation_key, csr_info, "der")

        # Build final CSR: SEQUENCE { csrInfo, signAlgorithm, signature }
        csr_io = IO::Memory.new

        # CSR info
        csr_io.write_byte 0x30_u8 # SEQUENCE tag
        write_der_length(csr_io, csr_info.size)
        csr_io.write csr_info

        # Signature algorithm (ECDSA with SHA-256)
        # SEQUENCE { OID ecdsa-with-SHA256 }
        sig_algo = Bytes[0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02]
        csr_io.write sig_algo

        # Signature (BIT STRING)
        csr_io.write_byte 0x03_u8 # BIT STRING tag
        write_der_length(csr_io, signature.size + 1)
        csr_io.write_byte 0x00_u8 # No unused bits
        csr_io.write signature

        # Wrap in final SEQUENCE
        csr_content = csr_io.to_slice
        result = IO::Memory.new
        result.write_byte 0x30_u8 # SEQUENCE tag
        write_der_length(result, csr_content.size)
        result.write csr_content

        result.to_slice
      end

      private def write_der_length(io : IO, length : Int)
        if length < 128
          io.write_byte length.to_u8
        else
          # Long form
          bytes = [] of UInt8
          temp = length
          while temp > 0
            bytes.unshift(temp.to_u8 & 0xFF)
            temp >>= 8
          end
          io.write_byte (0x80 | bytes.size).to_u8
          bytes.each { |b| io.write_byte b }
        end
      end

      private def extract_fabric_id_from_noc(noc : Bytes) : UInt64
        # Parse Matter certificate TLV to extract fabricId (field 21)
        # Matter certificates are TLV-encoded structures
        begin
          reader = TLV::Reader.new(noc)
          cert_data = reader.get

          # Navigate to the certificate structure
          # The NOC is a TLV structure containing subject fields
          # Look for field 21 (fabricId) in the certificate data
          fabric_id = find_tlv_field(cert_data, 21_u8)

          unless fabric_id
            raise "fabricId not found in NOC certificate"
          end

          # fabricId should be a UInt64
          case fabric_id
          when UInt64
            fabric_id
          when Int
            fabric_id.to_u64
          else
            raise "Invalid fabricId type: #{fabric_id.class}"
          end
        rescue ex
          # If parsing fails, raise with context
          raise "Failed to parse NOC certificate: #{ex.message}"
        end
      end

      private def extract_node_id_from_noc(noc : Bytes) : UInt64
        # Parse Matter certificate TLV to extract nodeId (field 17)
        begin
          reader = TLV::Reader.new(noc)
          cert_data = reader.get

          # Look for field 17 (nodeId) in the certificate data
          node_id = find_tlv_field(cert_data, 17_u8)

          unless node_id
            raise "nodeId not found in NOC certificate"
          end

          # nodeId should be a UInt64
          case node_id
          when UInt64
            node_id
          when Int
            node_id.to_u64
          else
            raise "Invalid nodeId type: #{node_id.class}"
          end
        rescue ex
          # If parsing fails, raise with context
          raise "Failed to parse NOC certificate: #{ex.message}"
        end
      end

      # Helper method to recursively find a TLV field by tag
      private def find_tlv_field(data : TLV::Value, tag : UInt8) : TLV::Value?
        case data
        when Hash
          # TLV library stores tags as strings, so convert tag to string
          tag_str = tag.to_s

          # Check if the tag exists in the hash as string
          return data[tag_str]? if data.has_key?(tag_str)

          # Also check numeric tag (UInt8)
          return data[tag]? if data.has_key?(tag)

          # Recursively search in nested hashes
          data.each_value do |value|
            if found = find_tlv_field(value, tag)
              return found
            end
          end
        when Array
          # Recursively search in array elements
          data.each do |value|
            if found = find_tlv_field(value, tag)
              return found
            end
          end
        end

        nil
      end

      # Validate basic certificate format (DER-encoded X.509)
      private def validate_certificate_format(cert : Bytes) : Bool
        # Check certificate is not empty
        return false if cert.empty?

        # Check certificate size is reasonable
        # Matter spec indicates certificates are typically 100-600 bytes
        return false if cert.size < 50 || cert.size > 1024

        # Check basic DER format (must start with SEQUENCE tag)
        return false if cert[0] != 0x30_u8

        # Check length encoding is valid
        if cert.size >= 2
          length_byte = cert[1]
          # Short form (length < 128) or long form indicator
          if length_byte >= 0x80
            # Long form - check we have enough bytes
            num_length_bytes = length_byte & 0x7F
            return false if num_length_bytes > 4 # Unreasonably long
            return false if cert.size < 2 + num_length_bytes
          end
        else
          return false
        end

        true
      end

      # TLV Encoding methods

      private def encode_noc_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Encode array of NOCStruct for all fabrics
        array_data = @fabric_table.all_fabrics.flat_map do |fabric|
          nocs(fabric.fabric_index).map do |noc_struct|
            {
                1_u8 => noc_struct.noc,
                2_u8 => noc_struct.icac,
              254_u8 => noc_struct.fabric_index,
            } of TLV::Tag => TLV::Value
          end
        end

        writer.put(nil, array_data)
        io.rewind.to_slice
      end

      private def encode_fabric_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Encode array of FabricDescriptorStruct
        array_data = fabrics.map do |fabric|
          {
              1_u8 => fabric.root_public_key,
              2_u8 => fabric.vendor_id,
              3_u8 => fabric.fabric_id,
              4_u8 => fabric.node_id,
              5_u8 => fabric.label,
            254_u8 => fabric.fabric_index,
          } of TLV::Tag => TLV::Value
        end

        writer.put(nil, array_data)
        io.rewind.to_slice
      end

      private def encode_certificate_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Encode array of certificate bytes
        writer.put(nil, @trusted_root_certs)
        io.rewind.to_slice
      end

      private def encode_noc_response(status : NodeOperationalCertStatus, fabric_index : UInt8?, debug_text : String? = nil) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        data = {
          0_u8 => status.value,
        } of TLV::Tag => TLV::Value

        if fabric_index
          data[1_u8] = fabric_index
        end

        if debug_text
          data[2_u8] = debug_text
        end

        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def encode_error_response(message : String) : Bytes
        # Return a simple error response
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => message,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end
    end
  end
end
