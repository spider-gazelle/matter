require "../spec_helper"
require "../../src/matter/crypto/crypto"
require "../../src/matter/session/secure_message"
require "../../src/matter/codec/message_codec"

# Integration test demonstrating successful decryption with all fixes
describe "Commissioning Integration Test" do
  it "successfully decrypts matter.js test vector (proof AES-CCM works)" do
    crypto = Matter::Crypto::StandardCrypto.new
    decrypt_key = "bacb178b2588443d5d5b1e4559e7accc".hexbytes
    encrypted_message = "001d350022145300ec2b931025dada82ed67521c966d2454d131a271023be699e4e2796650f568e590fd9b65f456c720a60a0da127eaa53974c5d41d3d933ed7b58a9ce5b5cb96ad94a7762611c48774cf75458327e74c34668a45dc9943546f8a6aa1dcd40bd4b8014befb49954a097a60cbdff333ee3f2fd1f49".hexbytes

    packet = Matter::Codec::MessageCodec::Base.decode_packet(encrypted_message)
    aad = encrypted_message[0, encrypted_message.size - packet.payload.size]
    nonce = Matter::Session::SecureMessage.build_nonce(0_u64, packet.header.message_id, packet.header.security_flags)

    decrypted = crypto.decrypt(decrypt_key, packet.payload, nonce, aad)
    decrypted.size.should be > 0
  end

  it "successfully decrypts actual iPhone message (proof PASE + node_id=0 works)" do
    crypto = Matter::Crypto::StandardCrypto.new

    # Actual iPhone commissioning data
    ke = "a8b385a62edad6a52392b569b4e0979c".hexbytes # 16-byte Ke from SPAKE2+

    # Derive session keys using HKDF
    session_keys = crypto.create_hkdf_key(ke, Bytes.new(0), "SessionKeys".to_slice, 48)
    decryption_key = session_keys[0, 16] # I2R

    # Encrypted message from iPhone
    encrypted_payload = "a3070fa40655d108b11cd5c20bb8f6732c0a1d0274940764d62a6af6c964a84b509677ff5e26173ede46d6".hexbytes
    message_counter = 188256206_u32
    session_id = 64973_u16
    security_flags = 0x00_u8

    # Build nonce with node_id=0 (the critical fix!)
    nonce = Matter::Session::SecureMessage.build_nonce(0_u64, message_counter, security_flags)

    # Build AAD
    aad_io = IO::Memory.new
    aad_io.write_byte(0x00_u8)
    IO::ByteFormat::LittleEndian.encode(session_id, aad_io)
    aad_io.write_byte(security_flags)
    IO::ByteFormat::LittleEndian.encode(message_counter, aad_io)
    aad = aad_io.to_slice

    # Decrypt
    decrypted = crypto.decrypt(decryption_key, encrypted_payload, nonce, aad)
    decrypted.size.should be > 0

    # Verify it's a valid ReadRequest (protocol=0x01, type=0x02)
    # Payload header starts with flags, type, exchange_id...
    decrypted[1].should eq(0x02) # ReadRequest message type
  end

  it "verifies nonce construction fix (IO::Memory instead of direct Bytes encoding)" do
    # This would have failed before the fix
    nonce = Matter::Session::SecureMessage.build_nonce(
      0xFFFFFFFB00000001_u64,
      12345678_u32,
      0x00_u8
    )

    nonce.size.should eq(13)
    # Verify little-endian encoding worked correctly
    counter_bytes = nonce[1, 4]
    IO::ByteFormat::LittleEndian.decode(UInt32, counter_bytes).should eq(12345678_u32)
  end

  it "verifies HKDF produces 48 bytes with correct split" do
    crypto = Matter::Crypto::StandardCrypto.new
    ke = Bytes.new(16, 0xAA) # Dummy Ke

    session_keys = crypto.create_hkdf_key(ke, Bytes.new(0), "SessionKeys".to_slice, 48)

    session_keys.size.should eq(48)
    i2r = session_keys[0, 16]
    r2i = session_keys[16, 16]
    att = session_keys[32, 16]

    i2r.size.should eq(16)
    r2i.size.should eq(16)
    att.size.should eq(16)
  end
end
