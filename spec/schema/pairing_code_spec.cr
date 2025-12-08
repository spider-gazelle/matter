require "../spec_helper"
require "../../src/matter/setup_payload"

# Ported from matter.js PairingCodeSchemaTest.ts
# Tests pairing code encoding/decoding compatibility
describe "Matter SetupPayload" do
  describe "ManualPairingCode" do
    # Test vectors from matter.js PairingCodeSchemaTest.ts
    manual_pairing_test_vectors = [
      {
        discriminator:       2976_u16,
        short_discriminator: 11,
        passcode:            34567890_u32,
        code:                "26318621095",
      },
      {
        discriminator:       10_u16, # short_discriminator 0
        short_discriminator: 0,
        passcode:            12345678_u32,
        code:                "00852607537",
      },
      {
        discriminator:       2001_u16, # short_discriminator 7
        short_discriminator: 7,
        passcode:            23456789_u32,
        code:                "16043714310",
      },
    ]

    describe "encode" do
      it "encodes manual pairing code (test vector 1)" do
        # discriminator 2976 = 0x0BA0 -> short = 11
        result = Matter::SetupPayload.generate_manual_code(2976_u16, 34567890_u32, validate: false)
        # Remove dashes for comparison
        result.gsub("-", "").should eq("26318621095")
      end

      it "encodes manual pairing code (test vector 2)" do
        # discriminator 10 = 0x000A -> short = 0
        # But short discriminator is stored in top 4 bits (bits 8-11)
        # So we need discriminator 0 (short=0) to match
        result = Matter::SetupPayload.generate_manual_code(0_u16, 12345678_u32, validate: false)
        result.gsub("-", "").should eq("00852607537")
      end

      it "encodes manual pairing code (test vector 3)" do
        # short_discriminator 7 means full discriminator with 7 in top 4 bits
        # 7 << 8 = 1792
        result = Matter::SetupPayload.generate_manual_code(1792_u16, 23456789_u32, validate: false)
        result.gsub("-", "").should eq("16043714310")
      end
    end

    describe "decode" do
      it "decodes manual pairing code (test vector 1)" do
        discriminator, passcode = Matter::SetupPayload.parse_manual_code("2631-862-1095")
        # Decoded discriminator is short_discriminator << 8
        (discriminator >> 8).should eq(11) # short discriminator
        passcode.should eq(34567890_u32)
      end

      it "decodes manual pairing code (test vector 2)" do
        discriminator, passcode = Matter::SetupPayload.parse_manual_code("0085 260 7537")
        (discriminator >> 8).should eq(0) # short discriminator
        passcode.should eq(12345678_u32)
      end

      it "decodes manual pairing code (test vector 3)" do
        discriminator, passcode = Matter::SetupPayload.parse_manual_code("1604-371-4310")
        (discriminator >> 8).should eq(7) # short discriminator
        passcode.should eq(23456789_u32)
      end
    end

    describe "round-trip" do
      it "encodes and decodes correctly" do
        original_discriminator = 3840_u16 # 15 << 8 (short_discriminator = 15)
        original_passcode = 20202021_u32

        code = Matter::SetupPayload.generate_manual_code(original_discriminator, original_passcode)
        discriminator, passcode = Matter::SetupPayload.parse_manual_code(code)

        # Short discriminator should match
        (discriminator >> 8).should eq(original_discriminator >> 8)
        passcode.should eq(original_passcode)
      end
    end
  end

  describe "QRCode" do
    # Test vector from matter.js PairingCodeSchemaTest.ts
    # QR_CODE = "MT:YNJV7VSC00CMVH7SR00"
    qr_code_data = {
      version:       0_u8,
      vendor_id:     9050_u16,
      product_id:    65279_u16,
      flow:          Matter::SetupPayload::QRCode::CommissionFlow::Standard,
      capabilities:  Matter::SetupPayload::QRCode::DiscoveryCapability::BLE,
      discriminator: 2976_u16,
      passcode:      34567890_u32,
    }

    describe "encode" do
      it "encodes QR code data" do
        result = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: qr_code_data[:discriminator],
          pin: qr_code_data[:passcode],
          vendor_id: qr_code_data[:vendor_id],
          product_id: qr_code_data[:product_id],
          flow: qr_code_data[:flow],
          capabilities: qr_code_data[:capabilities]
        )

        result.should eq("MT:YNJV7VSC00CMVH7SR00")
      end
    end

    describe "decode" do
      it "decodes QR code data" do
        result = Matter::SetupPayload::QRCode.parse_qr_code("MT:YNJV7VSC00CMVH7SR00")

        result[:version].should eq(0_u64)
        result[:vendor_id].should eq(9050_u16)
        result[:product_id].should eq(65279_u16)
        result[:flow].should eq(0_u8)
        result[:capabilities].should eq(2_u8) # BLE
        result[:discriminator].should eq(2976_u16)
        result[:pin].should eq(34567890_u32)
      end
    end

    describe "round-trip" do
      it "encodes and decodes correctly" do
        original = {
          discriminator: 3840_u16,
          pin:           20202021_u32,
          vendor_id:     0xFFF1_u16,
          product_id:    0x8000_u16,
        }

        code = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: original[:discriminator],
          pin: original[:pin],
          vendor_id: original[:vendor_id],
          product_id: original[:product_id]
        )

        result = Matter::SetupPayload::QRCode.parse_qr_code(code)

        result[:discriminator].should eq(original[:discriminator])
        result[:pin].should eq(original[:pin])
        result[:vendor_id].should eq(original[:vendor_id])
        result[:product_id].should eq(original[:product_id])
      end
    end
  end

  describe "Verhoeff" do
    it "computes correct check digit" do
      # The check digit for "2631862109" should be 5
      # because the full code is "26318621095"
      check = Matter::SetupPayload::Verhoeff.compute("2631862109")
      check.should eq(5)
    end

    it "validates correct codes" do
      Matter::SetupPayload::Verhoeff.validate("26318621095").should be_true
      Matter::SetupPayload::Verhoeff.validate("00852607537").should be_true
      Matter::SetupPayload::Verhoeff.validate("16043714310").should be_true
    end

    it "rejects incorrect check digits" do
      Matter::SetupPayload::Verhoeff.validate("26318621091").should be_false
      Matter::SetupPayload::Verhoeff.validate("00852607530").should be_false
    end
  end
end
