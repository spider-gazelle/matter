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
