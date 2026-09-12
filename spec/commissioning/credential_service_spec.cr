require "../spec_helper"
require "../../src/matter/commissioning/credential_service"

# The credential flow on its own: no cluster, no wire.
CSR_NONCE_SIZE =     32
IPK_SIZE       =     16
TEST_SESSION   = 42_u64

private def credential_service(target : RecordingCredentialTarget, max_fabrics : UInt8 = 5_u8) : Matter::Commissioning::CredentialService
  fabric_table = Matter::FabricTable.new(Matter::Storage::Memory.new, max_fabrics: max_fabrics)
  Matter::Commissioning::CredentialService.new(target, fabric_table)
end

# Walks the commissioning credential exchange up to (but not including) AddNOC
private def commission(service : Matter::Commissioning::CredentialService, session_id : UInt64 = TEST_SESSION) : Nil
  service.create_csr(
    nonce: Bytes.new(CSR_NONCE_SIZE, 0x42_u8),
    session_id: session_id,
    is_for_update_noc: false,
    pase_session: true
  )
  service.add_trusted_root_certificate(CommissioningCertificates.root_certificate)
end

module Matter::Commissioning
  describe CredentialService do
    describe "#create_csr" do
      it "generates a CSR and remembers the session it belongs to" do
        service = credential_service(RecordingCredentialTarget.new)

        result = service.create_csr(
          nonce: Bytes.new(CSR_NONCE_SIZE, 0x42_u8),
          session_id: TEST_SESSION,
          is_for_update_noc: false,
          pase_session: true
        )

        result.should_not be_nil
        elements, signature = result.as(Tuple(Bytes, Bytes))
        elements.should_not be_empty
        signature.should_not be_empty
        service.pending.csr_exists?(TEST_SESSION).should be_true
      end

      it "refuses without an armed failsafe" do
        service = credential_service(RecordingCredentialTarget.new)
        service.failsafe_armed = false

        service.create_csr(
          nonce: Bytes.new(CSR_NONCE_SIZE, 0x42_u8),
          session_id: TEST_SESSION,
          is_for_update_noc: false,
          pase_session: true
        ).should be_nil
      end

      it "refuses an UpdateNOC CSR on a PASE session" do
        service = credential_service(RecordingCredentialTarget.new)

        service.create_csr(
          nonce: Bytes.new(CSR_NONCE_SIZE, 0x42_u8),
          session_id: TEST_SESSION,
          is_for_update_noc: true,
          pase_session: true
        ).should be_nil
      end
    end

    describe "#add_trusted_root_certificate" do
      it "stores the root certificate of this failsafe" do
        target = RecordingCredentialTarget.new
        service = credential_service(target)

        outcome = service.add_trusted_root_certificate(CommissioningCertificates.root_certificate)

        outcome.ok?.should be_true
        target.trusted_root_certificates.size.should eq(1)
        target.changes.should eq(1)
      end

      it "refuses a second root certificate in the same failsafe" do
        service = credential_service(RecordingCredentialTarget.new)
        service.add_trusted_root_certificate(CommissioningCertificates.root_certificate)

        outcome = service.add_trusted_root_certificate(CommissioningCertificates.root_certificate)

        outcome.status.should eq(NocStatus::InvalidNoc)
      end

      it "rejects something that is not a certificate" do
        service = credential_service(RecordingCredentialTarget.new)

        outcome = service.add_trusted_root_certificate(Bytes.new(8, 0xFF_u8))

        outcome.status.should eq(NocStatus::InvalidNoc)
      end
    end

    describe "#add_noc" do
      it "joins the fabric of the NOC" do
        target = RecordingCredentialTarget.new
        service = credential_service(target)
        added = [] of Fabric
        service.on_fabric_added = ->(fabric : Fabric) { added << fabric; nil }
        commission(service)

        outcome = service.add_noc(
          noc: CommissioningCertificates.noc,
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: TEST_SESSION
        )

        outcome.ok?.should be_true
        service.fabric_table.size.should eq(1)
        added.size.should eq(1)
        target.committed.should eq([{outcome.fabric_index.as(UInt8), 0x9999_u64}])
      end

      it "refuses a node certificate the trusted root did not issue" do
        service = credential_service(RecordingCredentialTarget.new)
        commission(service)

        outcome = service.add_noc(
          noc: CommissioningCertificates.foreign_noc,
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: TEST_SESSION
        )

        outcome.ok?.should be_false
        outcome.status.should eq(Matter::Commissioning::NocStatus::InvalidNoc)
        service.fabric_table.size.should eq(0)
      end

      it "requires the CSR of this session" do
        service = credential_service(RecordingCredentialTarget.new)
        commission(service, session_id: 1_u64)

        outcome = service.add_noc(
          noc: CommissioningCertificates.noc,
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: 2_u64
        )

        outcome.status.should eq(NocStatus::MissingCsr)
      end

      it "requires a root certificate" do
        service = credential_service(RecordingCredentialTarget.new)
        service.create_csr(
          nonce: Bytes.new(CSR_NONCE_SIZE, 0x42_u8),
          session_id: TEST_SESSION,
          is_for_update_noc: false,
          pase_session: true
        )

        outcome = service.add_noc(
          noc: CommissioningCertificates.noc,
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: TEST_SESSION
        )

        outcome.status.should eq(NocStatus::InvalidNoc)
      end

      it "refuses a NOC it cannot parse" do
        service = credential_service(RecordingCredentialTarget.new)
        commission(service)

        outcome = service.add_noc(
          noc: Bytes.new(100, 0_u8),
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: TEST_SESSION
        )

        outcome.status.should eq(NocStatus::InvalidNoc)
        outcome.debug_text.should_not be_nil
      end

      it "refuses to join the same fabric twice" do
        service = credential_service(RecordingCredentialTarget.new)
        commission(service)
        service.add_noc(
          noc: CommissioningCertificates.noc,
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: TEST_SESSION
        ).ok?.should be_true

        # A second commissioning session, same fabric and root certificate
        service.reset_pending
        commission(service)
        outcome = service.add_noc(
          noc: CommissioningCertificates.noc,
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: TEST_SESSION
        )

        outcome.status.should eq(NocStatus::FabricConflict)
      end
    end

    describe "#remove_fabric" do
      it "leaves the fabric and drops what was scoped to it" do
        target = RecordingCredentialTarget.new
        service = credential_service(target)
        removed = [] of UInt8
        service.on_fabric_removed = ->(fabric_index : UInt8) { removed << fabric_index; nil }
        commission(service)
        added = service.add_noc(
          noc: CommissioningCertificates.noc,
          icac: nil,
          ipk: Bytes.new(IPK_SIZE, 0_u8),
          case_admin_subject: 0x9999_u64,
          admin_vendor_id: 0xFFF1_u16,
          session_id: TEST_SESSION
        )
        fabric_index = added.fabric_index.as(UInt8)

        outcome = service.remove_fabric(fabric_index)

        outcome.ok?.should be_true
        service.fabric_table.size.should eq(0)
        removed.should eq([fabric_index])
        target.forgotten.should eq([fabric_index])
      end

      it "rejects the reserved fabric index" do
        service = credential_service(RecordingCredentialTarget.new)

        outcome = service.remove_fabric(DataType::NO_FABRIC)

        outcome.status.should eq(NocStatus::InvalidFabricIndex)
      end
    end

    describe "#public_key_from_certificate" do
      it "reads the public key of a Matter TLV certificate" do
        service = credential_service(RecordingCredentialTarget.new)

        key = service.public_key_from_certificate(CommissioningCertificates.root_certificate)

        key.should eq(CommissioningCertificates.root_public_key)
      end

      it "rejects a certificate in an unknown format" do
        service = credential_service(RecordingCredentialTarget.new)

        expect_raises(Matter::CertificateError, /Unknown certificate format/) do
          service.public_key_from_certificate(Bytes[0xFF, 0x01, 0x02])
        end
      end
    end

    describe "#reset_pending" do
      it "forgets the credentials of a failsafe that ended" do
        service = credential_service(RecordingCredentialTarget.new)
        commission(service)

        service.reset_pending

        service.pending.csr_exists?(TEST_SESSION).should be_false
        service.pending.root_cert_set?.should be_false
      end
    end
  end
end
