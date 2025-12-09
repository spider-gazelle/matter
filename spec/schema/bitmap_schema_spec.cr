require "../spec_helper"
require "../../src/matter/schema/bitmap_schema"

# Ported from matter.js BitmapSchemaTest.ts
# Tests bitmap encoding/decoding with named fields
describe Matter::Schema do
  describe "BitmapSchema" do
    # Test schema matching matter.js:
    # const TestBitmapSchema = BitmapSchema({
    #     flag1: BitFlag(2),
    #     flag2: BitFlag(4),
    #     enumTest: BitFieldEnum<EnumTest>(5, 2),
    #     numberTest: BitField(7, 2),
    # })
    test_schema = Matter::Schema::Bitmap.schema({
      "flag1"      => Matter::Schema::BitFlag.new(2),
      "flag2"      => Matter::Schema::BitFlag.new(4),
      "enumTest"   => Matter::Schema::BitField.new(5, 2),
      "numberTest" => Matter::Schema::BitField.new(7, 2),
    })

    describe "encode" do
      it "encodes a bitmap using the schema" do
        # { flag1: true, flag2: false, enumTest: VALUE_2 (2), numberTest: 1 }
        # Expected: 0xC4
        result = test_schema.encode({
          "flag1"      => true,
          "flag2"      => false,
          "enumTest"   => 2_i32, # VALUE_2
          "numberTest" => 1_i32,
        })

        result.should eq(0xC4_i64)
      end

      it "encodes a bitmap using the schema with not provided unset bits" do
        # { flag1: true, enumTest: VALUE_2 (2), numberTest: 1 }
        # Expected: 0xC4 (flag2 defaults to 0/false)
        result = test_schema.encode({
          "flag1"      => true,
          "enumTest"   => 2_i32,
          "numberTest" => 1_i32,
        })

        result.should eq(0xC4_i64)
      end

      it "encodes a bitmap using the schema with not provided unset bits #2" do
        # { flag1: true }
        # Expected: 0x4
        result = test_schema.encode({
          "flag1" => true,
        })

        result.should eq(0x4_i64)
      end

      it "encodes a bitmap using the schema with all unset bits" do
        # {}
        # Expected: 0
        result = test_schema.encode({} of String => Bool | Int32 | Int64)

        result.should eq(0_i64)
      end
    end

    describe "decode" do
      it "decodes a bitmap using the schema with all bit set" do
        # 0xB4 = 0b10110100
        # flag1 (bit 2) = 1
        # flag2 (bit 4) = 1
        # enumTest (bits 5-6) = 01 = 1 (VALUE_1)
        # numberTest (bits 7-8) = 01 = 1
        result = test_schema.decode(0xB4)

        result["flag1"].should eq(true)
        result["flag2"].should eq(true)
        result["enumTest"].should eq(1) # VALUE_1
        result["numberTest"].should eq(1)
      end

      it "decodes a bitmap using the schema with some set" do
        # 0xC4 = 0b11000100
        # flag1 (bit 2) = 1
        # flag2 (bit 4) = 0
        # enumTest (bits 5-6) = 10 = 2 (VALUE_2)
        # numberTest (bits 7-8) = 01 = 1
        result = test_schema.decode(0xC4)

        result["flag1"].should eq(true)
        result["flag2"].should eq(false)
        result["enumTest"].should eq(2) # VALUE_2
        result["numberTest"].should eq(1)
      end

      it "decodes a bitmap using the schema with none set" do
        # 0x0
        result = test_schema.decode(0x0)

        result["flag1"].should eq(false)
        result["flag2"].should eq(false)
        result["enumTest"].should eq(0)
        result["numberTest"].should eq(0)
      end
    end

    describe "round-trip" do
      it "round-trips encode/decode" do
        original = {
          "flag1"      => true,
          "flag2"      => true,
          "enumTest"   => 1_i32,
          "numberTest" => 3_i32,
        }

        encoded = test_schema.encode(original)
        decoded = test_schema.decode(encoded)

        decoded["flag1"].should eq(true)
        decoded["flag2"].should eq(true)
        decoded["enumTest"].should eq(1)
        decoded["numberTest"].should eq(3)
      end
    end
  end

  describe "ByteArrayBitmapSchema" do
    # Test schema matching matter.js:
    # const TestByteArrayBitmapSchema = ByteArrayBitmapSchema({
    #     flag1: BitFlag(0),
    #     number: BitField(1, 14),
    #     flag2: BitFlag(15),
    # })
    test_byte_schema = Matter::Schema::Bitmap.byte_array_schema({
      "flag1"  => Matter::Schema::BitFlag.new(0),
      "number" => Matter::Schema::BitField.new(1, 14),
      "flag2"  => Matter::Schema::BitFlag.new(15),
    })

    describe "encode" do
      it "encodes a bitmap using the schema" do
        # { flag1: true, flag2: true, number: 0x2000 }
        # Expected: "01c0"
        result = test_byte_schema.encode({
          "flag1"  => true,
          "flag2"  => true,
          "number" => 0x2000_i32,
        })

        result.hexstring.should eq("01c0")
      end
    end

    describe "decode" do
      it "decodes a bitmap using the schema" do
        # Input: "01c0"
        # Expected: { flag1: true, flag2: true, number: 0x2000 }
        result = test_byte_schema.decode("01c0".hexbytes)

        result["flag1"].should eq(true)
        result["flag2"].should eq(true)
        result["number"].should eq(0x2000)
      end
    end

    describe "round-trip" do
      it "round-trips encode/decode" do
        original = {
          "flag1"  => true,
          "flag2"  => false,
          "number" => 0x1234_i32,
        }

        encoded = test_byte_schema.encode(original)
        decoded = test_byte_schema.decode(encoded)

        decoded["flag1"].should eq(true)
        decoded["flag2"].should eq(false)
        decoded["number"].should eq(0x1234)
      end
    end
  end
end
