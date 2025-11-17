require "../spec_helper"
require "../../src/matter/codec/der_codec"

describe Matter::Codec::DERCodec do
  describe "Basic DER encoding helpers" do
    it "encodes OCTET STRING" do
      data = Bytes[0x01, 0x02, 0x03, 0x04]
      encoded = Matter::Codec::DERCodec::Base.encode_octet_string(data)

      # Should be: 04 04 01 02 03 04
      # 04 = OCTET STRING tag
      # 04 = length (4 bytes)
      # 01 02 03 04 = data
      encoded[0].should eq(0x04) # OCTET STRING tag
      encoded[1].should eq(0x04) # length
      encoded[2..5].should eq(data)
    end

    it "encodes SEQUENCE" do
      data = Bytes[0x01, 0x02, 0x03]
      encoded = Matter::Codec::DERCodec::Base.encode_sequence(data)

      # Should be: 30 03 01 02 03
      # 30 = SEQUENCE tag (0x10 | 0x20 constructed)
      # 03 = length (3 bytes)
      # 01 02 03 = data
      encoded[0].should eq(0x30) # SEQUENCE tag
      encoded[1].should eq(0x03) # length
      encoded[2..4].should eq(data)
    end

    it "encodes empty OCTET STRING" do
      data = Bytes.empty
      encoded = Matter::Codec::DERCodec::Base.encode_octet_string(data)

      # Should be: 04 00
      encoded[0].should eq(0x04) # OCTET STRING tag
      encoded[1].should eq(0x00) # length = 0
      encoded.size.should eq(2)
    end

    it "encodes long OCTET STRING with multi-byte length" do
      # Create data > 127 bytes to test multi-byte length encoding
      data = Bytes.new(200, 0xFF_u8)
      encoded = Matter::Codec::DERCodec::Base.encode_octet_string(data)

      encoded[0].should eq(0x04) # OCTET STRING tag
      # Length should be encoded as: 81 C8 (0x81 = one length byte follows, 0xC8 = 200)
      encoded[1].should eq(0x81) # Long form: 1 byte follows
      encoded[2].should eq(0xC8) # 200 in hex
      encoded[3..202].should eq(data)
    end
  end

  describe "OID encoding" do
    it "parses dotted decimal OID notation" do
      oid = Matter::Codec::DERCodec::Base.parse_oid("1.2.840.10045.4.3.2")
      oid.should eq([1_u32, 2_u32, 840_u32, 10045_u32, 4_u32, 3_u32, 2_u32])
    end

    it "encodes simple OID (1.2.840.10045.2.1)" do
      # EC Public Key OID: 1.2.840.10045.2.1
      # First two arcs: 1*40 + 2 = 42 (0x2A)
      # Remaining: 840 (0x86 0x48), 10045 (0xCE 0x3D), 2 (0x02), 1 (0x01)
      encoded = Matter::Codec::DERCodec::Base.encode_oid("1.2.840.10045.2.1")

      # Should be: 06 07 2A 86 48 CE 3D 02 01
      # 06 = OBJECT IDENTIFIER tag
      # 07 = length (7 bytes)
      # 2A 86 48 CE 3D 02 01 = encoded arcs
      encoded[0].should eq(0x06)                 # OBJECT IDENTIFIER tag
      encoded[1].should eq(0x07)                 # length
      encoded[2].should eq(0x2A)                 # 1*40 + 2 = 42
      encoded[3..4].should eq(Bytes[0x86, 0x48]) # 840 in base-128
      encoded[5..6].should eq(Bytes[0xCE, 0x3D]) # 10045 in base-128
      encoded[7].should eq(0x02)                 # 2
      encoded[8].should eq(0x01)                 # 1
    end

    it "encodes OID with large arc values" do
      # Test OID: 2.16.840.1.101.3.4.2.1 (SHA-256)
      # First two: 2*40 + 16 = 96 (0x60)
      # 840 = 0x86 0x48
      # 1 = 0x01
      # 101 = 0x65
      # 3 = 0x03
      # 4 = 0x04
      # 2 = 0x02
      # 1 = 0x01
      encoded = Matter::Codec::DERCodec::Base.encode_oid("2.16.840.1.101.3.4.2.1")

      encoded[0].should eq(0x06) # OBJECT IDENTIFIER tag
      encoded[2].should eq(0x60) # 2*40 + 16 = 96
    end

    it "encodes OID from array of arcs" do
      arcs = [1_u32, 2_u32, 840_u32, 10045_u32, 4_u32, 3_u32, 2_u32]
      encoded = Matter::Codec::DERCodec::Base.encode_oid(arcs)

      # Should match ECDSA with SHA-256: 1.2.840.10045.4.3.2
      encoded[0].should eq(0x06) # OBJECT IDENTIFIER tag
      encoded[2].should eq(0x2A) # 1*40 + 2 = 42
    end

    it "validates OID has at least 2 arcs" do
      expect_raises(ArgumentError, "OID must have at least 2 arcs") do
        Matter::Codec::DERCodec::Base.encode_oid("1")
      end
    end

    it "validates first arc is 0, 1, or 2" do
      expect_raises(ArgumentError, "First arc must be 0, 1, or 2") do
        Matter::Codec::DERCodec::Base.encode_oid("3.2.840")
      end
    end

    it "validates second arc < 40 for first arc 0 or 1" do
      expect_raises(ArgumentError, "Second arc must be < 40 when first arc is 0 or 1") do
        Matter::Codec::DERCodec::Base.encode_oid("1.50.840")
      end
    end
  end

  describe "ObjectId class" do
    it "accepts hex string format (legacy)" do
      # EC Public Key OID as hex: 2A8648CE3D0201
      oid = Matter::Codec::DERCodec::ObjectId.new("2A8648CE3D0201")
      oid.value["_tag"].should eq(0x06)
      oid.value["_bytes"].should eq(Bytes[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
    end

    it "accepts dotted decimal notation (new)" do
      # EC Public Key OID: 1.2.840.10045.2.1
      oid = Matter::Codec::DERCodec::ObjectId.new("1.2.840.10045.2.1")
      oid.value["_tag"].should eq(0x06)
      oid.value["_bytes"].should eq(Bytes[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
    end

    it "produces same result for hex and dotted formats" do
      oid_hex = Matter::Codec::DERCodec::ObjectId.new("2A8648CE3D0201")
      oid_dotted = Matter::Codec::DERCodec::ObjectId.new("1.2.840.10045.2.1")

      oid_hex.value["_bytes"].should eq(oid_dotted.value["_bytes"])
    end
  end

  describe "Real OID examples" do
    it "encodes EC Public Key OID" do
      # 1.2.840.10045.2.1
      encoded = Matter::Codec::DERCodec::Base.encode_oid("1.2.840.10045.2.1")
      # Should match hex: 06 07 2A 86 48 CE 3D 02 01
      encoded.hexstring.upcase.should eq("06072A8648CE3D0201")
    end

    it "encodes prime256v1 curve OID" do
      # 1.2.840.10045.3.1.7
      encoded = Matter::Codec::DERCodec::Base.encode_oid("1.2.840.10045.3.1.7")
      # Should match hex: 06 08 2A 86 48 CE 3D 03 01 07
      encoded.hexstring.upcase.should eq("06082A8648CE3D030107")
    end

    it "encodes ECDSA with SHA-256 OID" do
      # 1.2.840.10045.4.3.2
      encoded = Matter::Codec::DERCodec::Base.encode_oid("1.2.840.10045.4.3.2")
      # Should match hex: 06 08 2A 86 48 CE 3D 04 03 02
      encoded.hexstring.upcase.should eq("06082A8648CE3D040302")
    end

    it "encodes SHA-256 OID" do
      # 2.16.840.1.101.3.4.2.1
      encoded = Matter::Codec::DERCodec::Base.encode_oid("2.16.840.1.101.3.4.2.1")
      # Should match hex: 06 09 60 86 48 01 65 03 04 02 01
      encoded.hexstring.upcase.should eq("0609608648016503040201")
    end

    it "encodes PKCS#7 data OID" do
      # 1.2.840.113549.1.7.1
      # First two: 1*40 + 2 = 42 (0x2A)
      # 840 = 0x86 0x48
      # 113549 = 0x86 0xF7 0x0D (base-128: 1*128^2 + 119*128 + 13)
      # 1 = 0x01
      # 7 = 0x07
      # 1 = 0x01
      encoded = Matter::Codec::DERCodec::Base.encode_oid("1.2.840.113549.1.7.1")
      encoded.hexstring.upcase.should eq("06092A864886F70D010701")
    end

    it "encodes PKCS#7 SignedData OID" do
      # 1.2.840.113549.1.7.2
      encoded = Matter::Codec::DERCodec::Base.encode_oid("1.2.840.113549.1.7.2")
      encoded.hexstring.upcase.should eq("06092A864886F70D010702")
    end
  end
end
