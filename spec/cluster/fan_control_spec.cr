require "../spec_helper"

describe Matter::Cluster::FanControlCluster do
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

  describe "initialization" do
    it "creates with default values (off)" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
      cluster.fan_mode_sequence.should eq(Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHigh)
      cluster.percent_setting.should eq(0_u8)
      cluster.percent_current.should eq(0_u8)
    end

    it "creates with custom values" do
      cluster = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControlCluster::FanMode::High,
        fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHigh,
        percent_setting: 75_u8,
        percent_current: 75_u8
      )
      cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::High)
      cluster.fan_mode_sequence.should eq(Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHigh)
      cluster.percent_setting.should eq(75_u8)
      cluster.percent_current.should eq(75_u8)
    end

    it "creates with OffLowMedHighAuto sequence" do
      cluster = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControlCluster::FanMode::Auto,
        fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHighAuto
      )
      cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Auto)
      cluster.fan_mode_sequence.should eq(Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHighAuto)
    end

    it "validates percent_setting range" do
      expect_raises(ArgumentError, /percent_setting must be between 0 and 100/) do
        Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          percent_setting: 101_u8
        )
      end
    end

    it "validates percent_current range" do
      expect_raises(ArgumentError, /percent_current must be between 0 and 100/) do
        Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          percent_current: 101_u8
        )
      end
    end

    it "validates fan mode is supported by sequence" do
      expect_raises(ArgumentError, /FanMode Medium not supported/) do
        Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControlCluster::FanMode::Medium,
          fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHigh
        )
      end
    end

    it "allows Off mode for all sequences" do
      sequences = [
        Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHigh,
        Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHigh,
        Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHighAuto,
        Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHighAuto,
        Matter::Cluster::FanControlCluster::FanModeSequence::OffHighAuto,
        Matter::Cluster::FanControlCluster::FanModeSequence::OffHigh,
      ]

      sequences.each do |sequence|
        cluster = Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off,
          fan_mode_sequence: sequence
        )
        cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
      end
    end
  end

  describe "attributes" do
    it "has required attributes including speed" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
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
      cluster = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControlCluster::FanMode::High
      )
      bytes = cluster.read_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE)
      bytes.should be_a(Bytes)
      decode_tlv_value(bytes.as(Bytes)).should eq(3_u8) # High = 3
    end

    it "reads FanModeSequence" do
      cluster = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHigh
      )
      bytes = cluster.read_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE_SEQUENCE)
      bytes.should be_a(Bytes)
      decode_tlv_value(bytes.as(Bytes)).should eq(1_u8) # OffLowHigh = 1
    end

    it "reads PercentSetting" do
      cluster = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        percent_setting: 50_u8
      )
      bytes = cluster.read_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING)
      bytes.should be_a(Bytes)
      decode_tlv_value(bytes.as(Bytes)).should eq(50_u8)
    end

    it "reads PercentCurrent" do
      cluster = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        percent_current: 75_u8
      )
      bytes = cluster.read_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_CURRENT)
      bytes.should be_a(Bytes)
      decode_tlv_value(bytes.as(Bytes)).should eq(75_u8)
    end

    it "marks fanMode as writable" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      attr = cluster.attributes.find { |attribute| attribute.name == "fanMode" }
      attr.should_not be_nil
      attr.as(Matter::Cluster::AttributeMetadata).writable?.should be_true
    end

    it "marks percentSetting as writable" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      attr = cluster.attributes.find { |attribute| attribute.name == "percentSetting" }
      attr.should_not be_nil
      attr.as(Matter::Cluster::AttributeMetadata).writable?.should be_true
    end
  end

  describe "write_attribute" do
    describe "FanMode" do
      it "writes valid fan mode" do
        cluster = Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off
        )

        status = cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
          Bytes[1] # Low
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Low)
      end

      it "rejects unsupported fan mode for sequence" do
        cluster = Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHigh
        )

        status = cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
          Bytes[2] # Medium - not supported
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
        cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off) # Unchanged
      end

      it "rejects invalid fan mode value" do
        cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)

        status = cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
          Bytes[7] # Invalid value
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end

      it "sets percent to 0 when fan mode changes to Off" do
        cluster = Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControlCluster::FanMode::High,
          percent_setting: 75_u8,
          percent_current: 75_u8
        )

        cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
          Bytes[0] # Off
        )
        cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
        cluster.percent_setting.should eq(0_u8)
        cluster.percent_current.should eq(0_u8)
      end

      it "calls callback when fan mode changes" do
        cluster = Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off
        )

        old_mode = nil.as(Matter::Cluster::FanControlCluster::FanMode?)
        new_mode = nil.as(Matter::Cluster::FanControlCluster::FanMode?)
        cluster.on_fan_mode_changed do |old, new|
          old_mode = old
          new_mode = new
        end

        cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
          Bytes[1] # Low
        )
        old_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
        new_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Low)
      end
    end

    describe "PercentSetting" do
      it "writes valid percent setting" do
        cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)

        status = cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING,
          Bytes[50]
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.percent_setting.should eq(50_u8)
        cluster.percent_current.should eq(50_u8)
      end

      it "rejects percent setting > 100" do
        cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)

        status = cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING,
          Bytes[101]
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end

      it "sets fan mode to Off when percent is 0" do
        cluster = Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControlCluster::FanMode::High,
          percent_setting: 75_u8
        )

        cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING,
          Bytes[0]
        )
        cluster.percent_setting.should eq(0_u8)
        cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
      end

      it "turns fan on when setting non-zero percent from Off" do
        cluster = Matter::Cluster::FanControlCluster.new(
          endpoint_id,
          fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off
        )

        cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING,
          Bytes[50]
        )
        cluster.percent_setting.should eq(50_u8)
        cluster.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Low)
      end

      it "calls callback when percent changes" do
        cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)

        old_percent = nil.as(UInt8??)
        new_percent = nil.as(UInt8?)
        cluster.on_percent_changed do |old, new|
          old_percent = old
          new_percent = new
        end

        cluster.write_attribute(
          Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING,
          Bytes[50]
        )
        old_percent.should eq(0_u8)
        new_percent.should eq(50_u8)
      end
    end

    it "returns error for read-only attributes" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      status = cluster.write_attribute(
        Matter::Cluster::FanControlCluster::ATTR_FAN_MODE_SEQUENCE,
        Bytes[1]
      )
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end

    it "returns error for unsupported attributes" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      status = cluster.write_attribute(0x9999_u32, Bytes[1])
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "update_percent_current" do
    it "updates percent current" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      cluster.update_percent_current(75_u8)
      cluster.percent_current.should eq(75_u8)
    end

    it "validates range" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      expect_raises(ArgumentError, /percent_current must be between 0 and 100/) do
        cluster.update_percent_current(101_u8)
      end
    end

    it "increments data version on change" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      initial_version = cluster.data_version
      cluster.update_percent_current(50_u8)
      cluster.data_version.should eq(initial_version + 1)
    end

    it "doesn't increment version if value unchanged" do
      cluster = Matter::Cluster::FanControlCluster.new(
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
      fan = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControlCluster::FanMode::Off,
        fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHigh
      )

      # Turn on to low speed
      fan.write_attribute(
        Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
        Bytes[1] # Low
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Low)

      # Increase to medium
      fan.write_attribute(
        Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
        Bytes[2] # Medium
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Medium)

      # Increase to high
      fan.write_attribute(
        Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
        Bytes[3] # High
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::High)

      # Turn off
      fan.write_attribute(
        Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
        Bytes[0] # Off
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
    end

    it "models a simple two-speed fan" do
      # Fan with Off, Low, High only
      fan = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowHigh
      )

      # Can use Low and High
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE, Bytes[1]) # Low
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Low)

      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE, Bytes[3]) # High
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::High)

      # Cannot use Medium
      status = fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE, Bytes[2])
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
    end

    it "models a smart fan with automatic mode" do
      # Fan with Auto mode support
      fan = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHighAuto
      )

      # Set to Auto mode
      fan.write_attribute(
        Matter::Cluster::FanControlCluster::ATTR_FAN_MODE,
        Bytes[5] # Auto
      )
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Auto)
    end

    it "syncs speed and percent when writing percent" do
      fan = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        speed_max: 4_u8
      )

      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING, Bytes[50])
      fan.percent_setting.should eq(50_u8)
      fan.speed_setting.should eq(2_u8)
      fan.speed_current.should eq(2_u8)

      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING, Bytes[100])
      fan.speed_setting.should eq(4_u8)
    end

    it "syncs percent and speed when writing speed" do
      fan = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        speed_max: 4_u8
      )

      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_SPEED_SETTING, Bytes[3])
      fan.speed_setting.should eq(3_u8)
      fan.percent_setting.should eq(75_u8)
      fan.percent_current.should eq(75_u8)

      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_SPEED_SETTING, Bytes[0])
      fan.percent_setting.should eq(0_u8)
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
    end

    it "fires percent callback when speed is written" do
      fan = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        speed_max: 4_u8
      )

      received_percent = nil.as(UInt8?)
      fan.on_percent_changed do |_old, new_val|
        received_percent = new_val
      end

      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_SPEED_SETTING, Bytes[2])
      received_percent.should eq(50_u8)
    end

    it "fires speed callback when percent is written" do
      fan = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        speed_max: 4_u8
      )

      received_speed = nil.as(UInt8?)
      fan.on_speed_changed do |_old, new_val|
        received_speed = new_val
      end

      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING, Bytes[75])
      received_speed.should eq(3_u8)
    end

    it "models percent-based speed control" do
      # Fan controlled by percentage
      fan = Matter::Cluster::FanControlCluster.new(endpoint_id)

      # Set to 25% speed
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING, Bytes[25])
      fan.percent_setting.should eq(25_u8)
      fan.percent_current.should eq(25_u8)

      # Increase to 75%
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING, Bytes[75])
      fan.percent_setting.should eq(75_u8)

      # Turn off via percent
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING, Bytes[0])
      fan.percent_setting.should eq(0_u8)
      fan.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::Off)
    end

    it "tracks state changes with callbacks" do
      fan = Matter::Cluster::FanControlCluster.new(endpoint_id)

      mode_changes = [] of String
      fan.on_fan_mode_changed do |old, new|
        mode_changes << "#{old} -> #{new}"
      end

      percent_changes = [] of String
      fan.on_percent_changed do |old, new|
        percent_changes << "#{old} -> #{new}"
      end

      # Multiple state changes
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE, Bytes[1]) # Low
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_PERCENT_SETTING, Bytes[50])
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE, Bytes[3]) # High
      fan.write_attribute(Matter::Cluster::FanControlCluster::ATTR_FAN_MODE, Bytes[0]) # Off

      mode_changes.should eq([
        "Off -> Low",
        "Low -> High",
        "High -> Off",
      ])

      percent_changes.size.should eq(2)
    end

    it "models an air purifier with fan control" do
      # Air purifier from the behavioral test
      air_purifier = Matter::Cluster::FanControlCluster.new(
        endpoint_id,
        fan_mode: Matter::Cluster::FanControlCluster::FanMode::On, # Deprecated but supported
        fan_mode_sequence: Matter::Cluster::FanControlCluster::FanModeSequence::OffLowMedHigh,
        percent_setting: 50_u8,
        percent_current: 50_u8
      )

      air_purifier.fan_mode.should eq(Matter::Cluster::FanControlCluster::FanMode::On)
      air_purifier.percent_setting.should eq(50_u8)
      air_purifier.percent_current.should eq(50_u8)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute reads" do
      cluster = Matter::Cluster::FanControlCluster.new(endpoint_id)
      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end
end
