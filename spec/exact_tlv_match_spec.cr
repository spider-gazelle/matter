require "./spec_helper"
require "tlv"

# Build exact matter.js encoding step-by-step to identify difference
describe "Exact TLV Match with matter.js" do
  it "builds structure step by step to match matter.js" do
    # Target: 153601153501260055156878370124020024032824040918240201181818290424ff0118
    # Decoded: {1 => [{1 => {0 => 2020087125, 1 => [0, 40, 9], 2 => 1}}], 4 => true, 255 => 1}

    io = IO::Memory.new
    writer = TLV::Writer.new(io)

    # Start root structure (anonymous)
    writer.start_structure(nil)

    # Tag 1: attributeReports (array)
    writer.start_array(1_u8)

    # Array element 0: AttributeReportIB
    writer.start_structure(nil)

    # Tag 1: attributeData (the AttributeDataIB)
    writer.start_structure(1_u8)

    # Tag 0: dataVersion
    writer.put(0_u8, 2020087125_u32)

    # Tag 1: path (as PATH container with TAGGED elements!)
    # PATH is TLV type 0x17
    # Elements use tags 2, 3, 4 (not anonymous!)
    writer.start_container(tag: 1_u8, container_type: 0x17_u8) # PATH type
    writer.put(2_u8, 0_u16)  # Tag 2: endpoint
    writer.put(3_u8, 40_u32) # Tag 3: cluster
    writer.put(4_u8, 9_u32)  # Tag 4: attribute
    writer.end_container # End path

    # Tag 2: data
    # matter.js encodes boolean as UInt8 value 1/0, not Bool type!
    writer.put(2_u8, 1_u8) # true encoded as UInt8 value 1

    writer.end_container # End AttributeDataIB (tag 1)
    writer.end_container # End AttributeReportIB
    writer.end_container # End attributeReports array

    # Tag 4: moreChunkedMessages
    # matter.js includes this field
    writer.put(4_u8, true) # This DOES use Bool type

    # Tag 0xFF: interactionModelRevision
    writer.put(0xFF_u8, 1_u8)

    writer.end_container # End root structure

    encoded = io.rewind.to_slice

    puts "\n=== Manual Step-by-Step Encoding ==="
    puts "Our hex:       #{encoded.hexstring}"
    puts "matter.js hex: 153601153501260055156878370124020024032824040918240201181818290424ff0118"
    puts "Match: #{encoded.hexstring == "153601153501260055156878370124020024032824040918240201181818290424ff0118"}"
    puts ""

    # Compare sizes
    expected_size = 36
    puts "Our size: #{encoded.size} bytes"
    puts "Expected: #{expected_size} bytes"
    puts "Difference: #{expected_size - encoded.size} bytes"
  end
end
