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
      CLUSTER_ID = 0x0403_u32

      # Attributes
      ATTR_MEASURED_VALUE     = 0x0000_u32
      ATTR_MIN_MEASURED_VALUE = 0x0001_u32
      ATTR_MAX_MEASURED_VALUE = 0x0002_u32
      ATTR_TOLERANCE          = 0x0003_u32

      # Pressure limits (in 0.1 kPa)
      # Range: Int16 covers -3276.7 kPa to +3276.6 kPa
      MIN_PRESSURE = -32768_i16 # Minimum Int16
      MAX_PRESSURE =  32767_i16 # Maximum Int16

      # Current measured pressure (in 0.1 kPa), or nil if unknown
      property measured_value : Int16?

      # Minimum measurable pressure (in 0.1 kPa), or nil if unknown
      property min_measured_value : Int16?

      # Maximum measurable pressure (in 0.1 kPa), or nil if unknown
      property max_measured_value : Int16?

      # Measurement tolerance (in 0.1 kPa), optional
      property tolerance : UInt16?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @measured_value : Int16? = nil,
                     @min_measured_value : Int16? = nil,
                     @max_measured_value : Int16? = nil,
                     @tolerance : UInt16? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate min_measured_value if provided (max 32766 per spec)
        if min = @min_measured_value
          raise ArgumentError.new("min_measured_value must be <= 32766") if min > 32766_i16
        end

        # Validate min/max relationship if both provided
        if (min = @min_measured_value) && (max = @max_measured_value)
          raise ArgumentError.new("min_measured_value must be <= max_measured_value") if min > max
        end

        # Validate measured_value if provided
        if measured = @measured_value
          if (min = @min_measured_value) && measured < min
            raise ArgumentError.new("measured_value must be >= min_measured_value")
          end
          if (max = @max_measured_value) && measured > max
            raise ArgumentError.new("measured_value must be <= max_measured_value")
          end
        end

        # Validate tolerance if provided
        if tolerance = @tolerance
          raise ArgumentError.new("tolerance must be <= 2048") if tolerance > 2048_u16
        end
      end

      def name : String
        "PressureMeasurement"
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
          if value = @min_measured_value
            encode_int16(value)
          else
            nil.to_tlv
          end
        when ATTR_MAX_MEASURED_VALUE
          if value = @max_measured_value
            encode_int16(value)
          else
            nil.to_tlv
          end
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

      # Update the measured pressure value
      def update_pressure(value : Int16?)
        old_value = @measured_value

        # Validate new value
        if value
          if (min = @min_measured_value) && value < min
            raise ArgumentError.new("Pressure #{value} is below minimum measurable value #{min}")
          end
          if (max = @max_measured_value) && value > max
            raise ArgumentError.new("Pressure #{value} is above maximum measurable value #{max}")
          end
        end

        @measured_value = value

        # Invoke callback if value changed
        if old_value != value
          @on_pressure_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Callback when pressure changes
      @on_pressure_changed : Proc(Int16?, Int16?, Nil)?

      def on_pressure_changed(&block : Int16?, Int16? -> Nil)
        @on_pressure_changed = block
      end

      # Helper methods for pressure conversion

      # Convert from 0.1 kPa to kPa (Float)
      def self.to_kilopascals(value : Int16) : Float64
        value / 10.0
      end

      # Convert from kPa (Float) to 0.1 kPa (Int16)
      def self.from_kilopascals(value : Float64) : Int16
        (value * 10.0).round.to_i16
      end

      # Convert from 0.1 kPa to hPa/mbar (Float)
      # 1 kPa = 10 hPa = 10 mbar
      def self.to_hectopascals(value : Int16) : Float64
        value.to_f # 0.1 kPa = 1 hPa
      end

      # Convert from hPa/mbar (Float) to 0.1 kPa (Int16)
      def self.from_hectopascals(value : Float64) : Int16
        value.round.to_i16
      end

      # Convert from 0.1 kPa to mmHg (Float)
      # 1 kPa = 7.50062 mmHg
      def self.to_mmhg(value : Int16) : Float64
        to_kilopascals(value) * 7.50062
      end

      # Convert from mmHg (Float) to 0.1 kPa (Int16)
      def self.from_mmhg(value : Float64) : Int16
        from_kilopascals(value / 7.50062)
      end

      # Convert from 0.1 kPa to inches of mercury (Float)
      # 1 kPa = 0.2953 inHg
      def self.to_inhg(value : Int16) : Float64
        to_kilopascals(value) * 0.2953
      end

      # Convert from inches of mercury (Float) to 0.1 kPa (Int16)
      def self.from_inhg(value : Float64) : Int16
        from_kilopascals(value / 0.2953)
      end

      # NOTE: Attributes are returned as TLV-encoded bytes (use `value.to_tlv`).

      # encode_int16 uses TLV encoding for attribute responses
      private def encode_int16(value : Int16) : Bytes
        TLV::Any.new(value, nil).to_slice
      end
    end
  end
end
