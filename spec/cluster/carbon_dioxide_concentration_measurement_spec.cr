require "../spec_helper"
require "../../src/matter/cluster/carbon_dioxide_concentration_measurement"

describe Matter::Cluster::CarbonDioxideConcentrationMeasurement do
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

  describe "initialization" do
    it "creates with NumericMeasurement feature" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      sensor.name.should eq("CarbonDioxideConcentrationMeasurement")
      sensor.numeric_measurement_enabled?.should be_true
      sensor.level_indication_enabled?.should be_false
      sensor.measured_value.should eq(400.0_f32)
      sensor.min_measured_value.should eq(0.0_f32)
      sensor.max_measured_value.should eq(5000.0_f32)
      sensor.measurement_unit.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm)
    end

    it "creates with LevelIndication feature" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      sensor.numeric_measurement_enabled?.should be_false
      sensor.level_indication_enabled?.should be_true
      sensor.level_value.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low)
    end

    it "creates with both NumericMeasurement and LevelIndication features (from matter.js test)" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 4.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 10000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::High
      )

      sensor.numeric_measurement_enabled?.should be_true
      sensor.level_indication_enabled?.should be_true
      sensor.measured_value.should eq(4.0_f32)
      sensor.level_value.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::High)
    end

    it "creates with PeakMeasurement feature" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        peak_measured_value: 500.0_f32,
        peak_measured_value_window: 3600_u32
      )

      sensor.peak_measurement_enabled?.should be_true
      sensor.peak_measured_value.should eq(500.0_f32)
      sensor.peak_measured_value_window.should eq(3600_u32)
    end

    it "creates with AverageMeasurement feature" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        average_measured_value: 380.0_f32,
        average_measured_value_window: 3600_u32
      )

      sensor.average_measurement_enabled?.should be_true
      sensor.average_measured_value.should eq(380.0_f32)
      sensor.average_measured_value_window.should eq(3600_u32)
    end

    it "validates NumericMeasurement feature requires all mandatory attributes" do
      expect_raises(ArgumentError, /NumericMeasurement feature requires/) do
        Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
          endpoint_id,
          measured_value: 400.0_f32 # Missing min, max, and unit
        )
      end
    end

    it "validates PeakMeasurement requires both attributes" do
      expect_raises(ArgumentError, /PeakMeasurement feature requires peak_measured_value_window/) do
        Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
          endpoint_id,
          measured_value: 400.0_f32,
          min_measured_value: 0.0_f32,
          max_measured_value: 5000.0_f32,
          measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
          peak_measured_value: 500.0_f32 # Missing window
        )
      end
    end

    it "validates AverageMeasurement requires both attributes" do
      expect_raises(ArgumentError, /AverageMeasurement feature requires average_measured_value_window/) do
        Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
          endpoint_id,
          measured_value: 400.0_f32,
          min_measured_value: 0.0_f32,
          max_measured_value: 5000.0_f32,
          measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
          average_measured_value: 380.0_f32 # Missing window
        )
      end
    end

    it "validates peak measurement window max value" do
      expect_raises(ArgumentError, /peak_measured_value_window must be <= 604800/) do
        Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
          endpoint_id,
          measured_value: 400.0_f32,
          min_measured_value: 0.0_f32,
          max_measured_value: 5000.0_f32,
          measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
          peak_measured_value: 500.0_f32,
          peak_measured_value_window: 700000_u32 # > 604800 (7 days)
        )
      end
    end

    it "validates at least one feature must be enabled" do
      expect_raises(ArgumentError, /At least one feature/) do
        Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
          endpoint_id
        )
      end
    end
  end

  describe "attributes" do
    it "has measurement medium attribute" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      attrs = sensor.attributes
      attrs.map(&.name).should contain("measurementMedium")
    end

    it "has NumericMeasurement attributes when feature enabled" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      attrs = sensor.attributes
      attrs.find { |attr| attr.name == "measuredValue" }.should_not be_nil
      attrs.find { |attr| attr.name == "minMeasuredValue" }.should_not be_nil
      attrs.find { |attr| attr.name == "maxMeasuredValue" }.should_not be_nil
      attrs.find { |attr| attr.name == "measurementUnit" }.should_not be_nil
    end

    it "has LevelIndication attributes when feature enabled" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::High
      )

      attrs = sensor.attributes
      attrs.find { |attr| attr.name == "levelValue" }.should_not be_nil
    end

    it "does not have NumericMeasurement attributes when feature disabled" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      attrs = sensor.attributes
      attrs.find { |attr| attr.name == "measuredValue" }.should be_nil
      attrs.find { |attr| attr.name == "measurementUnit" }.should be_nil
    end

    it "reads measurement medium" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Water,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      read(sensor, Matter::Cluster::CarbonDioxideConcentrationMeasurement::ATTR_MEASUREMENT_MEDIUM).should eq(1_u8) # Water = 1
    end

    it "reads measured value" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 450.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      read(sensor, Matter::Cluster::CarbonDioxideConcentrationMeasurement::ATTR_MEASURED_VALUE).should eq(450.0_f32)
    end

    it "reads level value" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Critical
      )

      read(sensor, Matter::Cluster::CarbonDioxideConcentrationMeasurement::ATTR_LEVEL_VALUE).should eq(4_u8) # Critical = 4
    end

    it "returns unsupported for NumericMeasurement attributes when feature disabled" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      read_status(sensor, Matter::Cluster::CarbonDioxideConcentrationMeasurement::ATTR_MEASURED_VALUE).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end

    it "returns unsupported for LevelIndication attributes when feature disabled" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      read_status(sensor, Matter::Cluster::CarbonDioxideConcentrationMeasurement::ATTR_LEVEL_VALUE).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "update methods" do
    it "updates measured value" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      sensor.update_measured_value(450.0_f32)
      sensor.measured_value.should eq(450.0_f32)
    end

    it "updates level value" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      sensor.update_level_value(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::High)
      sensor.level_value.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::High)
    end

    it "updates peak measured value" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        peak_measured_value: 500.0_f32,
        peak_measured_value_window: 3600_u32
      )

      sensor.update_peak_measured_value(550.0_f32)
      sensor.peak_measured_value.should eq(550.0_f32)
    end

    it "updates average measured value" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        average_measured_value: 380.0_f32,
        average_measured_value_window: 3600_u32
      )

      sensor.update_average_measured_value(390.0_f32)
      sensor.average_measured_value.should eq(390.0_f32)
    end

    it "calls callback when measured value changes" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      old_val = nil
      new_val = nil
      sensor.on_measured_value_changed do |old, new|
        old_val = old
        new_val = new
      end

      sensor.update_measured_value(450.0_f32)
      old_val.should eq(400.0_f32)
      new_val.should eq(450.0_f32)
    end

    it "calls callback when level value changes" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      old_val = nil
      new_val = nil
      sensor.on_level_value_changed do |old, new|
        old_val = old
        new_val = new
      end

      sensor.update_level_value(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::High)
      old_val.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low)
      new_val.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::High)
    end

    it "increments version when measured value changes" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      initial_version = sensor.data_version
      sensor.update_measured_value(450.0_f32)
      sensor.data_version.should_not eq(initial_version)
    end

    it "does not increment version when value unchanged" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      initial_version = sensor.data_version
      sensor.update_measured_value(400.0_f32)
      sensor.data_version.should eq(initial_version)
    end
  end

  describe "practical scenarios" do
    it "models indoor air quality sensor with numeric measurement" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 450.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        uncertainty: 50.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm
      )

      sensor.measurement_medium.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air)
      sensor.measured_value.should eq(450.0_f32)
      sensor.uncertainty.should eq(50.0_f32)
      sensor.numeric_measurement_enabled?.should be_true
    end

    it "models simple level indicator sensor" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Medium
      )

      sensor.level_indication_enabled?.should be_true
      sensor.numeric_measurement_enabled?.should be_false
      sensor.level_value.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Medium)
    end

    it "models sensor with peak tracking" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        peak_measured_value: 800.0_f32,
        peak_measured_value_window: 86400_u32 # 24 hours
      )

      sensor.peak_measurement_enabled?.should be_true
      sensor.peak_measured_value.should eq(800.0_f32)
      sensor.peak_measured_value_window.should eq(86400_u32)
    end

    it "models sensor with average tracking" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 450.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        average_measured_value: 420.0_f32,
        average_measured_value_window: 3600_u32 # 1 hour
      )

      sensor.average_measurement_enabled?.should be_true
      sensor.average_measured_value.should eq(420.0_f32)
      sensor.average_measured_value_window.should eq(3600_u32)
    end

    it "models water quality monitoring sensor" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Water,
        measured_value: 25.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 100.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Mgm3
      )

      sensor.measurement_medium.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Water)
      sensor.measurement_unit.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Mgm3)
    end

    it "models CO2 level monitoring over time" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        measurement_medium: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementMedium::Air,
        measured_value: 400.0_f32,
        min_measured_value: 0.0_f32,
        max_measured_value: 5000.0_f32,
        measurement_unit: Matter::Cluster::CarbonDioxideConcentrationMeasurement::MeasurementUnit::Ppm,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      # Simulate CO2 level rising
      sensor.update_measured_value(600.0_f32)
      sensor.update_level_value(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Medium)
      sensor.measured_value.should eq(600.0_f32)
      sensor.level_value.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Medium)

      # Simulate CO2 level rising to critical
      sensor.update_measured_value(2000.0_f32)
      sensor.update_level_value(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Critical)
      sensor.measured_value.should eq(2000.0_f32)
      sensor.level_value.should eq(Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Critical)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute" do
      sensor = Matter::Cluster::CarbonDioxideConcentrationMeasurement.new(
        endpoint_id,
        level_value: Matter::Cluster::CarbonDioxideConcentrationMeasurement::LevelValue::Low
      )

      read_status(sensor, 0x9999_u32).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end
end
