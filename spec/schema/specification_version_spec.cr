require "../spec_helper"
require "../../src/matter/schema/specification_version"

# Ported from matter.js SpecificationVersionSchemaTest.ts
# Tests specification version encoding/decoding
describe Matter::Schema::SpecificationVersion do
  it "encodes and decodes a specification version" do
    version = Matter::Schema::SpecificationVersionData.new(
      major: 1_u8,
      minor: 2_u8,
      patch: 3_u8
    )

    encoded = Matter::Schema::SpecificationVersion.encode(version)

    encoded.should eq(0x01020300_u32)

    decoded = Matter::Schema::SpecificationVersion.decode(encoded)

    decoded.major.should eq(1_u8)
    decoded.minor.should eq(2_u8)
    decoded.patch.should eq(3_u8)
    decoded.reserved.should eq(0_u8)
  end

  it "decode our encoded version" do
    # SPECIFICATION_VERSION = 0x01040200 (Matter 1.4.2)
    decoded = Matter::Schema::SpecificationVersion.decode(
      Matter::Schema::SpecificationVersion::SPECIFICATION_VERSION
    )

    decoded.major.should eq(1_u8)
    decoded.minor.should eq(4_u8)
    decoded.patch.should eq(2_u8)
    decoded.reserved.should eq(0_u8)
  end

  it "formats version as string" do
    version = Matter::Schema::SpecificationVersionData.new(
      major: 1_u8,
      minor: 4_u8,
      patch: 2_u8
    )

    Matter::Schema::SpecificationVersion.to_s(version).should eq("1.4.2")
  end

  it "round-trips a version" do
    original = Matter::Schema::SpecificationVersionData.new(
      major: 2_u8,
      minor: 0_u8,
      patch: 1_u8,
      reserved: 5_u8
    )

    encoded = Matter::Schema::SpecificationVersion.encode(original)
    decoded = Matter::Schema::SpecificationVersion.decode(encoded)

    decoded.major.should eq(original.major)
    decoded.minor.should eq(original.minor)
    decoded.patch.should eq(original.patch)
    decoded.reserved.should eq(original.reserved)
  end
end
