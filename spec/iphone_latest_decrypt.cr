require "./spec_helper"
require "../src/matter/crypto/crypto"

# Test with LATEST iPhone values (2025-11-14 10:08:19)
describe "iPhone Latest Decryption Test" do
  it "attempts to decrypt with latest iPhone data" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Latest values from logs
    decryption_key = "fb506c991bc90c281cf9d657369441e9".hexbytes
    encrypted_payload = "a3127b1fb7bc6d5e16a1a7fa48d84f66ea4976f451d1408e7b1ba1293e99958c9269cff77cdf30a94e4d48".hexbytes
    nonce = "00d663990301000000fbffffff".hexbytes
    aad = "005a0f00d6639903".hexbytes

    puts "\n🧪 Testing iPhone message decryption (latest data)"
    puts "  Decryption key: #{decryption_key.hexstring}"
    puts "  Nonce: #{nonce.hexstring}"
    puts "  AAD: #{aad.hexstring}"
    puts "  Encrypted: #{encrypted_payload.hexstring}"
    puts "  Payload size: #{encrypted_payload.size} bytes (#{encrypted_payload.size - 16} ciphertext + 16 tag)"
    puts ""

    # Test direct decryption
    begin
      decrypted = crypto.decrypt(decryption_key, encrypted_payload, nonce, aad)
      puts "  ✅ SUCCESS! Decrypted #{decrypted.size} bytes"
      puts "  Decrypted: #{decrypted.hexstring}"
      decrypted.size.should be > 0
    rescue ex
      puts "  ❌ FAILED: #{ex.message}"

      # Try with different AAD/nonce combinations to diagnose
      puts ""
      puts "  🔬 Diagnostic tests:"

      # Test 1: Empty AAD
      begin
        crypto.decrypt(decryption_key, encrypted_payload, nonce, Bytes.new(0))
        puts "    - Empty AAD: ✅ Works (AAD was wrong!)"
      rescue
        puts "    - Empty AAD: ❌ Still fails"
      end

      # Test 2: Different nonce (all zeros)
      begin
        crypto.decrypt(decryption_key, encrypted_payload, Bytes.new(13, 0), aad)
        puts "    - Zero nonce: ✅ Works (nonce was wrong!)"
      rescue
        puts "    - Zero nonce: ❌ Still fails"
      end

      # Test 3: Wrong key
      begin
        crypto.decrypt(Bytes.new(16, 0xFF), encrypted_payload, nonce, aad)
        puts "    - Wrong key: ✅ Works (key was wrong!)"
      rescue
        puts "    - Wrong key: ❌ Still fails (expected)"
      end

      fail "Decryption failed - investigate AES-CCM implementation or key derivation"
    end
  end
end
