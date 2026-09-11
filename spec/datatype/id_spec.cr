require "../spec_helper"

# A structure carrying every generated identifier type as a context-tagged
# field, to prove the wrappers encode as bare integers inside TLV graphs.
private struct IdCarrier
  include TLV::Serializable

  @[TLV::Field(tag: 0)]
  getter attribute : Matter::DataType::AttributeId

  @[TLV::Field(tag: 1)]
  getter cluster : Matter::DataType::ClusterId

  @[TLV::Field(tag: 2)]
  getter command : Matter::DataType::CommandId

  @[TLV::Field(tag: 3)]
  getter device_type : Matter::DataType::DeviceTypeId

  @[TLV::Field(tag: 4)]
  getter event : Matter::DataType::EventId

  @[TLV::Field(tag: 5)]
  getter group : Matter::DataType::GroupId

  @[TLV::Field(tag: 6)]
  getter endpoint : Matter::DataType::EndpointNumber

  @[TLV::Field(tag: 7)]
  getter node : Matter::DataType::NodeId

  def initialize(@attribute, @cluster, @command, @device_type, @event, @group, @endpoint, @node)
  end
end

module Matter::DataType
  describe "define_id value types" do
    describe "equality" do
      it "compares and hashes by value" do
        AttributeId.new(5_u32).should eq(AttributeId.new(5_u32))
        AttributeId.new(5_u32).hash.should eq(AttributeId.new(5_u32).hash)
        AttributeId.new(5_u32).should_not eq(AttributeId.new(6_u32))
        EndpointNumber.new(1_u16).should eq(EndpointNumber.new(1_u16))
        NodeId.new(1_u64).should eq(NodeId.new(1_u64))
      end

      it "works as a Hash key" do
        table = {ClusterId.new(6_u32) => "OnOff"}
        table[ClusterId.new(6_u32)].should eq("OnOff")
      end
    end

    describe "TLV" do
      it "round-trips each type as a bare integer" do
        {
          AttributeId.new(0xFFFD_u32),
          ClusterId.new(0x0006_u32),
          CommandId.new(0x01_u32),
          DeviceTypeId.new(0x0100_u32),
          EventId.new(0x02_u32),
          GroupId.new(0x1234_u16),
          EndpointNumber.new(3_u16),
          NodeId.new(0x1234_5678_9ABC_DEF0_u64),
        }.each do |id|
          bytes = id.to_slice
          TLV::Any.from_slice(bytes).value.is_a?(Int).should be_true
          id.class.from_slice(bytes).should eq(id)
        end
      end

      it "encodes as context-tagged integers inside a structure" do
        carrier = IdCarrier.new(
          AttributeId.new(1_u32), ClusterId.new(2_u32), CommandId.new(3_u32), DeviceTypeId.new(4_u32),
          EventId.new(5_u32), GroupId.new(6_u16), EndpointNumber.new(7_u16), NodeId.new(8_u64),
        )
        bytes = carrier.to_slice

        structure = TLV::Any.from_slice(bytes).value.as(TLV::Structure)
        structure[7_u8].value.should eq(8_u64)
        structure[6_u8].value.should eq(7_u16)

        decoded = IdCarrier.from_slice(bytes)
        decoded.attribute.should eq(AttributeId.new(1_u32))
        decoded.group.should eq(GroupId.new(6_u16))
        decoded.endpoint.should eq(EndpointNumber.new(7_u16))
        decoded.node.should eq(NodeId.new(8_u64))
      end
    end

    describe "#to_s" do
      it "prints fixed-width hex sized to the underlying integer" do
        AttributeId.new(0x1F_u32).to_s.should eq("0x0000001f")
        GroupId.new(0x1F_u16).to_s.should eq("0x001f")
        EndpointNumber.new(1_u16).to_s.should eq("0x0001")
        "#{NodeId.new(1_u64)}".should eq("0x0000000000000001")
      end

      it "inspects with the type name" do
        ClusterId.new(6_u32).inspect.should eq("ClusterId(0x00000006)")
      end
    end

    describe "accessor names" do
      it "keeps EndpointNumber#number" do
        EndpointNumber.new(2_u16).number.should eq(2_u16)
      end
    end
  end
end
