require "../spec_helper"
require "../../src/matter/protocol/im_handler"

# A cluster whose handlers raise whichever exception the test asks for, so the
# mapping performed at the cluster boundary can be observed directly.
private class RaisingCluster < Matter::Cluster::Base
  CLUSTER_ID     = 0x1236_u32
  CMD_RAISE      = 0x0000_u32
  ATTR_RAISE     = 0x0000_u32
  CLUSTER_STATUS =    0x2A_u8

  property failure : Exception? = nil

  def initialize(endpoint_id : Matter::DataType::EndpointNumber)
    super(endpoint_id, Matter::DataType::ClusterId.new(CLUSTER_ID))
  end

  def name : String
    "RaisingCluster"
  end

  def attributes : Array(Matter::Cluster::AttributeMetadata)
    [
      Matter::Cluster::AttributeMetadata.new(
        id: Matter::DataType::AttributeId.new(ATTR_RAISE),
        name: "RaisesOnWrite",
        type: :uint8,
        writable: true,
      ),
    ]
  end

  def commands : Array(Matter::Cluster::CommandMetadata)
    [
      Matter::Cluster::CommandMetadata.new(
        id: Matter::DataType::CommandId.new(CMD_RAISE),
        name: "RaisesOnInvoke",
      ),
    ]
  end

  protected def handle_command(command_id : UInt32, fields : TLV::Any?) : Matter::InteractionModel::Status | Matter::Cluster::CommandResponse
    if error = @failure
      raise error
    end
    Matter::InteractionModel::Status.success
  end

  protected def handle_write_attribute(attribute_id : UInt32, value : TLV::Any) : Matter::InteractionModel::Status
    if error = @failure
      raise error
    end
    Matter::InteractionModel::Status.success
  end
end

private def build_raising_cluster(failure : Exception?) : RaisingCluster
  cluster = RaisingCluster.new(Matter::DataType::EndpointNumber.new(1_u16))
  cluster.failure = failure
  cluster
end

describe "cluster boundary error mapping" do
  cluster_error = Matter::ClusterError.new(
    "busy",
    Matter::InteractionModel::StatusCode::Busy,
    RaisingCluster::CLUSTER_STATUS
  )

  describe "Cluster::Base#invoke_command" do
    it "returns the status carried by a ClusterError" do
      cluster = build_raising_cluster(cluster_error)
      result = invoke(cluster, RaisingCluster::CMD_RAISE)
      result.should eq(Matter::InteractionModel::Status.new(Matter::InteractionModel::StatusCode::Busy, RaisingCluster::CLUSTER_STATUS))
    end

    it "maps CodecError and TLV deserialization failures to InvalidCommand" do
      cluster = build_raising_cluster(Matter::CodecError.new("truncated"))
      invoke(cluster, RaisingCluster::CMD_RAISE).should eq(Matter::InteractionModel::Status.invalid_command)

      cluster = build_raising_cluster(TLV::DeserializationError.new("bad element"))
      invoke(cluster, RaisingCluster::CMD_RAISE).should eq(Matter::InteractionModel::Status.invalid_command)
    end

    it "maps ArgumentError to InvalidCommand" do
      cluster = build_raising_cluster(ArgumentError.new("field out of range"))
      invoke(cluster, RaisingCluster::CMD_RAISE).should eq(Matter::InteractionModel::Status.invalid_command)
    end

    it "maps any other exception to Failure" do
      cluster = build_raising_cluster(Matter::CryptoError.new("no key"))
      invoke(cluster, RaisingCluster::CMD_RAISE).should eq(Matter::InteractionModel::Status.failure)

      cluster = build_raising_cluster(Exception.new("bug"))
      invoke(cluster, RaisingCluster::CMD_RAISE).should eq(Matter::InteractionModel::Status.failure)
    end

    it "passes a successful handler result through" do
      cluster = build_raising_cluster(nil)
      invoke(cluster, RaisingCluster::CMD_RAISE).should eq(Matter::InteractionModel::Status.success)
    end
  end

  describe "Cluster::Base#write_attribute" do
    value = TLV::Any.new(1_u8)

    it "returns the status carried by a ClusterError" do
      cluster = build_raising_cluster(cluster_error)
      write(cluster, RaisingCluster::ATTR_RAISE, value).should eq(cluster_error.to_status)
    end

    it "maps CodecError, TLV deserialization failures and ArgumentError to InvalidDataType" do
      cluster = build_raising_cluster(Matter::CodecError.new("truncated"))
      write(cluster, RaisingCluster::ATTR_RAISE, value).should eq(Matter::InteractionModel::Status.invalid_data_type)

      cluster = build_raising_cluster(TLV::DeserializationError.new("bad element"))
      write(cluster, RaisingCluster::ATTR_RAISE, value).should eq(Matter::InteractionModel::Status.invalid_data_type)

      cluster = build_raising_cluster(ArgumentError.new("too long"))
      write(cluster, RaisingCluster::ATTR_RAISE, value).should eq(Matter::InteractionModel::Status.invalid_data_type)
    end

    it "maps any other exception to Failure" do
      cluster = build_raising_cluster(Matter::StorageError.new("disk"))
      write(cluster, RaisingCluster::ATTR_RAISE, value).should eq(Matter::InteractionModel::Status.failure)
    end

    it "passes a successful handler result through" do
      cluster = build_raising_cluster(nil)
      write(cluster, RaisingCluster::ATTR_RAISE, value).should eq(Matter::InteractionModel::Status.success)
    end
  end

  describe "IMHandler.invoke_commands" do
    it "still produces an InvokeResponse carrying the mapped status" do
      cluster = build_raising_cluster(cluster_error)
      endpoint_id = cluster.endpoint_id.number
      clusters = {
        {endpoint_id, RaisingCluster::CLUSTER_ID} => cluster.as(Matter::Cluster::Base),
      }
      path = Matter::InteractionModel::CommandPath.new(endpoint_id, RaisingCluster::CLUSTER_ID, RaisingCluster::CMD_RAISE)
      request = Matter::InteractionModel::CommandDataIBTlv.new(path)

      responses = Matter::Protocol::IMHandler.invoke_commands([request], clusters)

      responses.size.should eq(1)
      status = responses.first.command_status
      status.should_not be_nil
      status = status.as(Matter::InteractionModel::CommandStatusIB)
      status.command_path.should eq(path)
      status.status.status.should eq(Matter::InteractionModel::StatusCode::Busy.value)
      status.status.cluster_status.should eq(RaisingCluster::CLUSTER_STATUS)
    end
  end
end
