require "./cluster"

module Matter
  module Cluster
    # Illuminance Measurement Cluster (0x0400)
    #
    # Provides an interface to illuminance measurement functionality,
    # including configuration and provision of notifications of illuminance measurements.
    #
    # Illuminance values are expressed using a logarithmic scale:
    #   MeasuredValue = 10,000 x log10(illuminance) + 1
    # where illuminance is in lux (lx).
    #
    # Special values:
    # - 0 indicates illuminance too low to measure
    # - null indicates invalid measurement
    # - Range: 1 lx to 3.576 Mlx (MeasuredValue: 1 to 0xFFFE)
    #
    # Specification: Matter 1.4 § 2.2
    class IlluminanceMeasurementCluster < Base
      CLUSTER_ID = 0x0400_u32

      # Attributes
      ATTR_MEASURED_VALUE     = 0x0000_u32
      ATTR_MIN_MEASURED_VALUE = 0x0001_u32
      ATTR_MAX_MEASURED_VALUE = 0x0002_u32
      ATTR_TOLERANCE          = 0x0003_u32
      ATTR_LIGHT_SENSOR_TYPE  = 0x0004_u32

      # Illuminance value limits
      MIN_ILLUMINANCE =     0_u16 # Too low to measure
      MAX_ILLUMINANCE = 65534_u16 # 0xFFFE

      # Light sensor types
      enum LightSensorType
        Photodiode = 0
        CMOS       = 1
      end

      # Current measured illuminance, or nil if unknown
      # Value of 0 indicates too low to measure
      property measured_value : UInt16?

      # Minimum measurable illuminance (1-65533, or nil)
      property min_measured_value : UInt16?

      # Maximum measurable illuminance (or nil)
      property max_measured_value : UInt16?

      # Measurement tolerance (max 2048), optional
      property tolerance : UInt16?

      # Light sensor type, optional
      property light_sensor_type : LightSensorType?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @measured_value : UInt16? = nil,
                     @min_measured_value : UInt16? = nil,
                     @max_measured_value : UInt16? = nil,
                     @tolerance : UInt16? = nil,
                     @light_sensor_type : LightSensorType? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate min_measured_value if provided
        if min = @min_measured_value
          raise ArgumentError.new("min_measured_value must be between 1 and 65533") if min < 1_u16 || min > 65533_u16
        end

        # Validate max_measured_value if provided
        if max = @max_measured_value
          raise ArgumentError.new("max_measured_value must be <= #{MAX_ILLUMINANCE}") if max > MAX_ILLUMINANCE
        end

        # Validate min/max relationship if both provided
        if (min = @min_measured_value) && (max = @max_measured_value)
          raise ArgumentError.new("min_measured_value must be <= max_measured_value") if min > max
        end

        # Validate measured_value if provided
        if measured = @measured_value
          # 0 is valid (too low to measure)
          if measured > 0
            if (min = @min_measured_value) && measured < min
              raise ArgumentError.new("measured_value must be >= min_measured_value")
            end
            if (max = @max_measured_value) && measured > max
              raise ArgumentError.new("measured_value must be <= max_measured_value")
            end
          end
        end

        # Validate tolerance if provided
        if tolerance = @tolerance
          raise ArgumentError.new("tolerance must be <= 2048") if tolerance > 2048_u16
        end
      end

      def name : String
        "IlluminanceMeasurement"
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
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_LIGHT_SENSOR_TYPE),
            "LightSensorType",
            :uint8,
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
            encode_uint16(value)
          else
            Bytes[0xFF, 0xFF] # Null value for UInt16
          end
        when ATTR_MIN_MEASURED_VALUE
          if value = @min_measured_value
            encode_uint16(value)
          else
            Bytes[0xFF, 0xFF] # Null value
          end
        when ATTR_MAX_MEASURED_VALUE
          if value = @max_measured_value
            encode_uint16(value)
          else
            Bytes[0xFF, 0xFF] # Null value
          end
        when ATTR_TOLERANCE
          if tolerance = @tolerance
            encode_uint16(tolerance)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_LIGHT_SENSOR_TYPE
          if sensor_type = @light_sensor_type
            Bytes[sensor_type.value.to_u8]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      # Update the measured illuminance value
      def update_illuminance(value : UInt16?)
        old_value = @measured_value

        # Validate new value
        if value
          # 0 is valid (too low to measure)
          if value > 0
            if (min = @min_measured_value) && value < min
              raise ArgumentError.new("Illuminance #{value} is below minimum measurable value #{min}")
            end
            if (max = @max_measured_value) && value > max
              raise ArgumentError.new("Illuminance #{value} is above maximum measurable value #{max}")
            end
          end
        end

        @measured_value = value

        # Invoke callback if value changed
        if old_value != value
          @on_illuminance_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Callback when illuminance changes
      @on_illuminance_changed : Proc(UInt16?, UInt16?, Nil)?

      def on_illuminance_changed(&block : UInt16?, UInt16? -> Nil)
        @on_illuminance_changed = block
      end

      # Helper methods for illuminance conversion

      # Convert from measured value to lux (illuminance)
      # Formula: illuminance = 10^((MeasuredValue - 1) / 10000)
      def self.to_lux(measured_value : UInt16) : Float64
        return 0.0 if measured_value == 0 # Too low to measure
        10.0 ** ((measured_value - 1) / 10000.0)
      end

      # Convert from lux (illuminance) to measured value
      # Formula: MeasuredValue = 10,000 x log10(illuminance) + 1
      # Valid range: 1 lx to 3.576 Mlx
      def self.from_lux(lux : Float64) : UInt16
        return 0_u16 if lux < 1.0 # Too low to measure
        raise ArgumentError.new("Illuminance must be <= 3,576,000 lux") if lux > 3_576_000.0

        value = (10000.0 * Math.log10(lux) + 1.0).round.to_u16
        # Clamp to valid range
        value = 1_u16 if value < 1_u16
        value = MAX_ILLUMINANCE if value > MAX_ILLUMINANCE
        value
      end

      private def encode_uint16(value : UInt16) : Bytes
        bytes = Bytes.new(2)
        IO::ByteFormat::LittleEndian.encode(value, bytes)
        bytes
      end
    end
  end
end
