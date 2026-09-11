require "./cluster"

module Matter
  module Cluster
    # Pressure Measurement Cluster (0x0403)
    #
    # Provides an interface to pressure measurement functionality,
    # including configuration and provision of notifications of pressure measurements.
    #
    # Pressure values are expressed in tenths of kilopascals (0.1 kPa):
    #   MeasuredValue = 10 x Pressure [kPa]
    #
    # For example, 1013 represents 101.3 kPa (standard atmospheric pressure).
    #
    # Specification: Matter 1.4 § 2.4
    class PressureMeasurementCluster < Base
      cluster 0x0403, revision: 3

      # Pressure limits (in 0.1 kPa)
      # Range: Int16 covers -3276.7 kPa to +3276.6 kPa
      MIN_PRESSURE = Int16::MIN
      MAX_PRESSURE = Int16::MAX

      # MinMeasuredValue must leave room for a larger MaxMeasuredValue
      MAX_MIN_MEASURED_VALUE = MAX_PRESSURE - 1

      # Largest tolerance the specification allows (in 0.1 kPa)
      MAX_TOLERANCE = 2048_u16

      # Tenths of a kilopascal per kilopascal
      DECI_PER_UNIT = 10.0

      # 1 kPa = 7.50062 mmHg
      MMHG_PER_KPA = 7.50062

      # 1 kPa = 0.2953 inHg
      INHG_PER_KPA = 0.2953

      attribute 0x0000, :measured_value, Int16, nullable: true
      attribute 0x0001, :min_measured_value, Int16, nullable: true, max: MAX_MIN_MEASURED_VALUE
      attribute 0x0002, :max_measured_value, Int16, nullable: true
      attribute 0x0003, :tolerance, UInt16, nullable: true, optional: true, max: MAX_TOLERANCE, present_if: :tolerance

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @measured_value : Int16? = nil,
                     @min_measured_value : Int16? = nil,
                     @max_measured_value : Int16? = nil,
                     @tolerance : UInt16? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        if min = @min_measured_value
          raise ArgumentError.new("min_measured_value must be <= #{MAX_MIN_MEASURED_VALUE}") if min > MAX_MIN_MEASURED_VALUE
        end

        if (min = @min_measured_value) && (max = @max_measured_value)
          raise ArgumentError.new("min_measured_value must be <= max_measured_value") if min > max
        end

        if measured = @measured_value
          raise ArgumentError.new("measured_value must be >= min_measured_value") if below_minimum?(measured)
          raise ArgumentError.new("measured_value must be <= max_measured_value") if above_maximum?(measured)
        end

        if tolerance = @tolerance
          raise ArgumentError.new("tolerance must be <= #{MAX_TOLERANCE}") if tolerance > MAX_TOLERANCE
        end
      end

      # Tolerance is optional: unsupported until the device reports one.
      # Reports a new reading (nil when unknown); `measured_value=` with a
      # device-facing name that enforces the measurable range.
      def update_pressure(value : Int16?) : Nil
        if value
          raise ArgumentError.new("Pressure #{value} is below minimum measurable value #{@min_measured_value}") if below_minimum?(value)
          raise ArgumentError.new("Pressure #{value} is above maximum measurable value #{@max_measured_value}") if above_maximum?(value)
        end
        self.measured_value = value
      end

      # Called with the previous and the new value whenever MeasuredValue changes
      def on_pressure_changed(&block : Int16?, Int16? -> Nil) : Nil
        on_measured_value_changed(&block)
      end

      private def below_minimum?(value : Int16) : Bool
        (min = @min_measured_value) ? value < min : false
      end

      private def above_maximum?(value : Int16) : Bool
        (max = @max_measured_value) ? value > max : false
      end

      # Helper methods for pressure conversion

      # Convert from 0.1 kPa to kPa (Float)
      def self.to_kilopascals(value : Int16) : Float64
        value / DECI_PER_UNIT
      end

      # Convert from kPa (Float) to 0.1 kPa (Int16)
      def self.from_kilopascals(value : Float64) : Int16
        (value * DECI_PER_UNIT).round.to_i16
      end

      # Convert from 0.1 kPa to hPa/mbar (Float)
      # 1 kPa = 10 hPa = 10 mbar, so 0.1 kPa = 1 hPa
      def self.to_hectopascals(value : Int16) : Float64
        value.to_f
      end

      # Convert from hPa/mbar (Float) to 0.1 kPa (Int16)
      def self.from_hectopascals(value : Float64) : Int16
        value.round.to_i16
      end

      # Convert from 0.1 kPa to mmHg (Float)
      def self.to_mmhg(value : Int16) : Float64
        to_kilopascals(value) * MMHG_PER_KPA
      end

      # Convert from mmHg (Float) to 0.1 kPa (Int16)
      def self.from_mmhg(value : Float64) : Int16
        from_kilopascals(value / MMHG_PER_KPA)
      end

      # Convert from 0.1 kPa to inches of mercury (Float)
      def self.to_inhg(value : Int16) : Float64
        to_kilopascals(value) * INHG_PER_KPA
      end

      # Convert from inches of mercury (Float) to 0.1 kPa (Int16)
      def self.from_inhg(value : Float64) : Int16
        from_kilopascals(value / INHG_PER_KPA)
      end
    end
  end
end
