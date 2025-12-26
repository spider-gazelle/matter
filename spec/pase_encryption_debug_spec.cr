require "./spec_helper"
require "../src/matter/crypto/crypto"
require "../src/matter/session/secure_message"

describe "PASE Encryption Debug" do
  it "verifies AES-CCM encryption with actual PASE session keys" do
    # Keys from actual PASE session with chip-tool
    r2i_key = "e2026b112be29895b05028cd1efe175b".hexbytes

    # Simple test payload
    plaintext = "15360124000018".hexbytes

    # Nonce: security_flags (1) + message_counter (4 LE) + node_id (8 LE)
    nonce = "00000000000000000000000000".hexbytes # counter=0, node_id=0

    # AAD: flags (1) + session_id (2 LE) + security_flags (1) + counter (4 LE)
    aad = "00168d0000000000".hexbytes # session_id=36118, counter=0

    crypto = Matter::Crypto::StandardCrypto.new

    # Encrypt with R2I (responder encrypts to initiator)
    ciphertext = crypto.encrypt(r2i_key, plaintext, nonce, aad)

    puts "\n=== Encryption Test ==="
    puts "Key (R2I):      #{r2i_key.hexstring}"
    puts "Nonce:          #{nonce.hexstring}"
    puts "AAD:            #{aad.hexstring}"
    puts "Plaintext:      #{plaintext.hexstring} (#{plaintext.size} bytes)"
    puts "Ciphertext:     #{ciphertext.hexstring} (#{ciphertext.size} bytes)"
    puts ""

    # Verify round-trip with same key
    decrypted = crypto.decrypt(r2i_key, ciphertext, nonce, aad)
    decrypted.should eq(plaintext)
    puts "✓ Round-trip with R2I key successful"

    # Verify ciphertext structure
    ciphertext.size.should eq(plaintext.size + 16) # plaintext + 16-byte MIC
    puts "✓ Ciphertext size correct (plaintext #{plaintext.size} + MIC 16 = #{ciphertext.size})"
  end

  it "verifies nonce construction matches incoming messages" do
    # From actual chip-tool message we successfully decrypted
    expected_nonce = "005e15fa040000000000000000".hexbytes

    # Reconstruct using our function
    security_flags = 0_u8
    message_counter = 83498334_u32 # 0x04fa155e in LE
    source_node_id = 0_u64

    nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

    puts "\n=== Nonce Construction Test ==="
    puts "Expected: #{expected_nonce.hexstring}"
    puts "Built:    #{nonce.hexstring}"

    nonce.should eq(expected_nonce)
    puts "✓ Nonce construction matches chip-tool format"
  end

  it "shows encryption parameters used in actual session" do
    puts "\n=== Actual PASE Session Parameters ==="
    puts "HKDF Output (48 bytes):"
    puts "  Full: 6505a71d0651fbc5d739b659de0cfae3e2026b112be29895b05028cd1efe175b7468c99c0b2584be68573558bfaaa03f"
    puts "  I2R (bytes 0-15):  6505a71d0651fbc5d739b659de0cfae3"
    puts "  R2I (bytes 16-31): e2026b112be29895b05028cd1efe175b"
    puts ""
    puts "Responder (our device):"
    puts "  Encrypts with:  R2I = e2026b112be29895b05028cd1efe175b"
    puts "  Decrypts with:  I2R = 6505a71d0651fbc5d739b659de0cfae3"
    puts ""
    puts "Initiator (chip-tool):"
    puts "  Should encrypt with:  I2R = 6505a71d0651fbc5d739b659de0cfae3"
    puts "  Should decrypt with:  R2I = e2026b112be29895b05028cd1efe175b"
    puts ""
    puts "Status: We can decrypt chip-tool's messages ✓"
    puts "        chip-tool CANNOT decrypt our messages ✗"
  end
end
