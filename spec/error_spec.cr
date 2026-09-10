require "./spec_helper"

describe Matter::Error do
  it "roots every library error class" do
    [
      Matter::CodecError, Matter::CryptoError, Matter::AuthenticationError,
      Matter::CertificateError, Matter::StorageError, Matter::SessionError,
      Matter::ProtocolError, Matter::TimeoutError, Matter::CommissioningError,
      Matter::TransportError, Matter::ClusterError,
    ].each do |klass|
      klass.new("x").should be_a(Matter::Error)
    end
  end

  it "nests the specialised classes under their parents" do
    Matter::AuthenticationError.new("x").should be_a(Matter::CryptoError)
    Matter::TimeoutError.new("x").should be_a(Matter::ProtocolError)
  end

  it "keeps the cause" do
    cause = IO::Error.new("disk")
    error = Matter::StorageError.new("load failed", cause: cause)
    error.message.should eq("load failed")
    error.cause.should be(cause)
  end

  describe Matter::ClusterError do
    it "defaults to the generic Failure status" do
      Matter::ClusterError.new("boom").to_status.should eq(Matter::InteractionModel::Status.failure)
    end

    it "carries an IM status and an optional cluster status" do
      error = Matter::ClusterError.new("full", Matter::InteractionModel::StatusCode::ResourceExhausted)
      error.status.should eq(Matter::InteractionModel::StatusCode::ResourceExhausted)
      error.cluster_status.should be_nil
      error.to_status.should eq(Matter::InteractionModel::Status.resource_exhausted)

      error = Matter::ClusterError.new("pake", Matter::InteractionModel::StatusCode::Failure, 3_u8)
      error.to_status.should eq(Matter::InteractionModel::Status.cluster_failure(3_u8))
    end

    it "builds from a wire status byte, falling back to Failure for unknown codes" do
      busy = Matter::InteractionModel::StatusCode::Busy
      error = Matter::ClusterError.from_wire("busy", busy.value, 7_u8)
      error.status.should eq(busy)
      error.cluster_status.should eq(7_u8)
      error.message.should eq("busy")

      unknown = Matter::ClusterError.from_wire("unknown", 0xFE_u8)
      unknown.status.should eq(Matter::InteractionModel::StatusCode::Failure)
    end
  end
end
