require "../spec_helper"
require "../../src/matter/cluster/identify_cluster"

# Helper to encode a uint16 as TLV for attribute writes
def encode_tlv_uint16(value : UInt16) : Bytes
  TLV::Any.new(value, nil).to_slice
end

# Helper to encode Identify command (tag 0 = IdentifyTime)
def encode_identify_command(time : UInt16) : Bytes
  Matter::Cluster::Definitions::Identify::Request.new(time).to_slice
end

# Helper to encode TriggerEffect command (tag 0 = EffectIdentifier, tag 1 = EffectVariant)
def encode_trigger_effect_command(effect : UInt8, variant : UInt8) : Bytes
  Matter::Cluster::Definitions::Identify::TriggerEffectRequest.new(
    effect_identifier: Matter::Cluster::Definitions::Identify::EffectIdentifier.new(effect),
    effect_variany: Matter::Cluster::Definitions::Identify::EffectVariant.new(variant)
  ).to_slice
end

describe Matter::Cluster::IdentifyCluster do
  describe "initialization" do
    it "creates identify cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0003_u32)
      cluster.name.should eq("Identify")
      cluster.identify_time.should eq(0_u16)
      cluster.identify_type.should eq(Matter::Cluster::IdentifyCluster::IdentifyType::None)
    end

    it "initializes with custom identify type" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint_id,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )

      cluster.identify_type.should eq(Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight)
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 2

      identify_time = attributes.find { |a| a.id.id == Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME }
      identify_time.should_not be_nil
      identify_time.not_nil!.name.should eq("IdentifyTime")
      identify_time.not_nil!.type.should eq(:uint16)
      identify_time.not_nil!.writable.should be_true

      identify_type = attributes.find { |a| a.id.id == Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TYPE }
      identify_type.should_not be_nil
      identify_type.not_nil!.name.should eq("IdentifyType")
      identify_type.not_nil!.writable.should be_false
    end

    it "reads IdentifyTime attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      result = cluster.read_attribute(Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(0_u16)
    end

    it "reads IdentifyType attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint_id,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::AudibleBeep
      )

      result = cluster.read_attribute(Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TYPE)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(Matter::Cluster::IdentifyCluster::IdentifyType::AudibleBeep.value)
    end

    it "writes IdentifyTime attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      # Encode 60 seconds as TLV uint16
      status = cluster.write_attribute(
        Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME,
        encode_tlv_uint16(60_u16)
      )

      status.success?.should be_true
      cluster.identify_time.should eq(60_u16)
    end

    it "rejects writing to IdentifyType" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      status = cluster.write_attribute(
        Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TYPE,
        encode_tlv_uint16(2_u16)
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      commands = cluster.commands
      commands.size.should eq(2)

      identify_cmd = commands.find { |c| c.id.id == Matter::Cluster::IdentifyCluster::CMD_IDENTIFY }
      identify_cmd.should_not be_nil
      identify_cmd.not_nil!.name.should eq("Identify")

      trigger_effect_cmd = commands.find { |c| c.id.id == Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT }
      trigger_effect_cmd.should_not be_nil
      trigger_effect_cmd.not_nil!.name.should eq("TriggerEffect")
    end

    it "executes Identify command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      cluster.identify_time.should eq(0_u16)

      # Encode identify time (60 seconds) as TLV struct
      result = cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_IDENTIFY,
        encode_identify_command(60_u16)
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.identify_time.should eq(60_u16)
    end

    it "executes TriggerEffect command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      # Encode effect (Blink) and effect variant as TLV struct
      result = cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT,
        encode_trigger_effect_command(
          Matter::Cluster::IdentifyCluster::EffectIdentifier::Blink.value,
          Matter::Cluster::IdentifyCluster::EffectVariant::Default.value
        )
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
    end

    it "stops identify when time is 0" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      # Start identifying
      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(10_u16))
      cluster.identify_time.should eq(10_u16)
      cluster.identifying?.should be_true

      # Stop identifying
      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(0_u16))
      cluster.identify_time.should eq(0_u16)
      cluster.identifying?.should be_false
    end
  end

  describe "IdentifyType enum" do
    it "has all identify types" do
      Matter::Cluster::IdentifyCluster::IdentifyType::None.value.should eq(0)
      Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight.value.should eq(1)
      Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED.value.should eq(2)
      Matter::Cluster::IdentifyCluster::IdentifyType::AudibleBeep.value.should eq(3)
      Matter::Cluster::IdentifyCluster::IdentifyType::Display.value.should eq(4)
      Matter::Cluster::IdentifyCluster::IdentifyType::Actuator.value.should eq(5)
    end
  end

  describe "EffectIdentifier enum" do
    it "has all effect identifiers" do
      Matter::Cluster::IdentifyCluster::EffectIdentifier::Blink.value.should eq(0)
      Matter::Cluster::IdentifyCluster::EffectIdentifier::Breathe.value.should eq(1)
      Matter::Cluster::IdentifyCluster::EffectIdentifier::Okay.value.should eq(2)
      Matter::Cluster::IdentifyCluster::EffectIdentifier::ChannelChange.value.should eq(11)
      Matter::Cluster::IdentifyCluster::EffectIdentifier::FinishEffect.value.should eq(254)
      Matter::Cluster::IdentifyCluster::EffectIdentifier::StopEffect.value.should eq(255)
    end
  end

  describe "EffectVariant enum" do
    it "has effect variants" do
      Matter::Cluster::IdentifyCluster::EffectVariant::Default.value.should eq(0)
    end
  end

  describe "identify state" do
    it "tracks identifying state" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      cluster.identifying?.should be_false

      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(30_u16))
      cluster.identifying?.should be_true

      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(0_u16))
      cluster.identifying?.should be_false
    end

    it "can check remaining identify time" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(120_u16))
      cluster.identify_time.should eq(120_u16)
    end
  end

  describe "callbacks" do
    it "calls identify callback when started" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      callback_called = false
      cluster.on_identify_started do
        callback_called = true
      end

      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(60_u16))
      callback_called.should be_true
    end

    it "calls identify callback when stopped" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      callback_called = false
      cluster.on_identify_stopped do
        callback_called = true
      end

      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(60_u16))
      callback_called.should be_false # Not stopped yet

      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(0_u16))
      callback_called.should be_true
    end

    it "calls effect callback on TriggerEffect" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      received_effect = Matter::Cluster::IdentifyCluster::EffectIdentifier::Blink
      received_variant = Matter::Cluster::IdentifyCluster::EffectVariant::Default

      cluster.on_trigger_effect do |effect, variant|
        received_effect = effect
        received_variant = variant
      end

      cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT,
        encode_trigger_effect_command(
          Matter::Cluster::IdentifyCluster::EffectIdentifier::Breathe.value,
          Matter::Cluster::IdentifyCluster::EffectVariant::Default.value
        )
      )

      received_effect.should eq(Matter::Cluster::IdentifyCluster::EffectIdentifier::Breathe)
      received_variant.should eq(Matter::Cluster::IdentifyCluster::EffectVariant::Default)
    end
  end

  describe "different identify types" do
    it "creates cluster for visible light device" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint_id,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )

      cluster.identify_type.should eq(Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight)
    end

    it "creates cluster for LED device" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint_id,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED
      )

      cluster.identify_type.should eq(Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLED)
    end

    it "creates cluster for audible device" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint_id,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::AudibleBeep
      )

      cluster.identify_type.should eq(Matter::Cluster::IdentifyCluster::IdentifyType::AudibleBeep)
    end

    it "creates cluster for display device" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint_id,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::Display
      )

      cluster.identify_type.should eq(Matter::Cluster::IdentifyCluster::IdentifyType::Display)
    end

    it "creates cluster for actuator device" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint_id,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::Actuator
      )

      cluster.identify_type.should eq(Matter::Cluster::IdentifyCluster::IdentifyType::Actuator)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end

    it "returns error for unsupported command" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      result = cluster.invoke_command(0x99_u32, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedCommand
      )
    end
  end

  describe "data versioning" do
    it "increments version when identify time changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      initial_version = cluster.data_version

      cluster.invoke_command(Matter::Cluster::IdentifyCluster::CMD_IDENTIFY, encode_identify_command(30_u16))
      cluster.data_version.should eq(initial_version + 1)
    end

    it "increments version when writing IdentifyTime" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint_id)

      initial_version = cluster.data_version

      cluster.write_attribute(
        Matter::Cluster::IdentifyCluster::ATTR_IDENTIFY_TIME,
        encode_tlv_uint16(45_u16)
      )

      cluster.data_version.should eq(initial_version + 1)
    end
  end
end
