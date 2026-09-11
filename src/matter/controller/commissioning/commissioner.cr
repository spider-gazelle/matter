require "log"

require "../../cluster/general_commissioning"
require "../../cluster/operational_credentials"
require "../../crypto/certificate"
require "../../crypto/key"
require "../scanner"
require "../../setup_payload"

require "../certificate_util"
require "../client"
require "../im_client"
require "../pairing/case_pairing"
require "../pairing/pase_pairing"
require "../state"
require "../state_store"

module Matter
  module Controller
    module Commissioning
      class Commissioner
        Log = ::Log.for("matter.controller.commissioning.commissioner")

        def initialize(
          @store : StateStore,
          @client : Client = Client.new,
          @timeout : Time::Span = 15.seconds,
          @crypto : Crypto::CryptoBase = Crypto::StandardCrypto.new,
        )
        end

        def close : Nil
          @client.close
        end

        def pairing_code(
          node_id : UInt64,
          manual_code : String,
          peer : Socket::IPAddress? = nil,
        ) : Nil
          discriminator, pin_code = SetupPayload.parse_manual_code(manual_code)
          state = @store.load

          fabric = state.fabric
          unless fabric
            fabric = create_fabric(controller_node_id: state.commissioner_node_id)
            state.fabric = fabric
          end
          @store.save(state)

          peer_addr = peer || discover_commissionable(discriminator)

          Log.info { "Commissioning: discriminator=#{discriminator} node_id=0x#{node_id.to_s(16)} peer=#{peer_addr}" }

          pase = Pairing::PasePairing.new(@crypto)
          pase_session = pase.pair(@client, peer_addr, pin_code, timeout: @timeout)
          @client.register_session(pase_session)

          im = ImClient.new(@client, @timeout)

          arm = Cluster::GeneralCommissioning::ArmFailSafeRequest.new(
            expiry_length_seconds: 60_u16,
            breadcrumb: 0_u64,
            timeout_ms: 0_u32
          )
          arm_resp = im.invoke(
            session: pase_session,
            peer: peer_addr,
            endpoint_id: 0_u16,
            cluster_id: Cluster::GeneralCommissioning::CLUSTER_ID,
            command_id: Cluster::GeneralCommissioning::CMD_ARM_FAIL_SAFE,
            fields: arm.to_slice
          )
          assert_invoke_ok!(arm_resp, "ArmFailSafe")

          add_root_req = Cluster::OperationalCredentials::Tlv::AddTrustedRootCertificateRequest.new(
            root_certificate: fabric.root_cert.to_slice
          )
          add_root_resp = im.invoke(
            session: pase_session,
            peer: peer_addr,
            endpoint_id: 0_u16,
            cluster_id: Cluster::OperationalCredentials::CLUSTER_ID,
            command_id: Cluster::OperationalCredentials::CMD_ADD_TRUSTED_ROOT_CERTIFICATE,
            fields: add_root_req.to_slice
          )
          assert_invoke_ok!(add_root_resp, "AddTrustedRootCertificate")

          csr_nonce = @crypto.random_bytes(32)
          csr_req = Cluster::OperationalCredentials::Tlv::CsrRequest.new(
            csr_nonce: csr_nonce.to_slice,
            is_for_update_noc: nil
          )
          csr_resp_msg = im.invoke(
            session: pase_session,
            peer: peer_addr,
            endpoint_id: 0_u16,
            cluster_id: Cluster::OperationalCredentials::CLUSTER_ID,
            command_id: Cluster::OperationalCredentials::CMD_CSR_REQUEST,
            fields: csr_req.to_slice
          )
          csr_fields = first_command_fields(csr_resp_msg, Cluster::OperationalCredentials::CMD_CSR_REQUEST_RESPONSE)
          csr_resp = Cluster::OperationalCredentials::Tlv::CsrResponse.from_slice(csr_fields)
          csr_elements = Cluster::OperationalCredentials::CSRElements.from_slice(csr_resp.nocsr_elements)

          device_pub_key = CertificateUtil.extract_uncompressed_public_key_from_csr(csr_elements.csr)
          device_noc = create_noc(fabric_id: fabric.fabric_id, node_id: node_id, public_key: device_pub_key)

          add_noc_req = Cluster::OperationalCredentials::Tlv::AddNocRequest.new(
            noc_value: device_noc.to_slice,
            icac_value: nil,
            ipk_value: fabric.ipk_value.to_slice,
            case_admin_subject: fabric.controller_node_id,
            admin_vendor_id: fabric.admin_vendor_id
          )
          add_noc_resp_msg = im.invoke(
            session: pase_session,
            peer: peer_addr,
            endpoint_id: 0_u16,
            cluster_id: Cluster::OperationalCredentials::CLUSTER_ID,
            command_id: Cluster::OperationalCredentials::CMD_ADD_NOC,
            fields: add_noc_req.to_slice
          )
          noc_fields = first_command_fields(add_noc_resp_msg, Cluster::OperationalCredentials::CMD_ADD_NOC_RESPONSE)
          noc_resp = Cluster::OperationalCredentials::Tlv::TlvNocResponse.from_slice(noc_fields)
          unless noc_resp.status_code.ok?
            raise Matter::CommissioningError.new("AddNOC failed (status=#{noc_resp.status_code} debug=#{noc_resp.debug_text})")
          end

          case_pairing = Pairing::CasePairing.new(@crypto)
          case_session = case_pairing.pair(@client, peer_addr, fabric, peer_node_id: node_id, timeout: @timeout)

          commissioning_complete_resp = im.invoke(
            session: case_session,
            peer: peer_addr,
            endpoint_id: 0_u16,
            cluster_id: Cluster::GeneralCommissioning::CLUSTER_ID,
            command_id: Cluster::GeneralCommissioning::CMD_COMMISSIONING_COMPLETE,
            fields: Bytes.empty
          )
          assert_invoke_ok!(commissioning_complete_resp, "CommissioningComplete")

          state.nodes[node_id] = NodeInfo.new(node_id: node_id, address: peer_addr.address, port: peer_addr.port)
          state.unsecured_message_counter = @client.transport.message_counter.counter
          @store.save(state)
        end

        private def discover_commissionable(discriminator : UInt16) : Socket::IPAddress
          scanner = nil.as(Scanner?)
          scanner = Scanner.new
          scanner.start
          scanner.query_commissioning
          short_only = (discriminator & 0x00ff_u16) == 0_u16
          short_discriminator = SetupPayload.short_discriminator(discriminator)

          deadline = Time.instant + @timeout
          loop do
            dev = scanner.commissioning_devices.find do |device|
              disc = device.discriminator
              next false unless disc
              next true if disc == discriminator
              short_only && SetupPayload.short_discriminator(disc) == short_discriminator
            end
            if dev
              address = dev.addresses.find(&.family.inet?) || dev.addresses.first?
              if addr = address
                return Socket::IPAddress.new(addr.address, dev.port)
              end
            end

            break if Time.instant >= deadline
            sleep 100.milliseconds
          end

          raise Matter::TransportError.new("Failed to discover commissionable node via mDNS (discriminator=#{discriminator})")
        ensure
          scanner.try(&.close)
        end

        private def create_fabric(controller_node_id : UInt64) : FabricInfo
          fabric_id = loop do
            id = @crypto.random_uint64
            break id unless id == 0_u64
          end

          if controller_node_id == 0_u64
            raise ArgumentError.new("controller_node_id must be non-zero")
          end

          ipk = @crypto.random_bytes(16)

          root_key = Crypto::Key.generate_key_pair
          root_public_key = root_key.public_key
          root_cert = create_root_cert(root_public_key)

          controller_key = Crypto::Key.generate_key_pair
          controller_noc = create_noc(fabric_id: fabric_id, node_id: controller_node_id, public_key: controller_key.public_key)

          info = FabricInfo.new(
            fabric_id: fabric_id,
            controller_node_id: controller_node_id,
            ipk_value: ipk,
            root_cert: root_cert,
            root_public_key: root_public_key,
            controller_noc: controller_noc,
            controller_private_key: controller_key.private_key
          )
          info
        end

        private def create_root_cert(public_key : Bytes) : Bytes
          signature = @crypto.random_bytes(64)
          subject = Crypto::DNAttributes.new(rcac_id: 1_u64)
          issuer = Crypto::DNAttributes.new(rcac_id: 1_u64)

          Crypto::MatterCertificate.new(
            serial_number: Bytes[0x01],
            signature_algorithm: 1_u8,
            issuer: issuer,
            not_before: 0_u32,
            not_after: 0xFFFFFFFF_u32,
            subject: subject,
            public_key_algorithm: 1_u8,
            elliptic_curve_id: 1_u8,
            ec_public_key: public_key,
            signature: signature
          ).to_slice
        end

        private def create_noc(fabric_id : UInt64, node_id : UInt64, public_key : Bytes) : Bytes
          signature = @crypto.random_bytes(64)
          subject = Crypto::DNAttributes.new(fabric_id: fabric_id, node_id: node_id)
          issuer = Crypto::DNAttributes.new(rcac_id: 1_u64)

          Crypto::MatterCertificate.new(
            serial_number: Bytes[0x01],
            signature_algorithm: 1_u8,
            issuer: issuer,
            not_before: 0_u32,
            not_after: 0xFFFFFFFF_u32,
            subject: subject,
            public_key_algorithm: 1_u8,
            elliptic_curve_id: 1_u8,
            ec_public_key: public_key,
            signature: signature
          ).to_slice
        end

        private def assert_invoke_ok!(response : InteractionModel::InvokeResponseMessage, name : String) : Nil
          saw_any = false

          response.invoke_responses.each do |resp|
            if resp.command_data
              saw_any = true
              next
            end

            if status_ib = resp.command_status
              saw_any = true
              # Some commands use CommandStatusIB with Success and no CommandDataIB.
              return if status_ib.status.status == InteractionModel::StatusCode::Success.value
              raise Matter::CommissioningError.new("#{name} failed (status=#{status_ib.status.status})")
            end
          end

          raise Matter::ProtocolError.new("#{name} failed (empty InvokeResponse)") unless saw_any
        end

        private def first_command_fields(response : InteractionModel::InvokeResponseMessage, command_id : UInt32) : Bytes
          response.invoke_responses.each do |invoke_response|
            cmd = invoke_response.command_data
            next unless cmd
            next unless cmd.command_path.command == command_id
            fields = cmd.command_fields
            return fields ? fields.to_slice : Bytes.empty
          end
          raise Matter::ProtocolError.new("InvokeResponse missing command_data for command_id=0x#{command_id.to_s(16)}")
        end
      end
    end
  end
end
