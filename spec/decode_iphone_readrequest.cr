require "./spec_helper"
require "tlv"

# Decode the actual iPhone ReadRequest TLV to understand its structure
describe "iPhone ReadRequest TLV Structure" do
  it "decodes and displays the ReadRequest structure" do
    # From logs: Decrypted payload: 050249df01001536001724020024031d2404031818290324ff0c18
    # Skip payload header (first 6 bytes): 050249df0100
    # TLV starts at: 1536001724020024031d2404031818290324ff0c18

    tlv_payload = "1536001724020024031d2404031818290324ff0c18".hexbytes

    puts "\n🔍 Decoding iPhone ReadRequest TLV:"
    puts "  Payload: #{tlv_payload.hexstring}"
    puts "  Size: #{tlv_payload.size} bytes"
    puts ""

    reader = TLV::Reader.new(tlv_payload)
    data = reader.get

    puts "  Root type: #{data.class}"
    puts ""

    def dump_tlv(value, indent = 0)
      prefix = "  " * indent
      case value
      when Hash
        value.each do |tag, val|
          tag_str = case tag
                    when UInt8
                      "tag #{tag}"
                    when String
                      tag
                    when Tuple
                      "tag #{tag}"
                    else
                      tag.inspect
                    end
          puts "#{prefix}#{tag_str}:"
          dump_tlv(val, indent + 1)
        end
      when Array
        puts "#{prefix}Array[#{value.size}]:"
        value.each_with_index do |item, idx|
          puts "#{prefix}  [#{idx}]:"
          dump_tlv(item, indent + 2)
        end
      when Bytes
        puts "#{prefix}Bytes(#{value.size}): #{value.hexstring[0, [40, value.hexstring.size].min]}"
      else
        puts "#{prefix}#{value.class}: #{value}"
      end
    end

    dump_tlv(data)

    puts ""
    puts "Expected structure for ReadRequest:"
    puts "  Anonymous structure {"
    puts "    tag 0: AttributeRequests (array) ["
    puts "      Structure {"
    puts "        tag 2: Endpoint (uint16)"
    puts "        tag 3: Cluster (uint32)"
    puts "        tag 4: Attribute (uint32)"
    puts "      }"
    puts "    ]"
    puts "    tag 3: FabricFiltered (bool, optional)"
    puts "  }"
  end
end
