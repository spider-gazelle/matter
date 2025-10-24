require "./spec_helper"
require "tlv"

describe "TLV Compatibility with matter.js" do
  # Test vectors from matter.js TlvNumberTest.ts
  # These tests verify that the TLV library produces the same byte encoding
  # as matter.js for interoperability

  describe "Number encoding" do
    it "encodes 1 byte signed int" do
      # decoded: -1, encoded: "00ff"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, -1)
      io.to_slice.hexstring.should eq("00ff")
    end

    it "encodes 2 bytes signed int" do
      # decoded: 0x0100, encoded: "010001"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 0x0100)
      io.to_slice.hexstring.should eq("010001")
    end

    it "encodes 4 bytes signed int" do
      # decoded: 0x01000000, encoded: "0200000001"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 0x01000000)
      io.to_slice.hexstring.should eq("0200000001")
    end

    it "encodes 8 bytes signed int" do
      # decoded: 0x01000000000000, encoded: "030000000000000100"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 0x01000000000000_i64)
      io.to_slice.hexstring.should eq("030000000000000100")
    end

    it "encodes 1 byte unsigned int" do
      # decoded: 1, encoded: "0401"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 1_u64)
      io.to_slice.hexstring.should eq("0401")
    end

    it "encodes 2 bytes unsigned int" do
      # decoded: 0x0100, encoded: "050001"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 0x0100_u64)
      io.to_slice.hexstring.should eq("050001")
    end

    it "encodes 4 bytes unsigned int" do
      # decoded: 0x01000000, encoded: "0600000001"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 0x01000000_u64)
      io.to_slice.hexstring.should eq("0600000001")
    end

    it "encodes 8 bytes unsigned int" do
      # decoded: 0x01000000000000, encoded: "070000000000000100"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 0x01000000000000_u64)
      io.to_slice.hexstring.should eq("070000000000000100")
    end

    it "encodes a float" do
      # decoded: 6546.25390625, encoded: "0a0892cc45"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 6546.25390625_f32)
      io.to_slice.hexstring.should eq("0a0892cc45")
    end

    it "encodes a double" do
      # decoded: 6546.254, encoded: "0b2fdd24064192b940"
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, 6546.254)
      io.to_slice.hexstring.should eq("0b2fdd24064192b940")
    end
  end

  describe "Number decoding" do
    it "decodes 1 byte signed int" do
      # encoded: "00ff", decoded: -1
      bytes = "00ff".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(-1)
    end

    it "decodes 2 bytes signed int" do
      # encoded: "010001", decoded: 0x0100
      bytes = "010001".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(0x0100)
    end

    it "decodes 4 bytes signed int" do
      # encoded: "0200000001", decoded: 0x01000000
      bytes = "0200000001".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(0x01000000)
    end

    it "decodes 8 bytes signed int" do
      # encoded: "030000000000000100", decoded: 0x01000000000000
      bytes = "030000000000000100".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(0x01000000000000_i64)
    end

    it "decodes 1 byte unsigned int" do
      # encoded: "0401", decoded: 1
      bytes = "0401".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(1_u64)
    end

    it "decodes 2 bytes unsigned int" do
      # encoded: "050001", decoded: 0x0100
      bytes = "050001".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(0x0100_u64)
    end

    it "decodes 4 bytes unsigned int" do
      # encoded: "0600000001", decoded: 0x01000000
      bytes = "0600000001".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(0x01000000_u64)
    end

    it "decodes 8 bytes unsigned int" do
      # encoded: "070000000000000100", decoded: 0x01000000000000
      bytes = "070000000000000100".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(0x01000000000000_u64)
    end

    it "decodes a float" do
      # encoded: "0a0892cc45", decoded: 6546.25390625
      bytes = "0a0892cc45".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].as(Float32).should be_close(6546.25390625_f32, 0.001)
    end

    it "decodes a double" do
      # encoded: "0b2fdd24064192b940", decoded: 6546.254
      bytes = "0b2fdd24064192b940".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].as(Float64).should be_close(6546.254, 0.001)
    end

    it "decodes 8 bytes small value as a number" do
      # Test from matter.js: decodes value 1 encoded as 8-byte uint
      # encoded: "070100000000000000", decoded: 1
      bytes = "070100000000000000".hexbytes
      reader = TLV::Reader.new(bytes)
      result = reader.get
      result.as(Hash)["Any"].should eq(1_u64)
    end
  end

  describe "Round-trip encoding/decoding" do
    it "round-trips signed integers" do
      values = [-1, 256, 0x01000000, 0x01000000000000_i64]

      values.each do |value|
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put(nil, value)

        io.rewind
        reader = TLV::Reader.new(io.to_slice)
        result = reader.get

        result.as(Hash)["Any"].should eq(value)
      end
    end

    it "round-trips unsigned integers" do
      values = [1_u64, 0x0100_u64, 0x01000000_u64, 0x01000000000000_u64]

      values.each do |value|
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put(nil, value)

        io.rewind
        reader = TLV::Reader.new(io.to_slice)
        result = reader.get

        result.as(Hash)["Any"].should eq(value)
      end
    end

    it "round-trips floating point numbers" do
      float_val = 6546.25390625_f32
      double_val = 6546.254_f64

      # Test float
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, float_val)

      io.rewind
      reader = TLV::Reader.new(io.to_slice)
      result = reader.get
      result.as(Hash)["Any"].as(Float32).should be_close(float_val, 0.001)

      # Test double
      io = IO::Memory.new
      writer = TLV::Writer.new(io)
      writer.put(nil, double_val)

      io.rewind
      reader = TLV::Reader.new(io.to_slice)
      result = reader.get
      result.as(Hash)["Any"].as(Float64).should be_close(double_val, 0.001)
    end
  end
end
