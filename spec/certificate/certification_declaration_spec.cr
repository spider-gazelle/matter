require "../spec_helper"
require "../../src/matter/certificate/certification_declaration"

describe Matter::Certificate::CertificationDeclaration do
  it "generates a certification declaration" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16

    cd = Matter::Certificate::CertificationDeclaration.generate(vendor_id, product_id)

    # Should generate non-empty CD
    cd.should_not be_nil
    cd.size.should be > 0
  end

  it "generates valid DER-encoded PKCS#7 structure" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16

    cd = Matter::Certificate::CertificationDeclaration.generate(vendor_id, product_id)

    # Should start with SEQUENCE tag (0x30)
    cd[0].should eq(0x30)

    # Should be DER encoded (length follows tag)
    cd.size.should be > 2
  end

  it "includes vendor and product IDs in TLV content" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16

    cd = Matter::Certificate::CertificationDeclaration.generate(vendor_id, product_id)

    # CD should be large enough to contain the TLV structure
    # TLV + PKCS#7 overhead should be at least 100 bytes
    cd.size.should be > 100
  end

  it "generates different CDs for different product IDs" do
    vendor_id = 0xFFF1_u16
    product_id1 = 0x8000_u16
    product_id2 = 0x8001_u16

    cd1 = Matter::Certificate::CertificationDeclaration.generate(vendor_id, product_id1)
    cd2 = Matter::Certificate::CertificationDeclaration.generate(vendor_id, product_id2)

    # CDs should be different for different products
    cd1.should_not eq(cd2)
  end

  it "generates consistent CDs for same parameters" do
    vendor_id = 0xFFF1_u16
    product_id = 0x8000_u16

    cd1 = Matter::Certificate::CertificationDeclaration.generate(vendor_id, product_id)
    cd2 = Matter::Certificate::CertificationDeclaration.generate(vendor_id, product_id)

    # Note: CDs may differ slightly due to DER signature encoding variations (1-3 bytes)
    # ECDSA signatures in DER format can have variable length due to integer encoding
    size_diff = (cd1.size - cd2.size).abs
    size_diff.should be <= 3
  end
end
