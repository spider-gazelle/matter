require "../../src/matter/commissioning"

# Records what a failsafe rollback asked it to restore, so a rollback can be
# asserted on without a cluster.
class RecordingRollbackTarget
  include Matter::Commissioning::RollbackTargets

  getter network_state : Hash(String, String)?
  getter regulatory_config : Tuple(UInt8, String)?
  getter windows_closed : Int32 = 0

  def restore_network_state(snapshot : Hash(String, String)) : Nil
    @network_state = snapshot
  end

  def restore_regulatory_config(location_type : UInt8, country_code : String) : Nil
    @regulatory_config = {location_type, country_code}
  end

  def close_commissioning_window : Nil
    @windows_closed += 1
  end
end

# Every restore step fails; a rollback must still complete.
class RaisingRollbackTarget
  include Matter::Commissioning::RollbackTargets

  def restore_network_state(snapshot : Hash(String, String)) : Nil
    raise Matter::CommissioningError.new("network restore failed")
  end

  def restore_regulatory_config(location_type : UInt8, country_code : String) : Nil
    raise Matter::CommissioningError.new("regulatory restore failed")
  end

  def close_commissioning_window : Nil
    raise Matter::CommissioningError.new("window close failed")
  end
end

# Captures what the window service published, standing in for the cluster
# attributes a commissioner reads.
class RecordingWindowTarget
  include Matter::Commissioning::WindowTarget

  getter status : Matter::Commissioning::WindowStatus = Matter::Commissioning::WindowStatus::WindowNotOpen
  getter admin_fabric_index : UInt8?
  getter admin_vendor_id : UInt16?
  getter notifications : Int32 = 0

  def publish_window_state(
    status : Matter::Commissioning::WindowStatus,
    admin_fabric_index : UInt8?,
    admin_vendor_id : UInt16?,
    notify : Bool,
  ) : Nil
    @status = status
    @admin_fabric_index = admin_fabric_index
    @admin_vendor_id = admin_vendor_id
    @notifications += 1 if notify
  end
end

# Records the credential changes the service publishes outside the fabric table.
class RecordingCredentialTarget
  include Matter::Commissioning::CredentialTarget

  getter trusted_root_certificates : Array(Bytes) = [] of Bytes
  getter changes : Int32 = 0
  getter committed : Array(Tuple(UInt8, UInt64)) = [] of Tuple(UInt8, UInt64)
  getter forgotten : Array(UInt8) = [] of UInt8

  def credentials_changed : Nil
    @changes += 1
  end

  def fabric_committed(fabric : Matter::Fabric, case_admin_subject : UInt64) : Nil
    @committed << {fabric.fabric_index, case_admin_subject}
  end

  def fabric_forgotten(fabric_index : UInt8) : Nil
    @forgotten << fabric_index
  end
end

# Matter TLV certificates the credential flow accepts.
module CommissioningCertificates
  extend self

  PUBLIC_KEY_SIZE = 65
  SIGNATURE_SIZE  = 64

  def public_key : Bytes
    key = Bytes.new(PUBLIC_KEY_SIZE, 0_u8)
    key[0] = 0x04_u8
    (1..32).each { |i| key[i] = i.to_u8 }
    (33..64).each { |i| key[i] = (i - 32).to_u8 }
    key
  end

  def root_certificate(rcac_id : UInt64 = 1_u64) : Bytes
    certificate(Matter::Crypto::DNAttributes.new(rcac_id: rcac_id))
  end

  def noc(fabric_id : UInt64 = 0x1234567890_u64, node_id : UInt64 = 0xABCDEF_u64) : Bytes
    certificate(Matter::Crypto::DNAttributes.new(fabric_id: fabric_id, node_id: node_id))
  end

  private def certificate(subject : Matter::Crypto::DNAttributes) : Bytes
    Matter::Crypto::MatterCertificate.new(
      serial_number: Bytes[0x01],
      signature_algorithm: 1_u8,
      issuer: Matter::Crypto::DNAttributes.new(rcac_id: 1_u64),
      not_before: 0_u32,
      not_after: 0xFFFFFFFF_u32,
      subject: subject,
      public_key_algorithm: 1_u8,
      elliptic_curve_id: 1_u8,
      ec_public_key: public_key,
      signature: Bytes.new(SIGNATURE_SIZE, 0xAB_u8)
    ).to_slice
  end
end
