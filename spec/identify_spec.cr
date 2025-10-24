require "./spec_helper"
require "../src/matter/cluster/identify_cluster"

describe Matter::Cluster::IdentifyCluster do
  describe "initialization" do
    it "creates cluster with default values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      cluster.name.should eq("Identify")
      cluster.cluster_id.id.should eq(0x0003_u32)
      cluster.identify_time.should eq(0_u16)
      cluster.identify_type.should eq(Matter::Cluster::Definitions::Identify::Type::None)
    end

    it "creates cluster with custom values" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_time: 10_u16,
        identify_type: Matter::Cluster::Definitions::Identify::Type::LightOutput
      )

      cluster.identify_time.should eq(10_u16)
      cluster.identify_type.should eq(Matter::Cluster::Definitions::Identify::Type::LightOutput)
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      attrs = cluster.attributes
      attrs.size.should eq(4)

      # Check IdentifyTime attribute
      identify_time = attrs.find { |a| a.id.id == Matter::Cluster::IdentifyCluster::IDENTIFY_TIME }
      identify_time.should_not be_nil
      identify_time.not_nil!.name.should eq("IdentifyTime")
      identify_time.not_nil!.type.should eq(:uint16)
      identify_time.not_nil!.writable.should be_true

      # Check IdentifyType attribute
      identify_type = attrs.find { |a| a.id.id == Matter::Cluster::IdentifyCluster::IDENTIFY_TYPE }
      identify_type.should_not be_nil
      identify_type.not_nil!.name.should eq("IdentifyType")
      identify_type.not_nil!.writable.should be_false
    end

    it "reads IdentifyTime attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint, identify_time: 30_u16)

      result = cluster.read_attribute(Matter::Cluster::IdentifyCluster::IDENTIFY_TIME)
      result.should be_a(Bytes)
      # Decode little-endian UInt16
      IO::ByteFormat::LittleEndian.decode(UInt16, result.as(Bytes)).should eq(30_u16)
    end

    it "reads IdentifyType attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::Definitions::Identify::Type::VisibleIndicator
      )

      result = cluster.read_attribute(Matter::Cluster::IdentifyCluster::IDENTIFY_TYPE)
      result.should be_a(Bytes)
      result.as(Bytes).should eq(Bytes[2]) # VisibleIndicator = 2
    end

    it "writes IdentifyTime attribute" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      initial_version = cluster.data_version

      # Encode UInt16 as little-endian
      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(15_u16, io)

      status = cluster.write_attribute(
        Matter::Cluster::IdentifyCluster::IDENTIFY_TIME,
        io.to_slice
      )

      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.identify_time.should eq(15_u16)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "rejects writing IdentifyType (read-only)" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      status = cluster.write_attribute(
        Matter::Cluster::IdentifyCluster::IDENTIFY_TYPE,
        Bytes[1]
      )

      status.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedWrite
      )
    end
  end

  describe "commands" do
    it "has required commands" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      cmds = cluster.commands
      cmds.size.should eq(3)

      identify = cmds.find { |c| c.id.id == Matter::Cluster::IdentifyCluster::CMD_IDENTIFY }
      identify.should_not be_nil
      identify.not_nil!.name.should eq("Identify")

      trigger_effect = cmds.find { |c| c.id.id == Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT }
      trigger_effect.should_not be_nil

      identify_query = cmds.find { |c| c.id.id == Matter::Cluster::IdentifyCluster::CMD_IDENTIFY_QUERY }
      identify_query.should_not be_nil
    end

    it "executes Identify command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      initial_version = cluster.data_version

      result = cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_IDENTIFY,
        Bytes.new(0)
      )

      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      # Simplified implementation sets identify time to 5 seconds
      cluster.identify_time.should eq(5_u16)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "executes TriggerEffect command" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      result = cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_TRIGGER_EFFECT,
        Bytes.new(0)
      )

      result.as(Matter::InteractionModel::Status).success?.should be_true
    end

    it "executes IdentifyQuery command when identifying" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint, identify_time: 20_u16)

      result = cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_IDENTIFY_QUERY,
        Bytes.new(0)
      )

      # Should return IdentifyQueryResponse with timeout
      result.should be_a(Bytes)
      result.as(Bytes).size.should eq(2) # UInt16
      IO::ByteFormat::LittleEndian.decode(UInt16, result.as(Bytes)).should eq(20_u16)
    end

    it "executes IdentifyQuery command when not identifying" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint, identify_time: 0_u16)

      result = cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_IDENTIFY_QUERY,
        Bytes.new(0)
      )

      # Should return success but no response data
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
    end
  end

  describe "callback mechanism" do
    it "calls on_identify callback when Identify command is executed" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      callback_called = false
      callback_duration : UInt16 = 0_u16

      cluster.on_identify = ->(duration : UInt16) {
        callback_called = true
        callback_duration = duration
      }

      cluster.invoke_command(
        Matter::Cluster::IdentifyCluster::CMD_IDENTIFY,
        Bytes.new(0)
      )

      callback_called.should be_true
      callback_duration.should eq(5_u16)
    end

    it "calls on_identify callback when IdentifyTime attribute is written" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      callback_called = false
      callback_duration : UInt16 = 0_u16

      cluster.on_identify = ->(duration : UInt16) {
        callback_called = true
        callback_duration = duration
      }

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(12_u16, io)

      cluster.write_attribute(
        Matter::Cluster::IdentifyCluster::IDENTIFY_TIME,
        io.to_slice
      )

      callback_called.should be_true
      callback_duration.should eq(12_u16)
    end

    it "does not call callback when IdentifyTime is set to zero" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      callback_called = false

      cluster.on_identify = ->(duration : UInt16) {
        callback_called = true
      }

      io = IO::Memory.new
      IO::ByteFormat::LittleEndian.encode(0_u16, io)

      cluster.write_attribute(
        Matter::Cluster::IdentifyCluster::IDENTIFY_TIME,
        io.to_slice
      )

      callback_called.should be_false
    end
  end

  describe "helper methods" do
    it "starts identifying with start_identify" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      callback_called = false

      cluster.on_identify = ->(duration : UInt16) {
        callback_called = true
      }

      cluster.start_identify(10_u16)

      cluster.identify_time.should eq(10_u16)
      callback_called.should be_true
    end

    it "stops identifying with stop_identify" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint, identify_time: 20_u16)

      cluster.stop_identify

      cluster.identify_time.should eq(0_u16)
    end
  end

  describe "data versioning" do
    it "increments version on identify time changes" do
      endpoint = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::IdentifyCluster.new(endpoint)

      initial_version = cluster.data_version

      cluster.start_identify(5_u16)
      cluster.data_version.should eq(initial_version + 1)

      cluster.stop_identify
      cluster.data_version.should eq(initial_version + 2)
    end
  end
end
