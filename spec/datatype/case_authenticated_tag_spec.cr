require "../spec_helper"
require "../../src/matter/datatype/case_authenticated_tag"

# Ported from matter.js CaseAuthenticatedTagTest.ts
# Tests CaseAuthenticatedTag datatype functionality
describe Matter::DataType::CaseAuthenticatedTag do
  it "should create a valid CaseAuthenticatedTag" do
    tag = Matter::DataType::CaseAuthenticatedTag.new(0x10001_u32)
    tag.value.should eq(0x10001_u32)
  end

  it "should get the identity value from a CaseAuthenticatedTag" do
    tag = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
    identity_value = tag.identity_value
    identity_value.should eq(0x1234_u16)
  end

  it "should get the version from a CaseAuthenticatedTag" do
    tag = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
    version = tag.version
    version.should eq(0x5678_u16)
  end

  it "should increase the version of a CaseAuthenticatedTag" do
    tag = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
    increased_tag = tag.increase_version
    increased_tag.value.should eq(0x12345679_u32)
  end

  it "should throw an error when increasing the version of a CaseAuthenticatedTag beyond the limit" do
    tag = Matter::DataType::CaseAuthenticatedTag.new(0x1234ffff_u32)
    expect_raises(ArgumentError, "CaseAuthenticatedTag version number must not exceed 0xffff.") do
      tag.increase_version
    end
  end

  it "should throw an error when creating a CaseAuthenticatedTag with version number 0" do
    expect_raises(ArgumentError, "CaseAuthenticatedTag version number must not be 0.") do
      Matter::DataType::CaseAuthenticatedTag.new(0x12340000_u32)
    end
  end

  describe "value semantics" do
    it "compares and hashes by value" do
      a = Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32)
      b = Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32)
      a.should eq(b)
      a.hash.should eq(b.hash)
      a.should_not eq(Matter::DataType::CaseAuthenticatedTag.new(0xABCD1235_u32))
    end

    it "compares against the raw value" do
      (Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32) == 0xABCD1234_u32).should be_true
    end

    it "exposes the layout as constants" do
      Matter::DataType::CaseAuthenticatedTag::IDENTITY_SHIFT.should eq(16)
      Matter::DataType::CaseAuthenticatedTag::VERSION_MASK.should eq(0xFFFF_u32)
      Matter::DataType::CaseAuthenticatedTag::MAX_VERSION.should eq(0xFFFF)
      Matter::DataType::CaseAuthenticatedTag::BYTE_SIZE.should eq(4)
    end

    it "prints as fixed-width hex" do
      "#{Matter::DataType::CaseAuthenticatedTag.new(0x00010001_u32)}".should eq("0x00010001")
    end
  end

  describe "create helper" do
    it "creates a tag from identity and version" do
      tag = Matter::DataType::CaseAuthenticatedTag.create(0x1234_u16, 0x5678_u16)
      tag.value.should eq(0x12345678_u32)
    end

    it "throws when version is 0" do
      expect_raises(ArgumentError, "CaseAuthenticatedTag version number must not be 0.") do
        Matter::DataType::CaseAuthenticatedTag.create(0x1234_u16, 0_u16)
      end
    end
  end

  describe "big-endian bytes" do
    it "serializes to 4 big-endian bytes" do
      tag = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
      tag.to_slice.should eq(Bytes[0x12, 0x34, 0x56, 0x78])
    end

    it "round-trips" do
      original = Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32)
      decoded = Matter::DataType::CaseAuthenticatedTag.new(original.to_slice)
      decoded.should eq(original)
    end

    it "rejects short slices" do
      expect_raises(ArgumentError, "CaseAuthenticatedTag slice must be at least 4 bytes") do
        Matter::DataType::CaseAuthenticatedTag.new(Bytes[1, 2])
      end
    end
  end
end
