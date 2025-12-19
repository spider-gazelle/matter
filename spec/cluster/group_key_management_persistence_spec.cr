require "../spec_helper"

require "../../src/matter/cluster/group_key_management_cluster"

describe Matter::Cluster::GroupKeyManagementCluster do
  it "persists key sets and group tables" do
    endpoint = Matter::DataType::EndpointNumber.new(0_u16)
    cluster = Matter::Cluster::GroupKeyManagementCluster.new(endpoint)

    fabric = 1_u8
    key_set_id = 1_u16
    epoch_key0 = Bytes.new(16, 0xAA_u8)
    epoch_start0 = 1_000_000_u64

    key_set = Matter::Cluster::GroupKeyManagementCluster::GroupKeySetStruct.new(
      group_key_set_id: key_set_id,
      epoch_key0: epoch_key0,
      epoch_start_time0: epoch_start0
    )
    cluster.handle_key_set_write(
      Matter::Cluster::GroupKeyManagementCluster::KeySetWriteRequest.new(key_set),
      fabric
    )

    cluster.add_group_key_map(0x1234_u16, key_set_id, fabric)
    cluster.add_group(0x1234_u16, 1_u16, "G", fabric)

    cluster.data_version = 9_u32
    json = cluster.save_state
    json.should_not be_nil

    cluster2 = Matter::Cluster::GroupKeyManagementCluster.new(endpoint)
    cluster2.restore_state(json.not_nil!)

    restored = cluster2.get_key_set(key_set_id, fabric)
    restored.should_not be_nil
    restored.not_nil!.epoch_key0.should eq(epoch_key0)
    restored.not_nil!.epoch_start_time0.should eq(epoch_start0)

    cluster2.group_key_map(fabric).size.should eq(1)
    cluster2.group_table(fabric).size.should eq(1)
    cluster2.data_version.should eq(9_u32)
  end
end
