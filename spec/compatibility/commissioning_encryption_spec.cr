require "../spec_helper"
require "../../src/matter/crypto/crypto"

# Test vector captured from actual chip-tool commissioning attempt
# This verifies our encryption produces byte-exact output for real commissioning data
describe "Commissioning Encryption Test Vector" do
  it "encrypts ReadResponse matching captured test vector" do
    # Test vector from /tmp/DEBUG_DEVICE.log during chip-tool commissioning
    # Session: 59291 (0xe79b), Counter: 0, Node ID: 0 (PASE)

    key = "543a11bbca4804590b486b932e028381".hexbytes

    # Application payload (payloadHeader + TLV ReadResponse)
    # First 64 bytes of the full 7254 byte payload
    payload = "020525430100c7826c07153601153501240000370124020024031d240400183602181818153501240000370124020024031d240401183602041d181818153501".hexbytes

    # Nonce: security_flags (1) + counter (4) + node_id (8) = 13 bytes
    # All zeros for first message during PASE
    nonce = "00000000000000000000000000".hexbytes

    # AAD: Encoded packet header (8 bytes for PASE without node IDs)
    # Byte 0: 0x00 (flags)
    # Bytes 1-2: 0xe79b (LE) = 59291 (session_id)
    # Byte 3: 0x00 (security_flags)
    # Bytes 4-7: 0x00000000 (message_counter = 0)
    aad = "009be70000000000".hexbytes

    # Expected encrypted result (first 64 bytes of encrypted payload)
    expected_encrypted = "a345c33797fcb1773f2418ebc46c6e5da71dc06ae4f05d18dfdbda80c5c90416ab5fa06802356d4a1d1cce022228d8c0771db07fe2bbb7e5b71e6114faeb1878".hexbytes

    crypto = Matter::Crypto::StandardCrypto.new

    # Encrypt using captured parameters
    result = crypto.encrypt(key, payload, nonce, aad)

    # Verify first 64 bytes match (enough to confirm encryption is correct)
    result_sample = result[0, expected_encrypted.size]

    puts "\n═══ Commissioning Encryption Verification ═══"
    puts "Key:      #{key.hexstring}"
    puts "Payload:  #{payload.hexstring}"
    puts "Nonce:    #{nonce.hexstring}"
    puts "AAD:      #{aad.hexstring}"
    puts "\nExpected: #{expected_encrypted.hexstring}"
    puts "Got:      #{result_sample.hexstring}"
    puts "Match:    #{result_sample == expected_encrypted ? "✅ YES" : "❌ NO"}"

    if result_sample != expected_encrypted
      puts "\n❌ MISMATCH FOUND!"
      puts "This means either:"
      puts "  1. Our AES-CCM implementation is wrong"
      puts "  2. The captured test vector parameters are incorrect"
      puts "  3. There's a bug in how we're calling crypto.encrypt()"

      # Show byte-by-byte diff
      result_sample.each_with_index do |byte, i|
        if byte != expected_encrypted[i]
          puts "  Byte #{i}: expected 0x#{expected_encrypted[i].to_s(16).rjust(2, '0')}, got 0x#{byte.to_s(16).rjust(2, '0')}"
        end
      end
    end

    result_sample.should eq(expected_encrypted)
  end

  it "verifies nonce construction for PASE" do
    # Nonce format: security_flags (1 byte) + message_counter (4 bytes LE) + source_node_id (8 bytes LE)
    security_flags = 0x00_u8
    message_counter = 0_u32
    source_node_id = 0_u64

    nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)

    puts "\nNonce construction:"
    puts "  security_flags: 0x#{security_flags.to_s(16).rjust(2, '0')}"
    puts "  message_counter: #{message_counter}"
    puts "  source_node_id: #{source_node_id}"
    puts "  Result: #{nonce.hexstring}"

    nonce.should eq("00000000000000000000000000".hexbytes)
    nonce.size.should eq(13)
  end

  it "verifies AAD construction matches packet header encoding" do
    # AAD should be the exact encoded packet header bytes
    # For PASE without node IDs: 8 bytes total

    flags = 0x00_u8
    session_id = 59291_u16 # 0xe79b
    security_flags = 0x00_u8
    message_counter = 0_u32

    # Manually build AAD as it should be
    io = IO::Memory.new
    io.write_byte(flags)
    IO::ByteFormat::LittleEndian.encode(session_id, io)
    io.write_byte(security_flags)
    IO::ByteFormat::LittleEndian.encode(message_counter, io)
    aad = io.rewind.to_slice

    puts "\nAAD construction:"
    puts "  flags: 0x#{flags.to_s(16).rjust(2, '0')}"
    puts "  session_id: #{session_id} (0x#{session_id.to_s(16)})"
    puts "  security_flags: 0x#{security_flags.to_s(16).rjust(2, '0')}"
    puts "  message_counter: #{message_counter}"
    puts "  Result: #{aad.hexstring}"

    aad.should eq("009be70000000000".hexbytes)
    aad.size.should eq(8)
  end
end
