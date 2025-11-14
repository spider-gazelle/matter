require "./spec_helper"
require "../src/matter/crypto/crypto"
require "../src/matter/session/secure_message"

# Test iPhone decryption with actual source node ID from logs
describe "iPhone Decryption with Actual Node ID" do
  it "decrypts iPhone message using actual source node ID from packet" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Latest iPhone values
    decryption_key = "aa1666c8c074733f9aafa05486f0cc65".hexbytes
    encrypted_payload = "d6319064a6b0d8bd1bb3bf07232235f937fee7a32d09127b0863a1d30d8df9ad3ccde3d100d733691bd844".hexbytes
    message_counter = 267096579_u32
    session_id = 30439_u16
    security_flags = 0x00_u8
    aad = "00e776000392eb0f".hexbytes

    puts "\n🧪 Testing iPhone decryption with different node IDs:"
    puts ""

    # Test 1: PASE temporary (current)
    node_id_pase = 0xFFFFFFFB00000001_u64
    nonce1 = Matter::Session::SecureMessage.build_nonce(node_id_pase, message_counter, security_flags)
    puts "  Test 1: PASE temporary (0xFFFFFFFB00000001)"
    puts "    Nonce: #{nonce1.hexstring}"
    begin
      crypto.decrypt(decryption_key, encrypted_payload, nonce1, aad)
      puts "    ✅ SUCCESS"
    rescue
      puts "    ❌ FAILED"
    end

    # Test 2: Node ID = 0
    node_id_zero = 0_u64
    nonce2 = Matter::Session::SecureMessage.build_nonce(node_id_zero, message_counter, security_flags)
    puts "\n  Test 2: Node ID = 0"
    puts "    Nonce: #{nonce2.hexstring}"
    begin
      crypto.decrypt(decryption_key, encrypted_payload, nonce2, aad)
      puts "    ✅ SUCCESS"
    rescue
      puts "    ❌ FAILED"
    end

    # Test 3: iPhone's actual source node ID from logs
    node_id_iphone = 17833059747937378302_u64 # From logs: @id=17833059747937378302
    nonce3 = Matter::Session::SecureMessage.build_nonce(node_id_iphone, message_counter, security_flags)
    puts "\n  Test 3: iPhone's source node ID (17833059747937378302)"
    puts "    Node ID hex: 0x#{node_id_iphone.to_s(16)}"
    puts "    Nonce: #{nonce3.hexstring}"
    begin
      decrypted = crypto.decrypt(decryption_key, encrypted_payload, nonce3, aad)
      puts "    ✅ SUCCESS! Decrypted #{decrypted.size} bytes"
      puts "    Decrypted: #{decrypted.hexstring[0, 40]}..."
      decrypted.size.should be > 0
    rescue
      puts "    ❌ FAILED"

      # If all 3 fail, there's something else wrong
      puts ""
      puts "  All node IDs failed - investigating other possibilities..."
      fail "Need to investigate further - keys are correct but decryption still fails"
    end
  end
end
