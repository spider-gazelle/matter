require "./spec_helper"
require "../src/matter/crypto/crypto"
require "../src/matter/session/secure_message"
require "../src/matter/codec/message_codec"

# Test with exact matter.js test vectors from SecureSessionTest.ts
describe "Matter.js Decryption Test Vector" do
  it "decrypts using matter.js SecureSessionTest.ts vectors" do
    crypto = Matter::Crypto::StandardCrypto.new

    # From matter.js SecureSessionTest.ts
    encrypt_key = "66951379d0a6d151cf5472cccf13f360".hexbytes
    decrypt_key = "bacb178b2588443d5d5b1e4559e7accc".hexbytes

    # Full encrypted message packet
    encrypted_message = "001d350022145300ec2b931025dada82ed67521c966d2454d131a271023be699e4e2796650f568e590fd9b65f456c720a60a0da127eaa53974c5d41d3d933ed7b58a9ce5b5cb96ad94a7762611c48774cf75458327e74c34668a45dc9943546f8a6aa1dcd40bd4b8014befb49954a097a60cbdff333ee3f2fd1f49".hexbytes

    # Just the encrypted payload
    encrypted_bytes = "1f9c4e278a2e2a755ebb4fcb9478211efb09aa9518fcafb56d74f135544636037c16fb6b62347794da0c5bde142e1a8b1cc96575e9e55471c08b58f7640b7d7f4173c8ff967c39e9961f30a29cb1f64f68df4b5bc1e742587f778eeb9ec586c162ff384558596792a2c1e43c150cd0e9ec1484c50950f17cd6c084d07caed94ce45c20004210cbde48da44ebcf7d931657f03e07e3ea29ae41868b804bf39e628323cd025507773f07268301aa1e77a82927fce041241839cee4114f6307b6befe3befde87a2d3f13eeef96b27b36e788d907b44bef2d195aa802692f4f12acc015aede3cd29da272d1e4b7f3f59683d25bf08f0e29fba2a8a9b".hexbytes

    # Expected decrypted payload
    expected_decrypted = "153600172403312504fcff18172402002403302404001817240200240330240401181724020024033024040218172402002403302404031817240200240328240402181724020024032824040418172403312404031818290324ff0118".hexbytes

    # Parse packet header
    packet = Matter::Codec::MessageCodec::Base.decode_packet(encrypted_message)

    puts "\n🧪 Testing matter.js decryption test vector:"
    puts "  Session ID: #{packet.header.session_id} (0x#{packet.header.session_id.to_s(16)})"
    puts "  Message ID: #{packet.header.message_id}"
    puts "  Decrypt key: #{decrypt_key.hexstring}"
    puts ""

    # AAD = entire message minus encrypted payload
    # Per matter.js test line 60-63
    aad = encrypted_message[0, encrypted_message.size - packet.payload.size]
    puts "  AAD (#{aad.size} bytes): #{aad.hexstring}"
    puts "  Encrypted payload (#{packet.payload.size} bytes): #{packet.payload.hexstring[0, 64]}..."
    puts ""

    # Build nonce - need to know the source node ID used
    # From the test: peerNodeId: NodeId.UNSPECIFIED_NODE_ID = 0
    # The test explicitly uses node ID 0, not PASE temporary IDs!

    peer_node_id = 0_u64 # UNSPECIFIED_NODE_ID from matter.js test

    message_counter = packet.header.message_id
    security_flags = packet.header.security_flags

    nonce = Matter::Session::SecureMessage.build_nonce(peer_node_id, message_counter, security_flags)
    puts "  Nonce: #{nonce.hexstring}"
    puts "  Message counter: #{message_counter}"
    puts ""

    # Try decryption
    begin
      decrypted = crypto.decrypt(decrypt_key, packet.payload, nonce, aad)
      puts "  ✅ SUCCESS!"
      puts "  Decrypted (#{decrypted.size} bytes): #{decrypted.hexstring[0, 64]}..."
      puts ""

      # Verify it matches expected
      if decrypted == expected_decrypted
        puts "  ✅ Decrypted payload matches expected test vector!"
      else
        puts "  ❌ Decrypted payload DOES NOT match expected"
        puts "    Expected: #{expected_decrypted.hexstring[0, 64]}..."
        puts "    Got:      #{decrypted.hexstring[0, 64]}..."
      end

      decrypted.should eq(expected_decrypted)
    rescue ex
      puts "  ❌ Decryption FAILED: #{ex.message}"
      puts ""
      puts "  This test uses exact matter.js test vectors."
      puts "  If this fails, there's a fundamental issue with our AES-CCM or nonce/AAD construction."
      fail "Matter.js test vector decryption failed"
    end
  end
end
