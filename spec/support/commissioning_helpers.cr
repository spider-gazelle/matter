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
