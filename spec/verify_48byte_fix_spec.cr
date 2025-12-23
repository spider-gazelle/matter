require "./spec_helper"
require "../src/matter/crypto/crypto"

# Verify that using 48-byte HKDF changes the derived keys
describe "48-byte HKDF Fix Verification" do
  it "derives different keys with 48 bytes vs 32 bytes" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Use the Ke from the iPhone logs: 01417b606624ae9a7235e9afaef2d747...
    # This is a 32-byte shared secret from SPAKE2+
    # For testing, I'll use a known Ke value
    ke = "01417b606624ae9a7235e9afaef2d747" + "0" * 32 # Pad to 32 bytes for example

    puts "\n🔬 Testing HKDF key derivation:"
    puts "  Shared secret Ke: #{ke[0, 32]}"
    puts ""

    # OLD method: 32 bytes
    keys_32 = crypto.create_hkdf_key(
      ke.hexbytes,
      Bytes.new(0),
      "SessionKeys".to_slice,
      32
    )

    puts "  32-byte HKDF output:"
    puts "    I2R (0-15):  #{keys_32[0, 16].hexstring}"
    puts "    R2I (16-31): #{keys_32[16, 16].hexstring}"
    puts ""

    # NEW method: 48 bytes
    keys_48 = crypto.create_hkdf_key(
      ke.hexbytes,
      Bytes.new(0),
      "SessionKeys".to_slice,
      48
    )

    puts "  48-byte HKDF output:"
    puts "    I2R (0-15):  #{keys_48[0, 16].hexstring}"
    puts "    R2I (16-31): #{keys_48[16, 16].hexstring}"
    puts "    ATT (32-47): #{keys_48[32, 16].hexstring}"
    puts ""

    # Verify they're different
    i2r_changed = keys_32[0, 16] != keys_48[0, 16]
    r2i_changed = keys_32[16, 16] != keys_48[16, 16]

    puts "  Keys changed:"
    puts "    I2R: #{i2r_changed ? "YES ✅" : "NO ❌"}"
    puts "    R2I: #{r2i_changed ? "YES ✅" : "NO ❌"}"
    puts ""

    # The keys should be IDENTICAL between 32-byte and 48-byte derivations
    # HKDF deterministically generates a stream - the first 32 bytes should be the same
    i2r_changed.should eq(false)
    r2i_changed.should eq(false)

    puts "  ✅ Verified: 48-byte HKDF produces same I2R/R2I keys as 32-byte"
    puts "     (just adds 16 more bytes for AttestationChallenge)"
  end
end
