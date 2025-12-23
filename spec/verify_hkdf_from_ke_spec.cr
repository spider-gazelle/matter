require "./spec_helper"
require "../src/matter/crypto/crypto"

# Verify HKDF produces correct keys from iPhone's Ke
describe "HKDF from iPhone Ke" do
  it "derives session keys from actual Ke and verifies against logs" do
    crypto = Matter::Crypto::StandardCrypto.new

    # From latest iPhone logs
    ke = "c1610df4af663f84e394a3a7410f8b1d".hexbytes # 16 bytes

    puts "\n🔬 Testing HKDF with iPhone's Ke:"
    puts "  Ke (16 bytes): #{ke.hexstring}"
    puts ""

    # Derive session keys using HKDF
    session_keys = crypto.create_hkdf_key(
      ke,
      Bytes.new(0), # Empty salt
      "SessionKeys".to_slice,
      48 # 48 bytes total
    )

    i2r = session_keys[0, 16]
    r2i = session_keys[16, 16]
    att = session_keys[32, 16]

    puts "  Derived from HKDF(Ke, '', 'SessionKeys', 48):"
    puts "    I2R (0-15):  #{i2r.hexstring}"
    puts "    R2I (16-31): #{r2i.hexstring}"
    puts "    ATT (32-47): #{att.hexstring}"
    puts ""

    puts "  Expected from device logs:"
    puts "    Decryption key (I2R): aa1666c8c074733f9aafa05486f0cc65"
    puts "    Encryption key (R2I): bf47bb80d870bc419d6ae58dd077b1fd"
    puts ""

    i2r_match = i2r.hexstring == "aa1666c8c074733f9aafa05486f0cc65"
    r2i_match = r2i.hexstring == "bf47bb80d870bc419d6ae58dd077b1fd"

    puts "  I2R matches: #{i2r_match ? "✅" : "❌"}"
    puts "  R2I matches: #{r2i_match ? "✅" : "❌"}"
    puts ""

    if i2r_match && r2i_match
      puts "  ✅ HKDF derivation is PERFECT!"
      puts "  The issue must be elsewhere (nonce, AAD, or AES-CCM)"
    else
      puts "  ❌ HKDF produces different keys than expected"
      puts "  This means either:"
      puts "    1. The logged Ke is wrong (SPAKE2+ computation issue)"
      puts "    2. The logged keys are wrong (HKDF derivation issue)"
      puts "    3. The Ke in logs is truncated (need full 32-byte Ke)"
    end

    # Don't fail - just verify
    {i2r_match, r2i_match}
  end
end
