# mDNS / DNS-SD: service advertisement for commissionable and operational
# nodes. The device-side responder is loaded here; `mdns/scanner` is
# controller-only and is loaded by `matter/controller`.
require "./mdns/service_description"
require "./mdns/service_type"
require "./mdns/multicast_socket"
require "./mdns/server"
require "./mdns/record_builder"
require "./mdns/responder_interface"
require "./mdns/responder"
require "./mdns/commissionable_advertisement"
require "./mdns/advertiser"

module Matter
  module MDNS
    Log = ::Log.for("matter.mdns")
  end
end
