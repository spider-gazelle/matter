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
    identity_value = tag.get_identity_value
    identity_value.should eq(0x1234_u16)
  end

  it "should get the version from a CaseAuthenticatedTag" do
    tag = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
    version = tag.get_version
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

  describe "class methods" do
    it "get_identity_value returns upper 16 bits" do
      tag = Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32)
      Matter::DataType::CaseAuthenticatedTag.get_identity_value(tag).should eq(0xABCD_u16)
    end

    it "get_version returns lower 16 bits" do
      tag = Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32)
      Matter::DataType::CaseAuthenticatedTag.get_version(tag).should eq(0x1234_u16)
    end

    it "increase_version returns new tag with incremented version" do
      tag = Matter::DataType::CaseAuthenticatedTag.new(0xABCD0001_u32)
      new_tag = Matter::DataType::CaseAuthenticatedTag.increase_version(tag)
      new_tag.value.should eq(0xABCD0002_u32)
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

  describe "TLV serialization" do
    it "serializes to TLV" do
      tag = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
      slice = tag.to_slice
      slice.size.should be > 0
    end

    it "round-trips through TLV" do
      original = Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32)
      slice = original.to_slice
      decoded = Matter::DataType::CaseAuthenticatedTag.new(slice)
      decoded.value.should eq(original.value)
    end
  end
end
