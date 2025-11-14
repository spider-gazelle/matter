require "./spec_helper"
require "../src/matter/crypto/crypto"

# Verify what keys SHOULD be derived from the iPhone's Ke
describe "iPhone Ke -> Session Keys" do
  it "derives session keys from iPhone's Ke" do
    crypto = Matter::Crypto::StandardCrypto.new

    # From iPhone logs: Shared secret Ke (first 16 bytes): 0ce140601d545ef362085f4018d1a1e3
    # The full Ke is 32 bytes (need to get the rest from logs)
    # For now, let's pad with zeros
    ke_first_16 = "0ce140601d545ef362085f4018d1a1e3".hexbytes
    ke = Bytes.new(32)
    ke[0, 16].copy_from(ke_first_16)
    # TODO: Need the full 32 bytes of Ke from logs

    puts "\n🔬 Deriving session keys from iPhone's Ke:"
    puts "  Ke (partial): #{ke.hexstring}"
    puts ""

    # Derive using 48-byte HKDF
    session_keys = crypto.create_hkdf_key(
      ke,
      Bytes.new(0), # Empty salt
      "SessionKeys".to_slice,
      48
    )

    i2r = session_keys[0, 16]
    r2i = session_keys[16, 16]
    att = session_keys[32, 16]

    puts "  Derived keys (from partial Ke):"
    puts "    I2R (0-15):  #{i2r.hexstring}"
    puts "    R2I (16-31): #{r2i.hexstring}"
    puts "    ATT (32-47): #{att.hexstring}"
    puts ""

    puts "  Expected from logs:"
    puts "    Decryption key (I2R): fb506c991bc90c281cf9d657369441e9"
    puts "    Encryption key (R2I): f5f5c54260ff980a87630c2a8d3e829e"
    puts ""

    # If these match, our HKDF is perfect
    # If they don't match, we need the full 32-byte Ke from the logs
    if i2r.hexstring == "fb506c991bc90c281cf9d657369441e9"
      puts "  ✅ I2R matches! HKDF derivation is correct"
    else
      puts "  ❌ I2R doesn't match - need full 32-byte Ke from logs"
    end

    # Don't fail the test - just diagnostic
    pending "Need full 32-byte Ke from logs to verify"
  end
end
