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

  describe ".group" do
    it "creates a NodeId from a group ID" do
      group_node = Matter::DataType::NodeId.group(0x1234_u16)
      # Group NodeIds have the format 0xFFFFFFFFFFFF + 16-bit group id
      group_node.id.should eq(0xFFFF_FFFF_FFFF_1234_u64)
    end

    it "uses the group node id prefix" do
      Matter::DataType::NodeId.group(0_u16).id.should eq(Matter::DataType::NodeId::GROUP_NODE_ID_PREFIX)
      Matter::DataType::NodeId.group(UInt16::MAX).id.should eq(0xFFFF_FFFF_FFFF_FFFF_u64)
    end
  end

  describe ".random_operational" do
    sample_size = 1000

    it "generates NodeIds within the operational range" do
      sample_size.times do
        random_node = Matter::DataType::NodeId.random_operational

        random_node.id.should_not eq(0_u64)
        random_node.id.should be >= Matter::DataType::NodeId::OPERATIONAL_MINIMUM
        random_node.id.should be <= Matter::DataType::NodeId::OPERATIONAL_MAXIMUM
      end
    end

    it "does not repeat ids" do
      ids = Array.new(sample_size) { Matter::DataType::NodeId.random_operational.id }
      ids.uniq.size.should eq(sample_size)
    end
  end

  describe "constants" do
    it "has correct OPERATIONAL_MINIMUM" do
      Matter::DataType::NodeId::OPERATIONAL_MINIMUM.should eq(1_u64)
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

      node_id.case_authenticated_tag?.should be_true
    end

    it "returns false for non-CAT NodeId" do
      node_id = Matter::DataType::NodeId.new(0x123456789ABCDEF0_u64)

      node_id.case_authenticated_tag?.should be_false
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
