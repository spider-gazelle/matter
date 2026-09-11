require "../spec_helper"
require "../../src/matter/cluster/on_off"

# Tests for OnOff Cluster feature-based composition
# Verifies correct attribute/command inclusion based on feature flags
describe Matter::Cluster::OnOff do
  describe "feature-based composition" do
    describe "base cluster (no features)" do
      it "has base attributes" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::None
        )

        attr_names = cluster.attributes.map(&.name)

        # onOff is a cluster-specific attribute
        attr_names.includes?("onOff").should be_true

        # featureMap and clusterRevision are global attributes (handled by base class)
        # They're accessible via read_attribute, not in the attributes array
        result = cluster.read_attribute(Matter::Cluster::Base::GLOBAL_FEATURE_MAP)
        result.should be_a(TLV::Any)

        result = cluster.read_attribute(Matter::Cluster::Base::GLOBAL_CLUSTER_REVISION)
        result.should be_a(TLV::Any)
      end

      it "does not have Lighting attributes" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::None
        )

        attr_names = cluster.attributes.map(&.name)

        attr_names.includes?("globalSceneControl").should be_false
        attr_names.includes?("onTime").should be_false
        attr_names.includes?("offWaitTime").should be_false
        attr_names.includes?("startUpOnOff").should be_false
      end

      it "has Off, On, and Toggle commands" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::None
        )

        cmd_names = cluster.commands.map(&.name)

        cmd_names.includes?("off").should be_true
        cmd_names.includes?("on").should be_true
        cmd_names.includes?("toggle").should be_true
      end

      it "does not have Lighting commands" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::None
        )

        cmd_names = cluster.commands.map(&.name)

        cmd_names.includes?("offWithEffect").should be_false
        cmd_names.includes?("onWithRecallGlobalScene").should be_false
        cmd_names.includes?("onWithTimedOff").should be_false
      end
    end

    describe "with Lighting feature" do
      it "has Lighting attributes" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::Lighting
        )

        attr_names = cluster.attributes.map(&.name)

        attr_names.includes?("globalSceneControl").should be_true
        attr_names.includes?("onTime").should be_true
        attr_names.includes?("offWaitTime").should be_true
        attr_names.includes?("startUpOnOff").should be_true
      end

      it "has Lighting commands" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::Lighting
        )

        cmd_names = cluster.commands.map(&.name)

        cmd_names.includes?("offWithEffect").should be_true
        cmd_names.includes?("onWithRecallGlobalScene").should be_true
        cmd_names.includes?("onWithTimedOff").should be_true
      end

      it "still has On and Toggle commands" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::Lighting
        )

        cmd_names = cluster.commands.map(&.name)

        cmd_names.includes?("on").should be_true
        cmd_names.includes?("toggle").should be_true
      end
    end

    describe "with OffOnly feature" do
      it "only has Off command" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::OffOnly
        )

        cmd_names = cluster.commands.map(&.name)

        cmd_names.includes?("off").should be_true
        cmd_names.includes?("on").should be_false
        cmd_names.includes?("toggle").should be_false
      end

      it "rejects On command" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::OffOnly
        )

        result = invoke(cluster, Matter::Cluster::OnOff::CMD_ON, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status)
        result.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedCommand)
      end

      it "rejects Toggle command" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::OffOnly
        )

        result = invoke(cluster, Matter::Cluster::OnOff::CMD_TOGGLE, Bytes.new(0))
        result.should be_a(Matter::InteractionModel::Status)
        result.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedCommand)
      end
    end

    describe "with DeadFrontBehavior feature" do
      it "can be combined with Lighting" do
        cluster = Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::Lighting |
                       Matter::Cluster::OnOff::Feature::DeadFrontBehavior
        )

        cluster.feature_map.lighting?.should be_true
        cluster.feature_map.dead_front_behavior?.should be_true
      end
    end
  end

  describe "illegal feature combinations" do
    it "rejects Lighting + OffOnly" do
      expect_raises(ArgumentError, /Lighting and OffOnly features cannot be combined/) do
        Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::Lighting |
                       Matter::Cluster::OnOff::Feature::OffOnly
        )
      end
    end

    it "rejects DeadFrontBehavior + OffOnly" do
      expect_raises(ArgumentError, /DeadFrontBehavior and OffOnly features cannot be combined/) do
        Matter::Cluster::OnOff.new(
          endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
          feature_map: Matter::Cluster::OnOff::Feature::DeadFrontBehavior |
                       Matter::Cluster::OnOff::Feature::OffOnly
        )
      end
    end
  end

  describe "attribute read access" do
    it "returns UnsupportedAttribute for Lighting attrs without feature" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::None
      )

      read_status(cluster, Matter::Cluster::OnOff::ATTR_GLOBAL_SCENE_CONTROL).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
      read_status(cluster, Matter::Cluster::OnOff::ATTR_ON_TIME).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end

    it "can read Lighting attrs with feature enabled" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      result = cluster.read_attribute(Matter::Cluster::OnOff::ATTR_GLOBAL_SCENE_CONTROL)
      result.should be_a(TLV::Any)

      result = cluster.read_attribute(Matter::Cluster::OnOff::ATTR_ON_TIME)
      result.should be_a(TLV::Any)
    end
  end

  describe "attribute write access" do
    it "returns UnsupportedAttribute for Lighting writes without feature" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::None
      )

      result = write(cluster, Matter::Cluster::OnOff::ATTR_ON_TIME, 100_u16)
      result.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end

    it "can write Lighting attrs with feature enabled" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      result = write(cluster, Matter::Cluster::OnOff::ATTR_ON_TIME, 100_u16)
      result.status.should eq(Matter::InteractionModel::StatusCode::Success)

      cluster.on_time.should eq(100_u16)
    end
  end

  describe "command invocation" do
    it "rejects Lighting commands without feature" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::None
      )

      result = invoke(cluster, Matter::Cluster::OnOff::CMD_OFF_WITH_EFFECT, Bytes.new(0))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedCommand)
    end

    it "accepts Lighting commands with feature enabled" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      # Turn on first
      invoke(cluster, Matter::Cluster::OnOff::CMD_ON, Bytes.new(0))
      cluster.on_off?.should be_true

      request = Matter::Cluster::OnOff::OffWithEffectRequest.new(Matter::Cluster::OnOff::EffectIdentifier::DyingLight, 0_u8)
      result = invoke(cluster, Matter::Cluster::OnOff::CMD_OFF_WITH_EFFECT, request)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.on_off?.should be_false
    end
  end

  describe "globalSceneControl behavior" do
    it "sets globalSceneControl to true on On command" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      invoke(cluster, Matter::Cluster::OnOff::CMD_ON, Bytes.new(0))
      cluster.global_scene_control?.should be_true
    end

    it "sets globalSceneControl to false on Off command" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      # Turn on first
      invoke(cluster, Matter::Cluster::OnOff::CMD_ON, Bytes.new(0))

      # Then off
      invoke(cluster, Matter::Cluster::OnOff::CMD_OFF, Bytes.new(0))
      cluster.global_scene_control?.should be_false
    end
  end

  describe "element counts" do
    it "has more attributes with Lighting feature" do
      base = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::None
      )

      lighting = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      lighting.attributes.size.should eq(base.attributes.size + 4)
    end

    it "has more commands with Lighting feature" do
      base = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::None
      )

      lighting = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting
      )

      lighting.commands.size.should eq(base.commands.size + 3)
    end

    it "has fewer commands with OffOnly feature" do
      base = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::None
      )

      off_only = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::OffOnly
      )

      # Base has Off, On, Toggle (3)
      # OffOnly has just Off (1)
      base.commands.size.should eq(3)
      off_only.commands.size.should eq(1)
    end
  end

  describe "feature map" do
    it "returns correct feature map value" do
      cluster = Matter::Cluster::OnOff.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        feature_map: Matter::Cluster::OnOff::Feature::Lighting |
                     Matter::Cluster::OnOff::Feature::DeadFrontBehavior
      )

      # Lighting (0x01) | DeadFrontBehavior (0x02) = 0x03
      cluster.feature_map.value.should eq(0x03_u32)
      cluster.feature_map.lighting?.should be_true
      cluster.feature_map.dead_front_behavior?.should be_true
      cluster.feature_map.off_only?.should be_false
    end
  end
end
