require "spec"
require "timecop"
require "../src/matter"
require "./support/test_network_backend"

# Helper to decode TLV-encoded attribute values
def decode_tlv_value(bytes : Bytes)
  reader = TLV::Reader.new(bytes)
  reader.get["Any"]
end

Spec.before_suite do
  ::Log.setup("*", :trace)
end
