require "./cluster"

module Matter
  module Cluster
    # Relative Humidity Measurement Cluster (0x0405)
    #
    # Provides an interface to water content measurement functionality.
    # The measurement is reportable and may be configured for reporting.
    #
    # Humidity values are expressed in hundredths of percent (0.01%).
    # For example, 5500 represents 55.00% relative humidity.
    #
    # Specification: Matter 1.4 § 2.6
    class RelativeHumidityMeasurementCluster < Base
      CLUSTER_ID = 0x0405_u32

      # Attributes
      ATTR_MEASURED_VALUE     = 0x0000_u32
      ATTR_MIN_MEASURED_VALUE = 0x0001_u32
      ATTR_MAX_MEASURED_VALUE = 0x0002_u32
      ATTR_TOLERANCE          = 0x0003_u32

      # Humidity limits (in 0.01%)
      MIN_HUMIDITY =     0_u16 # 0.00%
      MAX_HUMIDITY = 10000_u16 # 100.00%

      # Current measured humidity (in 0.01%), or nil if unknown
      property measured_value : UInt16?

      # Minimum measurable humidity (in 0.01%)
      property min_measured_value : UInt16

      # Maximum measurable humidity (in 0.01%)
      property max_measured_value : UInt16

      # Measurement tolerance (in 0.01%), optional
      property tolerance : UInt16?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @measured_value : UInt16? = nil,
                     @min_measured_value : UInt16 = MIN_HUMIDITY,
                     @max_measured_value : UInt16 = MAX_HUMIDITY,
                     @tolerance : UInt16? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate ranges
        raise ArgumentError.new("min_measured_value must be <= 9999") if @min_measured_value > 9999_u16
        raise ArgumentError.new("max_measured_value must be <= #{MAX_HUMIDITY}") if @max_measured_value > MAX_HUMIDITY
        raise ArgumentError.new("min_measured_value must be <= max_measured_value") if @min_measured_value > @max_measured_value

        # Validate measured_value if provided
        if measured_value = @measured_value
          raise ArgumentError.new("measured_value must be between min and max") if measured_value < @min_measured_value || measured_value > @max_measured_value
        end

        # Validate tolerance if provided
        if tolerance = @tolerance
          raise ArgumentError.new("tolerance must be <= 2048") if tolerance > 2048_u16
        end
      end

      def name : String
        "RelativeHumidityMeasurement"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MEASURED_VALUE),
            "MeasuredValue",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MIN_MEASURED_VALUE),
            "MinMeasuredValue",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MAX_MEASURED_VALUE),
            "MaxMeasuredValue",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_TOLERANCE),
            "Tolerance",
            :uint16,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands for measurement clusters
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_MEASURED_VALUE
          if value = @measured_value
            value.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_MIN_MEASURED_VALUE
          @min_measured_value.to_tlv
        when ATTR_MAX_MEASURED_VALUE
          @max_measured_value.to_tlv
        when ATTR_TOLERANCE
          if tolerance = @tolerance
            tolerance.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      # Update the measured humidity value
      def update_humidity(value : UInt16?)
        old_value = @measured_value

        # Validate new value
        if value
          if value < @min_measured_value || value > @max_measured_value
            raise ArgumentError.new("Humidity #{value} is outside measurable range [#{@min_measured_value}, #{@max_measured_value}]")
          end
        end

        @measured_value = value

        # Invoke callback if value changed
        if old_value != value
          @on_humidity_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Callback when humidity changes
      @on_humidity_changed : Proc(UInt16?, UInt16?, Nil)?

      def on_humidity_changed(&block : UInt16?, UInt16? -> Nil)
        @on_humidity_changed = block
      end

      # Helper methods for humidity conversion

      # Convert from 0.01% to percent (Float)
      def self.to_percent(value : UInt16) : Float64
        value / 100.0
      end

      # Convert from percent (Float) to 0.01% (UInt16)
      def self.from_percent(value : Float64) : UInt16
        raise ArgumentError.new("Humidity percent must be between 0 and 100") if value < 0.0 || value > 100.0
        (value * 100).round.to_u16
      end

      # NOTE: Attributes are returned as TLV-encoded bytes (use `value.to_tlv`).
    end
  end
end
