require "../src/matter"
require "tlv"

# Add helper to main TLV module
require "../../tlv/src/tlv/helpers"

# Demo: Before and After using TLV::Helpers

puts "=" * 70
puts "TLV Helpers Demo - Simplifying ReadRequest Parsing"
puts "=" * 70
puts ""

# Sample ReadRequest TLV from iPhone
tlv_data = "1536001724020024031d2404031818290324ff0c18".hexbytes

reader = TLV::Reader.new(tlv_data)
data = reader.get

puts "Raw TLV structure: #{data.inspect[0, 80]}..."
puts ""

# ======================================================================
# BEFORE: Manual parsing with lots of boilerplate
# ======================================================================

puts "📝 BEFORE (current manual approach):"
puts ""

request_data = data["Any"].as(Hash(TLV::Tag, TLV::Value))

if attr_req_array = request_data[0_u8]?.as?(Array)
  attr_req_array.each do |attr_req|
    if attr_req.is_a?(Array)
      arr = attr_req.as(Array)
      ep_val = arr[0]?.as?(Int32)
      endpoint = ep_val ? ep_val.to_u16 : nil
      cl_val = arr[1]?.as?(Int32)
      cluster = cl_val ? cl_val.to_u32 : nil
      at_val = arr[2]?.as?(Int32)
      attribute = at_val ? at_val.to_u32 : nil

      cluster_hex = cluster ? "0x#{cluster.to_s(16)}" : "nil"
      puts "  ⚠️  Manual: endpoint=#{endpoint}, cluster=#{cluster_hex}, attr=#{attribute}"
    elsif attr_req.is_a?(Hash)
      path_data = attr_req.as(Hash(TLV::Tag, TLV::Value))
      endpoint = path_data[2_u8]?.as?(UInt16)
      cluster = path_data[3_u8]?.as?(UInt32)
      attribute = path_data[4_u8]?.as?(UInt32)

      cluster_hex = cluster ? "0x#{cluster.to_s(16)}" : "nil"
      puts "  ⚠️  Manual: endpoint=#{endpoint}, cluster=#{cluster_hex}, attr=#{attribute}"
    end
  end
end

puts ""

# ======================================================================
# AFTER: Using TLV::Helpers
# ======================================================================

puts "✨ AFTER (with TLV::Helpers):"
puts ""

# Unwrap anonymous structure
request = TLV::Helpers.unwrap_anonymous(data)

# Get attribute requests array
if attr_requests = TLV::Helpers.get_array(request, 0)
  attr_requests.each do |attr_req|
    # Parse path (handles both list and structure forms automatically!)
    endpoint, cluster, attribute = TLV::Helpers.parse_attribute_path(attr_req)
    puts "  ✅ Simple: endpoint=#{endpoint}, cluster=0x#{cluster.try(&.to_s(16)) || "nil"}, attr=#{attribute}"
  end
end

# Get fabric_filtered flag
fabric_filtered = TLV::Helpers.get_bool(request, 3, default: true)
puts "  Fabric filtered: #{fabric_filtered}"

puts ""
puts "=" * 70
puts "Code Comparison:"
puts "=" * 70
puts ""
puts "Lines of code:"
puts "  Before: ~40 lines with type casts and conditionals"
puts "  After:  ~5 lines using helpers"
puts ""
puts "Benefits:"
puts "  ✅ Handles both list and structure forms automatically"
puts "  ✅ Cleaner error handling"
puts "  ✅ Type-safe conversions"
puts "  ✅ More readable"
