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

  it "returns PAI certificate via get_pai_cert" do
    vendor_id = 0xFFF1_u16
    manager = Matter::Certificate::AttestationCertificateManager.new(vendor_id)

    pai_cert = manager.get_pai_cert
    pai_cert.should eq(manager.pai_cert)
    pai_cert.should_not be_nil
    pai_cert.size.should be > 0
  end
end
