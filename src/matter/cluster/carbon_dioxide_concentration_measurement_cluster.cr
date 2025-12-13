require "./cluster"

module Matter
  module Cluster
    # Carbon Dioxide Concentration Measurement Cluster (0x040D)
    #
    # Provides attributes for reporting Carbon Dioxide (CO2) concentration measurements
    # and level indications in air, water, or soil. This cluster is a derived cluster
    # from the base Concentration Measurement cluster specification.
    #
    # Supports two main measurement modes:
    # - NumericMeasurement: Provides actual measured values in configurable units
    # - LevelIndication: Provides coarse level indication (Unknown, Low, Medium, High, Critical)
    #
    # Specification: Matter 1.4 § 2.10 (Concentration Measurement)
    class CarbonDioxideConcentrationMeasurementCluster < Base
      CLUSTER_ID = 0x040D_u32

      # Base Attributes
      ATTR_MEASUREMENT_MEDIUM = 0x0009_u32

      # NumericMeasurement Feature Attributes
      ATTR_MEASURED_VALUE     = 0x0000_u32
      ATTR_MIN_MEASURED_VALUE = 0x0001_u32
      ATTR_MAX_MEASURED_VALUE = 0x0002_u32
      ATTR_UNCERTAINTY        = 0x0007_u32
      ATTR_MEASUREMENT_UNIT   = 0x0008_u32

      # LevelIndication Feature Attributes
      ATTR_LEVEL_VALUE = 0x000A_u32

      # PeakMeasurement Feature Attributes
      ATTR_PEAK_MEASURED_VALUE        = 0x0003_u32
      ATTR_PEAK_MEASURED_VALUE_WINDOW = 0x0004_u32

      # AverageMeasurement Feature Attributes
      ATTR_AVERAGE_MEASURED_VALUE        = 0x0005_u32
      ATTR_AVERAGE_MEASURED_VALUE_WINDOW = 0x0006_u32

      # Measurement unit values
      enum MeasurementUnit
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
      enum LevelValue
        Unknown  = 0 # Level is unknown
        Low      = 1 # Level is considered Low
        Medium   = 2 # Level is considered Medium
        High     = 3 # Level is considered High
        Critical = 4 # Level is considered Critical
      end

      # Measurement medium
      enum MeasurementMedium
        Air   = 0 # Measurement is being made in Air
        Water = 1 # Measurement is being made in Water
        Soil  = 2 # Measurement is being made in Soil
      end

      # Measurement medium (mandatory)
      property measurement_medium : MeasurementMedium

      # NumericMeasurement feature attributes
      property measured_value : Float32?
      property min_measured_value : Float32?
      property max_measured_value : Float32?
      property uncertainty : Float32?
      property measurement_unit : MeasurementUnit?

      # LevelIndication feature attributes
      property level_value : LevelValue?

      # PeakMeasurement feature attributes
      property peak_measured_value : Float32?
      property peak_measured_value_window : UInt32?

      # AverageMeasurement feature attributes
      property average_measured_value : Float32?
      property average_measured_value_window : UInt32?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @measurement_medium : MeasurementMedium = MeasurementMedium::Air,
                     @measured_value : Float32? = nil,
                     @min_measured_value : Float32? = nil,
                     @max_measured_value : Float32? = nil,
                     @uncertainty : Float32? = nil,
                     @measurement_unit : MeasurementUnit? = nil,
                     @level_value : LevelValue? = nil,
                     @peak_measured_value : Float32? = nil,
                     @peak_measured_value_window : UInt32? = nil,
                     @average_measured_value : Float32? = nil,
                     @average_measured_value_window : UInt32? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate NumericMeasurement feature: if any numeric measurement attribute is set,
        # mandatory attributes must be present
        numeric_attrs = [@measured_value, @min_measured_value, @max_measured_value, @measurement_unit]
        if numeric_attrs.any?(&.!=(nil))
          unless @measured_value && @min_measured_value && @max_measured_value && @measurement_unit
            raise ArgumentError.new("NumericMeasurement feature requires measured_value, min_measured_value, max_measured_value, and measurement_unit")
          end
        end

        # Validate PeakMeasurement feature: both attributes must be set together
        if @peak_measured_value && !@peak_measured_value_window
          raise ArgumentError.new("PeakMeasurement feature requires peak_measured_value_window")
        end
        if @peak_measured_value_window && !@peak_measured_value
          raise ArgumentError.new("PeakMeasurement feature requires peak_measured_value")
        end

        # Validate AverageMeasurement feature: both attributes must be set together
        if @average_measured_value && !@average_measured_value_window
          raise ArgumentError.new("AverageMeasurement feature requires average_measured_value_window")
        end
        if @average_measured_value_window && !@average_measured_value
          raise ArgumentError.new("AverageMeasurement feature requires average_measured_value")
        end

        # Validate peak measurement window (max 604800 seconds = 7 days)
        if window = @peak_measured_value_window
          raise ArgumentError.new("peak_measured_value_window must be <= 604800 seconds") if window > 604800
        end

        # Validate average measurement window (max 604800 seconds = 7 days)
        if window = @average_measured_value_window
          raise ArgumentError.new("average_measured_value_window must be <= 604800 seconds") if window > 604800
        end

        # At least one feature must be enabled
        unless numeric_measurement_enabled? || level_indication_enabled?
          raise ArgumentError.new("At least one feature (NumericMeasurement or LevelIndication) must be enabled")
        end
      end

      def name : String
        "CarbonDioxideConcentrationMeasurement"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MEASUREMENT_MEDIUM),
            "MeasurementMedium",
            :uint8,
            writable: false
          ),
        ]

        # Add NumericMeasurement feature attributes if enabled
        if numeric_measurement_enabled?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MEASURED_VALUE),
            "MeasuredValue",
            :float,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MIN_MEASURED_VALUE),
            "MinMeasuredValue",
            :float,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MAX_MEASURED_VALUE),
            "MaxMeasuredValue",
            :float,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_UNCERTAINTY),
            "Uncertainty",
            :float,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MEASUREMENT_UNIT),
            "MeasurementUnit",
            :uint8,
            writable: false
          )
        end

        # Add LevelIndication feature attributes if enabled
        if level_indication_enabled?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_LEVEL_VALUE),
            "LevelValue",
            :uint8,
            writable: false
          )
        end

        # Add PeakMeasurement feature attributes if enabled
        if peak_measurement_enabled?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PEAK_MEASURED_VALUE),
            "PeakMeasuredValue",
            :float,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PEAK_MEASURED_VALUE_WINDOW),
            "PeakMeasuredValueWindow",
            :uint32,
            writable: false
          )
        end

        # Add AverageMeasurement feature attributes if enabled
        if average_measurement_enabled?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_AVERAGE_MEASURED_VALUE),
            "AverageMeasuredValue",
            :float,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_AVERAGE_MEASURED_VALUE_WINDOW),
            "AverageMeasuredValueWindow",
            :uint32,
            writable: false
          )
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands for concentration measurement cluster
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_MEASUREMENT_MEDIUM
          Bytes[@measurement_medium.value.to_u8]
        when ATTR_MEASURED_VALUE
          if value = @measured_value
            encode_float(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_MIN_MEASURED_VALUE
          if value = @min_measured_value
            encode_float(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_MAX_MEASURED_VALUE
          if value = @max_measured_value
            encode_float(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_UNCERTAINTY
          if value = @uncertainty
            encode_float(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_MEASUREMENT_UNIT
          if unit = @measurement_unit
            Bytes[unit.value.to_u8]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_LEVEL_VALUE
          if value = @level_value
            Bytes[value.value.to_u8]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PEAK_MEASURED_VALUE
          if value = @peak_measured_value
            encode_float(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PEAK_MEASURED_VALUE_WINDOW
          if value = @peak_measured_value_window
            encode_uint32(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_AVERAGE_MEASURED_VALUE
          if value = @average_measured_value
            encode_float(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_AVERAGE_MEASURED_VALUE_WINDOW
          if value = @average_measured_value_window
            encode_uint32(value)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      # Update the measured CO2 concentration value
      def update_measured_value(value : Float32)
        return unless numeric_measurement_enabled?

        old_value = @measured_value
        @measured_value = value

        if old_value != value
          @on_measured_value_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Update the level indication value
      def update_level_value(value : LevelValue)
        return unless level_indication_enabled?

        old_value = @level_value
        @level_value = value

        if old_value != value
          @on_level_value_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Update the peak measured value
      def update_peak_measured_value(value : Float32)
        return unless peak_measurement_enabled?

        old_value = @peak_measured_value
        @peak_measured_value = value

        if old_value != value
          @on_peak_measured_value_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Update the average measured value
      def update_average_measured_value(value : Float32)
        return unless average_measurement_enabled?

        old_value = @average_measured_value
        @average_measured_value = value

        if old_value != value
          @on_average_measured_value_changed.try &.call(old_value, value)
          increment_version
        end
      end

      # Check if NumericMeasurement feature is enabled
      def numeric_measurement_enabled? : Bool
        !@measured_value.nil?
      end

      # Check if LevelIndication feature is enabled
      def level_indication_enabled? : Bool
        !@level_value.nil?
      end

      # Check if PeakMeasurement feature is enabled
      def peak_measurement_enabled? : Bool
        !@peak_measured_value.nil?
      end

      # Check if AverageMeasurement feature is enabled
      def average_measurement_enabled? : Bool
        !@average_measured_value.nil?
      end

      # Callback when measured value changes
      @on_measured_value_changed : Proc(Float32?, Float32, Nil)?

      def on_measured_value_changed(&block : Float32?, Float32 -> Nil)
        @on_measured_value_changed = block
      end

      # Callback when level value changes
      @on_level_value_changed : Proc(LevelValue?, LevelValue, Nil)?

      def on_level_value_changed(&block : LevelValue?, LevelValue -> Nil)
        @on_level_value_changed = block
      end

      # Callback when peak measured value changes
      @on_peak_measured_value_changed : Proc(Float32?, Float32, Nil)?

      def on_peak_measured_value_changed(&block : Float32?, Float32 -> Nil)
        @on_peak_measured_value_changed = block
      end

      # Callback when average measured value changes
      @on_average_measured_value_changed : Proc(Float32?, Float32, Nil)?

      def on_average_measured_value_changed(&block : Float32?, Float32 -> Nil)
        @on_average_measured_value_changed = block
      end

      # NOTE: encode_uint32 inherited from Base class with proper TLV encoding
      # Do NOT override with raw byte encoding

      # encode_float uses TLV encoding for attribute responses
      private def encode_float(value : Float32) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put(nil, value)
        io.rewind.to_slice
      end
    end
  end
end
