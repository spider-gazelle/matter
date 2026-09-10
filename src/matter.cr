require "big"
require "log"
require "json"
require "time/instant"

require "tlv"
require "verhoeff"

module Matter
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}

  # Fallback logger for files that do not define their own `Log` constant.
  Log = ::Log.for("matter")
end

# Subsystems are loaded in dependency order: lower layers first.
require "./matter/hex"
require "./matter/datatype"
require "./matter/interaction_model"
require "./matter/codec"
require "./matter/crypto"
require "./matter/certificate"
require "./matter/storage"
require "./matter/fabric"
require "./matter/fabric_table"
require "./matter/network"
require "./matter/transport"
require "./matter/session"
require "./matter/commissioning_window"
require "./matter/failsafe_timer"
require "./matter/failsafe_context"
require "./matter/cluster"
require "./matter/protocol"
# Storage::Manager depends on the fabric table, protocol persistence and
# clusters, so it cannot live in `matter/storage`. Phase 3 of the refactor
# moves it out of the storage namespace.
require "./matter/storage/manager"
require "./matter/mdns"
require "./matter/device_type"
require "./matter/endpoint"
require "./matter/setup_payload"
require "./matter/device"
