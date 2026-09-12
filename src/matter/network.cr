# Network commissioning support: constants, credentials, the backend
# abstraction used by the NetworkCommissioning cluster, and local address
# discovery for device advertisement.
module Matter
  module Network
    # Fallback logger for network files that do not define their own `Log`.
    Log = ::Log.for("matter.network")
  end
end

require "./network/constants"
require "./network/credentials"
require "./network/backend"
require "./network/local_addresses"
