require "../spec_helper"
require "../../src/matter/certificate/attestation_certificate_manager"

describe Matter::Certificate::AttestationCertificateManager do
  it "creates a certificate manager with PAA and PAI" do
    vendor_id = 0xFFF1_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)

    # Should have generated PAA key pair
    manager.paa_key_pair.should_not be_nil
    manager.paa_key_pair.public_key.size.should eq(65) # Uncompressed P-256 key
    manager.paa_key_pair.private_key.size.should eq(32)

    # Should have generated PAI key pair
    manager.pai_key_pair.should_not be_nil
    manager.pai_key_pair.public_key.size.should eq(65)
    manager.pai_key_pair.private_key.size.should eq(32)

    # Should have generated PAA certificate
    manager.paa_cert.should_not be_nil
    manager.paa_cert.size.should be > 0

    # Should have generated PAI certificate
    manager.pai_cert.should_not be_nil
    manager.pai_cert.size.should be > 0

    # Verify vendor ID
    manager.vendor_id.should eq(vendor_id)
  end

  it "creates a certificate manager with PAA, PAI, and product ID" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id, product_id)

    manager.vendor_id.should eq(vendor_id)
    manager.product_id.should eq(product_id)
  end

  it "generates a DAC certificate" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)

    dac_cert, dac_key = manager.get_dac_cert(product_id)

    # Should have generated DAC certificate
    dac_cert.should_not be_nil
    dac_cert.size.should be > 0

    # Should have generated DAC key pair
    dac_key.should_not be_nil
    dac_key.public_key.size.should eq(65)
    dac_key.private_key.size.should eq(32)
  end

  it "generates valid X.509 DER certificates" do
    vendor_id = 0xFFF1_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)

    # Parse PAA certificate (self-signed root)
    paa_cert = OpenSSL::X509::Certificate.from_der(manager.paa_cert)
    paa_cert.version.should eq(2) # X.509 v3
    paa_cert.subject.should_not be_nil
    paa_cert.issuer.should_not be_nil

    # Parse PAI certificate (intermediate CA)
    pai_cert = OpenSSL::X509::Certificate.from_der(manager.pai_cert)
    pai_cert.version.should eq(2) # X.509 v3
    pai_cert.subject.should_not be_nil
    pai_cert.issuer.should_not be_nil

    # Parse DAC certificate (device leaf certificate)
    product_id = 0x8000_u16
    dac_cert_bytes, _ = manager.get_dac_cert(product_id)
    dac_cert = OpenSSL::X509::Certificate.from_der(dac_cert_bytes)
    dac_cert.version.should eq(2) # X.509 v3
    dac_cert.subject.should_not be_nil
    dac_cert.issuer.should_not be_nil
  end

  it "generates PAA certificate with correct extensions" do
    vendor_id = 0xFFF1_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)
    paa_cert = OpenSSL::X509::Certificate.from_der(manager.paa_cert)

    # Check that required extensions exist
    basic_constraints = paa_cert.extensions.find { |ext| ext.oid == "basicConstraints" }
    basic_constraints.should_not be_nil

    key_usage = paa_cert.extensions.find { |ext| ext.oid == "keyUsage" }
    key_usage.should_not be_nil

    # Note: SKI and AKI extensions not yet implemented
    # Will be added in future iteration with proper DER encoding
  end

  it "generates PAI certificate with correct extensions" do
    vendor_id = 0xFFF1_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)
    pai_cert = OpenSSL::X509::Certificate.from_der(manager.pai_cert)

    # Check that required extensions exist
    basic_constraints = pai_cert.extensions.find { |ext| ext.oid == "basicConstraints" }
    basic_constraints.should_not be_nil

    key_usage = pai_cert.extensions.find { |ext| ext.oid == "keyUsage" }
    key_usage.should_not be_nil
  end

  it "generates DAC certificate with correct extensions" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)
    dac_cert_bytes, _ = manager.get_dac_cert(product_id)
    dac_cert = OpenSSL::X509::Certificate.from_der(dac_cert_bytes)

    # Check that required extensions exist
    basic_constraints = dac_cert.extensions.find { |ext| ext.oid == "basicConstraints" }
    basic_constraints.should_not be_nil

    key_usage = dac_cert.extensions.find { |ext| ext.oid == "keyUsage" }
    key_usage.should_not be_nil
  end

  it "uses incrementing serial numbers" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)

    paa_cert = OpenSSL::X509::Certificate.from_der(manager.paa_cert)
    pai_cert = OpenSSL::X509::Certificate.from_der(manager.pai_cert)
    dac_cert_bytes, _ = manager.get_dac_cert(product_id)
    dac_cert = OpenSSL::X509::Certificate.from_der(dac_cert_bytes)

    # Serial numbers should be different
    paa_cert.serial.should_not eq(pai_cert.serial)
    pai_cert.serial.should_not eq(dac_cert.serial)
    paa_cert.serial.should_not eq(dac_cert.serial)
  end

  it "generates multiple DACs with different serial numbers" do
    vendor_id = 0xFFF1_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)

    dac1_bytes, _ = manager.get_dac_cert(0x8000_u16)
    dac2_bytes, _ = manager.get_dac_cert(0x8001_u16)

    dac1 = OpenSSL::X509::Certificate.from_der(dac1_bytes)
    dac2 = OpenSSL::X509::Certificate.from_der(dac2_bytes)

    # Serial numbers should be different
    dac1.serial.should_not eq(dac2.serial)
  end

  it "returns PAI certificate via pai_cert" do
    vendor_id = 0xFFF1_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)

    pai_cert = manager.pai_cert
    pai_cert.should eq(manager.pai_cert)
    pai_cert.should_not be_nil
    pai_cert.size.should be > 0
  end

  it "encodes Matter vendor ID in PAI subject DN per spec" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id, product_id)

    # Parse PAI certificate
    pai_cert = OpenSSL::X509::Certificate.from_der(manager.pai_cert)
    entries = pai_cert.subject.to_a

    # Per Matter spec: PAI includes only vendorId (not productId)
    # This matches matter.js behavior where PAI is reusable across products
    # VendorId OID: 1.3.6.1.4.1.37244.2.1
    # Expected format: "FFF1" (zero-padded to 4 chars)

    # Find vendor ID entry
    vid_entry = entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.1") }
    vid_entry.should_not be_nil
    vid_entry.as(Tuple(String, String))[1].should eq("FFF1")

    # PAI should NOT include productId (it's only in DAC)
    pid_entry = entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.2") }
    pid_entry.should be_nil
  end

  it "encodes Matter vendor/product ID in DAC subject DN per spec" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id, product_id)

    # Get and parse DAC certificate
    dac_cert_der, _key = manager.get_dac_cert(product_id)
    dac_cert = OpenSSL::X509::Certificate.from_der(dac_cert_der)
    entries = dac_cert.subject.to_a

    # Per Matter spec: vendor/product IDs should be 4-character uppercase hex
    # VendorId OID: 1.3.6.1.4.1.37244.2.1
    # ProductId OID: 1.3.6.1.4.1.37244.2.2

    # Find vendor ID entry
    vid_entry = entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.1") }
    vid_entry.should_not be_nil
    vid_entry.as(Tuple(String, String))[1].should eq("FFF1")

    # Find product ID entry
    pid_entry = entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.2") }
    pid_entry.should_not be_nil
    pid_entry.as(Tuple(String, String))[1].should eq("8000")
  end

  it "properly zero-pads vendor/product IDs in subject DN" do
    # Test with small values that require zero-padding
    vendor_id = 0x00AB_u16  # Should encode as "00AB"
    product_id = 0x0012_u16 # Should encode as "0012"
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id, product_id)

    # Check PAI (only vendorId, no productId per matter.js)
    pai_cert = OpenSSL::X509::Certificate.from_der(manager.pai_cert)
    pai_entries = pai_cert.subject.to_a

    vid_entry = pai_entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.1") }
    vid_entry.should_not be_nil
    vid_entry.as(Tuple(String, String))[1].should eq("00AB")

    # PAI should NOT include productId
    pid_entry = pai_entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.2") }
    pid_entry.should be_nil

    # Check DAC (includes both vendorId and productId)
    dac_cert_der, _key = manager.get_dac_cert(product_id)
    dac_cert = OpenSSL::X509::Certificate.from_der(dac_cert_der)
    dac_entries = dac_cert.subject.to_a

    vid_entry = dac_entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.1") }
    vid_entry.should_not be_nil
    vid_entry.as(Tuple(String, String))[1].should eq("00AB")

    pid_entry = dac_entries.find { |(oid, _value)| oid.starts_with?("1.3.6.1.4.1.37244.2.2") }
    pid_entry.should_not be_nil
    pid_entry.as(Tuple(String, String))[1].should eq("0012")
  end
end

describe Matter::Certificate::AttestationCertificateManager do
  it "preserves SHA1 subject and issuer key identifiers through OpenSSL extension generation" do
    manager = Matter::Certificate::AttestationCertificateManager.new(0xFFF1_u16)
    dac_der, dac_key = manager.get_dac_cert(0x8000_u16)
    pai = OpenSSL::X509::Certificate.from_der(manager.pai_cert)
    dac = OpenSSL::X509::Certificate.from_der(dac_der)
    pai_hash = OpenSSL::Digest.new("SHA1").update(manager.pai_key_pair.public_key).final
    dac_hash = OpenSSL::Digest.new("SHA1").update(dac_key.public_key).final
    paa_hash = Matter::Certificate::ChipPAAuthorities::TEST_CERT_PAA_NO_VID_SKID
    # Assert the actual DER extension values, independently of the encoder.
    ski_tag = 0x04_u8
    aki_sequence_tag = 0x30_u8
    aki_identifier_tag = 0x80_u8
    identifier_length = 20_u8
    tagged_identifier_length = identifier_length + 2_u8
    { {pai, pai_hash, paa_hash}, {dac, dac_hash, pai_hash} }.each do |cert, subject, authority|
      ski = cert.extensions.find { |extension| extension.oid == "subjectKeyIdentifier" }.as(OpenSSL::X509::Extension)
      aki = cert.extensions.find { |extension| extension.oid == "authorityKeyIdentifier" }.as(OpenSSL::X509::Extension)
      { {ski, Slice.join([Bytes[ski_tag, identifier_length], subject])},
       {aki, Slice.join([Bytes[aki_sequence_tag, tagged_identifier_length, aki_identifier_tag, identifier_length], authority])} }.each do |extension, expected|
        data = LibCrypto.x509_extension_get_data(extension)
        Bytes.new(LibCrypto.asn1_string_get0_data(data), LibCrypto.asn1_string_length(data)).should eq(expected)
      end
    end
  end
end
