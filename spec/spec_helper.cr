require "spec"
require "timecop"
require "../src/matter"
require "./support/test_network_backend"
require "./support/cluster_helpers"
require "./support/commissioning_helpers"

# Some CI/sandbox environments disallow creating UDP sockets (Operation not permitted).
# Use this helper at the top of specs that require real sockets, so the rest of the
# suite can still run.
macro require_udp_sockets!
  begin
    socket = UDPSocket.new
    socket.close
  rescue ex : Socket::Error
    pending! "UDP sockets are not available in this environment: #{ex.message}"
  end
end

# Helper to decode TLV-encoded attribute values
def decode_tlv_value(value : TLV::Any)
  value.value
end

# Helper to parse TLV arrays - returns the value, which should be an Array for list types
def parse_tlv_array(value : TLV::Any)
  value.as_list
end

# Log level for the suite. Defaults to :warn to keep output quiet; set
# MATTER_SPEC_LOG=trace (or debug, info, ...) to see protocol tracing:
#   MATTER_SPEC_LOG=trace crystal spec
Spec.before_suite do
  level = ::Log::Severity.parse(ENV["MATTER_SPEC_LOG"]? || "warn")
  ::Log.setup("*", level)
end
