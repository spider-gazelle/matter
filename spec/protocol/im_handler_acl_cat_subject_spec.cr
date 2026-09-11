require "../spec_helper"

require "../../src/matter/cluster/access_control"
require "../../src/matter/cluster/descriptor"
require "../../src/matter/datatype/case_authenticated_tag"
require "../../src/matter/datatype/node_id"
require "../../src/matter/protocol/im_handler"

describe "IMHandler ACL CAT subjects" do
  it "authorizes reads when peer presents matching CAT subject" do
    endpoint_0 = Matter::DataType::EndpointNumber.new(0_u16)

    acl_cluster = Matter::Cluster::AccessControl.new(endpoint_0)
    descriptor = Matter::Cluster::Descriptor.new(endpoint_0)

    clusters = {} of Tuple(UInt16, UInt32) => Matter::Cluster::Base
    clusters[{0_u16, Matter::Cluster::AccessControl::CLUSTER_ID}] = acl_cluster
    clusters[{0_u16, Matter::Cluster::Descriptor::CLUSTER_ID}] = descriptor

    # iOS commonly installs ACL entries with CAT subjects (NodeId-encoded).
    cat = Matter::DataType::CaseAuthenticatedTag.new(0x321d0001_u32)
    cat_node_id = Matter::DataType::NodeId.from_case_authenticated_tag(cat).id

    acl_cluster.acl << Matter::Cluster::AccessControl::AccessControlEntry.new(
      privilege: Matter::Cluster::AccessControl::AccessControlEntryPrivilege::View,
      auth_mode: Matter::Cluster::AccessControl::AccessControlEntryAuthMode::CASE,
      subjects: [cat_node_id],
      targets: nil,
      fabric_index: 1_u8
    )

    path = Matter::InteractionModel::AttributePath.new(
      endpoint: 0_u16,
      cluster: Matter::Cluster::Descriptor::CLUSTER_ID,
      attribute: Matter::Cluster::Descriptor::ATTR_DEVICE_TYPE_LIST
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
