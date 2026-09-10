# Matter controller (commissioner / client) entrypoint.
#
# The core `matter` library is device-only; require this file to get the
# mDNS scanner, secure client, PASE/CASE pairing and commissioning flows.
require "../matter"

require "./controller/scanner"
require "./controller/state"
require "./controller/state_store"
require "./controller/certificate_util"
require "./controller/client"
require "./controller/im_client"
require "./controller/clusters/access_control"
require "./controller/pairing/pase_pairing"
require "./controller/pairing/case_pairing"
require "./controller/commissioning/commissioner"
require "./controller/commissioning/window_opener"
