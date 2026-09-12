require "../spec_helper"
require "../../src/matter/crypto/crypto"
require "../../src/matter/session/secure_message"

describe Matter::Session::SecureMessage do
  it "round-trips AES-CCM with PASE session keys captured from chip-tool" do
    r2i_key = "e2026b112be29895b05028cd1efe175b".hexbytes
    plaintext = "15360124000018".hexbytes

    # Nonce: security_flags (1) + message_counter (4 LE) + node_id (8 LE), counter=0, node_id=0
    nonce = "00000000000000000000000000".hexbytes
    # AAD: flags (1) + session_id (2 LE) + security_flags (1) + counter (4 LE), session_id=36118
    aad = "00168d0000000000".hexbytes

    crypto = Matter::Crypto::StandardCrypto.new
    ciphertext = crypto.encrypt(r2i_key, plaintext, nonce, aad)

    ciphertext.size.should eq(plaintext.size + Matter::Session::SecureMessage::MIC_LENGTH)
    crypto.decrypt(r2i_key, ciphertext, nonce, aad).should eq(plaintext)
  end

  it "builds the nonce for an incoming chip-tool message" do
    expected_nonce = "005e15fa040000000000000000".hexbytes
    security_flags = 0_u8
    message_counter = 83498334_u32 # 0x04fa155e
    source_node_id = 0_u64

    nonce = Matter::Session::SecureMessage.build_nonce(source_node_id, message_counter, security_flags)
    nonce.should eq(expected_nonce)
  end
end
