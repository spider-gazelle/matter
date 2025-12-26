require "../spec_helper"

describe Matter::Controller::Clusters::AccessControl do
  it "parses ACL JSON and encodes TLV accepted by AccessControlCluster" do
    # Use a subject > Int64::MAX to ensure the parser doesn't rely on `JSON.parse` (which uses Int64).
    json = %([{"fabricIndex":2,"privilege":1,"authMode":2,"subjects":[16234001066904631842],"targets":[{"endpoint":1,"cluster":6,"deviceType":null}]}])

    entries = Matter::Controller::Clusters::AccessControl.parse_acl_json(json)
    entries.size.should eq 1
    entries[0].fabric_index.should be_nil

    tlv = Matter::Controller::Clusters::AccessControl.encode_acl_tlv(entries)

    cluster = Matter::Cluster::AccessControlCluster.new(Matter::DataType::EndpointNumber.new(0_u16))
    status = cluster.write_attribute(Matter::Cluster::AccessControlCluster::ATTR_ACL, tlv)
    status.status.should eq Matter::InteractionModel::StatusCode::Success

    cluster.acl.size.should eq 1
    entry = cluster.acl[0]
    entry.privilege.should eq Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege::View
    entry.auth_mode.should eq Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode::CASE
    entry.subjects.should eq [16234001066904631842_u64]
    entry.targets.as(Array(Matter::Cluster::AccessControlCluster::Target)).size.should eq 1
    entry.targets.as(Array(Matter::Cluster::AccessControlCluster::Target))[0].endpoint.should eq 1_u16
    entry.targets.as(Array(Matter::Cluster::AccessControlCluster::Target))[0].cluster.should eq 6_u32
    entry.targets.as(Array(Matter::Cluster::AccessControlCluster::Target))[0].device_type.should be_nil
  end
end
