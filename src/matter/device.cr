# Device runtime: fabric lifecycle management and the `Device::Base` node.
module Matter
  module Device
    # Fallback logger for device files that do not define their own `Log`.
    Log = ::Log.for("matter.device")
  end
end

require "./device/lifecycle_manager"
require "./device/base"
