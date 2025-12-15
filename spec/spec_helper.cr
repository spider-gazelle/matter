require "spec"
require "timecop"
require "../src/matter"
require "./support/test_network_backend"

# Helper to decode TLV-encoded attribute values
def decode_tlv_value(bytes : Bytes)
  parsed = TLV::Any.from_slice(bytes)
  parsed.value
end

# Helper to parse TLV arrays - returns the value, which should be an Array for list types
def parse_tlv_array(bytes : Bytes)
  parsed = TLV::Any.from_slice(bytes)
  parsed.value.as(Array(TLV::Any))
end

Spec.before_suite do
  ::Log.setup("*", :trace)
end
