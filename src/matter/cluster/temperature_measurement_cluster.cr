require "./cluster"

module Matter
  module Cluster
    # Temperature Measurement Cluster (0x0402)
    #
    # Provides an interface to temperature measurement functionality,
    # including configuration and provision of notifications of temperature measurements.
    #
    # Temperature values are expressed in hundredths of degrees Celsius (0.01°C).
    # For example, 2550 represents 25.50°C.
    #
    # Specification: Matter 1.4 § 2.3
    class TemperatureMeasurementCluster < Base
      CLUSTER_ID = 0x0402_u32

      # Attributes
      ATTR_MEASURED_VALUE     = 0x0000_u32
      ATTR_MIN_MEASURED_VALUE = 0x0001_u32
      ATTR_MAX_MEASURED_VALUE = 0x0002_u32
      ATTR_TOLERANCE          = 0x0003_u32

      # Temperature limits (in 0.01°C)
      MIN_TEMPERATURE = -27315_i16 # -273.15°C (absolute zero)
      MAX_TEMPERATURE =  32767_i16 # 327.67°C

      # Current measured temperature (in 0.01°C), or nil if unknown
      property measured_value : Int16?

      # Minimum measurable temperature (in 0.01°C)
      property min_measured_value : Int16

      # Maximum measurable temperature (in 0.01°C)
      property max_measured_value : Int16

      # Measurement tolerance (in 0.01°C), optional
      property tolerance : UInt16?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @measured_value : Int16? = nil,
                     @min_measured_value : Int16 = MIN_TEMPERATURE,
                     @max_measured_value : Int16 = MAX_TEMPERATURE,
                     @tolerance : UInt16? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate ranges
        raise ArgumentError.new("min_measured_value must be >= #{MIN_TEMPERATURE}") if @min_measured_value < MIN_TEMPERATURE
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
        "TemperatureMeasurement"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MEASURED_VALUE),
            "MeasuredValue",
            :int16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MIN_MEASURED_VALUE),
            "MinMeasuredValue",
            :int16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MAX_MEASURED_VALUE),
            "MaxMeasuredValue",
            :int16,
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
            encode_int16(value)
          else
            nil.to_tlv
          end
        when ATTR_MIN_MEASURED_VALUE
          encode_int16(@min_measured_value)
        when ATTR_MAX_MEASURED_VALUE
          encode_int16(@max_measured_value)
        when ATTR_TOLERANCE
          if tolerance = @tolerance
            tolerance.to_tlv
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      # Update the measured temperature value
      def update_temperature(value : Int16?)
        old_value = @measured_value

        # Validate new value
        if value
          if value < @min_measured_value || value > @max_measured_value
            raise ArgumentError.new("Temperature #{value} is outside measurable range [#{@min_measured_value}, #{@max_measured_value}]")
          end
        end

        @measured_value = value

        # Invoke callback if value changed
        if old_value != value
          @on_temperature_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Callback when temperature changes
      @on_temperature_changed : Proc(Int16?, Int16?, Nil)?

      def on_temperature_changed(&block : Int16?, Int16? -> Nil)
        @on_temperature_changed = block
      end

      # Helper methods for temperature conversion

      # Convert from 0.01°C to Celsius (Float)
      def self.to_celsius(value : Int16) : Float64
        value / 100.0
      end

      # Convert from Celsius (Float) to 0.01°C (Int16)
      def self.from_celsius(value : Float64) : Int16
        (value * 100).round.to_i16
      end

      # Convert from 0.01°C to Fahrenheit (Float)
      def self.to_fahrenheit(value : Int16) : Float64
        to_celsius(value) * 9.0 / 5.0 + 32.0
      end

      # Convert from Fahrenheit (Float) to 0.01°C (Int16)
      def self.from_fahrenheit(value : Float64) : Int16
        from_celsius((value - 32.0) * 5.0 / 9.0)
      end

      # NOTE: Attributes are returned as TLV-encoded bytes (use `value.to_tlv`).

      # encode_int16 uses TLV encoding for attribute responses
      private def encode_int16(value : Int16) : Bytes
        TLV::Any.new(value, nil).to_slice
      end
    end
  end
end
