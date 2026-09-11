require "./cluster"

module Matter
  module Cluster
    # Carbon Dioxide Concentration Measurement Cluster (0x040D)
    #
    # Provides attributes for reporting Carbon Dioxide (CO2) concentration measurements
    # and level indications in air, water, or soil. This cluster is a derived cluster
    # from the base Concentration Measurement cluster specification.
    #
    # Features (derived from the values the cluster is constructed with):
    # - NumericMeasurement (MEA): actual measured values in configurable units
    # - LevelIndication (LEV): coarse level indication (Unknown, Low, Medium, High, Critical)
    # - PeakMeasurement (PEA): peak value over a window
    # - AverageMeasurement (AVG): average value over a window
    #
    # Specification: Matter 1.4 § 2.10 (Concentration Measurement)
    class CarbonDioxideConcentrationMeasurementCluster < Base
      cluster 0x040D, revision: 3

      feature :numeric_measurement, bit: 0 # MEA - Numeric measurement
      feature :level_indication, bit: 1    # LEV - Level indication
      feature :peak_measurement, bit: 4    # PEA - Peak measurement
      feature :average_measurement, bit: 5 # AVG - Average measurement

      # Longest peak / average window the specification allows (seconds, 7 days)
      MAX_WINDOW = 604_800_u32

      # Measurement unit values
      enum MeasurementUnit : UInt8
        Ppm  = 0 # Parts per Million (10^6)
        Ppb  = 1 # Parts per Billion (10^9)
        Ppt  = 2 # Parts per Trillion (10^12)
        Mgm3 = 3 # Milligram per m³
        Ugm3 = 4 # Microgram per m³
        Ngm3 = 5 # Nanogram per m³
        Pm3  = 6 # Particles per m³
        Bqm3 = 7 # Becquerel per m³
      end

      # Level value for coarse indication
      enum LevelValue : UInt8
        Unknown  = 0 # Level is unknown
        Low      = 1 # Level is considered Low
        Medium   = 2 # Level is considered Medium
        High     = 3 # Level is considered High
        Critical = 4 # Level is considered Critical
      end

      # Measurement medium
      enum MeasurementMedium : UInt8
        Air   = 0 # Measurement is being made in Air
        Water = 1 # Measurement is being made in Water
        Soil  = 2 # Measurement is being made in Soil
      end

      attribute 0x0000, :measured_value, Float32, nullable: true, requires: :numeric_measurement
      attribute 0x0001, :min_measured_value, Float32, nullable: true, requires: :numeric_measurement
      attribute 0x0002, :max_measured_value, Float32, nullable: true, requires: :numeric_measurement
      attribute 0x0003, :peak_measured_value, Float32, nullable: true, requires: :peak_measurement
      attribute 0x0004, :peak_measured_value_window, UInt32, default: 0_u32, max: MAX_WINDOW, requires: :peak_measurement
      attribute 0x0005, :average_measured_value, Float32, nullable: true, requires: :average_measurement
      attribute 0x0006, :average_measured_value_window, UInt32, default: 0_u32, max: MAX_WINDOW, requires: :average_measurement
      attribute 0x0007, :uncertainty, Float32, nullable: true, optional: true, requires: :numeric_measurement, present_if: :uncertainty
      attribute 0x0008, :measurement_unit, MeasurementUnit, default: MeasurementUnit::Ppm, fixed: true, requires: :numeric_measurement
      attribute 0x0009, :measurement_medium, MeasurementMedium, default: MeasurementMedium::Air, fixed: true
      attribute 0x000A, :level_value, LevelValue, default: LevelValue::Unknown, requires: :level_indication

      # The FeatureMap follows the values given: numeric measurement needs the
      # measured, min and max values and the unit; peak and average need
      # their value and window; level indication needs a level.
      def initialize(endpoint_id : DataType::EndpointNumber,
                     @measurement_medium : MeasurementMedium = MeasurementMedium::Air,
                     @measured_value : Float32? = nil,
                     @min_measured_value : Float32? = nil,
                     @max_measured_value : Float32? = nil,
                     @uncertainty : Float32? = nil,
                     measurement_unit : MeasurementUnit? = nil,
                     level_value : LevelValue? = nil,
                     @peak_measured_value : Float32? = nil,
                     peak_measured_value_window : UInt32? = nil,
                     @average_measured_value : Float32? = nil,
                     average_measured_value_window : UInt32? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        numeric = {@measured_value, @min_measured_value, @max_measured_value, measurement_unit}
        if numeric.any?(Nil) && !numeric.all?(Nil)
          raise ArgumentError.new("NumericMeasurement feature requires measured_value, min_measured_value, max_measured_value, and measurement_unit")
        end
        raise ArgumentError.new("PeakMeasurement feature requires peak_measured_value_window") if @peak_measured_value && peak_measured_value_window.nil?
        raise ArgumentError.new("PeakMeasurement feature requires peak_measured_value") if peak_measured_value_window && @peak_measured_value.nil?
        raise ArgumentError.new("AverageMeasurement feature requires average_measured_value_window") if @average_measured_value && average_measured_value_window.nil?
        raise ArgumentError.new("AverageMeasurement feature requires average_measured_value") if average_measured_value_window && @average_measured_value.nil?

        if window = peak_measured_value_window
          raise ArgumentError.new("peak_measured_value_window must be <= #{MAX_WINDOW} seconds") if window > MAX_WINDOW
          @peak_measured_value_window = window
        end
        if window = average_measured_value_window
          raise ArgumentError.new("average_measured_value_window must be <= #{MAX_WINDOW} seconds") if window > MAX_WINDOW
          @average_measured_value_window = window
        end

        unless measurement_unit || level_value
          raise ArgumentError.new("At least one feature (NumericMeasurement or LevelIndication) must be enabled")
        end

        features = Feature::None
        if measurement_unit
          @measurement_unit = measurement_unit
          features |= Feature::NumericMeasurement
        end
        if level_value
          @level_value = level_value
          features |= Feature::LevelIndication
        end
        features |= Feature::PeakMeasurement if @peak_measured_value
        features |= Feature::AverageMeasurement if @average_measured_value
        @feature_map = features
      end

      # Uncertainty is optional: unsupported until the device reports one.
      # ------------------------------------------------------------------------
      # Public Interface
      # ------------------------------------------------------------------------

      # Reports a new reading; ignored unless NumericMeasurement is enabled
      def update_measured_value(value : Float32) : Nil
        return unless numeric_measurement_enabled?
        self.measured_value = value
      end

      # Reports a new level; ignored unless LevelIndication is enabled
      def update_level_value(value : LevelValue) : Nil
        return unless level_indication_enabled?
        self.level_value = value
      end

      # Reports a new peak; ignored unless PeakMeasurement is enabled
      def update_peak_measured_value(value : Float32) : Nil
        return unless peak_measurement_enabled?
        self.peak_measured_value = value
      end

      # Reports a new average; ignored unless AverageMeasurement is enabled
      def update_average_measured_value(value : Float32) : Nil
        return unless average_measurement_enabled?
        self.average_measured_value = value
      end

      def numeric_measurement_enabled? : Bool
        @feature_map.numeric_measurement?
      end

      def level_indication_enabled? : Bool
        @feature_map.level_indication?
      end

      def peak_measurement_enabled? : Bool
        @feature_map.peak_measurement?
      end

      def average_measurement_enabled? : Bool
        @feature_map.average_measurement?
      end
    end
  end
end
