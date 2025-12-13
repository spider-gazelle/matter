require "../spec_helper"
require "../../src/matter/cluster/relative_humidity_measurement_cluster"

describe Matter::Cluster::RelativeHumidityMeasurementCluster do
  describe "initialization" do
    it "creates humidity measurement cluster with defaults" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0405_u32)
      cluster.name.should eq("RelativeHumidityMeasurement")
      cluster.measured_value.should be_nil
      cluster.min_measured_value.should eq(0_u16)
      cluster.max_measured_value.should eq(10000_u16)
      cluster.tolerance.should be_nil
    end

    it "creates with custom values" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 5500_u16,     # 55.00%
        min_measured_value: 1000_u16, # 10.00%
        max_measured_value: 9500_u16, # 95.00%
        tolerance: 200_u16            # ±2.00%
      )

      cluster.measured_value.should eq(5500_u16)
      cluster.min_measured_value.should eq(1000_u16)
      cluster.max_measured_value.should eq(9500_u16)
      cluster.tolerance.should eq(200_u16)
    end

    it "rejects min_measured_value above 9999" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /min_measured_value must be <= 9999/) do
        Matter::Cluster::RelativeHumidityMeasurementCluster.new(
          endpoint_id,
          min_measured_value: 10000_u16
        )
      end
    end

    it "accepts max_measured_value at absolute maximum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        max_measured_value: 10000_u16
      )

      cluster.max_measured_value.should eq(10000_u16)
    end

    it "rejects min > max" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /min_measured_value must be <= max_measured_value/) do
        Matter::Cluster::RelativeHumidityMeasurementCluster.new(
          endpoint_id,
          min_measured_value: 8000_u16,
          max_measured_value: 5000_u16
        )
      end
    end

    it "rejects measured_value outside range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /measured_value must be between min and max/) do
        Matter::Cluster::RelativeHumidityMeasurementCluster.new(
          endpoint_id,
          measured_value: 9500_u16,
          min_measured_value: 1000_u16,
          max_measured_value: 8000_u16
        )
      end
    end

    it "rejects tolerance above maximum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

      expect_raises(ArgumentError, /tolerance must be <= 2048/) do
        Matter::Cluster::RelativeHumidityMeasurementCluster.new(
          endpoint_id,
          tolerance: 3000_u16
        )
      end
    end
  end

  describe "attributes" do
    it "has required attributes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(endpoint_id)

      attributes = cluster.attributes
      attributes.size.should eq(4)

      measured_value = attributes.find { |a| a.id.id == 0x0000_u32 }
      measured_value.should_not be_nil
      measured_value.not_nil!.name.should eq("MeasuredValue")
      measured_value.not_nil!.writable.should be_false

      min_value = attributes.find { |a| a.id.id == 0x0001_u32 }
      min_value.should_not be_nil
      min_value.not_nil!.name.should eq("MinMeasuredValue")

      max_value = attributes.find { |a| a.id.id == 0x0002_u32 }
      max_value.should_not be_nil
      max_value.not_nil!.name.should eq("MaxMeasuredValue")

      tolerance = attributes.find { |a| a.id.id == 0x0003_u32 }
      tolerance.should_not be_nil
      tolerance.not_nil!.name.should eq("Tolerance")
    end

    it "reads MeasuredValue attribute when set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 4500_u16 # 45.00%
      )

      result = cluster.read_attribute(0x0000_u32)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(4500)
    end

    it "reads MeasuredValue as null when not set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(endpoint_id)

      result = cluster.read_attribute(0x0000_u32)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should be_nil
    end

    it "reads MinMeasuredValue attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        min_measured_value: 2000_u16
      )

      result = cluster.read_attribute(0x0001_u32)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(2000)
    end

    it "reads MaxMeasuredValue attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        max_measured_value: 9500_u16
      )

      result = cluster.read_attribute(0x0002_u32)
      result.should be_a(Bytes)
      decode_tlv_value(result.as(Bytes)).should eq(9500)
    end

    it "reads Tolerance attribute when set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        tolerance: 150_u16
      )

      result = cluster.read_attribute(0x0003_u32)
      result.should be_a(Bytes)
      value = decode_tlv_value(result.as(Bytes))
      value.should eq(150_u16)
    end

    it "returns unsupported for Tolerance when not set" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(endpoint_id)

      result = cluster.read_attribute(0x0003_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end
  end

  describe "update_humidity" do
    it "updates humidity value" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(endpoint_id)

      cluster.update_humidity(6000_u16)
      cluster.measured_value.should eq(6000_u16)
    end

    it "accepts nil to indicate unknown humidity" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 5000_u16
      )

      cluster.update_humidity(nil)
      cluster.measured_value.should be_nil
    end

    it "rejects humidity below minimum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        min_measured_value: 1000_u16,
        max_measured_value: 9000_u16
      )

      expect_raises(ArgumentError, /outside measurable range/) do
        cluster.update_humidity(500_u16)
      end
    end

    it "rejects humidity above maximum" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        min_measured_value: 1000_u16,
        max_measured_value: 9000_u16
      )

      expect_raises(ArgumentError, /outside measurable range/) do
        cluster.update_humidity(9500_u16)
      end
    end

    it "calls callback when humidity changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 5000_u16
      )

      old_value : UInt16? = nil
      new_value : UInt16? = nil

      cluster.on_humidity_changed do |old, new|
        old_value = old
        new_value = new
      end

      cluster.update_humidity(5500_u16)

      old_value.should eq(5000_u16)
      new_value.should eq(5500_u16)
    end

    it "does not call callback when humidity doesn't change" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 5000_u16
      )

      callback_called = false

      cluster.on_humidity_changed do |old, new|
        callback_called = true
      end

      cluster.update_humidity(5000_u16)

      callback_called.should be_false
    end

    it "increments data version when humidity changes" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 5000_u16
      )

      initial_version = cluster.data_version

      cluster.update_humidity(5500_u16)

      cluster.data_version.should eq(initial_version + 1)
    end

    it "does not increment data version when humidity doesn't change" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 5000_u16
      )

      initial_version = cluster.data_version

      cluster.update_humidity(5000_u16)

      cluster.data_version.should eq(initial_version)
    end
  end

  describe "humidity conversion helpers" do
    it "converts from 0.01% to percent" do
      Matter::Cluster::RelativeHumidityMeasurementCluster.to_percent(5500_u16).should be_close(55.0, 0.01)
      Matter::Cluster::RelativeHumidityMeasurementCluster.to_percent(0_u16).should be_close(0.0, 0.01)
      Matter::Cluster::RelativeHumidityMeasurementCluster.to_percent(10000_u16).should be_close(100.0, 0.01)
    end

    it "converts from percent to 0.01%" do
      Matter::Cluster::RelativeHumidityMeasurementCluster.from_percent(55.0).should eq(5500_u16)
      Matter::Cluster::RelativeHumidityMeasurementCluster.from_percent(0.0).should eq(0_u16)
      Matter::Cluster::RelativeHumidityMeasurementCluster.from_percent(100.0).should eq(10000_u16)
    end

    it "rejects negative percent values" do
      expect_raises(ArgumentError, /must be between 0 and 100/) do
        Matter::Cluster::RelativeHumidityMeasurementCluster.from_percent(-5.0)
      end
    end

    it "rejects percent values above 100" do
      expect_raises(ArgumentError, /must be between 0 and 100/) do
        Matter::Cluster::RelativeHumidityMeasurementCluster.from_percent(105.0)
      end
    end
  end

  describe "practical scenarios" do
    it "models an indoor humidity sensor" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 4500_u16,     # 45.00%
        min_measured_value: 1000_u16, # 10.00%
        max_measured_value: 9500_u16, # 95.00%
        tolerance: 200_u16            # ±2.00%
      )

      # Simulating humidity changes
      changes = [] of {UInt16?, UInt16?}

      sensor.on_humidity_changed do |old, new|
        changes << {old, new}
      end

      # Humidity increases
      sensor.update_humidity(5000_u16) # 50.00%
      sensor.update_humidity(5500_u16) # 55.00%
      sensor.update_humidity(6000_u16) # 60.00%

      changes.size.should eq(3)
      changes[0].should eq({4500_u16, 5000_u16})
      changes[1].should eq({5000_u16, 5500_u16})
      changes[2].should eq({5500_u16, 6000_u16})
    end

    it "models a greenhouse humidity sensor with wide range" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 7000_u16,     # 70.00%
        min_measured_value: 2000_u16, # 20.00%
        max_measured_value: 9800_u16, # 98.00%
        tolerance: 300_u16            # ±3.00%
      )

      # Test low humidity
      sensor.update_humidity(2500_u16) # 25.00%
      sensor.measured_value.should eq(2500_u16)

      # Test high humidity
      sensor.update_humidity(9500_u16) # 95.00%
      sensor.measured_value.should eq(9500_u16)
    end

    it "handles sensor failure (unknown humidity)" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 5000_u16
      )

      # Sensor reports normal humidity
      sensor.measured_value.should eq(5000_u16)

      # Sensor fails and reports unknown
      sensor.update_humidity(nil)
      sensor.measured_value.should be_nil

      # Sensor recovers
      sensor.update_humidity(5000_u16)
      sensor.measured_value.should eq(5000_u16)
    end

    it "works with conversion helpers" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::RelativeHumidityMeasurementCluster.new(endpoint_id)

      # Set humidity in percent
      percent_value = 62.5
      encoded_value = Matter::Cluster::RelativeHumidityMeasurementCluster.from_percent(percent_value)
      sensor.update_humidity(encoded_value)

      # Read back in percent
      measured = sensor.measured_value.not_nil!
      result_percent = Matter::Cluster::RelativeHumidityMeasurementCluster.to_percent(measured)
      result_percent.should be_close(62.5, 0.01)
    end

    it "models a bathroom humidity sensor tracking shower use" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      sensor = Matter::Cluster::RelativeHumidityMeasurementCluster.new(
        endpoint_id,
        measured_value: 4500_u16, # 45.00% - normal
        min_measured_value: 2000_u16,
        max_measured_value: 9500_u16,
        tolerance: 200_u16
      )

      # Before shower
      sensor.measured_value.should eq(4500_u16)

      # During shower - humidity rises
      sensor.update_humidity(7000_u16) # 70.00%
      sensor.update_humidity(8000_u16) # 80.00%
      sensor.update_humidity(8500_u16) # 85.00%

      # After shower - humidity drops
      sensor.update_humidity(7500_u16) # 75.00%
      sensor.update_humidity(6500_u16) # 65.00%
      sensor.update_humidity(5000_u16) # 50.00%

      # Returns to normal
      sensor.measured_value.should eq(5000_u16)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::RelativeHumidityMeasurementCluster.new(endpoint_id)

      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).status.should eq(
        Matter::InteractionModel::StatusCode::UnsupportedAttribute
      )
    end
  end
end
