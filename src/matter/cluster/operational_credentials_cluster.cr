require "./cluster"
require "./definitions/operational_credentials"

module Matter
  module Cluster
    # Operational Credentials Cluster (0x003E)
    #
    # Functionality to manage operational certificates and fabric membership.
    # This cluster is required for Matter commissioning and fabric management.
    #
    # Matter Spec: Core 11.17
    class OperationalCredentialsCluster < Base
      CLUSTER_ID = 0x003E_u32

      # Certificate Chain Type
      enum CertificateChainType : UInt8
        DACCertificate = 1 # Device Attestation Certificate
        PAICertificate = 2 # Product Attestation Intermediate Certificate
      end

      # Node Operational Certificate Status Codes
      enum NodeOperationalCertStatus : UInt8
        OK                    =  0 # Success
        InvalidPublicKey      =  1 # Public key invalid
        InvalidNodeOpId       =  2 # Node Operational ID invalid
        InvalidNOC            =  3 # NOC invalid
        MissingCsr            =  4 # CSR not found
        TableFull             =  5 # Fabric table full
        InvalidAdminSubject   =  6 # AdminSubject field is invalid
        Reserved              =  7 # Reserved
        InsufficientPrivilege =  8 # Insufficient privilege
        FabricConflict        =  9 # Fabric collision
        LabelConflict         = 10 # Label conflict
        InvalidFabricIndex    = 11 # Invalid fabric index
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

      # Attribute storage
      property nocs : Array(NOCStruct)
      property fabrics : Array(FabricDescriptorStruct)
      property supported_fabrics : UInt8
      property commissioned_fabrics : UInt8
      property trusted_root_certificates : Array(Bytes)
      property current_fabric_index : UInt8

      # Operational state
      property csr_nonce : Bytes?
      property attestation_challenge : Bytes?

      # Device Attestation Certificate (DAC) and Product Attestation Intermediate (PAI)
      property dac_certificate : Bytes?
      property pai_certificate : Bytes?
      property dac_private_key : Crypto::Key?

      # Callbacks
      property on_attestation_request : Proc(Bytes, Tuple(Bytes, Bytes))? # (nonce) -> (attestation_elements, signature)
      property on_csr_request : Proc(Bytes, Tuple(Bytes, Bytes))?         # (nonce) -> (csr_elements, signature)
      property on_add_noc : Proc(Bytes, Bytes?, Bytes, UInt64, UInt16, NodeOperationalCertStatus)?
      property on_update_noc : Proc(Bytes, Bytes?, NodeOperationalCertStatus)?
      property on_remove_fabric : Proc(UInt8, NodeOperationalCertStatus)?

      def initialize(endpoint_id : DataType::EndpointNumber)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @nocs = [] of NOCStruct
        @fabrics = [] of FabricDescriptorStruct
        @supported_fabrics = 16_u8 # Matter spec minimum
        @commissioned_fabrics = 0_u8
        @trusted_root_certificates = [] of Bytes
        @current_fabric_index = 0_u8

        @csr_nonce = nil
        @attestation_challenge = nil

        @dac_certificate = nil
        @pai_certificate = nil
        @dac_private_key = nil

        @on_attestation_request = nil
        @on_csr_request = nil
        @on_add_noc = nil
        @on_update_noc = nil
        @on_remove_fabric = nil
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

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_NOCS
          encode_noc_list
        when ATTR_FABRICS
          encode_fabric_list
        when ATTR_SUPPORTED_FABRICS
          encode_uint8(@supported_fabrics)
        when ATTR_COMMISSIONED_FABRICS
          encode_uint8(@commissioned_fabrics)
        when ATTR_TRUSTED_ROOT_CERTIFICATES
          encode_certificate_list
        when ATTR_CURRENT_FABRIC_INDEX
          encode_uint8(@current_fabric_index)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        # All attributes are read-only
        super
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        case command_id
        when CMD_ATTESTATION_REQUEST
          handle_attestation_request(fields)
        when CMD_CERTIFICATE_CHAIN_REQUEST
          handle_certificate_chain_request(fields)
        when CMD_CSR_REQUEST
          handle_csr_request(fields)
        when CMD_ADD_NOC
          handle_add_noc(fields)
        when CMD_UPDATE_NOC
          handle_update_noc(fields)
        when CMD_UPDATE_FABRIC_LABEL
          handle_update_fabric_label(fields)
        when CMD_REMOVE_FABRIC
          handle_remove_fabric(fields)
        when CMD_ADD_TRUSTED_ROOT_CERTIFICATE
          handle_add_trusted_root_certificate(fields)
        else
          super
        end
      end

      private def handle_attestation_request(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::AttestationRequest.new(fields)

        # Use callback if available, otherwise return empty response
        attestation_elements, signature = if callback = @on_attestation_request
                                            callback.call(request.attestation_nonce)
                                          else
                                            {Bytes.new(0), Bytes.new(0)}
                                          end

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => attestation_elements,
          1_u8 => signature,
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
                        @dac_certificate
                      when Definitions::OperationalCredentials::CertificateChainType::PaiCertificate
                        @pai_certificate
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

        # Use callback if available, otherwise return empty response
        csr_elements, signature = if callback = @on_csr_request
                                    callback.call(request.csr_nonce)
                                  else
                                    {Bytes.new(0), Bytes.new(0)}
                                  end

        # Encode response as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => csr_elements,
          1_u8 => signature,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_add_noc(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::AddNocRequest.new(fields)

        # Use callback if available
        status = if callback = @on_add_noc
                   callback.call(
                     request.noc_value,
                     request.icac_value,
                     request.ipk_value,
                     request.case_admin_subject.id,
                     request.admin_vendor_id.id
                   )
                 else
                   # Default: return OK status
                   NodeOperationalCertStatus::OK
                 end

        # Encode NOCResponse as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => status.value,
          # fabric_index at tag 1 would go here on success
          # debug_text at tag 2 would go here if needed
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_update_noc(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::UpdateNocRequest.new(fields)

        # Use callback if available
        status = if callback = @on_update_noc
                   callback.call(request.noc_value, request.icac_value)
                 else
                   # Default: return OK status
                   NodeOperationalCertStatus::OK
                 end

        # Encode NOCResponse as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = if fabric_index = request.fabric_index.index
                 {
                   0_u8 => status.value,
                   1_u8 => fabric_index,
                 } of TLV::Tag => TLV::Value
               else
                 {
                   0_u8 => status.value,
                 } of TLV::Tag => TLV::Value
               end
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_update_fabric_label(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::UpdateFabricLabelRequest.new(fields)

        # Update fabric label
        fabric_idx = request.fabric_index.index
        status = if fabric_idx && (fabric = get_fabric_by_index(fabric_idx))
                   fabric.label = request.label
                   increment_version
                   NodeOperationalCertStatus::OK
                 else
                   NodeOperationalCertStatus::InvalidFabricIndex
                 end

        # Encode NOCResponse as TLV
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = if status == NodeOperationalCertStatus::OK && fabric_idx
                 {
                   0_u8 => status.value,
                   1_u8 => fabric_idx,
                 } of TLV::Tag => TLV::Value
               else
                 {
                   0_u8 => status.value,
                 } of TLV::Tag => TLV::Value
               end
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_remove_fabric(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::RemoveFabricRequest.new(fields)

        # Use callback if available
        fabric_idx = request.fabric_index.index
        status = if fabric_idx && (callback = @on_remove_fabric)
                   callback.call(fabric_idx)
                 elsif fabric_idx
                   # Default implementation: remove fabric and NOC
                   if get_fabric_by_index(fabric_idx)
                     @fabrics.reject! { |f| f.fabric_index == fabric_idx }
                     @nocs.reject! { |n| n.fabric_index == fabric_idx }
                     update_commissioned_fabrics
                     NodeOperationalCertStatus::OK
                   else
                     NodeOperationalCertStatus::InvalidFabricIndex
                   end
                 else
                   NodeOperationalCertStatus::InvalidFabricIndex
                 end

        # Encode NOCResponse as TLV (no fabric_index on removal)
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        data = {
          0_u8 => status.value,
        } of TLV::Tag => TLV::Value
        writer.put(nil, data)
        io.rewind.to_slice
      end

      private def handle_add_trusted_root_certificate(fields : Bytes) : Bytes
        # Parse TLV-encoded request
        request = Definitions::OperationalCredentials::AddTrustedRootCertificateRequest.new(fields)

        # Add trusted root certificate
        @trusted_root_certificates << request.root_certificate
        increment_version

        # This command has no response (returns empty bytes on success)
        Bytes.new(0)
      end

      # Helper: Get fabric by index
      def get_fabric_by_index(index : UInt8) : FabricDescriptorStruct?
        @fabrics.find { |f| f.fabric_index == index }
      end

      # Helper: Get NOC by fabric index
      def get_noc_by_fabric_index(index : UInt8) : NOCStruct?
        @nocs.find { |n| n.fabric_index == index }
      end

      # Helper: Check if there's capacity for more fabrics
      def has_fabric_capacity? : Bool
        @commissioned_fabrics < @supported_fabrics
      end

      # Helper: Allocate a new fabric index
      def allocate_fabric_index : UInt8?
        return nil unless has_fabric_capacity?

        # Find first available index (1-254)
        (1_u8..254_u8).each do |index|
          unless @fabrics.any? { |f| f.fabric_index == index }
            return index
          end
        end

        nil
      end

      # Helper: Update commissioned fabric count
      def update_commissioned_fabrics : Nil
        @commissioned_fabrics = @fabrics.size.to_u8
        increment_version
      end

      # TLV Encoding methods

      private def encode_noc_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Encode array of NOCStruct
        array_data = @nocs.map do |noc_struct|
          {
              1_u8 => noc_struct.noc,
              2_u8 => noc_struct.icac,
            254_u8 => noc_struct.fabric_index,
          } of TLV::Tag => TLV::Value
        end

        writer.put(nil, array_data)
        io.rewind.to_slice
      end

      private def encode_fabric_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Encode array of FabricDescriptorStruct
        array_data = @fabrics.map do |fabric|
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
        writer.put(nil, @trusted_root_certificates)
        io.rewind.to_slice
      end
    end
  end
end
