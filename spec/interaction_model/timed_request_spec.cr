require "../spec_helper"

module TimedRequestSpec
  TIMEOUT = 5000_u16
  # Anonymous structure, timeout UInt16 at tag 0, revision UInt8 at tag 255.
  # Matches matter.js TlvTimedRequest's schema and minimal-width encoding.
  VECTOR = Bytes[0x15, 0x25, 0x00, 0x88, 0x13, 0x24, 0xFF, 0x0C, 0x18]

  enum Tag : UInt8
    Timeout  =    0
    Revision = 0xFF
  end
end

describe Matter::InteractionModel::TimedRequestMessage do
  it "decodes and reproduces the Matter timed request wire layout" do
    request = Matter::InteractionModel::TimedRequestMessage.from_slice(TimedRequestSpec::VECTOR)
    request.timeout.should eq TimedRequestSpec::TIMEOUT
    request.interaction_model_revision.should eq Matter::InteractionModel::INTERACTION_MODEL_REVISION
    request.to_slice.should eq TimedRequestSpec::VECTOR
  end

  it "rejects a timeout with the wrong wire type" do
    fields = TLV::Structure{
      TimedRequestSpec::Tag::Timeout.value  => TLV::Any.new("5000"),
      TimedRequestSpec::Tag::Revision.value => TLV::Any.new(Matter::InteractionModel::INTERACTION_MODEL_REVISION),
    }
    expect_raises(TLV::DeserializationError) do
      Matter::InteractionModel::TimedRequestMessage.from_tlv(TLV::Any.new(fields))
    end
  end
end
