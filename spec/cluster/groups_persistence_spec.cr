require "../spec_helper"

require "../../src/matter/cluster/groups_cluster"

describe Matter::Cluster::GroupsCluster do
  it "persists group table" do
    endpoint = Matter::DataType::EndpointNumber.new(1_u16)
    cluster = Matter::Cluster::GroupsCluster.new(endpoint)

    # Add group 0x0001 named "Test"
    payload = Bytes.new(2 + 4)
    IO::ByteFormat::LittleEndian.encode(1_u16, payload[0, 2])
    payload[2, 4].copy_from("Test".to_slice)
    cluster.invoke_command(Matter::Cluster::GroupsCluster::CMD_ADD_GROUP, payload)

    cluster.group_count.should eq(1)
    cluster.member_of?(1_u16).should be_true

    cluster.data_version = 7_u32
    json = cluster.save_state
    json.should_not be_nil

    cluster2 = Matter::Cluster::GroupsCluster.new(endpoint)
    cluster2.restore_state(json.as(String))

    cluster2.group_count.should eq(1)
    cluster2.groups[1_u16].should eq("Test")
    cluster2.data_version.should eq(7_u32)
  end
end
