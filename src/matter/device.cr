module Matter
  abstract class Device
    # Fallback logger for the device files that do not define their own `Log`.
    Log = ::Log.for("matter.device")
  end
end

# A Matter device application: `runtime.cr` holds the node, its persistence,
# its transport and its commissioning lifecycle; `dsl.cr` the declarations an
# application writes it with.
require "./device/persistence"
require "./device/lifecycle_manager"
require "./device/dsl"
require "./device/runtime"
