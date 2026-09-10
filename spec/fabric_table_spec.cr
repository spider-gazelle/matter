require "./spec_helper"

private def build_fabric(fabric_index : UInt8) : Matter::Fabric
  Matter::Fabric.new(
    fabric_id: fabric_index.to_u64,
    fabric_index: fabric_index,
    node_id: 0x1_u64,
    root_public_key: Random::Secure.random_bytes(65),
    operational_cert: Random::Secure.random_bytes(200),
    operational_key: Matter::Crypto::Key.generate_key_pair,
    ipk: Random::Secure.random_bytes(16),
    label: "Fabric #{fabric_index}"
  )
end

private def stored_fabric_table(entries : Hash(String, Hash(String, JSON::Any::Type))) : Matter::Storage::MemoryBackend
  storage = Matter::Storage::MemoryBackend.new
  storage.set(Matter::FabricTable::STORAGE_CONTEXT, "fabric_table", entries.to_json)
  storage
end

private def entry(fabric : Matter::Fabric, overrides : Hash(String, JSON::Any::Type)) : Hash(String, JSON::Any::Type)
  hash = {} of String => JSON::Any::Type
  fabric.to_h.each { |key, value| hash[key] = value.is_a?(String) ? value : value.to_i64 }
  overrides.each { |key, value| hash[key] = value }
  hash
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

      # Create new table with same storage
      table2 = Matter::FabricTable.new(storage, max_fabrics: 10_u8)
      table2.size.should eq(1)

      found = table2.get_fabric(1_u8)
      found.should_not be_nil
      found.as(Matter::Fabric).label.should eq("Persisted")
    end
  end

  describe "#load_from_storage" do
    it "loads the remaining fabrics when an entry has a nil field" do
      good = build_fabric(1_u8)
      bad = build_fabric(2_u8)

      storage = stored_fabric_table({
        "1" => entry(good, {} of String => JSON::Any::Type),
        "2" => entry(bad, {"fabric_id" => nil.as(JSON::Any::Type)}),
      })

      table = Matter::FabricTable.new(storage)
      table.size.should eq(1)
      table.get_fabric(1_u8).try(&.label).should eq("Fabric 1")
      table.get_fabric(2_u8).should be_nil
    end

    it "loads the remaining fabrics when an entry has an array field" do
      good = build_fabric(1_u8)
      bad = build_fabric(2_u8)

      storage = stored_fabric_table({
        "1" => entry(good, {} of String => JSON::Any::Type),
        "2" => entry(bad, {"label" => [JSON::Any.new("x")].as(JSON::Any::Type)}),
      })

      table = Matter::FabricTable.new(storage)
      table.size.should eq(1)
      table.get_fabric(1_u8).should_not be_nil
    end

    it "coerces float fields to integers" do
      created_at = 1_700_000_000_i64
      fabric = build_fabric(1_u8)

      storage = stored_fabric_table({
        "1" => entry(fabric, {"created_at" => created_at.to_f64.as(JSON::Any::Type)}),
      })

      table = Matter::FabricTable.new(storage)
      table.size.should eq(1)
      table.get_fabric(1_u8).try(&.created_at).should eq(created_at)
    end
  end
end
