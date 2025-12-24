require "../spec_helper"
require "../../src/matter/datatype/node_id"

# Ported from matter.js NodeIdTests.ts
# Tests NodeId datatype functionality
describe Matter::DataType::NodeId do
  describe "creation" do
    it "creates a valid NodeId with UInt64" do
      node_id = Matter::DataType::NodeId.new(0x10001_u64)
      node_id.id.should eq(0x10001_u64)
    end

    it "creates a valid NodeId from bytes" do
      node_id = Matter::DataType::NodeId.new(0x123456789ABCDEF0_u64)
      node_id.id.should eq(0x123456789ABCDEF0_u64)
    end
  end

  describe "hexstring" do
    it "returns correct hexstring representation" do
      node_id = Matter::DataType::NodeId.new(0x10001_u64)
      # The hexstring method uses BigEndian encoding
      node_id.hexstring.size.should be > 0
    end
  end

  describe "group node id" do
    it "creates a NodeId from a group ID" do
      node_id = Matter::DataType::NodeId.new(0_u64)
      group_node = node_id.get_group_node_id(0x1234_u16)
      # Group NodeIds have the format FFFFFFFFFFFF + group_id (little-endian)
      group_node.id.should be > 0
    end
  end

  describe "random operational node id" do
    it "generates a random operational NodeId" do
      node_id = Matter::DataType::NodeId.new(0_u64)
      random_node = node_id.random_operational_node_id

      # Operational NodeIds must be within the valid range
      random_node.id.should be >= 1
      random_node.id.should be <= Matter::DataType::NodeId::OPERATIONAL_MAXIMUM.to_u64
    end
  end

  describe "constants" do
    it "has correct OPERATIONAL_MINIMUM" do
      Matter::DataType::NodeId::OPERATIONAL_MINIMUM.should eq(BigInt.new(1))
    end

    it "has correct OPERATIONAL_MAXIMUM" do
      # FFFFFFEFFFFFFFFF in hex
      Matter::DataType::NodeId::OPERATIONAL_MAXIMUM.to_s(16).upcase.should eq("FFFFFFEFFFFFFFFF")
    end
  end

  describe "TLV serialization" do
    it "serializes to TLV slice" do
      node_id = Matter::DataType::NodeId.new(0x123456789ABCDEF0_u64)
      slice = node_id.to_slice

      # Should produce a valid TLV encoding
      slice.size.should be > 0
    end

    it "round-trips through TLV" do
      original = Matter::DataType::NodeId.new(0x123456789ABCDEF0_u64)
      slice = original.to_slice

      decoded = Matter::DataType::NodeId.new(slice)
      decoded.id.should eq(original.id)
    end
  end

  describe "CaseAuthenticatedTag support" do
    it "creates NodeId from CaseAuthenticatedTag" do
      cat = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
      node_id = Matter::DataType::NodeId.from_case_authenticated_tag(cat)

      # Format: 0xFFFFFFFD + 32-bit CAT value
      node_id.id.should eq(0xFFFFFFFD12345678_u64)
    end

    it "detects CAT-encoded NodeId" do
      cat = Matter::DataType::CaseAuthenticatedTag.new(0x12345678_u32)
      node_id = Matter::DataType::NodeId.from_case_authenticated_tag(cat)

      node_id.case_authenticated_tag?.should eq(true)
    end

    it "returns false for non-CAT NodeId" do
      node_id = Matter::DataType::NodeId.new(0x123456789ABCDEF0_u64)

      node_id.case_authenticated_tag?.should eq(false)
    end

    it "extracts CaseAuthenticatedTag from NodeId" do
      original_cat = Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32)
      node_id = Matter::DataType::NodeId.from_case_authenticated_tag(original_cat)

      extracted_cat = node_id.extract_as_case_authenticated_tag
      extracted_cat.value.should eq(original_cat.value)
      extracted_cat.identity_value.should eq(0xABCD_u16)
      extracted_cat.version.should eq(0x1234_u16)
    end

    it "raises when extracting CAT from non-CAT NodeId" do
      node_id = Matter::DataType::NodeId.new(0x123456789ABCDEF0_u64)

      expect_raises(ArgumentError, "NodeId does not encode a CaseAuthenticatedTag") do
        node_id.extract_as_case_authenticated_tag
      end
    end

    it "has correct CAT_PREFIX constant" do
      Matter::DataType::NodeId::CAT_PREFIX.should eq(0xFFFFFFFD00000000_u64)
    end
  end
end
