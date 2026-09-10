require "../spec_helper"

private struct FanStepWireRequest
  include TLV::Serializable

  @[TLV::Field(tag: 0)]
  property direction : UInt8

  @[TLV::Field(tag: 1, optional: true)]
  property wrap : Bool?

  @[TLV::Field(tag: 2, optional: true)]
  property lowest_off : Bool?

  def initialize(@direction, @wrap = nil, @lowest_off = nil)
  end
end

private struct ThermostatSetpointWireRequest
  include TLV::Serializable

  @[TLV::Field(tag: 0)]
  property mode : UInt8

  @[TLV::Field(tag: 1)]
  property amount : Int8

  def initialize(@mode, @amount)
  end
end

private def dispatch_cluster_command(cluster : Matter::Cluster::Base, command : UInt32, request)
  path = Matter::InteractionModel::CommandPath.new(cluster.endpoint_id.number, cluster.cluster_id.id, command)
  data = Matter::InteractionModel::CommandDataIBTlv.new(path, request.to_tlv(nil))
  clusters = { {cluster.endpoint_id.number, cluster.cluster_id.id} => cluster }
  responses = Matter::Protocol::IMHandler.invoke_commands([data], clusters)
  responses.first.command_status.as(Matter::InteractionModel::CommandStatusIB).status.status
end

describe "typed cluster command dispatch" do
  it "dispatches a FanControl Step request with optional booleans" do
    fan = Matter::Cluster::FanControlCluster.new(endpoint(1), feature_map: Matter::Cluster::FanControlCluster::Feature::Step,
      percent_setting: 100_u8, percent_current: 100_u8)
    request = FanStepWireRequest.new(direction: Matter::Cluster::FanControlCluster::StepDirection::Increase.value.to_u8, wrap: true, lowest_off: false)

    dispatch_cluster_command(fan, Matter::Cluster::FanControlCluster::CMD_STEP, request).should eq(Matter::InteractionModel::StatusCode::Success.value)
    fan.percent_setting.should eq(1_u8)
  end

  it "dispatches a signed Thermostat SetpointRaiseLower amount" do
    thermostat = Matter::Cluster::ThermostatCluster.new(endpoint(1))
    previous = thermostat.occupied_heating_setpoint
    request = ThermostatSetpointWireRequest.new(mode: Matter::Cluster::Definitions::Thermostat::SetpointAdjustMode::Heat.value, amount: -10_i8)

    dispatch_cluster_command(thermostat, Matter::Cluster::ThermostatCluster::CMD_SETPOINT_RAISE_LOWER, request).should eq(Matter::InteractionModel::StatusCode::Success.value)
    thermostat.occupied_heating_setpoint.should eq(previous - 100)
  end
end
