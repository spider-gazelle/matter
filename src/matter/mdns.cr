# mDNS / DNS-SD: service advertisement for commissionable and operational
# nodes. The device-side responder is loaded here; the scanner is
# controller-only and is loaded by `matter/controller`.
require "./mdns/service_type"
require "./mdns/record_builder"
require "./mdns/responder_interface"
require "./mdns/responder"

module Matter
  module MDNS
    Log = ::Log.for("matter.mdns")
  end
end
