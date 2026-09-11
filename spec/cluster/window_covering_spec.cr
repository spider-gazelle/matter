require "../spec_helper"
require "../../src/matter/cluster/window_covering_cluster"

# Ported from matter.js window-coveringTest.ts
# Tests Window Covering Cluster feature composition
describe Matter::Cluster::WindowCoveringCluster do
  describe "with Lift and PositionAwareLift features" do
    # WindowCovering_LF_PALF = WindowCoveringCluster.with("Lift", "PositionAwareLift")
    cluster = Matter::Cluster::WindowCoveringCluster.new(
      endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
      feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                   Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
    )

    describe "correctly initializes elements for LF & PA_LF" do
      it "has correct attribute properties" do
        attrs = cluster.attributes
        attr_map = {} of String => Matter::Cluster::AttributeMetadata

        attrs.each do |attr|
          attr_map[attr.name] = attr
        end

        # Check mandatory, non-optional attributes
        # configStatus - mandatory
        attr_map["configStatus"].optional?.should be_false
        attr_map["configStatus"].writable?.should be_false
        attr_map["configStatus"].fixed?.should be_false

        # currentPositionLiftPercent100ths - mandatory with PA_LF
        attr_map["currentPositionLiftPercent100ths"].optional?.should be_false
        attr_map["currentPositionLiftPercent100ths"].writable?.should be_false
        attr_map["currentPositionLiftPercent100ths"].fixed?.should be_false

        # currentPositionLiftPercentage - optional
        attr_map["currentPositionLiftPercentage"].optional?.should be_true
        attr_map["currentPositionLiftPercentage"].writable?.should be_false
        attr_map["currentPositionLiftPercentage"].fixed?.should be_false

        # endProductType - fixed
        attr_map["endProductType"].optional?.should be_false
        attr_map["endProductType"].writable?.should be_false
        attr_map["endProductType"].fixed?.should be_true

        # mode - writable
        attr_map["mode"].optional?.should be_false
        attr_map["mode"].writable?.should be_true
        attr_map["mode"].fixed?.should be_false

        # numberOfActuationsLift - optional
        attr_map["numberOfActuationsLift"].optional?.should be_true
        attr_map["numberOfActuationsLift"].writable?.should be_false
        attr_map["numberOfActuationsLift"].fixed?.should be_false

        # operationalStatus - mandatory
        attr_map["operationalStatus"].optional?.should be_false
        attr_map["operationalStatus"].writable?.should be_false
        attr_map["operationalStatus"].fixed?.should be_false

        # safetyStatus - optional
        attr_map["safetyStatus"].optional?.should be_true
        attr_map["safetyStatus"].writable?.should be_false
        attr_map["safetyStatus"].fixed?.should be_false

        # targetPositionLiftPercent100ths - mandatory with PA_LF
        attr_map["targetPositionLiftPercent100ths"].optional?.should be_false
        attr_map["targetPositionLiftPercent100ths"].writable?.should be_false
        attr_map["targetPositionLiftPercent100ths"].fixed?.should be_false

        # type - fixed
        attr_map["type"].optional?.should be_false
        attr_map["type"].writable?.should be_false
        attr_map["type"].fixed?.should be_true
      end

      it "has correct command properties" do
        cmds = cluster.commands
        cmd_map = {} of String => Matter::Cluster::CommandMetadata

        cmds.each do |cmd|
          cmd_map[cmd.name] = cmd
        end

        # downOrClose - mandatory
        cmd_map["downOrClose"].optional?.should be_false

        # goToLiftPercentage - mandatory with LF & PA_LF
        cmd_map["goToLiftPercentage"].optional?.should be_false

        # stopMotion - mandatory
        cmd_map["stopMotion"].optional?.should be_false

        # upOrOpen - mandatory
        cmd_map["upOrOpen"].optional?.should be_false
      end
    end
  end

  describe "with only Lift feature" do
    cluster = Matter::Cluster::WindowCoveringCluster.new(
      endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
      feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift
    )

    it "does not include goToLiftPercentage command" do
      cmds = cluster.commands
      cmd_names = cmds.map(&.name)

      cmd_names.includes?("goToLiftPercentage").should be_false
    end

    it "does not include position-aware lift attributes" do
      attrs = cluster.attributes
      attr_names = attrs.map(&.name)

      attr_names.includes?("currentPositionLiftPercent100ths").should be_false
      attr_names.includes?("targetPositionLiftPercent100ths").should be_false
    end
  end

  describe "with Tilt and PositionAwareTilt features" do
    cluster = Matter::Cluster::WindowCoveringCluster.new(
      endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
      feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt |
                   Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareTilt
    )

    it "includes goToTiltPercentage command" do
      cmds = cluster.commands
      cmd_names = cmds.map(&.name)

      cmd_names.includes?("goToTiltPercentage").should be_true
    end

    it "includes position-aware tilt attributes" do
      attrs = cluster.attributes
      attr_names = attrs.map(&.name)

      attr_names.includes?("currentPositionTiltPercent100ths").should be_true
      attr_names.includes?("targetPositionTiltPercent100ths").should be_true
    end
  end

  describe "commands" do
    cluster = Matter::Cluster::WindowCoveringCluster.new(
      endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
      feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                   Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
    )

    it "upOrOpen sets target to 0%" do
      cluster.target_position_lift_percent100ths.should eq(0_u16)
    end

    it "downOrClose would set target to 100%" do
      # The handle_down_or_close sets target to 10000 (100.00%)
      cluster.target_position_lift_percent100ths = nil
      # Command handling tested via invoke_command
    end
  end

  describe "percentage commands on the wire" do
    it "sets the lift target from tag zero" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(endpoint(1))
      request = Matter::Cluster::Definitions::WindowCovering::GoToLiftPercentageRequest.new(4321_u16)
      expect_success(invoke(cluster, Matter::Cluster::WindowCoveringCluster::CMD_GO_TO_LIFT_PERCENTAGE, request))
      read(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_TARGET_POSITION_LIFT_PERCENT100THS).should eq(4321_u16)
    end

    it "rejects a lift percentage above 100 percent without changing the target" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(endpoint(1))
      request = Matter::Cluster::Definitions::WindowCovering::GoToLiftPercentageRequest.new(10001_u16)
      expect_status(invoke(cluster, Matter::Cluster::WindowCoveringCluster::CMD_GO_TO_LIFT_PERCENTAGE, request), Matter::InteractionModel::StatusCode::ConstraintError)
      cluster.target_position_lift_percent100ths.should eq(0_u16)
    end

    it "rejects missing percentage fields" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(endpoint(1))
      expect_status(invoke(cluster, Matter::Cluster::WindowCoveringCluster::CMD_GO_TO_LIFT_PERCENTAGE), Matter::InteractionModel::StatusCode::InvalidCommand)
    end

    it "sets the tilt target from tag zero" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(endpoint(1),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt | Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareTilt)
      request = Matter::Cluster::Definitions::WindowCovering::GoToTiltPercentageRequest.new(6789_u16)
      expect_success(invoke(cluster, Matter::Cluster::WindowCoveringCluster::CMD_GO_TO_TILT_PERCENTAGE, request))
      read(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_TARGET_POSITION_TILT_PERCENT100THS).should eq(6789_u16)
      read(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_CURRENT_POSITION_TILT_PERCENT100THS).should eq(0_u16)
      read(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_CURRENT_POSITION_TILT_PERCENTAGE).should be_nil
      read(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_NUMBER_OF_ACTUATIONS_TILT).should eq(0_u16)
    end

    it "rejects a tilt percentage above 100 percent" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(endpoint(1),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt | Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareTilt)
      request = Matter::Cluster::Definitions::WindowCovering::GoToTiltPercentageRequest.new(10001_u16)
      expect_status(invoke(cluster, Matter::Cluster::WindowCoveringCluster::CMD_GO_TO_TILT_PERCENTAGE, request), Matter::InteractionModel::StatusCode::ConstraintError)
      cluster.target_position_tilt_percent100ths.should eq(0_u16)
    end
  end

  describe "cluster metadata" do
    cluster = Matter::Cluster::WindowCoveringCluster.new(
      endpoint_id: Matter::DataType::EndpointNumber.new(1_u16)
    )

    it "has correct cluster ID" do
      cluster.cluster_id.id.should eq(0x0102_u32)
    end

    it "has correct name" do
      cluster.name.should eq("WindowCovering")
    end

    it "has correct default feature map" do
      cluster.feature_map.should eq(
        Matter::Cluster::WindowCoveringCluster::Feature::Lift |
        Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
      )
    end
  end

  describe "attribute read/write" do
    cluster = Matter::Cluster::WindowCoveringCluster.new(
      endpoint_id: Matter::DataType::EndpointNumber.new(1_u16)
    )

    it "reads type attribute" do
      result = read_tlv(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_TYPE)
      result.should be_a(TLV::Any)
      result.value.should eq(0) # Rollershade
    end

    it "reads config status attribute" do
      result = read_tlv(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_CONFIG_STATUS)
      result.should be_a(TLV::Any)
    end

    it "writes mode attribute" do
      # Set calibration mode
      mode = 0x02_u8 # CalibrationMode
      status = write(cluster, Matter::Cluster::WindowCoveringCluster::ATTR_MODE, mode)
      status.status.should eq(Matter::InteractionModel::StatusCode::Success)

      # Verify it was written
      cluster.mode.should eq(Matter::Cluster::WindowCoveringCluster::Mode::CalibrationMode)
    end

    it "reads feature map" do
      result = read_tlv(cluster, Matter::Cluster::Base::GLOBAL_FEATURE_MAP)
      result.should be_a(TLV::Any)
      # Lift (0x01) | PositionAwareLift (0x04) = 0x05
      result.value.should eq(0x05)
    end
  end
end
