require "./spec_helper"
require "tlv"

describe "TLV Compatibility with matter.js" do
  # Test vectors from matter.js TlvNumberTest.ts
  # These tests verify that the TLV library produces the same byte encoding
  # as matter.js for interoperability

  describe "Number encoding" do
    it "encodes 1 byte signed int" do
      # decoded: -1, encoded: "00ff"
      TLV::Any.new(-1_i8, nil).to_slice.hexstring.should eq("00ff")
    end

    it "encodes 2 bytes signed int" do
      # decoded: 0x0100, encoded: "010001"
      TLV::Any.new(0x0100_i16, nil).to_slice.hexstring.should eq("010001")
    end

    it "encodes 4 bytes signed int" do
      # decoded: 0x01000000, encoded: "0200000001"
      TLV::Any.new(0x01000000_i32, nil).to_slice.hexstring.should eq("0200000001")
    end

    it "encodes 8 bytes signed int" do
      # decoded: 0x01000000000000, encoded: "030000000000000100"
      TLV::Any.new(0x01000000000000_i64, nil).to_slice.hexstring.should eq("030000000000000100")
    end

    it "encodes 1 byte unsigned int" do
      # decoded: 1, encoded: "0401"
      TLV::Any.new(1_u8, nil).to_slice.hexstring.should eq("0401")
    end

    it "encodes 2 bytes unsigned int" do
      # decoded: 0x0100, encoded: "050001"
      TLV::Any.new(0x0100_u16, nil).to_slice.hexstring.should eq("050001")
    end

    it "encodes 4 bytes unsigned int" do
      # decoded: 0x01000000, encoded: "0600000001"
      TLV::Any.new(0x01000000_u32, nil).to_slice.hexstring.should eq("0600000001")
    end

    it "encodes 8 bytes unsigned int" do
      # decoded: 0x01000000000000, encoded: "070000000000000100"
      TLV::Any.new(0x01000000000000_u64, nil).to_slice.hexstring.should eq("070000000000000100")
    end

    it "encodes a float" do
      # decoded: 6546.25390625, encoded: "0a0892cc45"
      TLV::Any.new(6546.25390625_f32, nil).to_slice.hexstring.should eq("0a0892cc45")
    end

    it "encodes a double" do
      # decoded: 6546.254, encoded: "0b2fdd24064192b940"
      TLV::Any.new(6546.254_f64, nil).to_slice.hexstring.should eq("0b2fdd24064192b940")
    end
  end

  describe "Number decoding" do
    it "decodes 1 byte signed int" do
      # encoded: "00ff", decoded: -1
      bytes = "00ff".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(-1)
    end

    it "decodes 2 bytes signed int" do
      # encoded: "010001", decoded: 0x0100
      bytes = "010001".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(0x0100)
    end

    it "decodes 4 bytes signed int" do
      # encoded: "0200000001", decoded: 0x01000000
      bytes = "0200000001".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(0x01000000)
    end

    it "decodes 8 bytes signed int" do
      # encoded: "030000000000000100", decoded: 0x01000000000000
      bytes = "030000000000000100".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(0x01000000000000_i64)
    end

    it "decodes 1 byte unsigned int" do
      # encoded: "0401", decoded: 1
      bytes = "0401".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(1)
    end

    it "decodes 2 bytes unsigned int" do
      # encoded: "050001", decoded: 0x0100
      bytes = "050001".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(0x0100)
    end

    it "decodes 4 bytes unsigned int" do
      # encoded: "0600000001", decoded: 0x01000000
      bytes = "0600000001".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(0x01000000)
    end

    it "decodes 8 bytes unsigned int" do
      # encoded: "070000000000000100", decoded: 0x01000000000000
      bytes = "070000000000000100".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(0x01000000000000_u64)
    end

    it "decodes a float" do
      # encoded: "0a0892cc45", decoded: 6546.25390625
      bytes = "0a0892cc45".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Float32).should be_close(6546.25390625_f32, 0.001)
    end

    it "decodes a double" do
      # encoded: "0b2fdd24064192b940", decoded: 6546.254
      bytes = "0b2fdd24064192b940".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Float64).should be_close(6546.254, 0.001)
    end

    it "decodes 8 bytes small value as a number" do
      # Test from matter.js: decodes value 1 encoded as 8-byte uint
      # encoded: "070100000000000000", decoded: 1
      bytes = "070100000000000000".hexbytes
      result = TLV::Any.from_slice(bytes)
      result.value.as(Int).should eq(1)
    end
  end

  describe "Round-trip encoding/decoding" do
    it "round-trips signed integers" do
      values = [{-1_i8, -1}, {0x0100_i16, 0x0100}, {0x01000000_i32, 0x01000000}, {0x01000000000000_i64, 0x01000000000000_i64}]

      values.each do |value, expected|
        encoded = TLV::Any.new(value, nil).to_slice
        result = TLV::Any.from_slice(encoded)
        result.value.as(Int).should eq(expected)
      end
    end

    it "round-trips unsigned integers" do
      values = [{1_u8, 1}, {0x0100_u16, 0x0100}, {0x01000000_u32, 0x01000000}, {0x01000000000000_u64, 0x01000000000000_u64}]

      values.each do |value, expected|
        encoded = TLV::Any.new(value, nil).to_slice
        result = TLV::Any.from_slice(encoded)
        result.value.as(Int).should eq(expected)
      end
    end

    it "round-trips floating point numbers" do
      float_val = 6546.25390625_f32
      double_val = 6546.254_f64

      # Test float
      encoded = TLV::Any.new(float_val, nil).to_slice
      result = TLV::Any.from_slice(encoded)
      result.value.as(Float32).should be_close(float_val, 0.001)

      # Test double
      encoded = TLV::Any.new(double_val, nil).to_slice
      result = TLV::Any.from_slice(encoded)
      result.value.as(Float64).should be_close(double_val, 0.001)
    end
  end
end
