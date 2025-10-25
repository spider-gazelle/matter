require "../spec_helper"

describe Matter::Cluster::PowerSourceCluster do
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

  describe "initialization" do
    it "creates with default values" do
      cluster = Matter::Cluster::PowerSourceCluster.new(endpoint_id)
      cluster.status.should eq(Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active)
      cluster.order.should eq(0_u8)
      cluster.description.should eq("Battery")
      cluster.bat_charge_level.should be_nil
      cluster.bat_replacement_needed.should be_nil
      cluster.bat_replaceability.should be_nil
      cluster.bat_replacement_description.should be_nil
      cluster.bat_quantity.should be_nil
      cluster.battery_feature_enabled?.should be_false
      cluster.replaceable_feature_enabled?.should be_false
    end

    it "creates with Battery feature (from matter.js test)" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        status: Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active,
        order: 1_u8,
        description: "aa batteries",
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )
      cluster.status.should eq(Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active)
      cluster.order.should eq(1_u8)
      cluster.description.should eq("aa batteries")
      cluster.bat_charge_level.should eq(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok)
      cluster.bat_replacement_needed.should be_false
      cluster.bat_replaceability.should eq(Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable)
      cluster.battery_feature_enabled?.should be_true
    end

    it "creates with Replaceable feature (from matter.js test)" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        status: Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active,
        order: 1_u8,
        description: "aa batteries",
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
        bat_replacement_description: "open, replace",
        bat_quantity: 2_u8
      )
      cluster.bat_replacement_description.should eq("open, replace")
      cluster.bat_quantity.should eq(2_u8)
      cluster.battery_feature_enabled?.should be_true
      cluster.replaceable_feature_enabled?.should be_true
    end

    it "validates description length" do
      expect_raises(ArgumentError, /description must be <= 60 characters/) do
        Matter::Cluster::PowerSourceCluster.new(
          endpoint_id,
          description: "a" * 61
        )
      end
    end

    it "validates bat_replacement_description length" do
      expect_raises(ArgumentError, /bat_replacement_description must be <= 60 characters/) do
        Matter::Cluster::PowerSourceCluster.new(
          endpoint_id,
          bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
          bat_replacement_needed: false,
          bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
          bat_replacement_description: "a" * 61,
          bat_quantity: 2_u8
        )
      end
    end

    it "validates Battery feature completeness" do
      expect_raises(ArgumentError, /Battery feature requires/) do
        Matter::Cluster::PowerSourceCluster.new(
          endpoint_id,
          bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok
          # Missing bat_replacement_needed and bat_replaceability
        )
      end
    end

    it "validates Replaceable feature completeness" do
      expect_raises(ArgumentError, /Replaceable feature requires/) do
        Matter::Cluster::PowerSourceCluster.new(
          endpoint_id,
          bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
          bat_replacement_needed: false,
          bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
          bat_replacement_description: "open, replace"
          # Missing bat_quantity
        )
      end
    end
  end

  describe "attributes" do
    it "has base attributes" do
      cluster = Matter::Cluster::PowerSourceCluster.new(endpoint_id)
      attrs = cluster.attributes
      attrs.size.should eq(3)
      attrs.map(&.name).should contain("Status")
      attrs.map(&.name).should contain("Order")
      attrs.map(&.name).should contain("Description")
    end

    it "has Battery feature attributes when enabled" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )
      attrs = cluster.attributes
      attrs.size.should eq(6)
      attrs.map(&.name).should contain("BatChargeLevel")
      attrs.map(&.name).should contain("BatReplacementNeeded")
      attrs.map(&.name).should contain("BatReplaceability")
    end

    it "has Replaceable feature attributes when enabled" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
        bat_replacement_description: "open, replace",
        bat_quantity: 2_u8
      )
      attrs = cluster.attributes
      attrs.size.should eq(8)
      attrs.map(&.name).should contain("BatReplacementDescription")
      attrs.map(&.name).should contain("BatQuantity")
    end

    it "reads Status" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        status: Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Standby
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_STATUS)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[2]) # Standby = 2
    end

    it "reads Order" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        order: 5_u8
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_ORDER)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[5])
    end

    it "reads Description" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        description: "DC Power"
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_DESCRIPTION)
      bytes.should be_a(Bytes)
      # String encoding: [length, ...bytes]
      bytes.as(Bytes)[0].should eq(8) # "DC Power" length
    end

    it "reads BatChargeLevel when Battery feature enabled" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Warning,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_BAT_CHARGE_LEVEL)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[1]) # Warning = 1
    end

    it "reads BatReplacementNeeded" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: true,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_BAT_REPLACEMENT_NEEDED)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[1]) # true = 1
    end

    it "reads BatReplaceability" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::FactoryReplaceable
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_BAT_REPLACEABILITY)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[3]) # FactoryReplaceable = 3
    end

    it "reads BatReplacementDescription when Replaceable feature enabled" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
        bat_replacement_description: "2x AA",
        bat_quantity: 2_u8
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_BAT_REPLACEMENT_DESCRIPTION)
      bytes.should be_a(Bytes)
      bytes.as(Bytes)[0].should eq(5) # "2x AA" length
    end

    it "reads BatQuantity" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
        bat_replacement_description: "2x AA",
        bat_quantity: 2_u8
      )
      bytes = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_BAT_QUANTITY)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[2])
    end

    it "returns unsupported for Battery attributes when feature not enabled" do
      cluster = Matter::Cluster::PowerSourceCluster.new(endpoint_id)
      result = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_BAT_CHARGE_LEVEL)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end

    it "returns unsupported for Replaceable attributes when feature not enabled" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )
      result = cluster.read_attribute(Matter::Cluster::PowerSourceCluster::ATTR_BAT_REPLACEMENT_DESCRIPTION)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "update methods" do
    it "updates battery charge level" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      cluster.update_bat_charge_level(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Warning)
      cluster.bat_charge_level.should eq(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Warning)
    end

    it "calls callback when charge level changes" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      old_level = nil.as(Matter::Cluster::PowerSourceCluster::BatChargeLevel??)
      new_level = nil.as(Matter::Cluster::PowerSourceCluster::BatChargeLevel?)
      cluster.on_charge_level_changed do |old, new|
        old_level = old
        new_level = new
      end

      cluster.update_bat_charge_level(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Critical)
      old_level.should eq(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok)
      new_level.should eq(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Critical)
    end

    it "updates battery replacement needed" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      cluster.update_bat_replacement_needed(true)
      cluster.bat_replacement_needed.should be_true
    end

    it "calls callback when replacement needed changes" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      old_needed = nil.as(Bool??)
      new_needed = nil.as(Bool?)
      cluster.on_replacement_needed_changed do |old, new|
        old_needed = old
        new_needed = new
      end

      cluster.update_bat_replacement_needed(true)
      old_needed.should be_false
      new_needed.should be_true
    end

    it "increments data version on change" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      initial_version = cluster.data_version
      cluster.update_bat_charge_level(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Warning)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "doesn't increment version if value unchanged" do
      cluster = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      initial_version = cluster.data_version
      cluster.update_bat_charge_level(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok)
      cluster.data_version.should eq(initial_version)
    end
  end

  describe "practical scenarios" do
    it "models AA battery powered sensor (from matter.js test)" do
      sensor = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        status: Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active,
        order: 1_u8,
        description: "aa batteries",
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
        bat_replacement_description: "open, replace",
        bat_quantity: 2_u8
      )

      sensor.battery_feature_enabled?.should be_true
      sensor.replaceable_feature_enabled?.should be_true
      sensor.status.should eq(Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active)
      sensor.bat_quantity.should eq(2_u8)
    end

    it "models rechargeable battery device" do
      device = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        status: Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active,
        order: 0_u8,
        description: "Lithium-ion battery",
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::NotReplaceable
      )

      device.bat_replaceability.should eq(Matter::Cluster::PowerSourceCluster::BatReplaceability::NotReplaceable)
    end

    it "models battery monitoring with charge level changes" do
      monitor = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      changes = [] of String
      monitor.on_charge_level_changed do |old, new|
        changes << "#{old} -> #{new}"
      end

      # Battery drains over time
      monitor.update_bat_charge_level(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Warning)
      monitor.update_bat_charge_level(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Critical)

      changes.should eq([
        "Ok -> Warning",
        "Warning -> Critical",
      ])
    end

    it "models battery replacement workflow" do
      device = Matter::Cluster::PowerSourceCluster.new(
        endpoint_id,
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Critical,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable,
        bat_replacement_description: "Replace with 2x AA alkaline",
        bat_quantity: 2_u8
      )

      # Mark battery for replacement
      device.update_bat_replacement_needed(true)
      device.bat_replacement_needed.should be_true
      device.bat_replacement_description.should eq("Replace with 2x AA alkaline")

      # After replacement (simulated by creating new state)
      device.update_bat_charge_level(Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok)
      device.update_bat_replacement_needed(false)
      device.bat_replacement_needed.should be_false
    end

    it "models device with primary and backup batteries" do
      # Primary battery (order 0 - preferred)
      primary = Matter::Cluster::PowerSourceCluster.new(
        Matter::DataType::EndpointNumber.new(1_u16),
        status: Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active,
        order: 0_u8,
        description: "Primary battery",
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      # Backup battery (order 1 - fallback)
      backup = Matter::Cluster::PowerSourceCluster.new(
        Matter::DataType::EndpointNumber.new(2_u16),
        status: Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Standby,
        order: 1_u8,
        description: "Backup battery",
        bat_charge_level: Matter::Cluster::PowerSourceCluster::BatChargeLevel::Ok,
        bat_replacement_needed: false,
        bat_replaceability: Matter::Cluster::PowerSourceCluster::BatReplaceability::UserReplaceable
      )

      primary.order.should be < backup.order
      primary.status.should eq(Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Active)
      backup.status.should eq(Matter::Cluster::PowerSourceCluster::PowerSourceStatus::Standby)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute reads" do
      cluster = Matter::Cluster::PowerSourceCluster.new(endpoint_id)
      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end
end
