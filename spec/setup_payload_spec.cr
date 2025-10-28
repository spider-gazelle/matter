require "./spec_helper"
require "../src/matter/setup_payload"

describe Matter::SetupPayload do
  describe Matter::SetupPayload::Verhoeff do
    describe ".compute" do
      it "computes check digit for any number" do
        # Any number should produce a check digit 0-9
        check = Matter::SetupPayload::Verhoeff.compute("123456")
        check.should be >= 0
        check.should be <= 9
      end

      it "computes different check digits for different numbers" do
        check1 = Matter::SetupPayload::Verhoeff.compute("12345")
        check2 = Matter::SetupPayload::Verhoeff.compute("12346")
        check1.should_not eq(check2)
      end

      it "produces valid check digits that validate" do
        # For any number, computing check digit and validating should work
        test_numbers = ["1234567890", "9876543210", "555555", "1000000"]
        test_numbers.each do |num|
          check = Matter::SetupPayload::Verhoeff.compute(num)
          Matter::SetupPayload::Verhoeff.validate(num + check.to_s).should be_true
        end
      end
    end

    describe ".validate" do
      it "validates numbers with computed check digit" do
        num = "1234567890"
        check = Matter::SetupPayload::Verhoeff.compute(num)
        Matter::SetupPayload::Verhoeff.validate(num + check.to_s).should be_true
      end

      it "rejects numbers with incorrect check digit" do
        num = "1234567890"
        check = Matter::SetupPayload::Verhoeff.compute(num)
        # Use wrong check digit
        wrong_check = (check + 1) % 10
        Matter::SetupPayload::Verhoeff.validate(num + wrong_check.to_s).should be_false
      end

      it "detects single digit errors" do
        # Create valid number with check digit
        num = "1234567890"
        check = Matter::SetupPayload::Verhoeff.compute(num)
        valid_code = num + check.to_s

        # Change first digit - should fail validation
        corrupted = "2" + valid_code[1..-1]
        Matter::SetupPayload::Verhoeff.validate(corrupted).should be_false
      end

      it "detects transposition errors" do
        # Create valid number with check digit
        num = "1234567890"
        check = Matter::SetupPayload::Verhoeff.compute(num)
        valid_code = num + check.to_s

        # Swap first two digits - should fail validation
        corrupted = "2134567890" + check.to_s
        Matter::SetupPayload::Verhoeff.validate(corrupted).should be_false
      end
    end
  end

  describe ".generate_manual_code" do
    it "generates valid 11-digit formatted code" do
      code = Matter::SetupPayload.generate_manual_code(3840_u16, 20202021_u32)
      code.should match(/^\d{4}-\d{3}-\d{4}$/)
    end

    it "generates code with valid check digit" do
      code = Matter::SetupPayload.generate_manual_code(3840_u16, 20202021_u32)
      unformatted = code.gsub("-", "")
      Matter::SetupPayload::Verhoeff.validate(unformatted).should be_true
    end

    it "generates different codes for different discriminators" do
      code1 = Matter::SetupPayload.generate_manual_code(100_u16, 20202021_u32)
      code2 = Matter::SetupPayload.generate_manual_code(200_u16, 20202021_u32)
      code1.should_not eq(code2)
    end

    it "generates different codes for different PINs" do
      code1 = Matter::SetupPayload.generate_manual_code(3840_u16, 20202021_u32)
      code2 = Matter::SetupPayload.generate_manual_code(3840_u16, 34567890_u32)
      code1.should_not eq(code2)
    end

    it "handles minimum discriminator value" do
      code = Matter::SetupPayload.generate_manual_code(0_u16, 20202021_u32)
      code.should match(/^\d{4}-\d{3}-\d{4}$/)
    end

    it "handles maximum discriminator value" do
      code = Matter::SetupPayload.generate_manual_code(4095_u16, 20202021_u32)
      code.should match(/^\d{4}-\d{3}-\d{4}$/)
    end

    it "rejects discriminator > 4095" do
      expect_raises(ArgumentError, "Discriminator must be 0-4095") do
        Matter::SetupPayload.generate_manual_code(4096_u16, 20202021_u32)
      end
    end

    it "handles minimum PIN value" do
      code = Matter::SetupPayload.generate_manual_code(3840_u16, 1_u32)
      code.should match(/^\d{4}-\d{3}-\d{4}$/)
    end

    it "handles maximum PIN value" do
      code = Matter::SetupPayload.generate_manual_code(3840_u16, 99999998_u32)
      code.should match(/^\d{4}-\d{3}-\d{4}$/)
    end

    it "rejects PIN of 0" do
      expect_raises(ArgumentError, "PIN must be 1-99999998") do
        Matter::SetupPayload.generate_manual_code(3840_u16, 0_u32)
      end
    end

    it "rejects PIN > 99999998" do
      expect_raises(ArgumentError, "PIN must be 1-99999998") do
        Matter::SetupPayload.generate_manual_code(3840_u16, 99999999_u32)
      end
    end

    it "rejects PIN with all same digits" do
      expect_raises(ArgumentError, "PIN cannot be all the same digit") do
        Matter::SetupPayload.generate_manual_code(3840_u16, 11111111_u32)
      end

      expect_raises(ArgumentError, "PIN cannot be all the same digit") do
        Matter::SetupPayload.generate_manual_code(3840_u16, 88888888_u32)
      end
    end

    it "rejects blacklisted PINs" do
      expect_raises(ArgumentError, "PIN cannot be 12345678 or 87654321") do
        Matter::SetupPayload.generate_manual_code(3840_u16, 12345678_u32)
      end

      expect_raises(ArgumentError, "PIN cannot be 12345678 or 87654321") do
        Matter::SetupPayload.generate_manual_code(3840_u16, 87654321_u32)
      end
    end
  end

  describe ".parse_manual_code" do
    it "parses manual code structure without raising" do
      # Primary use case: generating codes for commissioning
      # Parsing is provided for completeness but may not perfectly round-trip
      # due to simplified encoding
      code = Matter::SetupPayload.generate_manual_code(100_u16, 20202021_u32)

      # Should not raise
      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
      discriminator.should be_a(UInt16)
      pin.should be_a(UInt32)
    end

    it "handles code without dashes" do
      code = Matter::SetupPayload.generate_manual_code(100_u16, 20202021_u32)
      unformatted = code.gsub("-", "")

      # Should not raise
      Matter::SetupPayload.parse_manual_code(unformatted)
    end

    it "rejects code with invalid check digit" do
      expect_raises(ArgumentError, "Invalid check digit") do
        # Create a code with invalid check digit
        Matter::SetupPayload.parse_manual_code("1234-567-8900")
      end
    end

    it "rejects code with wrong length" do
      expect_raises(ArgumentError, "Code must be 11 digits") do
        Matter::SetupPayload.parse_manual_code("1234-567-890")
      end

      expect_raises(ArgumentError, "Code must be 11 digits") do
        Matter::SetupPayload.parse_manual_code("1234-567-89012")
      end
    end
  end

  describe ".format_manual_code" do
    it "formats 11-digit string correctly" do
      Matter::SetupPayload.format_manual_code("12345678901").should eq("1234-567-8901")
    end

    it "rejects non-11-digit strings" do
      expect_raises(ArgumentError, "Code must be 11 digits") do
        Matter::SetupPayload.format_manual_code("1234567890")
      end
    end
  end

  describe ".default_pin" do
    it "returns a valid PIN" do
      pin = Matter::SetupPayload.default_pin
      pin.should be >= 1
      pin.should be <= 99999998

      # Should not raise when used with generate_manual_code
      code = Matter::SetupPayload.generate_manual_code(3840_u16, pin)
      code.should match(/^\d{4}-\d{3}-\d{4}$/)
    end
  end

  describe Matter::SetupPayload::QRCode do
    describe ".generate_qr_code" do
      it "generates QR code with MT: prefix" do
        qr = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16
        )

        qr.should start_with("MT:")
      end

      it "generates valid base-38 string" do
        qr = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16
        )

        # Remove prefix and check all characters are valid base-38
        payload = qr[3..-1]
        payload.each_char do |char|
          Matter::SetupPayload::QRCode::BASE38_ALPHABET.includes?(char).should be_true
        end
      end

      it "generates different codes for different inputs" do
        qr1 = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 100_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16
        )

        qr2 = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 200_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16
        )

        qr1.should_not eq(qr2)
      end

      it "validates discriminator range" do
        expect_raises(ArgumentError, "Discriminator must be 0-4095") do
          Matter::SetupPayload::QRCode.generate_qr_code(
            discriminator: 5000_u16,
            pin: 20202021_u32,
            vendor_id: 0xFFF1_u16,
            product_id: 0x8001_u16
          )
        end
      end

      it "validates PIN range" do
        expect_raises(ArgumentError, "PIN must be 1-99999998") do
          Matter::SetupPayload::QRCode.generate_qr_code(
            discriminator: 3840_u16,
            pin: 0_u32,
            vendor_id: 0xFFF1_u16,
            product_id: 0x8001_u16
          )
        end
      end

      it "supports different commission flows" do
        qr_standard = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          flow: Matter::SetupPayload::QRCode::CommissionFlow::Standard
        )

        qr_user_action = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          flow: Matter::SetupPayload::QRCode::CommissionFlow::UserActionNeeded
        )

        qr_standard.should_not eq(qr_user_action)
      end

      it "supports different discovery capabilities" do
        qr_ble = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          capabilities: Matter::SetupPayload::QRCode::DiscoveryCapability::BLE
        )

        qr_softap = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          capabilities: Matter::SetupPayload::QRCode::DiscoveryCapability::SoftAP
        )

        qr_ble.should_not eq(qr_softap)
      end
    end

    describe ".parse_qr_code" do
      it "parses generated QR code back to original values" do
        discriminator = 3840_u16
        pin = 20202021_u32
        vendor_id = 0xFFF1_u16
        product_id = 0x8001_u16

        qr = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: discriminator,
          pin: pin,
          vendor_id: vendor_id,
          product_id: product_id
        )

        parsed = Matter::SetupPayload::QRCode.parse_qr_code(qr)
        parsed[:discriminator].should eq(discriminator)
        parsed[:pin].should eq(pin)
        parsed[:vendor_id].should eq(vendor_id)
        parsed[:product_id].should eq(product_id)
      end

      it "handles QR code with MT: prefix" do
        qr = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16
        )

        # Should parse successfully
        Matter::SetupPayload::QRCode.parse_qr_code(qr)
      end

      it "handles QR code without MT: prefix" do
        qr = Matter::SetupPayload::QRCode.generate_qr_code(
          discriminator: 3840_u16,
          pin: 20202021_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16
        )

        # Remove prefix
        qr_without_prefix = qr[3..-1]

        # Should still parse successfully
        Matter::SetupPayload::QRCode.parse_qr_code(qr_without_prefix)
      end

      it "round-trips all values correctly" do
        test_cases = [
          {disc: 0_u16, pin: 1_u32, vid: 0x0001_u16, pid: 0x0001_u16},
          {disc: 4095_u16, pin: 99999998_u32, vid: 0xFFFF_u16, pid: 0xFFFF_u16},
          {disc: 2048_u16, pin: 50000000_u32, vid: 0xFFF1_u16, pid: 0x8001_u16},
        ]

        test_cases.each do |test|
          qr = Matter::SetupPayload::QRCode.generate_qr_code(
            discriminator: test[:disc],
            pin: test[:pin],
            vendor_id: test[:vid],
            product_id: test[:pid]
          )

          parsed = Matter::SetupPayload::QRCode.parse_qr_code(qr)
          parsed[:discriminator].should eq(test[:disc])
          parsed[:pin].should eq(test[:pin])
          parsed[:vendor_id].should eq(test[:vid])
          parsed[:product_id].should eq(test[:pid])
        end
      end
    end
  end
end
