require "./spec_helper"

require "../src/matter/cluster/access_control_cluster"
require "../src/matter/cluster/descriptor_cluster"
require "../src/matter/datatype/case_authenticated_tag"
require "../src/matter/datatype/node_id"
require "../src/matter/protocol/im_handler"

describe "IMHandler ACL CAT subjects" do
  it "authorizes reads when peer presents matching CAT subject" do
    endpoint_0 = Matter::DataType::EndpointNumber.new(0_u16)

    acl_cluster = Matter::Cluster::AccessControlCluster.new(endpoint_0)
    descriptor = Matter::Cluster::DescriptorCluster.new(endpoint_0)

    clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base
    clusters[{0_u16, Matter::Cluster::AccessControlCluster::CLUSTER_ID}] = acl_cluster
    clusters[{0_u16, Matter::Cluster::DescriptorCluster::CLUSTER_ID}] = descriptor

    # iOS commonly installs ACL entries with CAT subjects (NodeId-encoded).
    cat = Matter::DataType::CaseAuthenticatedTag.new(0x321d0001_u32)
    cat_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(cat).id

    acl_cluster.acl << Matter::Cluster::AccessControlCluster::AccessControlEntry.new(
      privilege: Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View,
      auth_mode: Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE,
      subjects: [cat_node_id],
      targets: nil,
      fabric_index: 1_u8
    )

    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: Matter::Cluster::DescriptorCluster::CLUSTER_ID,
      attribute: Matter::Cluster::DescriptorCluster::ATTR_DEVICE_TYPE_LIST
    )

    denied = Matter::Protocol::IMHandler.read_attributes(
      [path],
      clusters,
      fabric_index: 1_u8,
      is_case_session: true,
      peer_subject_ids: [0x1111_u64] # NodeId only, no CAT
    )
    # With new return type, check that we got a status report (error), not data
    denied.size.should eq(1)
    denied.first.attribute_data.should be_nil
    if attr_status = denied.first.attribute_status
      attr_status.status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAccess.value)
    else
      fail "Expected attribute_status to not be nil"
    end

    allowed = Matter::Protocol::IMHandler.read_attributes(
      [path],
      clusters,
      fabric_index: 1_u8,
      is_case_session: true,
      peer_subject_ids: [0x1111_u64, cat_node_id]
    )
    # With new return type, check that we got data, not status
    allowed.size.should eq(1)
    allowed.first.attribute_data.should_not be_nil
    allowed.first.attribute_status.should be_nil
  end
end
