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
