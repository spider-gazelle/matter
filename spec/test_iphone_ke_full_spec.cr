require "./spec_helper"
require "../src/matter/crypto/crypto"

# Test with iPhone's Ke to see what keys we get
describe "iPhone Ke Derivation Test" do
  it "derives keys from iPhone's Ke" do
    crypto = Matter::Crypto::StandardCrypto.new

    # From logs: "Shared secret Ke (FULL 32 bytes): c1610df4af663f84e394a3a7410f8b1d"
    # But this is only 16 bytes (32 hex chars)!
    # The Ke should be 32 bytes (64 hex chars)

    # Let's test if the Ke is actually only 16 bytes
    ke_shown = "c1610df4af663f84e394a3a7410f8b1d".hexbytes

    puts "\n🔬 Testing Ke from iPhone logs:"
    puts "  Ke (as shown): #{ke_shown.hexstring}"
    puts "  Size: #{ke_shown.size} bytes"
    puts ""

    if ke_shown.size == 16
      puts "  ⚠️  WARNING: Ke is only 16 bytes, but should be 32 bytes!"
      puts "  This explains why decryption fails - the SPAKE2+ library is returning wrong Ke size"
      puts ""

      # Pad to 32 bytes for testing
      ke_padded = Bytes.new(32)
      ke_padded[0, 16].copy_from(ke_shown)

      puts "  Testing with zero-padded Ke (16 bytes + 16 zero bytes):"
      session_keys = crypto.create_hkdf_key(
        ke_padded,
        Bytes.new(0),
        "SessionKeys".to_slice,
        48
      )

      i2r = session_keys[0, 16]
      r2i = session_keys[16, 16]

      puts "    I2R: #{i2r.hexstring}"
      puts "    R2I: #{r2i.hexstring}"
      puts ""
      puts "  Expected from logs:"
      puts "    I2R: aa1666c8c074733f9aafa05486f0cc65"
      puts "    R2I: bf47bb80d870bc419d6ae58dd077b1fd"
      puts ""

      if i2r.hexstring == "aa1666c8c074733f9aafa05486f0cc65"
        puts "  ✅ MATCH! The issue is Ke is truncated to 16 bytes instead of 32"
      else
        puts "  ❌ No match - Ke truncation is not the only issue"
      end
    end

    ke_shown.size.should eq(16) # Verify our suspicion
  end
end
