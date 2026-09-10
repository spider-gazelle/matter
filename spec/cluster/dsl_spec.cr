require "../spec_helper"

# A spec-local cluster exercising every keyword of the cluster DSL.
module DslSpec
  enum Mode : UInt8
    Idle   = 0
    Active = 1
    Fault  = 2
  end

  struct PingRequest
    include TLV::Serializable

    @[TLV::Field(tag: 0)]
    property count : UInt8

    def initialize(@count : UInt8)
    end
  end

  struct PingResponse
    include TLV::Serializable

    @[TLV::Field(tag: 0)]
    property echoed : UInt8

    def initialize(@echoed : UInt8)
    end
  end

  class Widget < Matter::Cluster::Base
    cluster 0xFFF1_FC10, revision: 3

    feature :alpha, bit: 0
    feature :beta, bit: 1
    feature :gamma, bit: 2
    conflicts :beta, :gamma

    attribute 0x0000, :enabled, Bool, default: false, callback: :new_only
    attribute 0x0001, :level, UInt8, default: 10_u8, writable: true, min: 1, max: 100
    attribute 0x0002, :label, String, default: "widget", writable: true, max_length: 8
    attribute 0x0003, :mode, Mode, default: Mode::Idle, writable: true, persist: false
    attribute 0x0004, :offset, Int16, default: 0_i16, writable: true, min: -100, max: 100
    attribute 0x0005, :setpoint, UInt16, nullable: true, writable: true
    attribute 0x0006, :serial, String, default: "SN-1", fixed: true
    attribute 0x0007, :alpha_only, UInt8, default: 1_u8, writable: true, requires: :alpha
    attribute 0x0008, :not_beta, UInt8, default: 2_u8, requires: {beta: false}
    attribute 0x0009, :alpha_or_beta_without_gamma, UInt8, default: 3_u8, requires: [:alpha, {beta: true, gamma: false}]
    attribute 0x000A, :secret, UInt8, default: 0_u8, writable: true, persist: false, read_access: :operate, write_access: :manage
    attribute 0x000B, :counter, UInt32, default: 0_u32, persist: true, optional: true, scene: true, omit_changes: true, timed: true, fabric_scoped: true
    attribute 0x000C, :guarded, UInt8, default: 0_u8, writable: true, persist: false
    attribute 0x000D, :mirror, UInt8, default: 0_u8

    before_write :guarded do |value|
      Matter::InteractionModel::Status.constraint_error if value.odd?
    end

    after_write :guarded do
      self.mirror = @guarded
    end

    command 0x00, :ping, request: PingRequest, response: PingResponse, response_id: 0x01
    command 0x02, :reset
    command 0x03, :alpha_command, requires: :alpha
    command 0x04, :unimplemented, optional: true
    command 0x05, :implemented_optional, optional: true
    command 0x06, :guarded_command, timed: true, access: :manage
    command 0x07, :echo, request: PingRequest, response: PingResponse, response_id: 0x01
    command 0x08, :fallible, request: PingRequest, response: PingResponse, response_id: 0x09

    event 0x00, :tripped, priority: :critical
    event 0x01, :noted

    def ping(request : PingRequest) : PingResponse
      PingResponse.new(request.count)
    end

    def reset : Matter::InteractionModel::Status
      self.level = 10_u8
      Matter::InteractionModel::Status.success
    end

    def alpha_command : Matter::InteractionModel::Status
      Matter::InteractionModel::Status.success
    end

    def implemented_optional : Matter::Cluster::CommandResponse
      Matter::Cluster::CommandResponse.new(CMD_IMPLEMENTED_OPTIONAL, nil)
    end

    def guarded_command : Matter::InteractionModel::Status
      Matter::InteractionModel::Status.busy
    end

    def echo(request : PingRequest) : PingResponse
      PingResponse.new(request.count)
    end

    def fallible(request : PingRequest) : Matter::InteractionModel::Status | PingResponse
      return Matter::InteractionModel::Status.invalid_command if request.count.zero?
      PingResponse.new(request.count)
    end
  end
end

private alias Widget = DslSpec::Widget
private alias Privilege = Matter::Cluster::Definitions::AccessControl::EntryPrivilege
private alias StatusCode = Matter::InteractionModel::StatusCode

private def widget(feature_map : Widget::Feature = Widget::Feature::None) : Widget
  Widget.new(endpoint(1), feature_map: feature_map)
end

private def attribute_metadata(cluster : Widget, attribute_id : UInt32) : Matter::Cluster::AttributeMetadata
  cluster.get_attribute_metadata(attribute_id).as(Matter::Cluster::AttributeMetadata)
end

private def command_metadata(cluster : Widget, command_id : UInt32) : Matter::Cluster::CommandMetadata
  cluster.get_command_metadata(command_id).as(Matter::Cluster::CommandMetadata)
end

describe Matter::Cluster::DSL do
  describe "cluster" do
    it "generates the id, revision and name" do
      Widget::CLUSTER_ID.should eq(0xFFF1_FC10_u32)
      Widget.cluster_id.should eq(Widget::CLUSTER_ID)
      Widget::CLUSTER_REVISION.should eq(3_u16)

      cluster = widget
      cluster.name.should eq("Widget")
      cluster.cluster_id.id.should eq(Widget::CLUSTER_ID)
      cluster.cluster_revision.should eq(3_u16)
      read(cluster, Matter::Cluster::Base::GLOBAL_CLUSTER_REVISION).should eq(3_u16)
    end

    it "generates a constructor taking the feature map" do
      Widget.new(endpoint(2)).feature_map.should eq(Widget::Feature::None)
      widget(Widget::Feature::Alpha).feature_map.alpha?.should be_true
    end
  end

  describe "feature" do
    it "generates the Feature flags from the bit numbers" do
      Widget::Feature::Alpha.value.should eq(1_u32)
      Widget::Feature::Beta.value.should eq(2_u32)
      Widget::Feature::Gamma.value.should eq(4_u32)
      Widget::Feature::None.value.should eq(0_u32)
    end

    it "reports the feature map through the global attribute" do
      read(widget, Matter::Cluster::Base::GLOBAL_FEATURE_MAP).should eq(0_u32)
      read(widget(Widget::Feature::Alpha | Widget::Feature::Beta), Matter::Cluster::Base::GLOBAL_FEATURE_MAP).should eq(3_u32)
    end

    it "rejects conflicting features" do
      expect_raises(ArgumentError, /Widget cluster: Beta and Gamma features cannot be combined/) do
        widget(Widget::Feature::Beta | Widget::Feature::Gamma)
      end
    end
  end

  describe "attribute" do
    it "generates the id constants" do
      Widget::ATTR_ENABLED.should eq(0x0000_u32)
      Widget::ATTR_LEVEL.should eq(0x0001_u32)
      Widget::ATTR_ALPHA_OR_BETA_WITHOUT_GAMMA.should eq(0x0009_u32)
    end

    it "generates the metadata" do
      cluster = widget
      names = cluster.attributes.map(&.name)
      names.should eq(%w[enabled level label mode offset setpoint serial notBeta secret counter guarded mirror])

      level = attribute_metadata(cluster, Widget::ATTR_LEVEL)
      level.type.should eq(:uint8)
      level.writable?.should be_true
      level.optional?.should be_false
      level.fixed?.should be_false
      level.default.as(TLV::Any).as_u8.should eq(10_u8)
      level.min.should eq(1_i64)
      level.max.should eq(100_i64)
      level.access.should eq(Privilege::View)
      level.write_access.should eq(Privilege::View)
      level.timed?.should be_false
      level.scene?.should be_false

      attribute_metadata(cluster, Widget::ATTR_ENABLED).type.should eq(:bool)
      attribute_metadata(cluster, Widget::ATTR_LABEL).type.should eq(:string)
      attribute_metadata(cluster, Widget::ATTR_OFFSET).type.should eq(:int16)
      attribute_metadata(cluster, Widget::ATTR_OFFSET).min.should eq(-100_i64)
      attribute_metadata(cluster, Widget::ATTR_SETPOINT).type.should eq(:uint16)
      attribute_metadata(cluster, Widget::ATTR_SETPOINT).default.should be_nil

      mode = attribute_metadata(cluster, Widget::ATTR_MODE)
      mode.type.should eq(:enum)
      mode.default.as(TLV::Any).as_u8.should eq(DslSpec::Mode::Idle.value)

      counter = attribute_metadata(cluster, Widget::ATTR_COUNTER)
      counter.optional?.should be_true
      counter.scene?.should be_true
      counter.omit_changes?.should be_true
      counter.timed?.should be_true
      counter.fabric_scoped?.should be_true

      attribute_metadata(cluster, Widget::ATTR_SERIAL).fixed?.should be_true
      cluster.get_attribute_metadata(0x9999_u32).should be_nil
    end

    it "routes read_access: and write_access: to the metadata" do
      secret = attribute_metadata(widget, Widget::ATTR_SECRET)
      secret.access.should eq(Privilege::Operate)
      secret.write_access.should eq(Privilege::Manage)
    end

    it "generates typed getters" do
      cluster = widget
      cluster.enabled?.should be_false
      cluster.level.should eq(10_u8)
      cluster.label.should eq("widget")
      cluster.mode.should eq(DslSpec::Mode::Idle)
      cluster.setpoint.should be_nil
      cluster.serial.should eq("SN-1")
    end

    it "reads values as TLV" do
      cluster = widget
      read(cluster, Widget::ATTR_ENABLED).should be_false
      read(cluster, Widget::ATTR_LEVEL).should eq(10_u8)
      read(cluster, Widget::ATTR_LABEL).should eq("widget")
      read(cluster, Widget::ATTR_MODE).should eq(DslSpec::Mode::Idle.value)
      read(cluster, Widget::ATTR_OFFSET).should eq(0_i16)
      read(cluster, Widget::ATTR_SETPOINT).should be_nil
      read_status(cluster, 0x9999_u32).status.should eq(StatusCode::UnsupportedAttribute)
    end

    describe "setter" do
      it "ignores an equal value" do
        cluster = widget
        changes = capture_changes(cluster) do
          version_delta(cluster) { cluster.level = 10_u8 }.should eq(0)
        end
        changes.should be_empty
      end

      it "bumps the version, notifies and runs the (old, new) callback" do
        cluster = widget
        observed = [] of Tuple(UInt8, UInt8)
        cluster.on_level_changed { |old_value, new_value| observed << {old_value, new_value} }

        changes = capture_changes(cluster) do
          version_delta(cluster) { cluster.level = 20_u8 }.should eq(1)
        end

        changes.map(&.attribute).should eq([Widget::ATTR_LEVEL])
        changes[0].cluster.should eq(Widget::CLUSTER_ID)
        observed.should eq([{10_u8, 20_u8}])
        cluster.level.should eq(20_u8)
      end

      it "runs a callback: :new_only callback with the new value" do
        cluster = widget
        observed = [] of Bool
        cluster.on_enabled_changed { |value| observed << value }

        cluster.enabled = true
        cluster.enabled = true
        cluster.enabled = false

        observed.should eq([true, false])
      end
    end

    it "round trips a nullable attribute" do
      cluster = widget
      expect_success(write(cluster, Widget::ATTR_SETPOINT, 500_u16))
      read(cluster, Widget::ATTR_SETPOINT).should eq(500_u16)
      cluster.setpoint.should eq(500_u16)

      observed = [] of Tuple(UInt16?, UInt16?)
      cluster.on_setpoint_changed { |old_value, new_value| observed << {old_value, new_value} }
      changes = capture_changes(cluster) do
        version_delta(cluster) { expect_success(write(cluster, Widget::ATTR_SETPOINT, nil)) }.should eq(1)
      end
      changes.map(&.attribute).should eq([Widget::ATTR_SETPOINT])
      observed.should eq([{500_u16, nil}])
      read(cluster, Widget::ATTR_SETPOINT).should be_nil

      version_delta(cluster) { cluster.setpoint = nil }.should eq(0)
    end

    describe "writes" do
      it "rejects values outside min:/max: with ConstraintError" do
        cluster = widget
        expect_status(write(cluster, Widget::ATTR_LEVEL, 0_u8), StatusCode::ConstraintError)
        expect_status(write(cluster, Widget::ATTR_LEVEL, 101_u8), StatusCode::ConstraintError)
        cluster.level.should eq(10_u8)
        expect_success(write(cluster, Widget::ATTR_LEVEL, 100_u8))
        cluster.level.should eq(100_u8)

        expect_status(write(cluster, Widget::ATTR_OFFSET, -101_i16), StatusCode::ConstraintError)
        expect_success(write(cluster, Widget::ATTR_OFFSET, -100_i16))
        cluster.offset.should eq(-100_i16)
      end

      it "rejects strings longer than max_length: with ConstraintError" do
        cluster = widget
        expect_status(write(cluster, Widget::ATTR_LABEL, "too long!"), StatusCode::ConstraintError)
        cluster.label.should eq("widget")
        expect_success(write(cluster, Widget::ATTR_LABEL, "8 chars!"))
        cluster.label.should eq("8 chars!")
      end

      it "rejects an unknown enum member with ConstraintError" do
        cluster = widget
        expect_status(write(cluster, Widget::ATTR_MODE, DslSpec::Mode.values.size.to_u8), StatusCode::ConstraintError)
        cluster.mode.should eq(DslSpec::Mode::Idle)
        expect_success(write(cluster, Widget::ATTR_MODE, DslSpec::Mode::Fault.value))
        cluster.mode.should eq(DslSpec::Mode::Fault)
      end

      it "rejects the wrong TLV type with InvalidDataType" do
        cluster = widget
        expect_status(write(cluster, Widget::ATTR_LEVEL, "ten"), StatusCode::InvalidDataType)
        expect_status(write(cluster, Widget::ATTR_LEVEL, -1_i8), StatusCode::InvalidDataType)
        expect_status(write(cluster, Widget::ATTR_LABEL, 1_u8), StatusCode::InvalidDataType)
        expect_status(write(cluster, Widget::ATTR_MODE, "idle"), StatusCode::InvalidDataType)
        expect_status(write(cluster, Widget::ATTR_OFFSET, true), StatusCode::InvalidDataType)
        expect_status(write(cluster, Widget::ATTR_SETPOINT, "none"), StatusCode::InvalidDataType)
        cluster.data_version.should eq(0_u32)
      end

      it "rejects writes to read-only and fixed attributes with UnsupportedWrite" do
        cluster = widget
        expect_status(write(cluster, Widget::ATTR_ENABLED, true), StatusCode::UnsupportedWrite)
        expect_status(write(cluster, Widget::ATTR_SERIAL, "SN-2"), StatusCode::UnsupportedWrite)
        expect_status(write(cluster, 0x9999_u32, 1_u8), StatusCode::UnsupportedAttribute)
        cluster.serial.should eq("SN-1")
      end

      it "lets before_write reject and after_write react" do
        cluster = widget
        expect_status(write(cluster, Widget::ATTR_GUARDED, 3_u8), StatusCode::ConstraintError)
        cluster.guarded.should eq(0_u8)
        cluster.mirror.should eq(0_u8)

        expect_success(write(cluster, Widget::ATTR_GUARDED, 4_u8))
        cluster.guarded.should eq(4_u8)
        cluster.mirror.should eq(4_u8)
      end
    end
  end

  describe "requires:" do
    it "gates a symbol condition" do
      cluster = widget
      read_status(cluster, Widget::ATTR_ALPHA_ONLY).status.should eq(StatusCode::UnsupportedAttribute)
      expect_status(write(cluster, Widget::ATTR_ALPHA_ONLY, 5_u8), StatusCode::UnsupportedAttribute)
      cluster.get_attribute_metadata(Widget::ATTR_ALPHA_ONLY).should be_nil
      attribute_ids(cluster).should_not contain(Widget::ATTR_ALPHA_ONLY)

      cluster = widget(Widget::Feature::Alpha)
      read(cluster, Widget::ATTR_ALPHA_ONLY).should eq(1_u8)
      expect_success(write(cluster, Widget::ATTR_ALPHA_ONLY, 5_u8))
      cluster.alpha_only.should eq(5_u8)
      attribute_ids(cluster).should contain(Widget::ATTR_ALPHA_ONLY)
    end

    it "gates a hash condition" do
      attribute_ids(widget).should contain(Widget::ATTR_NOT_BETA)
      attribute_ids(widget(Widget::Feature::Beta)).should_not contain(Widget::ATTR_NOT_BETA)
      read_status(widget(Widget::Feature::Beta), Widget::ATTR_NOT_BETA).status.should eq(StatusCode::UnsupportedAttribute)
    end

    it "gates an array of conditions as any-of" do
      attribute_ids(widget).should_not contain(Widget::ATTR_ALPHA_OR_BETA_WITHOUT_GAMMA)
      attribute_ids(widget(Widget::Feature::Alpha)).should contain(Widget::ATTR_ALPHA_OR_BETA_WITHOUT_GAMMA)
      attribute_ids(widget(Widget::Feature::Beta)).should contain(Widget::ATTR_ALPHA_OR_BETA_WITHOUT_GAMMA)
      attribute_ids(widget(Widget::Feature::Gamma)).should_not contain(Widget::ATTR_ALPHA_OR_BETA_WITHOUT_GAMMA)
      attribute_ids(widget(Widget::Feature::Alpha | Widget::Feature::Gamma)).should contain(Widget::ATTR_ALPHA_OR_BETA_WITHOUT_GAMMA)
    end

    it "gates commands and the accepted command list" do
      cluster = widget
      expect_status(invoke(cluster, Widget::CMD_ALPHA_COMMAND), StatusCode::UnsupportedCommand)
      cluster.get_command_metadata(Widget::CMD_ALPHA_COMMAND).should be_nil
      accepted_command_ids(cluster).should_not contain(Widget::CMD_ALPHA_COMMAND)

      cluster = widget(Widget::Feature::Alpha)
      expect_success(invoke(cluster, Widget::CMD_ALPHA_COMMAND))
      accepted_command_ids(cluster).should contain(Widget::CMD_ALPHA_COMMAND)
    end

    it "lists the globals after the supported attributes" do
      attribute_ids(widget(Widget::Feature::Alpha)).should eq([
        Widget::ATTR_ENABLED, Widget::ATTR_LEVEL, Widget::ATTR_LABEL, Widget::ATTR_MODE, Widget::ATTR_OFFSET,
        Widget::ATTR_SETPOINT, Widget::ATTR_SERIAL, Widget::ATTR_ALPHA_ONLY, Widget::ATTR_NOT_BETA,
        Widget::ATTR_ALPHA_OR_BETA_WITHOUT_GAMMA, Widget::ATTR_SECRET, Widget::ATTR_COUNTER, Widget::ATTR_GUARDED,
        Widget::ATTR_MIRROR,
        Matter::Cluster::Base::GLOBAL_GENERATED_COMMAND_LIST, Matter::Cluster::Base::GLOBAL_ACCEPTED_COMMAND_LIST,
        Matter::Cluster::Base::GLOBAL_ATTRIBUTE_LIST, Matter::Cluster::Base::GLOBAL_FEATURE_MAP,
        Matter::Cluster::Base::GLOBAL_CLUSTER_REVISION,
      ])
    end
  end

  describe "command" do
    it "generates the id constants and metadata" do
      Widget::CMD_PING.should eq(0x00_u32)
      Widget::CMD_FALLIBLE.should eq(0x08_u32)

      cluster = widget
      cluster.commands.map(&.name).should eq(%w[ping reset implementedOptional guardedCommand echo fallible])

      ping = command_metadata(cluster, Widget::CMD_PING)
      ping.response_id.should eq(0x01_u32)
      ping.optional?.should be_false
      ping.timed?.should be_false
      ping.access.should eq(Privilege::Operate)

      command_metadata(cluster, Widget::CMD_RESET).response_id.should be_nil
      command_metadata(cluster, Widget::CMD_IMPLEMENTED_OPTIONAL).optional?.should be_true

      guarded = command_metadata(cluster, Widget::CMD_GUARDED_COMMAND)
      guarded.timed?.should be_true
      guarded.access.should eq(Privilege::Manage)
    end

    it "leaves an optional command without a handler out of the lists" do
      cluster = widget
      cluster.get_command_metadata(Widget::CMD_UNIMPLEMENTED).should be_nil
      accepted_command_ids(cluster).should eq([
        Widget::CMD_PING, Widget::CMD_RESET, Widget::CMD_IMPLEMENTED_OPTIONAL, Widget::CMD_GUARDED_COMMAND,
        Widget::CMD_ECHO, Widget::CMD_FALLIBLE,
      ])
      expect_status(invoke(cluster, Widget::CMD_UNIMPLEMENTED), StatusCode::UnsupportedCommand)
      expect_status(invoke(cluster, 0x99_u32), StatusCode::UnsupportedCommand)
    end

    it "dispatches to handlers and passes status results through" do
      cluster = widget
      cluster.level = 42_u8
      expect_success(invoke(cluster, Widget::CMD_RESET))
      cluster.level.should eq(10_u8)
      expect_status(invoke(cluster, Widget::CMD_GUARDED_COMMAND), StatusCode::Busy)

      result = invoke(cluster, Widget::CMD_IMPLEMENTED_OPTIONAL)
      result.as(Matter::Cluster::CommandResponse).command_id.should eq(Widget::CMD_IMPLEMENTED_OPTIONAL)
    end

    it "wraps a returned struct as the response command" do
      cluster = widget
      result = invoke(cluster, Widget::CMD_PING, DslSpec::PingRequest.new(7_u8))
      response = result.as(Matter::Cluster::CommandResponse)
      response.command_id.should eq(0x01_u32)
      DslSpec::PingResponse.from_tlv(response.response.as(TLV::Any)).echoed.should eq(7_u8)

      invoke_response(cluster, Widget::CMD_FALLIBLE, DslSpec::PingRequest.new(3_u8), DslSpec::PingResponse).echoed.should eq(3_u8)
      expect_status(invoke(cluster, Widget::CMD_FALLIBLE, DslSpec::PingRequest.new(0_u8)), StatusCode::InvalidCommand)
    end

    it "rejects a request that does not decode with InvalidCommand" do
      expect_status(invoke(widget, Widget::CMD_PING), StatusCode::InvalidCommand)
      expect_status(invoke(widget, Widget::CMD_PING, TLV::Any.new("ping")), StatusCode::InvalidCommand)
    end

    it "derives the generated command list from the distinct response ids" do
      generated_command_ids(widget).should eq([0x01_u32, 0x09_u32])
    end
  end

  describe "event" do
    it "generates the id constants and metadata" do
      Widget::EVENT_TRIPPED.should eq(0x00_u32)
      Widget::EVENT_NOTED.should eq(0x01_u32)

      events = widget.events
      events.map(&.name).should eq(%w[tripped noted])
      events.map(&.id.id).should eq([Widget::EVENT_TRIPPED, Widget::EVENT_NOTED])
      events.map(&.priority).should eq([Matter::InteractionModel::EventPriority::Critical, Matter::InteractionModel::EventPriority::Info])
    end
  end

  describe "persistence" do
    it "saves the persisted attributes with the feature map stamp" do
      cluster = widget(Widget::Feature::Alpha)
      cluster.level = 42_u8
      cluster.label = "abc"
      cluster.offset = -7_i16
      cluster.setpoint = 9_u16
      cluster.alpha_only = 5_u8
      cluster.counter = 77_u32
      cluster.mode = DslSpec::Mode::Active
      cluster.data_version = 12_u32

      document = cluster.save_state.as(Matter::Storage::Document)
      document.keys.sort!.should eq(%w[alpha_only counter data_version features label level offset setpoint])
      document["level"].should eq(42_i64)
      document["label"].should eq("abc")
      document["offset"].should eq(-7_i64)
      document["setpoint"].should eq(9_i64)
      document["alpha_only"].should eq(5_i64)
      document["counter"].should eq(77_i64)
      document["data_version"].should eq(12_i64)
      document["features"].should eq(Widget::Feature::Alpha.value.to_i64)

      restored = widget(Widget::Feature::Alpha)
      restored.restore_state(document)
      restored.level.should eq(42_u8)
      restored.label.should eq("abc")
      restored.offset.should eq(-7_i16)
      restored.setpoint.should eq(9_u16)
      restored.alpha_only.should eq(5_u8)
      restored.counter.should eq(77_u32)
      restored.data_version.should eq(12_u32)
      restored.mode.should eq(DslSpec::Mode::Idle)
    end

    it "discards state saved under a different feature map" do
      document = widget(Widget::Feature::Alpha).tap(&.level=(42_u8)).save_state.as(Matter::Storage::Document)

      restored = widget(Widget::Feature::Beta)
      restored.restore_state(document)
      restored.level.should eq(10_u8)
      restored.data_version.should eq(0_u32)
    end

    it "accepts state without a feature map stamp" do
      document = widget.tap(&.level=(42_u8)).save_state.as(Matter::Storage::Document)
      document.delete("features")

      restored = widget(Widget::Feature::Alpha)
      restored.restore_state(document)
      restored.level.should eq(42_u8)
    end

    it "starts fresh when the document does not decode" do
      document = widget.save_state.as(Matter::Storage::Document)
      document["level"] = "forty-two"

      restored = widget
      restored.level = 5_u8
      restored.restore_state(document)
      restored.level.should eq(5_u8)
    end
  end

  describe "compile-time checks" do
    it "rejects a mandatory command without a handler" do
      crystal = Process.find_executable("crystal")
      pending! "the crystal compiler is not on PATH" unless crystal

      fixture = File.join(__DIR__, "..", "fixtures", "dsl_missing_handler.cr")
      output = IO::Memory.new
      status = Process.run(crystal, ["build", "--no-codegen", fixture], output: output, error: output)

      status.success?.should be_false
      output.to_s.should contain("MissingHandlerCluster: command :unhandled has no handler method `unhandled`")
    end
  end
end
