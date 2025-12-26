require "../spec_helper"
require "../../src/matter/cluster/temperature_measurement_cluster"

describe Matter::Cluster::TemperatureMeasurementCluster do
  describe "initialization" do
    it "creates temperature measurement cluster with defaults" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0402_u32)
      cluster.name.should eq("TemperatureMeasurement")
      cluster.measured_value.should be_nil
      cluster.min_measured_value.should eq(-27315_i16)
      cluster.max_measured_value.should eq(32767_i16)
      cluster.tolerance.should be_nil
    end

    it "creates with custom values" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2550_i16,      # 25.50°C
        min_measured_value: -4000_i16, # -40.00°C
        max_measured_value: 8500_i16,  # 85.00°C
        tolerance: 50_u16              # ±0.50°C
      )

      cluster.measured_value.should eq(2550_i16)
      cluster.min_measured_value.should eq(-4000_i16)
      cluster.max_measured_value.should eq(8500_i16)
      cluster.tolerance.should eq(50_u16)
    end

    it "rejects min_measured_value below absolute minimum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /min_measured_value must be >= -27315/) do
        Matter::Cluster::TemperatureMeasurementCluster.new(
          endpoint_id,
          min_measured_value: -30000_i16
        )
      end
    end

    it "accepts max_measured_value at absolute maximum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        max_measured_value: 32767_i16
      )

      cluster.max_measured_value.should eq(32767_i16)
    end

    it "rejects min > max" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /min_measured_value must be <= max_measured_value/) do
        Matter::Cluster::TemperatureMeasurementCluster.new(
          endpoint_id,
          min_measured_value: 5000_i16,
          max_measured_value: 1000_i16
        )
      end
    end

    it "rejects measured_value outside range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /measured_value must be between min and max/) do
        Matter::Cluster::TemperatureMeasurementCluster.new(
          endpoint_id,
          measured_value: 10000_i16,
          min_measured_value: 0_i16,
          max_measured_value: 5000_i16
        )
      end
    end

    it "rejects tolerance above maximum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /tolerance must be <= 2048/) do
        Matter::Cluster::TemperatureMeasurementCluster.new(
          endpoint_id,
          tolerance: 3000_u16
        )
      end
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.size.should eq(4)

      measured_value = attributes.find { |attr| attr.id.id == 0x0000_u32 }
      measured_value.should_not be_nil
      measured_attr = measured_value.as(Matter::Cluster::AttributeMetadata)
      measured_attr.name.should eq("MeasuredValue")
      measured_attr.writable?.should be_false

      min_value = attributes.find { |attr| attr.id.id == 0x0001_u32 }
      min_value.should_not be_nil
      min_value.as(Matter::Cluster::AttributeMetadata).name.should eq("MinMeasuredValue")

      max_value = attributes.find { |attr| attr.id.id == 0x0002_u32 }
      max_value.should_not be_nil
      max_value.as(Matter::Cluster::AttributeMetadata).name.should eq("MaxMeasuredValue")

      tolerance = attributes.find { |attr| attr.id.id == 0x0003_u32 }
      tolerance.should_not be_nil
      tolerance.as(Matter::Cluster::AttributeMetadata).name.should eq("Tolerance")
    end

    it "reads MeasuredValue attribute when set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2000_i16 # 20.00°C
      )

      result = cluster.read_attribute(0x0000_u32)
      result.should be_a(Bytes)

      value = decode_tlv_value(result.as(Bytes))
      value.should eq(2000)
    end

    it "reads MeasuredValue as null when not set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(endpoint_id)

      result = cluster.read_attribute(0x0000_u32)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should be_nil
    end

    it "reads MinMeasuredValue attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        min_measured_value: -2000_i16
      )

      result = cluster.read_attribute(0x0001_u32)
      result.should be_a(Bytes)

      value = decode_tlv_value(result.as(Bytes))
      value.should eq(-2000)
    end

    it "reads MaxMeasuredValue attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        max_measured_value: 12500_i16
      )

      result = cluster.read_attribute(0x0002_u32)
      result.should be_a(Bytes)

      value = decode_tlv_value(result.as(Bytes))
      value.should eq(12500)
    end

    it "reads Tolerance attribute when set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        tolerance: 100_u16
      )

      result = cluster.read_attribute(0x0003_u32)
      result.should be_a(Bytes)

      value = decode_tlv_value(result.as(Bytes))
      value.should eq(100)
    end

    it "returns unsupported for Tolerance when not set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(endpoint_id)

      result = cluster.read_attribute(0x0003_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end
  end

  describe "update_temperature" do
    it "updates temperature value" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(endpoint_id)

      cluster.update_temperature(2550_i16)
      cluster.measured_value.should eq(2550_i16)
    end

    it "accepts nil to indicate unknown temperature" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2000_i16
      )

      cluster.update_temperature(nil)
      cluster.measured_value.should be_nil
    end

    it "rejects temperature below minimum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        min_measured_value: 0_i16,
        max_measured_value: 5000_i16
      )

      expect_raises(ArgumentError, /outside measurable range/) do
        cluster.update_temperature(-100_i16)
      end
    end

    it "rejects temperature above maximum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        min_measured_value: 0_i16,
        max_measured_value: 5000_i16
      )

      expect_raises(ArgumentError, /outside measurable range/) do
        cluster.update_temperature(6000_i16)
      end
    end

    it "calls callback when temperature changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2000_i16
      )

      old_value : Int16? = nil
      new_value : Int16? = nil

      cluster.on_temperature_changed do |old, new|
        old_value = old
        new_value = new
      end

      cluster.update_temperature(2500_i16)

      old_value.should eq(2000_i16)
      new_value.should eq(2500_i16)
    end

    it "does not call callback when temperature doesn't change" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2000_i16
      )

      callback_called = false

      cluster.on_temperature_changed do |_, _|
        callback_called = true
      end

      cluster.update_temperature(2000_i16)

      callback_called.should be_false
    end

    it "increments data version when temperature changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2000_i16
      )

      initial_version = cluster.data_version

      cluster.update_temperature(2500_i16)

      cluster.data_version.should eq(initial_version + 1)
    end

    it "does not increment data version when temperature doesn't change" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2000_i16
      )

      initial_version = cluster.data_version

      cluster.update_temperature(2000_i16)

      cluster.data_version.should eq(initial_version)
    end
  end

  describe "temperature conversion helpers" do
    it "converts from 0.01°C to Celsius" do
      Matter::Cluster::TemperatureMeasurementCluster.to_celsius(2550_i16).should be_close(25.50, 0.01)
      Matter::Cluster::TemperatureMeasurementCluster.to_celsius(0_i16).should be_close(0.0, 0.01)
      Matter::Cluster::TemperatureMeasurementCluster.to_celsius(-1500_i16).should be_close(-15.0, 0.01)
    end

    it "converts from Celsius to 0.01°C" do
      Matter::Cluster::TemperatureMeasurementCluster.from_celsius(25.50).should eq(2550_i16)
      Matter::Cluster::TemperatureMeasurementCluster.from_celsius(0.0).should eq(0_i16)
      Matter::Cluster::TemperatureMeasurementCluster.from_celsius(-15.0).should eq(-1500_i16)
    end

    it "converts from 0.01°C to Fahrenheit" do
      Matter::Cluster::TemperatureMeasurementCluster.to_fahrenheit(2550_i16).should be_close(77.9, 0.1)
      Matter::Cluster::TemperatureMeasurementCluster.to_fahrenheit(0_i16).should be_close(32.0, 0.1)
      Matter::Cluster::TemperatureMeasurementCluster.to_fahrenheit(-1500_i16).should be_close(5.0, 0.1)
    end

    it "converts from Fahrenheit to 0.01°C" do
      Matter::Cluster::TemperatureMeasurementCluster.from_fahrenheit(77.9).should be_close(2550_i16, 2)
      Matter::Cluster::TemperatureMeasurementCluster.from_fahrenheit(32.0).should eq(0_i16)
      Matter::Cluster::TemperatureMeasurementCluster.from_fahrenheit(5.0).should be_close(-1500_i16, 1)
    end
  end

  describe "practical scenarios" do
    it "models a room temperature sensor" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2200_i16,      # 22.00°C
        min_measured_value: -1000_i16, # -10.00°C
        max_measured_value: 5000_i16,  # 50.00°C
        tolerance: 50_u16              # ±0.50°C
      )

      # Simulating temperature changes
      changes = [] of {Int16?, Int16?}

      sensor.on_temperature_changed do |old, new|
        changes << {old, new}
      end

      # Room warms up
      sensor.update_temperature(2250_i16) # 22.50°C
      sensor.update_temperature(2300_i16) # 23.00°C
      sensor.update_temperature(2350_i16) # 23.50°C

      changes.size.should eq(3)
      changes[0].should eq({2200_i16, 2250_i16})
      changes[1].should eq({2250_i16, 2300_i16})
      changes[2].should eq({2300_i16, 2350_i16})
    end

    it "models an outdoor temperature sensor with wide range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 1500_i16,      # 15.00°C
        min_measured_value: -4000_i16, # -40.00°C
        max_measured_value: 6000_i16,  # 60.00°C
        tolerance: 100_u16             # ±1.00°C
      )

      # Test extreme cold
      sensor.update_temperature(-3500_i16) # -35.00°C
      sensor.measured_value.should eq(-3500_i16)

      # Test extreme heat
      sensor.update_temperature(5500_i16) # 55.00°C
      sensor.measured_value.should eq(5500_i16)
    end

    it "handles sensor failure (unknown temperature)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::TemperatureMeasurementCluster.new(
        endpoint_id,
        measured_value: 2200_i16
      )

      # Sensor reports normal temperature
      sensor.measured_value.should eq(2200_i16)

      # Sensor fails and reports unknown
      sensor.update_temperature(nil)
      sensor.measured_value.should be_nil

      # Sensor recovers
      sensor.update_temperature(2200_i16)
      sensor.measured_value.should eq(2200_i16)
    end

    it "works with Fahrenheit using conversion helpers" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::TemperatureMeasurementCluster.new(endpoint_id)

      # Set temperature in Fahrenheit
      fahrenheit_value = 72.0 # 72°F
      celsius_value = Matter::Cluster::TemperatureMeasurementCluster.from_fahrenheit(fahrenheit_value)
      sensor.update_temperature(celsius_value)

      # Read back in Fahrenheit
      measured = sensor.measured_value.as(Int16)
      result_fahrenheit = Matter::Cluster::TemperatureMeasurementCluster.to_fahrenheit(measured)
      result_fahrenheit.should be_close(72.0, 0.2)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::TemperatureMeasurementCluster.new(endpoint_id)

      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end
  end
end
