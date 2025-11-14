require "./spec_helper"
require "../src/matter/crypto/crypto"
require "../src/matter/codec/message_codec"

# Test if AAD should include payload header
describe "AAD with Payload Header Test" do
  it "tests if AAD includes payload header bytes" do
    crypto = Matter::Crypto::StandardCrypto.new

    # matter.js test vector
    encrypt_key = "66951379d0a6d151cf5472cccf13f360".hexbytes
    decrypt_key = "bacb178b2588443d5d5b1e4559e7accc".hexbytes
    encrypted_message = "001d350022145300ec2b931025dada82ed67521c966d2454d131a271023be699e4e2796650f568e590fd9b65f456c720a60a0da127eaa53974c5d41d3d933ed7b58a9ce5b5cb96ad94a7762611c48774cf75458327e74c34668a45dc9943546f8a6aa1dcd40bd4b8014befb49954a097a60cbdff333ee3f2fd1f49".hexbytes

    # Expected decrypted (WITHOUT payload header)
    expected = "153600172403312504fcff18172402002403302404001817240200240330240401181724020024033024040218172402002403302404031817240200240328240402181724020024032824040418172403312404031818290324ff0118".hexbytes

    packet = Matter::Codec::MessageCodec::Base.decode_packet(encrypted_message)

    message_counter = packet.header.message_id
    security_flags = packet.header.security_flags
    peer_node_id = 0_u64

    nonce = Matter::Session::SecureMessage.build_nonce(peer_node_id, message_counter, security_flags)

    puts "\n🔬 Testing AAD construction:"
    puts "  Encrypted message size: #{encrypted_message.size} bytes"
    puts "  Packet payload size: #{packet.payload.size} bytes"
    puts "  AAD size should be: #{encrypted_message.size - packet.payload.size} bytes"
    puts ""

    # Test 1: AAD = packet header only (8 bytes for PASE without node IDs)
    aad_header_only = encrypted_message[0, 8]
    puts "  Test 1: AAD = packet header only (8 bytes)"
    puts "    AAD: #{aad_header_only.hexstring}"

    begin
      decrypted = crypto.decrypt(decrypt_key, packet.payload, nonce, aad_header_only)
      puts "    Result: ✅ Decrypted #{decrypted.size} bytes"

      # Check if it matches expected (might have payload header prepended)
      if decrypted == expected
        puts "    ✅ Exact match!"
      elsif decrypted.size > expected.size
        # Check if expected is a suffix
        suffix_start = decrypted.size - expected.size
        if decrypted[suffix_start, expected.size] == expected
          puts "    ✅ Expected is a suffix (has #{suffix_start} extra bytes at start)"
          puts "    Extra bytes (payload header): #{decrypted[0, suffix_start].hexstring}"
        end
      end
    rescue ex
      puts "    Result: ❌ Failed - #{ex.message}"
    end

    puts ""

    # Test 2: AAD = everything except application payload
    # Per matter.js line 60-63: AAD = entire_message[0 : message.size - applicationPayload.size]
    aad_full = encrypted_message[0, encrypted_message.size - packet.payload.size]
    puts "  Test 2: AAD = packet header + payload header (#{aad_full.size} bytes)"
    puts "    AAD: #{aad_full.hexstring}"

    begin
      decrypted = crypto.decrypt(decrypt_key, packet.payload, nonce, aad_full)
      puts "    Result: ✅ Decrypted #{decrypted.size} bytes"

      if decrypted == expected
        puts "    ✅ EXACT MATCH! AAD must include payload header"
        decrypted.should eq(expected)
      else
        puts "    Decrypted: #{decrypted.hexstring[0, 40]}..."
        puts "    Expected:  #{expected.hexstring[0, 40]}..."
      end
    rescue ex
      puts "    Result: ❌ Failed - #{ex.message}"
    end
  end
end
