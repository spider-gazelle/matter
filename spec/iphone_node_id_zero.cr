require "./spec_helper"
require "../src/matter/crypto/crypto"
require "../src/matter/session/secure_message"

# Test iPhone decryption with node_id=0 (like matter.js test)
describe "iPhone Decryption with Node ID = 0" do
  it "decrypts iPhone message using node_id=0 instead of PASE temporary ID" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Latest iPhone values
    decryption_key = "fb506c991bc90c281cf9d657369441e9".hexbytes
    encrypted_payload = "a3127b1fb7bc6d5e16a1a7fa48d84f66ea4976f451d1408e7b1ba1293e99958c9269cff77cdf30a94e4d48".hexbytes
    message_counter = 180049233_u32
    session_id = 3930_u16
    security_flags = 0x00_u8
    aad = "00018a005155bb0a".hexbytes

    puts "\n🧪 Testing iPhone decryption with node_id=0:"
    puts ""

    # Test 1: PASE temporary node ID (current implementation)
    peer_node_id_pase = 0xFFFFFFFB00000001_u64
    nonce_pase = Matter::Session::SecureMessage.build_nonce(peer_node_id_pase, message_counter, security_flags)

    puts "  Test 1: PASE temporary node ID (0xFFFFFFFB00000001)"
    puts "    Nonce: #{nonce_pase.hexstring}"

    begin
      crypto.decrypt(decryption_key, encrypted_payload, nonce_pase, aad)
      puts "    Result: ✅ SUCCESS"
    rescue
      puts "    Result: ❌ FAILED"
    end

    puts ""

    # Test 2: Node ID = 0 (like matter.js test)
    peer_node_id_zero = 0_u64
    nonce_zero = Matter::Session::SecureMessage.build_nonce(peer_node_id_zero, message_counter, security_flags)

    puts "  Test 2: Node ID = 0 (UNSPECIFIED)"
    puts "    Nonce: #{nonce_zero.hexstring}"

    begin
      decrypted = crypto.decrypt(decryption_key, encrypted_payload, nonce_zero, aad)
      puts "    Result: ✅ SUCCESS!"
      puts "    Decrypted #{decrypted.size} bytes: #{decrypted.hexstring[0, 40]}..."
      decrypted.size.should be > 0
    rescue
      puts "    Result: ❌ FAILED"
      fail "Both node IDs failed - investigate further"
    end
  end
end
