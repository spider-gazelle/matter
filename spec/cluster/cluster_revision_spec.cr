require "../spec_helper"
require "../../src/matter/cluster/boolean_state_cluster"
require "../../src/matter/cluster/color_control_cluster"
require "../../src/matter/cluster/descriptor_cluster"
require "../../src/matter/cluster/door_lock_cluster"
require "../../src/matter/cluster/group_key_management_cluster"
require "../../src/matter/cluster/groups_cluster"
require "../../src/matter/cluster/icd_management_cluster"
require "../../src/matter/cluster/identify_cluster"
require "../../src/matter/cluster/level_control_cluster"
require "../../src/matter/cluster/on_off_cluster"
require "../../src/matter/cluster/window_covering_cluster"

private alias Base = Matter::Cluster::Base

# The ClusterRevision global attribute is read straight from each cluster's
# `CLUSTER_REVISION` constant, resolved in the subclass scope by `Base`'s
# `macro inherited`. One example per cluster whose revision is not the default.
describe "Cluster::Base ClusterRevision" do
  it "reports the Base default for a cluster that does not set CLUSTER_REVISION" do
    cluster = Matter::Cluster::BooleanStateCluster.new(endpoint(1))

    Base::CLUSTER_REVISION.should eq(1_u16)
    cluster.cluster_revision.should eq(Base::CLUSTER_REVISION)
    read(cluster, Base::GLOBAL_CLUSTER_REVISION).should eq(Base::CLUSTER_REVISION)
  end

  {% for pair in [
                   {Matter::Cluster::ColorControlCluster, 7_u16},
                   {Matter::Cluster::DescriptorCluster, 2_u16},
                   {Matter::Cluster::DoorLockCluster, 9_u16},
                   {Matter::Cluster::GroupKeyManagementCluster, 2_u16},
                   {Matter::Cluster::GroupsCluster, 4_u16},
                   {Matter::Cluster::IcdManagementCluster, 3_u16},
                   {Matter::Cluster::IdentifyCluster, 6_u16},
                   {Matter::Cluster::LevelControlCluster, 6_u16},
                   {Matter::Cluster::OnOffCluster, 6_u16},
                   {Matter::Cluster::WindowCoveringCluster, 6_u16},
                 ] %}
    it "reports {{ pair[0] }}::CLUSTER_REVISION ({{ pair[1] }})" do
      cluster = {{ pair[0] }}.new(endpoint(1))

      {{ pair[0] }}::CLUSTER_REVISION.should eq({{ pair[1] }})
      cluster.cluster_revision.should eq({{ pair[0] }}::CLUSTER_REVISION)
      read(cluster, Base::GLOBAL_CLUSTER_REVISION).should eq({{ pair[0] }}::CLUSTER_REVISION)
    end
  {% end %}
end
