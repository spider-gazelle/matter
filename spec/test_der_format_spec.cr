require "./spec_helper"
require "../src/matter/crypto/crypto"
require "../src/matter/crypto/key"

describe "DER Format Generation" do
  crypto = Matter::Crypto::StandardCrypto.new

  # Test vectors from crypto_compatibility_spec
  private_key_bytes = "727F1005CBA47ED7822A9D930943621617CFD3B79D9AF528B801ECF9F1992204".hexbytes
  public_key_bytes = "0462e2b6e1baff8d74a6fd8216c4cb67a3363a31e691492792e61aee610261481396725ef95e142686ba98f339b0ff65bc338bec7b9e8be0bdf3b2774982476220".hexbytes

  it "generates valid SEC1 DER for EC private key" do
    # Build our DER
    our_der = crypto.build_ec_private_key_der(private_key_bytes, public_key_bytes)

    puts "\nOur EC Private Key DER (#{our_der.size} bytes):"
    puts our_der.hexstring

    puts "\nHex dump:"
    our_der.each_slice(16) do |slice|
      hex = slice.map { |b| b.to_s(16).rjust(2, '0') }.join(" ")
      ascii = slice.map { |b| (32..126).includes?(b) ? b.chr : '.' }.join
      puts "#{hex.ljust(48)} #{ascii}"
    end

    # Try to load it
    pem = crypto.der_to_pem(our_der, "EC PRIVATE KEY")
    puts "\nPEM format:"
    puts pem

    pkey = OpenSSL::PKey::EC.new(pem)
    pkey.private?.should be_true
    puts "✅ Successfully loaded EC private key!"
  end

  it "generates valid SPKI DER for EC public key" do
    # Build our DER
    our_der = crypto.build_ec_public_key_der(public_key_bytes)

    puts "\nOur EC Public Key DER (#{our_der.size} bytes):"
    puts our_der.hexstring

    puts "\nHex dump:"
    our_der.each_slice(16) do |slice|
      hex = slice.map { |b| b.to_s(16).rjust(2, '0') }.join(" ")
      ascii = slice.map { |b| (32..126).includes?(b) ? b.chr : '.' }.join
      puts "#{hex.ljust(48)} #{ascii}"
    end

    # Try to load it
    pem = crypto.der_to_pem(our_der, "PUBLIC KEY")
    puts "\nPEM format:"
    puts pem

    pkey = OpenSSL::PKey::EC.new(pem)
    pkey.public?.should be_true
    puts "✅ Successfully loaded EC public key!"
  end
end
