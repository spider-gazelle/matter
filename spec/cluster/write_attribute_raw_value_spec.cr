require "../spec_helper"
require "../../src/matter/protocol/im_handler"
require "../../src/matter/cluster/identify_cluster"
require "../../src/matter/cluster/door_lock_cluster"
require "../../src/matter/cluster/bridged_device_basic_information_cluster"
require "../../src/matter/cluster/basic_information_cluster"
require "../../src/matter/cluster/on_off_cluster"
require "../../src/matter/cluster/level_control_cluster"
require "../../src/matter/cluster/thermostat_cluster"
require "../../src/matter/cluster/occupancy_sensing_cluster"
require "../../src/matter/interaction_model/tlv_messages"

# Regression tests for attribute writes arriving from the official chip-tool.
#
# The IM layer hands clusters the RAW value bytes of the TLV element (see
# IMHandler.tlv_value_bytes): integers arrive little-endian in whatever width the
# TLV encoder chose (60 is a single byte even for a uint16/uint32 attribute),
# strings arrive as UTF-8 bytes and booleans as a single byte. Clusters must not
# attempt to re-parse these bytes as TLV, nor assume a fixed integer width.
private def write_via_im(cluster : Matter::Cluster::Base, attribute_id : UInt32, data : TLV::Any) : Matter::InteractionModel::AttributeStatusIB
  endpoint = cluster.endpoint_id.number
  cluster_id = cluster.cluster_id.id
  clusters = {
    {endpoint, cluster_id} => cluster,
  }

  # Serialize and re-parse so the request takes exactly the same path as a
  # message arriving from the network.
  original_msg = Matter::InteractionModel::WriteRequestMessage.new(
    suppress_response: false,
    timed_request: false,
    write_requests: [
      Matter::InteractionModel::AttributeDataIB.new(
        path: Matter::InteractionModel::AttributePath.new(
          endpoint: endpoint,
          cluster: cluster_id,
          attribute: attribute_id,
        ),
        data: data,
      ),
    ],
  )
  parsed = Matter::Protocol::IMHandler.parse_write_request(original_msg.to_slice)
  parsed.should_not be_nil
  parsed = parsed.as(Matter::InteractionModel::WriteRequestMessage)

  results = Matter::Protocol::IMHandler.write_attributes(parsed.write_requests, clusters)
  results.size.should eq 1
  results[0]
end

describe "write_attribute with raw IM value bytes (chip-tool)" do
  endpoint = Matter::DataType::EndpointNumber.new(1_u16)
  success = Matter::InteractionModel::StatusCode::Success.value

  it "writes Identify IdentifyTime (uint16) sent as a single TLV byte" do
    identify = Matter::Cluster::IdentifyCluster.new(endpoint)

    # chip-tool identify write identify-time 60 1 1
    result = write_via_im(identify, Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME, TLV::Any.new(60_u16))
    result.status.status.should eq success
    identify.identify_time.should eq 60_u16
  end

  it "writes Identify IdentifyTime (uint16) sent as two TLV bytes" do
    identify = Matter::Cluster::IdentifyCluster.new(endpoint)

    result = write_via_im(identify, Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME, TLV::Any.new(1000_u16))
    result.status.status.should eq success
    identify.identify_time.should eq 1000_u16
  end

  it "writes DoorLock AutoRelockTime (uint32) sent as a single TLV byte" do
    lock = Matter::Cluster::DoorLockCluster.new(endpoint)

    # chip-tool doorlock write auto-relock-time 30 1 1 --timedInteractionTimeoutMs 2000
    result = write_via_im(lock, Matter::Cluster::DoorLockCluster::ATTR_AUTO_RELOCK_TIME, TLV::Any.new(30_u32))
    result.status.status.should eq success
    lock.auto_relock_time.should eq 30_u32
  end

  it "writes DoorLock Language (string), SoundVolume (enum) and EnableOneTouchLocking (bool)" do
    lock = Matter::Cluster::DoorLockCluster.new(endpoint)

    result = write_via_im(lock, Matter::Cluster::DoorLockCluster::ATTR_LANGUAGE, TLV::Any.new("fr"))
    result.status.status.should eq success
    lock.language.should eq "fr"

    result = write_via_im(lock, Matter::Cluster::DoorLockCluster::ATTR_SOUND_VOLUME, TLV::Any.new(3_u8))
    result.status.status.should eq success
    lock.sound_volume.should eq Matter::Cluster::DoorLockCluster::SoundVolume::High

    result = write_via_im(lock, Matter::Cluster::DoorLockCluster::ATTR_ENABLE_ONE_TOUCH_LOCKING, TLV::Any.new(true))
    result.status.status.should eq success
    lock.enable_one_touch_locking?.should be_true
  end

  it "writes BridgedDeviceBasicInformation NodeLabel (string)" do
    bridged = Matter::Cluster::BridgedDeviceBasicInformationCluster.new(endpoint, node_label: "Original")

    # chip-tool bridgeddevicebasicinformation write node-label "Porch Light" 1 1
    result = write_via_im(bridged, Matter::Cluster::BridgedDeviceBasicInformationCluster::ATTR_NODE_LABEL, TLV::Any.new("Porch Light"))
    result.status.status.should eq success
    bridged.node_label.should eq "Porch Light"
  end

  it "writes BasicInformation NodeLabel, Location (string) and LocalConfigDisabled (bool)" do
    basic = Matter::Cluster::BasicInformationCluster.new(endpoint_id: Matter::DataType::EndpointNumber.new(0_u16))

    result = write_via_im(basic, Matter::Cluster::BasicInformationCluster::ATTR_NODE_LABEL, TLV::Any.new("Kitchen"))
    result.status.status.should eq success
    basic.node_label.should eq "Kitchen"

    result = write_via_im(basic, Matter::Cluster::BasicInformationCluster::ATTR_LOCATION, TLV::Any.new("au"))
    result.status.status.should eq success
    basic.location.should eq "AU"

    result = write_via_im(basic, Matter::Cluster::BasicInformationCluster::ATTR_LOCAL_CONFIG_DISABLED, TLV::Any.new(true))
    result.status.status.should eq success
    basic.local_config_disabled?.should be_true
  end

  it "writes OnOff OnTime (uint16) sent as a single TLV byte" do
    on_off = Matter::Cluster::OnOffCluster.new(endpoint, feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting)

    # chip-tool onoff write on-time 5 1 1
    result = write_via_im(on_off, Matter::Cluster::OnOffCluster::ATTR_ON_TIME, TLV::Any.new(5_u16))
    result.status.status.should eq success
    on_off.on_time.should eq 5_u16

    result = write_via_im(on_off, Matter::Cluster::OnOffCluster::ATTR_OFF_WAIT_TIME, TLV::Any.new(7_u16))
    result.status.status.should eq success
    on_off.off_wait_time.should eq 7_u16
  end

  it "writes OnOff StartUpOnOff null sent as TLV null" do
    on_off = Matter::Cluster::OnOffCluster.new(endpoint, feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting)

    result = write_via_im(on_off, Matter::Cluster::OnOffCluster::ATTR_START_UP_ON_OFF, TLV::Any.new(1_u8))
    result.status.status.should eq success
    on_off.start_up_on_off.should eq Matter::Cluster::OnOffCluster::StartUpOnOff::On

    result = write_via_im(on_off, Matter::Cluster::OnOffCluster::ATTR_START_UP_ON_OFF, TLV::Any.new(nil))
    result.status.status.should eq success
    on_off.start_up_on_off.should be_nil
  end

  it "writes LevelControl OnOffTransitionTime (uint16) sent as a single TLV byte" do
    level = Matter::Cluster::LevelControlCluster.new(endpoint, feature_map: Matter::Cluster::LevelControlCluster::Feature::Lighting | Matter::Cluster::LevelControlCluster::Feature::OnOff)

    result = write_via_im(level, Matter::Cluster::LevelControlCluster::ATTR_ON_OFF_TRANSITION_TIME, TLV::Any.new(5_u16))
    result.status.status.should eq success
    level.on_off_transition_time.should eq 5_u16
  end

  it "writes Thermostat OccupiedHeatingSetpoint (int16) sent as a single TLV byte" do
    # Lower the heating limits so a setpoint small enough to fit in an int8
    # on the wire (1.00 degrees C) is within range.
    thermostat = Matter::Cluster::ThermostatCluster.new(
      endpoint,
      feature_map: Matter::Cluster::ThermostatCluster::Feature::Heating,
      abs_min_heat_setpoint_limit: 0_i16,
      min_heat_setpoint_limit: 0_i16,
    )

    result = write_via_im(thermostat, Matter::Cluster::ThermostatCluster::ATTR_OCCUPIED_HEATING_SETPOINT, TLV::Any.new(100_i16))
    result.status.status.should eq success
    thermostat.occupied_heating_setpoint.should eq 100_i16
  end

  it "writes OccupancySensing PIROccupiedToUnoccupiedDelay (uint16) sent as a single TLV byte" do
    occupancy = Matter::Cluster::OccupancySensingCluster.new(endpoint, feature_map: Matter::Cluster::OccupancySensingCluster::Feature::PassiveInfrared)

    # chip-tool occupancysensing write piroccupied-to-unoccupied-delay 10 1 1
    result = write_via_im(occupancy, Matter::Cluster::OccupancySensingCluster::ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY, TLV::Any.new(10_u16))
    result.status.status.should eq success
    occupancy.pir_occupied_to_unoccupied_delay.should eq 10_u16

    result = write_via_im(occupancy, Matter::Cluster::OccupancySensingCluster::ATTR_HOLD_TIME, TLV::Any.new(300_u16))
    result.status.status.should eq success
    occupancy.hold_time.should eq 300_u16
  end

  it "rejects a non-integer value with InvalidDataType" do
    identify = Matter::Cluster::IdentifyCluster.new(endpoint)

    result = write_via_im(identify, Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME, TLV::Any.new("sixty"))
    result.status.status.should eq Matter::InteractionModel::StatusCode::InvalidDataType.value
    identify.identify_time.should eq 0_u16
  end
end
