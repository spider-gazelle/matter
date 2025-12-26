require "./spec_helper"
require "../src/matter/fabric"
require "../src/matter/fabric_table"
require "../src/matter/storage/memory_backend"

describe Matter::Fabric do
  describe "initialization" do
    it "creates fabric with valid parameters" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0x1234567890ABCDEF_u64,
        fabric_index: 1_u8,
        node_id: 0x1122334455667788_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        vendor_id: 0xFFF1_u16,
        label: "Test Fabric"
      )

      fabric.fabric_id.should eq(0x1234567890ABCDEF_u64)
      fabric.fabric_index.should eq(1_u8)
      fabric.node_id.should eq(0x1122334455667788_u64)
      fabric.vendor_id.should eq(0xFFF1_u16)
      fabric.label.should eq("Test Fabric")
    end

    it "validates fabric_index range (must be 1-254)" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      expect_raises(ArgumentError, /fabric_index must be 1-254/) do
        Matter::Fabric.new(
          fabric_id: 0x1_u64,
          fabric_index: 0_u8, # Invalid: 0 is reserved
          node_id: 0x1_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: ipk
        )
      end

      expect_raises(ArgumentError, /fabric_index must be 1-254/) do
        Matter::Fabric.new(
          fabric_id: 0x1_u64,
          fabric_index: 255_u8, # Invalid: 255 is reserved
          node_id: 0x1_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: ipk
        )
      end
    end

    it "validates IPK is exactly 16 bytes" do
      key = Matter::Crypto::Key.generate_key_pair

      expect_raises(ArgumentError, /ipk must be 16 bytes/) do
        Matter::Fabric.new(
          fabric_id: 0x1_u64,
          fabric_index: 1_u8,
          node_id: 0x1_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: Random::Secure.random_bytes(15) # Too short
        )
      end
    end

    it "validates label length (max 32 chars)" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      expect_raises(ArgumentError, /label must be <= 32 characters/) do
        Matter::Fabric.new(
          fabric_id: 0x1_u64,
          fabric_index: 1_u8,
          node_id: 0x1_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: ipk,
          label: "A" * 33 # Too long
        )
      end
    end

    it "validates fabric_id is not zero" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      expect_raises(ArgumentError, /fabric_id must not be 0/) do
        Matter::Fabric.new(
          fabric_id: 0_u64,
          fabric_index: 1_u8,
          node_id: 0x1_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: ipk
        )
      end
    end

    it "validates node_id is not zero" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      expect_raises(ArgumentError, /node_id must not be 0/) do
        Matter::Fabric.new(
          fabric_id: 0x1_u64,
          fabric_index: 1_u8,
          node_id: 0_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: ipk
        )
      end
    end
  end

  describe "serialization" do
    it "serializes to hash" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0x1234567890ABCDEF_u64,
        fabric_index: 1_u8,
        node_id: 0x1122334455667788_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        vendor_id: 0xFFF1_u16,
        label: "Test"
      )

      hash = fabric.to_h
      hash["fabric_id"].should eq(0x1234567890ABCDEF_u64)
      hash["fabric_index"].should eq(1_u8)
      hash["vendor_id"].should eq(0xFFF1_u16)
      hash["label"].should eq("Test")
    end

    it "deserializes from hash" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)
      root_pk = Random::Secure.random_bytes(65)
      op_cert = Random::Secure.random_bytes(200)

      original = Matter::Fabric.new(
        fabric_id: 0x1234567890ABCDEF_u64,
        fabric_index: 1_u8,
        node_id: 0x1122334455667788_u64,
        root_public_key: root_pk,
        operational_cert: op_cert,
        operational_key: key,
        ipk: ipk,
        vendor_id: 0xFFF1_u16,
        label: "Test"
      )

      hash = original.to_h
      restored = Matter::Fabric.from_h(hash)

      restored.fabric_id.should eq(original.fabric_id)
      restored.fabric_index.should eq(original.fabric_index)
      restored.node_id.should eq(original.node_id)
      restored.vendor_id.should eq(original.vendor_id)
      restored.label.should eq(original.label)
      restored.ipk.should eq(original.ipk)
    end
  end

  describe "helper methods" do
    it "generates compressed fabric ID using HKDF" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      # Create a known root public key (65 bytes: 0x04 || x || y)
      root_pub_key = Bytes.new(65)
      root_pub_key[0] = 0x04_u8 # Uncompressed point indicator

      fabric = Matter::Fabric.new(
        fabric_id: 0x1234567890ABCDEF_u64,
        fabric_index: 1_u8,
        node_id: 0xAABBCCDDEEFF0011_u64,
        root_public_key: root_pub_key,
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      compressed = fabric.compressed_fabric_id

      # Compressed fabric ID should be 8 bytes
      compressed.size.should eq(8)

      # Verify it's deterministic (same inputs produce same output)
      compressed2 = fabric.compressed_fabric_id
      compressed.should eq(compressed2)
    end

    it "compressed fabric ID uses HKDF with correct parameters" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      # Create root public key
      root_pub_key = Bytes.new(65)
      root_pub_key[0] = 0x04_u8 # Uncompressed point indicator
      # Fill with test data
      (1...65).each { |i| root_pub_key[i] = (i % 256).to_u8 }

      fabric_id = 0x1234567890ABCDEF_u64

      fabric = Matter::Fabric.new(
        fabric_id: fabric_id,
        fabric_index: 1_u8,
        node_id: 0xAABBCCDDEEFF0011_u64,
        root_public_key: root_pub_key,
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      compressed = fabric.compressed_fabric_id

      # Manually calculate what it should be using HKDF
      # Key: root public key without first byte
      hkdf_key = root_pub_key[1..-1]

      # Salt: fabric_id as 8 bytes (big-endian per Matter spec 4.3.2.2)
      salt = Bytes.new(8)
      IO::ByteFormat::BigEndian.encode(fabric_id, salt)

      # Info: "CompressedFabric"
      info = "CompressedFabric".to_slice

      # Calculate expected value
      expected = Matter::Crypto.create_hkdf_key(hkdf_key, salt, info, 8)

      compressed.should eq(expected)
    end

    it "marks fabric as used" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      # Create fabric with an old timestamp
      old_time = Time.utc.to_unix - 100
      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        last_used_at: old_time
      )

      fabric.last_used_at.should eq(old_time)
      fabric.mark_used
      fabric.last_used_at.should be > old_time
    end

    it "checks if fabric is expired" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      # Create fabric with old timestamp
      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        last_used_at: Time.utc.to_unix - 365 * 24 * 3600 - 1 # Just over 1 year
      )

      fabric.expired?.should be_true

      # Fresh fabric should not be expired
      fresh = Matter::Fabric.new(
        fabric_id: 0x2_u64,
        fabric_index: 2_u8,
        node_id: 0x2_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      fresh.expired?.should be_false
    end
  end

  describe "CaseAuthenticatedTag (CAT) support" do
    it "creates fabric with CATs" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      cats = [
        Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32),
        Matter::DataType::CaseAuthenticatedTag.new(0x56780002_u32),
      ]

      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        cats: cats
      )

      fabric.cats.size.should eq(2)
      fabric.has_cats?.should be_true
      fabric.cats[0].value.should eq(0x12340001_u32)
      fabric.cats[1].value.should eq(0x56780002_u32)
    end

    it "defaults to empty CATs" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      fabric.cats.should be_empty
      fabric.has_cats?.should be_false
    end

    it "validates max 3 CATs" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      cats = [
        Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32),
        Matter::DataType::CaseAuthenticatedTag.new(0x56780002_u32),
        Matter::DataType::CaseAuthenticatedTag.new(0x9ABC0003_u32),
        Matter::DataType::CaseAuthenticatedTag.new(0xDEF00004_u32), # 4th CAT - invalid
      ]

      expect_raises(ArgumentError, /cats must have <= 3 entries/) do
        Matter::Fabric.new(
          fabric_id: 0x1_u64,
          fabric_index: 1_u8,
          node_id: 0x1_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: ipk,
          cats: cats
        )
      end
    end

    it "returns CAT-encoded NodeIds" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      cats = [
        Matter::DataType::CaseAuthenticatedTag.new(0x12340001_u32),
        Matter::DataType::CaseAuthenticatedTag.new(0x56780002_u32),
      ]

      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        cats: cats
      )

      cat_node_ids = fabric.cat_node_ids
      cat_node_ids.size.should eq(2)

      # CAT NodeId format: 0xFFFFFFFD + 32-bit CAT value
      cat_node_ids[0].should eq(0xFFFFFFFD12340001_u64)
      cat_node_ids[1].should eq(0xFFFFFFFD56780002_u64)
    end

    it "serializes and deserializes CATs" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      cats = [
        Matter::DataType::CaseAuthenticatedTag.new(0xABCD1234_u32),
        Matter::DataType::CaseAuthenticatedTag.new(0xEF567890_u32),
      ]

      original = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        cats: cats
      )

      hash = original.to_h
      hash["cats"].as(String).should eq("abcd1234,ef567890")

      restored = Matter::Fabric.from_h(hash)
      restored.cats.size.should eq(2)
      restored.cats[0].value.should eq(0xABCD1234_u32)
      restored.cats[1].value.should eq(0xEF567890_u32)
    end

    it "handles empty CATs in serialization" do
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      original = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
        # No cats specified - defaults to empty
      )

      hash = original.to_h
      hash["cats"].as(String).should eq("")

      restored = Matter::Fabric.from_h(hash)
      restored.cats.should be_empty
    end
  end
end

describe Matter::FabricTable do
  describe "initialization" do
    it "creates empty fabric table" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage)
      table.size.should eq(0)
      table.empty?.should be_true
      table.full?.should be_false
    end

    it "validates max_fabrics minimum" do
      storage = Matter::Storage::MemoryBackend.new
      expect_raises(ArgumentError, /must be >= 5/) do
        Matter::FabricTable.new(storage, max_fabrics: 4_u8)
      end
    end

    it "validates max_fabrics maximum" do
      storage = Matter::Storage::MemoryBackend.new
      expect_raises(ArgumentError, /must be <= 254/) do
        Matter::FabricTable.new(storage, max_fabrics: 255_u8)
      end
    end
  end

  describe "adding fabrics" do
    it "adds a fabric" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      result = table.add_fabric(fabric)
      result.should be_true
      table.size.should eq(1)
      table.empty?.should be_false
    end

    it "adds fabric with auto index" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = table.add_fabric_auto_index(
        fabric_id: 0x1_u64,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        label: "Auto"
      )

      fabric.should_not be_nil
      fabric.as(Matter::Fabric).fabric_index.should eq(1_u8)
      table.size.should eq(1)
    end

    it "prevents duplicate fabric indices" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric1 = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      fabric2 = Matter::Fabric.new(
        fabric_id: 0x2_u64,
        fabric_index: 1_u8, # Same index
        node_id: 0x2_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric1).should be_true
      table.add_fabric(fabric2).should be_false
      table.size.should eq(1)
    end

    it "allows duplicate fabric IDs across different roots" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      root_key_1 = Random::Secure.random_bytes(65)
      root_key_2 = Random::Secure.random_bytes(65)

      fabric1 = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: root_key_1,
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      fabric2 = Matter::Fabric.new(
        fabric_id: 0x1_u64, # Same fabric ID
        fabric_index: 2_u8,
        node_id: 0x2_u64,
        root_public_key: root_key_2,
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric1).should be_true
      table.add_fabric(fabric2).should be_true
      table.size.should eq(2)
    end

    it "prevents duplicate fabric identities (same root_public_key + fabric_id)" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      root_key = Random::Secure.random_bytes(65)

      fabric1 = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: root_key,
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      fabric2 = Matter::Fabric.new(
        fabric_id: 0x1_u64, # Same fabric ID
        fabric_index: 2_u8,
        node_id: 0x2_u64,
        root_public_key: root_key, # Same root key
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric1).should be_true
      table.add_fabric(fabric2).should be_false
      table.size.should eq(1)
    end

    it "respects max_fabrics limit" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 5_u8) # Matter spec minimum
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      # Add 5 fabrics (at limit)
      (1..5).each do |i|
        fabric = Matter::Fabric.new(
          fabric_id: i.to_u64,
          fabric_index: i.to_u8,
          node_id: i.to_u64,
          root_public_key: Random::Secure.random_bytes(65),
          operational_cert: Random::Secure.random_bytes(200),
          operational_key: key,
          ipk: ipk
        )
        table.add_fabric(fabric).should be_true
      end

      table.full?.should be_true
      table.size.should eq(5)

      # Try to add 6th fabric (should fail)
      fabric6 = Matter::Fabric.new(
        fabric_id: 6_u64,
        fabric_index: 6_u8,
        node_id: 6_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric6).should be_false # At capacity
      table.size.should eq(5)
    end
  end

  describe "removing fabrics" do
    it "removes fabric by index" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric)
      table.size.should eq(1)

      result = table.remove_fabric(1_u8)
      result.should be_true
      table.size.should eq(0)
    end

    it "removes fabric by fabric ID" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0xAABBCCDD_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric)
      result = table.remove_fabric_by_id(0xAABBCCDD_u64)
      result.should be_true
      table.size.should eq(0)
    end

    it "returns false when removing non-existent fabric" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      result = table.remove_fabric(99_u8)
      result.should be_false
    end
  end

  describe "lookups" do
    it "gets fabric by index" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0x1_u64,
        fabric_index: 5_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric)
      found = table.get_fabric(5_u8)
      found.should_not be_nil
      found.as(Matter::Fabric).fabric_id.should eq(0x1_u64)
    end

    it "finds fabric by fabric ID" do
      storage = Matter::Storage::MemoryBackend.new
      table = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0xDEADBEEF_u64,
        fabric_index: 1_u8,
        node_id: 0x1_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk
      )

      table.add_fabric(fabric)
      found = table.find_by_fabric_id(0xDEADBEEF_u64)
      found.should_not be_nil
      found.as(Matter::Fabric).fabric_index.should eq(1_u8)
    end
  end

  describe "persistence" do
    it "persists and loads fabrics" do
      storage = Matter::Storage::MemoryBackend.new
      table1 = Matter::FabricTable.new(storage, max_fabrics: 10_u8)

      key = Matter::Crypto::Key.generate_key_pair
      ipk = Random::Secure.random_bytes(16)

      fabric = Matter::Fabric.new(
        fabric_id: 0x123_u64,
        fabric_index: 1_u8,
        node_id: 0x456_u64,
        root_public_key: Random::Secure.random_bytes(65),
        operational_cert: Random::Secure.random_bytes(200),
        operational_key: key,
        ipk: ipk,
        label: "Persisted"
      )

      table1.add_fabric(fabric)
      table1.size.should eq(1)

      # Verify data was persisted
      stored_data = storage.get(["fabrics"], "fabric_table")
      stored_data.should_not be_nil
      puts "Stored data type: #{stored_data.class}"
      puts "Stored data: #{stored_data.inspect}" if stored_data.is_a?(String)

      # Create new table with same storage
      table2 = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      puts "Table2 size: #{table2.size}"
      table2.size.should eq(1)

      found = table2.get_fabric(1_u8)
      found.should_not be_nil
      found.as(Matter::Fabric).label.should eq("Persisted")
    end
  end
end
