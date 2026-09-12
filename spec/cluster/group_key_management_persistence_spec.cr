require "../spec_helper"

require "../../src/matter/cluster/group_key_management"

describe Matter::Cluster::GroupKeyManagement do
  it "persists key sets and group tables" do
    cluster = build(Matter::Cluster::GroupKeyManagement, 0)

    fabric = 1_u8
    key_set_id = 1_u16
    epoch_key0 = Bytes.new(16, 0xAA_u8)
    epoch_start0 = 1_000_000_u64

    key_set = Matter::Cluster::GroupKeyManagement::GroupKeySetStruct.new(
      group_key_set_id: key_set_id,
      epoch_key0: epoch_key0,
      epoch_start_time0: epoch_start0
    )
    cluster.handle_key_set_write(
      Matter::Cluster::GroupKeyManagement::KeySetWriteRequest.new(key_set),
      fabric
    )

    cluster.add_group_key_map(0x1234_u16, key_set_id, fabric)
    cluster.add_group(0x1234_u16, 1_u16, "G", fabric)

    cluster.data_version = 9_u32
    document = cluster.save_state.as(Matter::Storage::Document)
    key_sets = document["key_sets"].as(Matter::Storage::Document)
    persisted = key_sets["1"].as(Array(Matter::Storage::Type)).first.as(Matter::Storage::Document)
    persisted["epoch_key0"].should eq(epoch_key0)
    persisted["epoch_start_time0"].should eq(epoch_start0.to_i64)
    persisted["group_key_security_policy"].should eq("TrustFirst")
    document["data_version"].should eq(9_i64)

    cluster2 = build(Matter::Cluster::GroupKeyManagement, 0)
    cluster2.restore_state(document)

    restored = cluster2.get_key_set(key_set_id, fabric)
    restored.should_not be_nil
    restored_key_set = restored.as(Matter::Cluster::GroupKeyManagement::GroupKeySetStruct)
    restored_key_set.epoch_key0.should eq(epoch_key0)
    restored_key_set.epoch_start_time0.should eq(epoch_start0)

    cluster2.group_key_map(fabric).size.should eq(1)
    cluster2.group_table(fabric).size.should eq(1)
    cluster2.data_version.should eq(9_u32)
  end

  it "bumps the data version on every mutation" do
    cluster = build(Matter::Cluster::GroupKeyManagement, 0)
    fabric = 1_u8
    key_set_id = 1_u16
    versions = [] of UInt32

    key_set = Matter::Cluster::GroupKeyManagement::GroupKeySetStruct.new(
      group_key_set_id: key_set_id,
      epoch_key0: Bytes.new(16, 0xAA_u8),
      epoch_start_time0: 1_000_000_u64
    )
    cluster.handle_key_set_write(Matter::Cluster::GroupKeyManagement::KeySetWriteRequest.new(key_set), fabric)
    versions << cluster.data_version
    cluster.add_group_key_map(0x1234_u16, key_set_id, fabric)
    versions << cluster.data_version
    cluster.add_group(0x1234_u16, 1_u16, "G", fabric)
    versions << cluster.data_version
    cluster.remove_group(0x1234_u16, 1_u16, fabric)
    versions << cluster.data_version
    cluster.remove_group_key_map(0x1234_u16, fabric)
    versions << cluster.data_version
    cluster.handle_key_set_remove(Matter::Cluster::GroupKeyManagement::KeySetRemoveRequest.new(key_set_id), fabric)
    versions << cluster.data_version
    cluster.remove_fabric(fabric)
    versions << cluster.data_version

    versions.should eq((1_u32..7_u32).to_a)
  end
end
