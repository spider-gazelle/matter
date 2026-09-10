require "../spec_helper"

require "../../src/matter/cluster/basic_information_cluster"

describe Matter::Cluster::BasicInformationCluster do
  it "persists writable attributes (node_label/location/local_config_disabled)" do
    ep0 = Matter::DataType::EndpointNumber.new(0_u16)
    cluster = Matter::Cluster::BasicInformationCluster.new(
      endpoint_id: ep0,
      vendor_name: "Vendor",
      vendor_id: 0xFFF1_u16,
      product_name: "Prod",
      product_id: 0x8004_u16,
      node_label: "Initial",
      location: "XX"
    )

    cluster.node_label = "Kitchen"
    cluster.location = "AU"
    cluster.local_config_disabled = true
    cluster.data_version = 42_u32

    document = cluster.save_state.as(Matter::Storage::Document)
    document.should eq(Matter::Storage::Document{
      "node_label"            => "Kitchen",
      "location"              => "AU",
      "local_config_disabled" => true,
      "data_version"          => 42_i64,
    })

    cluster2 = Matter::Cluster::BasicInformationCluster.new(
      endpoint_id: ep0,
      vendor_name: "Vendor",
      vendor_id: 0xFFF1_u16,
      product_name: "Prod",
      product_id: 0x8004_u16,
      node_label: "Other",
      location: "XX"
    )
    cluster2.restore_state(document)

    cluster2.node_label.should eq("Kitchen")
    cluster2.location.should eq("AU")
    cluster2.local_config_disabled?.should be_true
    cluster2.data_version.should eq(42_u32)
  end
end
