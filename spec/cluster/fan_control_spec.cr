require "../spec_helper"

describe Matter::Cluster::FanControl do
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

  describe "initialization" do
    it "creates with default values (off)" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
      cluster.fan_mode_sequence.should eq(Matter::Cluster::FanControl::FanModeSequence::OffLowMedHigh)
      cluster.percent_setting.should eq(0_u8)
      cluster.percent_current.should eq(0_u8)
    end

    it "creates with custom values" do
      cluster = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControl::FanMode::High,
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowHigh,
        percent_setting: 75_u8,
        percent_current: 75_u8
      )
      cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::High)
      cluster.fan_mode_sequence.should eq(Matter::Cluster::FanControl::FanModeSequence::OffLowHigh)
      cluster.percent_setting.should eq(75_u8)
      cluster.percent_current.should eq(75_u8)
    end

    it "creates with OffLowMedHighAuto sequence" do
      cluster = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControl::FanMode::Auto,
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowMedHighAuto
      )
      cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Auto)
      cluster.fan_mode_sequence.should eq(Matter::Cluster::FanControl::FanModeSequence::OffLowMedHighAuto)
    end

    it "validates percent_setting range" do
      expect_raises(ArgumentError, /percent_setting must be between 0 and 100/) do
        Matter::Cluster::FanControl.new(
          endpoint_id,
          percent_setting: 101_u8
        )
      end
    end

    it "validates percent_current range" do
      expect_raises(ArgumentError, /percent_current must be between 0 and 100/) do
        Matter::Cluster::FanControl.new(
          endpoint_id,
          percent_current: 101_u8
        )
      end
    end

    it "validates fan mode is supported by sequence" do
      expect_raises(ArgumentError, /FanMode Medium not supported/) do
        Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControl::FanMode::Medium,
          fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowHigh
        )
      end
    end

    it "allows Off mode for all sequences" do
      sequences = [
        Matter::Cluster::FanControl::FanModeSequence::OffLowMedHigh,
        Matter::Cluster::FanControl::FanModeSequence::OffLowHigh,
        Matter::Cluster::FanControl::FanModeSequence::OffLowMedHighAuto,
        Matter::Cluster::FanControl::FanModeSequence::OffLowHighAuto,
        Matter::Cluster::FanControl::FanModeSequence::OffHighAuto,
        Matter::Cluster::FanControl::FanModeSequence::OffHigh,
      ]

      sequences.each do |sequence|
        cluster = Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControl::FanMode::Off,
          fan_mode_sequence: sequence
        )
        cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
      end
    end
  end

  describe "attributes" do
    it "has required attributes including speed" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      attrs = cluster.attributes
      attrs.size.should eq(7)
      attrs.map(&.name).should contain("fanMode")
      attrs.map(&.name).should contain("fanModeSequence")
      attrs.map(&.name).should contain("percentSetting")
      attrs.map(&.name).should contain("percentCurrent")
      attrs.map(&.name).should contain("speedMax")
      attrs.map(&.name).should contain("speedSetting")
      attrs.map(&.name).should contain("speedCurrent")
    end

    it "reads FanMode" do
      cluster = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControl::FanMode::High
      )
      read(cluster, Matter::Cluster::FanControl::ATTR_FAN_MODE).should eq(3_u8) # High = 3
    end

    it "reads FanModeSequence" do
      cluster = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowHigh
      )
      read(cluster, Matter::Cluster::FanControl::ATTR_FAN_MODE_SEQUENCE).should eq(1_u8) # OffLowHigh = 1
    end

    it "reads PercentSetting" do
      cluster = Matter::Cluster::FanControl.new(
        endpoint_id,
        percent_setting: 50_u8
      )
      read(cluster, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING).should eq(50_u8)
    end

    it "reads PercentCurrent" do
      cluster = Matter::Cluster::FanControl.new(
        endpoint_id,
        percent_current: 75_u8
      )
      read(cluster, Matter::Cluster::FanControl::ATTR_PERCENT_CURRENT).should eq(75_u8)
    end

    it "marks fanMode as writable" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      attr = cluster.attributes.find { |attribute| attribute.name == "fanMode" }
      attr.should_not be_nil
      attr.as(Matter::Cluster::AttributeMetadata).writable?.should be_true
    end

    it "marks percentSetting as writable" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      attr = cluster.attributes.find { |attribute| attribute.name == "percentSetting" }
      attr.should_not be_nil
      attr.as(Matter::Cluster::AttributeMetadata).writable?.should be_true
    end
  end

  describe "write_attribute" do
    describe "FanMode" do
      it "writes valid fan mode" do
        cluster = Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControl::FanMode::Off
        )

        status = write(cluster,
          Matter::Cluster::FanControl::ATTR_FAN_MODE,
          1_u8 # Low
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Low)
      end

      it "rejects unsupported fan mode for sequence" do
        cluster = Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowHigh
        )

        status = write(cluster,
          Matter::Cluster::FanControl::ATTR_FAN_MODE,
          2_u8 # Medium - not supported
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
        cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off) # Unchanged
      end

      it "rejects invalid fan mode value" do
        cluster = Matter::Cluster::FanControl.new(endpoint_id)

        status = write(cluster,
          Matter::Cluster::FanControl::ATTR_FAN_MODE,
          7_u8 # Invalid value
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end

      it "sets percent to 0 when fan mode changes to Off" do
        cluster = Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControl::FanMode::High,
          percent_setting: 75_u8,
          percent_current: 75_u8
        )

        write(cluster,
          Matter::Cluster::FanControl::ATTR_FAN_MODE,
          0_u8 # Off
        )
        cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
        cluster.percent_setting.should eq(0_u8)
        cluster.percent_current.should eq(0_u8)
      end

      it "calls callback when fan mode changes" do
        cluster = Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControl::FanMode::Off
        )

        old_mode = nil.as(Matter::Cluster::FanControl::FanMode?)
        new_mode = nil.as(Matter::Cluster::FanControl::FanMode?)
        cluster.on_fan_mode_changed do |old, new|
          old_mode = old
          new_mode = new
        end

        write(cluster,
          Matter::Cluster::FanControl::ATTR_FAN_MODE,
          1_u8 # Low
        )
        old_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
        new_mode.should eq(Matter::Cluster::FanControl::FanMode::Low)
      end
    end

    describe "PercentSetting" do
      it "writes valid percent setting" do
        cluster = Matter::Cluster::FanControl.new(endpoint_id)

        status = write(cluster,
          Matter::Cluster::FanControl::ATTR_PERCENT_SETTING,
          50_u8
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.percent_setting.should eq(50_u8)
        cluster.percent_current.should eq(50_u8)
      end

      it "rejects percent setting > 100" do
        cluster = Matter::Cluster::FanControl.new(endpoint_id)

        status = write(cluster,
          Matter::Cluster::FanControl::ATTR_PERCENT_SETTING,
          101_u8
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end

      it "sets fan mode to Off when percent is 0" do
        cluster = Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControl::FanMode::High,
          percent_setting: 75_u8
        )

        write(cluster,
          Matter::Cluster::FanControl::ATTR_PERCENT_SETTING,
          0_u8
        )
        cluster.percent_setting.should eq(0_u8)
        cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
      end

      it "turns fan on when setting non-zero percent from Off" do
        cluster = Matter::Cluster::FanControl.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControl::FanMode::Off
        )

        write(cluster,
          Matter::Cluster::FanControl::ATTR_PERCENT_SETTING,
          50_u8
        )
        cluster.percent_setting.should eq(50_u8)
        cluster.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Low)
      end

      it "calls callback when percent changes" do
        cluster = Matter::Cluster::FanControl.new(endpoint_id)

        old_percent = nil.as(UInt8??)
        new_percent = nil.as(UInt8?)
        cluster.on_percent_changed do |old, new|
          old_percent = old
          new_percent = new
        end

        write(cluster,
          Matter::Cluster::FanControl::ATTR_PERCENT_SETTING,
          50_u8
        )
        old_percent.should eq(0_u8)
        new_percent.should eq(50_u8)
      end
    end

    it "returns error for read-only attributes" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      status = write(cluster,
        Matter::Cluster::FanControl::ATTR_FAN_MODE_SEQUENCE,
        1_u8
      )
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end

    it "returns error for unsupported attributes" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      status = write(cluster, 0x9999_u32, 1_u8)
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "update_percent_current" do
    it "updates percent current" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      cluster.update_percent_current(75_u8)
      cluster.percent_current.should eq(75_u8)
    end

    it "validates range" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      expect_raises(ArgumentError, /percent_current must be between 0 and 100/) do
        cluster.update_percent_current(101_u8)
      end
    end

    it "increments data version on change" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      initial_version = cluster.data_version
      cluster.update_percent_current(50_u8)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "doesn't increment version if value unchanged" do
      cluster = Matter::Cluster::FanControl.new(
        endpoint_id,
        percent_current: 50_u8
      )
      initial_version = cluster.data_version
      cluster.update_percent_current(50_u8)
      cluster.data_version.should eq(initial_version)
    end
  end

  describe "practical scenarios" do
    it "models a basic ceiling fan with three speeds" do
      # Ceiling fan with Off, Low, Medium, High
      fan = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControl::FanMode::Off,
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowMedHigh
      )

      # Turn on to low speed
      write(fan,
        Matter::Cluster::FanControl::ATTR_FAN_MODE,
        1_u8 # Low
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Low)

      # Increase to medium
      write(fan,
        Matter::Cluster::FanControl::ATTR_FAN_MODE,
        2_u8 # Medium
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Medium)

      # Increase to high
      write(fan,
        Matter::Cluster::FanControl::ATTR_FAN_MODE,
        3_u8 # High
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::High)

      # Turn off
      write(fan,
        Matter::Cluster::FanControl::ATTR_FAN_MODE,
        0_u8 # Off
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
    end

    it "models a simple two-speed fan" do
      # Fan with Off, Low, High only
      fan = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowHigh
      )

      # Can use Low and High
      write(fan, Matter::Cluster::FanControl::ATTR_FAN_MODE, 1_u8) # Low
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Low)

      write(fan, Matter::Cluster::FanControl::ATTR_FAN_MODE, 3_u8) # High
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::High)

      # Cannot use Medium
      status = write(fan, Matter::Cluster::FanControl::ATTR_FAN_MODE, 2_u8)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
    end

    it "models a smart fan with automatic mode" do
      # Fan with Auto mode support
      fan = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowMedHighAuto
      )

      # Set to Auto mode
      write(fan,
        Matter::Cluster::FanControl::ATTR_FAN_MODE,
        5_u8 # Auto
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Auto)
    end

    it "syncs speed and percent when writing percent" do
      fan = Matter::Cluster::FanControl.new(
        endpoint_id,
        speed_max: 4_u8
      )

      write(fan, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, 50_u8)
      fan.percent_setting.should eq(50_u8)
      fan.speed_setting.should eq(2_u8)
      fan.speed_current.should eq(2_u8)

      write(fan, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, 100_u8)
      fan.speed_setting.should eq(4_u8)
    end

    it "syncs percent and speed when writing speed" do
      fan = Matter::Cluster::FanControl.new(
        endpoint_id,
        speed_max: 4_u8
      )

      write(fan, Matter::Cluster::FanControl::ATTR_SPEED_SETTING, 3_u8)
      fan.speed_setting.should eq(3_u8)
      fan.percent_setting.should eq(75_u8)
      fan.percent_current.should eq(75_u8)

      write(fan, Matter::Cluster::FanControl::ATTR_SPEED_SETTING, 0_u8)
      fan.percent_setting.should eq(0_u8)
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
    end

    it "fires percent callback when speed is written" do
      fan = Matter::Cluster::FanControl.new(
        endpoint_id,
        speed_max: 4_u8
      )

      received_percent = nil.as(UInt8?)
      fan.on_percent_changed do |_old, new_val|
        received_percent = new_val
      end

      write(fan, Matter::Cluster::FanControl::ATTR_SPEED_SETTING, 2_u8)
      received_percent.should eq(50_u8)
    end

    it "fires speed callback when percent is written" do
      fan = Matter::Cluster::FanControl.new(
        endpoint_id,
        speed_max: 4_u8
      )

      received_speed = nil.as(UInt8?)
      fan.on_speed_changed do |_old, new_val|
        received_speed = new_val
      end

      write(fan, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, 75_u8)
      received_speed.should eq(3_u8)
    end

    it "models percent-based speed control" do
      # Fan controlled by percentage
      fan = Matter::Cluster::FanControl.new(endpoint_id)

      # Set to 25% speed
      write(fan, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, 25_u8)
      fan.percent_setting.should eq(25_u8)
      fan.percent_current.should eq(25_u8)

      # Increase to 75%
      write(fan, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, 75_u8)
      fan.percent_setting.should eq(75_u8)

      # Turn off via percent
      write(fan, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, 0_u8)
      fan.percent_setting.should eq(0_u8)
      fan.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::Off)
    end

    it "tracks state changes with callbacks" do
      fan = Matter::Cluster::FanControl.new(endpoint_id)

      mode_changes = [] of String
      fan.on_fan_mode_changed do |old, new|
        mode_changes << "#{old} -> #{new}"
      end

      percent_changes = [] of String
      fan.on_percent_changed do |old, new|
        percent_changes << "#{old} -> #{new}"
      end

      # Multiple state changes
      write(fan, Matter::Cluster::FanControl::ATTR_FAN_MODE, 1_u8) # Low
      write(fan, Matter::Cluster::FanControl::ATTR_PERCENT_SETTING, 50_u8)
      write(fan, Matter::Cluster::FanControl::ATTR_FAN_MODE, 3_u8) # High
      write(fan, Matter::Cluster::FanControl::ATTR_FAN_MODE, 0_u8) # Off

      mode_changes.should eq([
        "Off -> Low",
        "Low -> High",
        "High -> Off",
      ])

      percent_changes.size.should eq(2)
    end

    it "models an air purifier with fan control" do
      # Air purifier from the behavioral test
      air_purifier = Matter::Cluster::FanControl.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControl::FanMode::On, # Deprecated but supported
        fan_mode_sequence: Matter::Cluster::FanControl::FanModeSequence::OffLowMedHigh,
        percent_setting: 50_u8,
        percent_current: 50_u8
      )

      air_purifier.fan_mode.should eq(Matter::Cluster::FanControl::FanMode::On)
      air_purifier.percent_setting.should eq(50_u8)
      air_purifier.percent_current.should eq(50_u8)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute reads" do
      cluster = Matter::Cluster::FanControl.new(endpoint_id)
      read_status(cluster, 0x9999_u32).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end
end
