require "../spec_helper"
require "../../src/matter/cluster/groups"
require "../../src/matter/cluster/color_control"
require "../../src/matter/cluster/window_covering"

describe "cluster command wire format" do
  it "decodes a tagged AddGroup request" do
    cluster = Matter::Cluster::Groups.new(endpoint(1))
    fields = TLV::Any.new({0_u8 => TLV::Any.new(1234_u16, 0_u8), 1_u8 => TLV::Any.new("Office", 1_u8)} of TLV::TagId => TLV::Any)
    invoke(cluster, Matter::Cluster::Groups::CMD_ADD_GROUP, fields.to_slice)
    cluster.groups[1234_u16]?.should eq("Office")
  end

  it "decodes tagged MoveToHue fields instead of the TLV header" do
    cluster = Matter::Cluster::ColorControl.new(endpoint(1))
    fields = Matter::Cluster::ColorControl::MoveToHueRequest.new(hue: 127_u8, direction: Matter::Cluster::ColorControl::Direction::ShortestDistance, transition_time: 0_u16, mask: 0_u8, override: 0_u8)
    expect_success(invoke(cluster, Matter::Cluster::ColorControl::CMD_MOVE_TO_HUE, fields))
    cluster.current_hue.should eq(127_u8)
  end

  it "decodes a tagged GoToLiftPercentage request" do
    cluster = Matter::Cluster::WindowCovering.new(endpoint(1))
    fields = TLV::Any.new({0_u8 => TLV::Any.new(4321_u16, 0_u8)} of TLV::TagId => TLV::Any)
    expect_success(invoke(cluster, Matter::Cluster::WindowCovering::CMD_GO_TO_LIFT_PERCENTAGE, fields.to_slice))
    cluster.target_position_lift_percent100ths.should eq(4321_u16)
  end
end
