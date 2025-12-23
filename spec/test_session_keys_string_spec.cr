require "./spec_helper"

# Verify "SessionKeys" string encoding
describe "SessionKeys String Encoding" do
  it "encodes SessionKeys correctly" do
    info = "SessionKeys".to_slice

    puts "\n🔍 SessionKeys info string:"
    puts "  Length: #{info.size} bytes"
    puts "  Hex: #{info.hexstring}"
    puts "  ASCII: #{String.new(info)}"
    puts ""

    # Should be 11 bytes: S e s s i o n K e y s
    info.size.should eq(11)

    # Verify bytes
    expected_bytes = [0x53, 0x65, 0x73, 0x73, 0x69, 0x6f, 0x6e, 0x4b, 0x65, 0x79, 0x73]
    info.to_a.should eq(expected_bytes)

    # Verify hex matches matter.js
    info.hexstring.should eq("53657373696f6e4b657973")

    puts "  ✅ SessionKeys encoding is correct"
  end
end
