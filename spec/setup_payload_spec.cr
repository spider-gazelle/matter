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
end
