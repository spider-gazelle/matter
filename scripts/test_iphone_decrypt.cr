#!/usr/bin/env crystal

# Quick script to test iPhone message decryption with different parameter combinations
# Usage: crystal run scripts/test_iphone_decrypt.cr

require "../src/matter/crypto/crypto"
require "../src/matter/session/secure_message"
require "../src/matter/codec/message_codec"

puts "🧪 iPhone Decryption Diagnostic Tool"
puts "=" * 70
puts ""

# Capture these from the iPhone commissioning logs:
puts "📝 Enter values from iPhone commissioning logs:"
puts ""
print "Decryption key (I2R) [32 hex chars]: "
decryption_key = gets.not_nil!.strip.hexbytes

print "Encrypted payload [86 hex chars for 43 bytes]: "
encrypted_payload = gets.not_nil!.strip.hexbytes

print "Message counter [decimal]: "
message_counter = gets.not_nil!.strip.to_u32

print "Session ID [decimal]: "
session_id = gets.not_nil!.strip.to_u16

puts ""
puts "🔍 Testing decryption with:"
puts "  Key: #{decryption_key.hexstring}"
puts "  Payload: #{encrypted_payload.hexstring[0, 32]}... (#{encrypted_payload.size} bytes)"
puts "  Counter: #{message_counter}"
puts "  Session: #{session_id}"
puts ""

# Build nonce and AAD
peer_node_id = 0xFFFFFFFB00000001_u64
security_flags = 0x00_u8

nonce = Matter::Session::SecureMessage.build_nonce(peer_node_id, message_counter, security_flags)
puts "  Nonce: #{nonce.hexstring}"

# Build AAD
aad_io = IO::Memory.new
aad_io.write_byte(0x00_u8) # flags
IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
aad_io.write_byte(security_flags)
IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
aad = aad_io.to_slice
puts "  AAD: #{aad.hexstring}"
puts ""

# Try decryption
crypto = Matter::Crypto::StandardCrypto.new

puts "🔓 Attempting decryption..."
begin
  decrypted = crypto.decrypt(decryption_key, encrypted_payload, nonce, aad)
  puts "✅ SUCCESS!"
  puts ""
  puts "Decrypted payload (#{decrypted.size} bytes):"
  puts decrypted.hexstring
rescue ex
  puts "❌ FAILED: #{ex.message}"
  puts ""
  puts "Try checking:"
  puts "  1. Is the decryption key correct (from 'Decryption key (I2R):' log)?"
  puts "  2. Is the encrypted payload complete (43 bytes = 86 hex chars)?"
  puts "  3. Are the message counter and session ID correct?"
end
