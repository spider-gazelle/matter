require "../spec_helper"
require "../../src/matter/cluster/window_covering_cluster"

# Ported concepts from matter.js cluster mutation tests:
# - ClusterTypeTest.ts
# - ClusterComposerTest.ts
# - ClusterTypeModifierTest.ts
# - MutableClusterTest.ts
#
# These tests verify feature-based cluster composition behavior:
# - Feature flags modify which attributes/commands are included
# - Optional vs required elements based on features
# - Feature validation and illegal combinations
describe "Cluster Composition" do
  describe "feature-based element composition" do
    describe "WindowCovering with different feature sets" do
      it "includes Lift attributes when Lift feature is enabled" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift
        )

        attr_names = cluster.attributes.map(&.name)

        # Lift feature adds numberOfActuationsLift (optional attribute)
        attr_names.includes?("numberOfActuationsLift").should be_true

        # Position-aware percentage attributes should NOT be present without PositionAwareLift
        attr_names.includes?("currentPositionLiftPercent100ths").should be_false
        attr_names.includes?("targetPositionLiftPercent100ths").should be_false
      end

      it "includes PositionAwareLift attributes when both Lift and PositionAwareLift enabled" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                       Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
        )

        attr_names = cluster.attributes.map(&.name)

        # Position-aware lift attributes should now be present
        attr_names.includes?("currentPositionLiftPercent100ths").should be_true
        attr_names.includes?("targetPositionLiftPercent100ths").should be_true
        attr_names.includes?("currentPositionLiftPercentage").should be_true
      end

      it "includes Tilt attributes when Tilt feature is enabled" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt
        )

        attr_names = cluster.attributes.map(&.name)

        # Tilt feature adds numberOfActuationsTilt (optional attribute)
        attr_names.includes?("numberOfActuationsTilt").should be_true

        # Position-aware tilt attributes should NOT be present without PositionAwareTilt
        attr_names.includes?("currentPositionTiltPercent100ths").should be_false
      end

      it "includes PositionAwareTilt attributes when both Tilt and PositionAwareTilt enabled" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt |
                       Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareTilt
        )

        attr_names = cluster.attributes.map(&.name)

        # Position-aware tilt attributes should now be present
        attr_names.includes?("currentPositionTiltPercent100ths").should be_true
        attr_names.includes?("targetPositionTiltPercent100ths").should be_true
        attr_names.includes?("currentPositionTiltPercentage").should be_true
      end

      it "includes both Lift and Tilt attributes when both features enabled" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                       Matter::Cluster::WindowCoveringCluster::Feature::Tilt
        )

        attr_names = cluster.attributes.map(&.name)

        # Both feature sets should be present
        attr_names.includes?("numberOfActuationsLift").should be_true
        attr_names.includes?("numberOfActuationsTilt").should be_true
      end
    end

    describe "command composition based on features" do
      it "includes goToLiftPercentage when Lift + PositionAwareLift enabled" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                       Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
        )

        cmd_names = cluster.commands.map(&.name)
        cmd_names.includes?("goToLiftPercentage").should be_true
      end

      it "excludes goToLiftPercentage when only Lift enabled (no PositionAwareLift)" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift
        )

        cmd_names = cluster.commands.map(&.name)
        cmd_names.includes?("goToLiftPercentage").should be_false
      end

      it "includes goToTiltPercentage when Tilt + PositionAwareTilt enabled" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt |
                       Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareTilt
        )

        cmd_names = cluster.commands.map(&.name)
        cmd_names.includes?("goToTiltPercentage").should be_true
      end

      it "excludes goToTiltPercentage when only Tilt enabled (no PositionAwareTilt)" do
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt
        )

        cmd_names = cluster.commands.map(&.name)
        cmd_names.includes?("goToTiltPercentage").should be_false
      end

      it "always includes base commands regardless of features" do
        # With minimal features
        cluster = Matter::Cluster::WindowCoveringCluster.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift
        )

        cmd_names = cluster.commands.map(&.name)

        # Base commands are always present
        cmd_names.includes?("upOrOpen").should be_true
        cmd_names.includes?("downOrClose").should be_true
        cmd_names.includes?("stopMotion").should be_true
      end
    end
  end

  describe "optional vs required element marking" do
    it "marks feature-dependent attributes as optional when feature not enabled" do
      # When only Lift is enabled, lift-specific attributes are present
      # but position-aware attributes are not (they require PositionAwareLift)
      cluster = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
      )

      attrs = cluster.attributes
      attr_map = attrs.index_by(&.name)

      # With PA_LF, currentPositionLiftPercent100ths becomes mandatory (not optional)
      attr_map["currentPositionLiftPercent100ths"].optional?.should be_false

      # numberOfActuationsLift is always optional even with Lift feature
      attr_map["numberOfActuationsLift"].optional?.should be_true

      # currentPositionLiftPercentage is optional even with PA_LF
      attr_map["currentPositionLiftPercentage"].optional?.should be_true
    end

    it "marks commands as mandatory when required by feature combination" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
      )

      cmds = cluster.commands
      cmd_map = cmds.index_by(&.name)

      # goToLiftPercentage is mandatory with LF + PA_LF
      cmd_map["goToLiftPercentage"].optional?.should be_false

      # Base commands are always mandatory
      cmd_map["upOrOpen"].optional?.should be_false
      cmd_map["downOrClose"].optional?.should be_false
      cmd_map["stopMotion"].optional?.should be_false
    end

    it "marks fixed attributes correctly" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16)
      )

      attrs = cluster.attributes
      attr_map = attrs.index_by(&.name)

      # type and endProductType are fixed (read-only constants)
      attr_map["type"].fixed?.should be_true
      attr_map["endProductType"].fixed?.should be_true

      # mode is writable, not fixed
      attr_map["mode"].fixed?.should be_false
      attr_map["mode"].writable?.should be_true
    end
  end

  describe "feature flag behavior" do
    it "feature_map correctly reflects enabled features" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
      )

      # Check individual feature bits
      (cluster.feature_map & Matter::Cluster::WindowCoveringCluster::Feature::Lift).should_not eq(Matter::Cluster::WindowCoveringCluster::Feature::None)
      (cluster.feature_map & Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift).should_not eq(Matter::Cluster::WindowCoveringCluster::Feature::None)
      (cluster.feature_map & Matter::Cluster::WindowCoveringCluster::Feature::Tilt).should eq(Matter::Cluster::WindowCoveringCluster::Feature::None)
    end

    it "default feature map provides sensible defaults" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16)
      )

      # Default is Lift + PositionAwareLift
      cluster.feature_map.should eq(
        Matter::Cluster::WindowCoveringCluster::Feature::Lift |
        Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
      )
    end

    it "feature map is readable via attribute" do
      cluster = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Tilt |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareTilt
      )

      # Tilt (0x02) | PositionAwareTilt (0x10) = 0x12
      read(cluster, Matter::Cluster::Base::GLOBAL_FEATURE_MAP).should eq(0x12)
    end
  end

  describe "element count varies by feature" do
    it "has more attributes with more features enabled" do
      lift_only = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift
      )

      lift_with_position = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
      )

      all_features = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift |
                     Matter::Cluster::WindowCoveringCluster::Feature::Tilt |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareTilt
      )

      # More features = more attributes
      lift_with_position.attributes.size.should be > lift_only.attributes.size
      all_features.attributes.size.should be > lift_with_position.attributes.size
    end

    it "has more commands with position-aware features" do
      lift_only = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift
      )

      lift_with_position = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift |
                     Matter::Cluster::WindowCoveringCluster::Feature::PositionAwareLift
      )

      # Position-aware adds goToLiftPercentage command
      lift_with_position.commands.size.should be > lift_only.commands.size
    end
  end

  describe "base attributes always present" do
    it "includes mandatory base attributes regardless of features" do
      # Even with minimal features, base attributes are present
      cluster = Matter::Cluster::WindowCoveringCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::WindowCoveringCluster::Feature::Lift
      )

      attr_names = cluster.attributes.map(&.name)

      # These are always present per Matter spec
      attr_names.includes?("type").should be_true
      attr_names.includes?("configStatus").should be_true
      attr_names.includes?("operationalStatus").should be_true
      attr_names.includes?("endProductType").should be_true
      attr_names.includes?("mode").should be_true
      attr_names.includes?("featureMap").should be_true
    end
  end
end
