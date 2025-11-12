require "./spec_helper"
require "../src/matter/setup_payload"

# Manual Pairing Code compatibility tests based on matter.js
# Source: matter.js/packages/types/test/schema/PairingCodeSchemaTest.ts
#
# These tests verify that our manual pairing code generation and parsing
# produces byte-for-byte compatible results with matter.js

describe Matter::SetupPayload, tags: "compatibility" do
  # Test vectors from matter.js PairingCodeSchemaTest.ts (lines 49-74)
  # Each vector specifies discriminator, PIN, and the expected 11-digit code
  describe "generate_manual_code" do
    it "generates code for discriminator 2976, PIN 34567890" do
      # matter.js test vector
      discriminator = 2976_u16
      pin = 34567890_u32
      expected = "26318621095"

      code = Matter::SetupPayload.generate_manual_code(discriminator, pin)

      # Remove dashes for comparison (both formats are valid)
      code.gsub("-", "").should eq(expected)
    end

    it "generates code for discriminator 10, PIN 12345678" do
      # matter.js test vector with spaces (ignored in actual code)
      # Note: PIN 12345678 is blacklisted for production use, but used in test vectors
      # to verify encoding algorithm. Pass validate: false to skip security checks.
      discriminator = 10_u16
      pin = 12345678_u32
      expected = "00852607537"

      code = Matter::SetupPayload.generate_manual_code(discriminator, pin, validate: false)
      code.gsub("-", "").should eq(expected)
    end

    it "generates code for discriminator 2001, PIN 23456789" do
      # matter.js test vector with dashes (ignored in actual code)
      discriminator = 2001_u16
      pin = 23456789_u32
      expected = "16043714310"

      code = Matter::SetupPayload.generate_manual_code(discriminator, pin)
      code.gsub("-", "").should eq(expected)
    end
  end

  describe "parse_manual_code" do
    it "parses code 26318621095 (discriminator 2976, PIN 34567890)" do
      # Manual codes only encode the SHORT discriminator (top 4 bits)
      # For discriminator 2976 = 0xBA0, short_discriminator = 11 = 0xB
      # Reconstructed discriminator = 11 << 8 = 2816 = 0xB00 (bottom 8 bits lost)
      code = "26318621095"
      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)

      # Verify short discriminator matches
      discriminator.should eq(2816_u16) # 11 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(11_u16)
      # PIN should be exact
      pin.should eq(34567890_u32)
    end

    it "parses code with spaces 0085 260 7537 (discriminator 10, PIN 12345678)" do
      # For discriminator 10 = 0x00A, short_discriminator = 0
      # Reconstructed discriminator = 0 << 8 = 0 (all bits lost)
      # Spaces should be ignored
      code = "0085 260 7537"
      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)

      discriminator.should eq(0_u16) # 0 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(0_u16)
      pin.should eq(12345678_u32)
    end

    it "parses code with dashes 1604-371-4310 (discriminator 2001, PIN 23456789)" do
      # For discriminator 2001 = 0x7D1, short_discriminator = 7 = 0x7
      # Reconstructed discriminator = 7 << 8 = 1792 = 0x700 (bottom 8 bits lost)
      # Dashes should be ignored
      code = "1604-371-4310"
      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)

      discriminator.should eq(1792_u16) # 7 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(7_u16)
      pin.should eq(23456789_u32)
    end
  end

  describe "round-trip encoding/decoding" do
    it "correctly round-trips all matter.js test vectors" do
      test_vectors = [
        {discriminator: 2976_u16, pin: 34567890_u32, validate: true},
        {discriminator: 10_u16, pin: 12345678_u32, validate: false}, # PIN blacklisted, skip validation for test
        {discriminator: 2001_u16, pin: 23456789_u32, validate: true},
      ]

      test_vectors.each do |vector|
        # Generate code
        code = Matter::SetupPayload.generate_manual_code(
          vector[:discriminator],
          vector[:pin],
          validate: vector[:validate]
        )

        # Parse it back
        parsed_discriminator, parsed_pin = Matter::SetupPayload.parse_manual_code(code)

        # PIN should match exactly
        parsed_pin.should eq(vector[:pin])

        # Short discriminator portion should match (lossy encoding)
        Matter::SetupPayload.short_discriminator(parsed_discriminator).should eq(
          Matter::SetupPayload.short_discriminator(vector[:discriminator])
        )
      end
    end
  end

  describe "Verhoeff check digit validation" do
    it "validates correct check digits" do
      # All matter.js test vectors have valid check digits
      valid_codes = [
        "26318621095",
        "00852607537",
        "16043714310",
      ]

      valid_codes.each do |code|
        # Should not raise an error
        Matter::SetupPayload.parse_manual_code(code)
      end
    end

    it "rejects invalid check digits" do
      # Tamper with the last digit (check digit)
      invalid_codes = [
        "26318621094", # Changed last digit from 5 to 4
        "00852607536", # Changed last digit from 7 to 6
        "16043714319", # Changed last digit from 0 to 9
      ]

      invalid_codes.each do |code|
        expect_raises(ArgumentError, /Invalid check digit/) do
          Matter::SetupPayload.parse_manual_code(code)
        end
      end
    end
  end

  describe "format_manual_code" do
    it "formats 11-digit code as xxxx-xxx-xxxx" do
      code = "26318621095"
      formatted = Matter::SetupPayload.format_manual_code(code)

      formatted.should eq("2631-862-1095")
    end

    it "rejects codes that are not 11 digits" do
      expect_raises(ArgumentError, /Code must be 11 digits/) do
        Matter::SetupPayload.format_manual_code("123456789") # Only 9 digits
      end

      expect_raises(ArgumentError, /Code must be 11 digits/) do
        Matter::SetupPayload.format_manual_code("123456789012") # 12 digits
      end
    end
  end

  describe "PIN validation" do
    it "rejects PINs outside valid range" do
      expect_raises(ArgumentError, /PIN must be 1-99999998/) do
        Matter::SetupPayload.generate_manual_code(100_u16, 0_u32) # PIN 0 invalid
      end

      expect_raises(ArgumentError, /PIN must be 1-99999998/) do
        Matter::SetupPayload.generate_manual_code(100_u16, 99999999_u32) # PIN too high
      end
    end

    it "rejects PINs with all same digits" do
      # 11111111, 22222222, etc. are invalid
      expect_raises(ArgumentError, /PIN cannot be all the same digit/) do
        Matter::SetupPayload.generate_manual_code(100_u16, 11111111_u32)
      end

      expect_raises(ArgumentError, /PIN cannot be all the same digit/) do
        Matter::SetupPayload.generate_manual_code(100_u16, 77777777_u32)
      end
    end

    it "rejects blacklisted PINs" do
      expect_raises(ArgumentError, /PIN cannot be 12345678 or 87654321/) do
        Matter::SetupPayload.generate_manual_code(100_u16, 12345678_u32)
      end

      expect_raises(ArgumentError, /PIN cannot be 12345678 or 87654321/) do
        Matter::SetupPayload.generate_manual_code(100_u16, 87654321_u32)
      end
    end
  end

  describe "discriminator validation" do
    it "rejects discriminators outside valid range" do
      expect_raises(ArgumentError, /Discriminator must be 0-4095/) do
        Matter::SetupPayload.generate_manual_code(4096_u16, 20202021_u32)
      end

      expect_raises(ArgumentError, /Discriminator must be 0-4095/) do
        Matter::SetupPayload.generate_manual_code(9999_u16, 20202021_u32)
      end
    end

    it "accepts discriminator 0" do
      # 0 is a valid discriminator
      code = Matter::SetupPayload.generate_manual_code(0_u16, 20202021_u32)

      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
      discriminator.should eq(0_u16)
      pin.should eq(20202021_u32)
    end

    it "accepts discriminator 4095 (maximum)" do
      # 4095 = 0xFFF is the maximum valid discriminator (12-bit value)
      # Short discriminator (bits 8-11) = 15 = 0xF
      # Reconstructed discriminator = 15 << 8 = 3840 = 0xF00
      code = Matter::SetupPayload.generate_manual_code(4095_u16, 20202021_u32)

      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
      # Verify short discriminator matches (lossy encoding)
      discriminator.should eq(3840_u16) # 15 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(15_u16)
      Matter::SetupPayload.short_discriminator(4095_u16).should eq(15_u16)
      pin.should eq(20202021_u32)
    end
  end

  describe "edge cases" do
    it "handles minimum PIN value (1)" do
      # Discriminator 100 = 0x064
      # Short discriminator (bits 8-11) = 0
      # Reconstructed discriminator = 0 << 8 = 0
      code = Matter::SetupPayload.generate_manual_code(100_u16, 1_u32)

      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
      # Verify short discriminator matches (lossy encoding)
      discriminator.should eq(0_u16) # 0 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(0_u16)
      Matter::SetupPayload.short_discriminator(100_u16).should eq(0_u16)
      pin.should eq(1_u32)
    end

    it "handles maximum PIN value (99999998)" do
      # Discriminator 100 = 0x064
      # Short discriminator (bits 8-11) = 0
      # Reconstructed discriminator = 0 << 8 = 0
      code = Matter::SetupPayload.generate_manual_code(100_u16, 99999998_u32)

      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
      # Verify short discriminator matches (lossy encoding)
      discriminator.should eq(0_u16) # 0 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(0_u16)
      Matter::SetupPayload.short_discriminator(100_u16).should eq(0_u16)
      pin.should eq(99999998_u32)
    end

    it "handles leading zeros in discriminator" do
      # Discriminator 5 = 0x005
      # Short discriminator (bits 8-11) = 0
      # Reconstructed discriminator = 0 << 8 = 0
      code = Matter::SetupPayload.generate_manual_code(5_u16, 20202021_u32)

      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
      # Verify short discriminator matches (lossy encoding)
      discriminator.should eq(0_u16) # 0 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(0_u16)
      Matter::SetupPayload.short_discriminator(5_u16).should eq(0_u16)
      pin.should eq(20202021_u32)
    end

    it "handles leading zeros in PIN" do
      # Discriminator 100 = 0x064
      # Short discriminator (bits 8-11) = 0
      # Reconstructed discriminator = 0 << 8 = 0
      # PIN 10 should be encoded/decoded correctly (treated as 00000010)
      code = Matter::SetupPayload.generate_manual_code(100_u16, 10_u32)

      discriminator, pin = Matter::SetupPayload.parse_manual_code(code)
      # Verify short discriminator matches (lossy encoding)
      discriminator.should eq(0_u16) # 0 << 8
      Matter::SetupPayload.short_discriminator(discriminator).should eq(0_u16)
      Matter::SetupPayload.short_discriminator(100_u16).should eq(0_u16)
      pin.should eq(10_u32)
    end
  end
end
