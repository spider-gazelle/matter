require "./cluster"

module Matter
  module Cluster
    # Fan Control Cluster (0x0202)
    #
    # Provides an interface to control the speed of a fan, including basic fan mode
    # control and percentage-based speed settings.
    #
    # This implementation provides the base functionality without optional features
    # (MultiSpeed, Rocking, Wind, AirflowDirection, Step).
    #
    # Specification: Matter 1.4 § 4.4
    class FanControlCluster < Base
      CLUSTER_ID = 0x0202_u32

      # Attributes
      ATTR_FAN_MODE          = 0x0000_u32
      ATTR_FAN_MODE_SEQUENCE = 0x0001_u32
      ATTR_PERCENT_SETTING   = 0x0002_u32
      ATTR_PERCENT_CURRENT   = 0x0003_u32

      # Fan mode values
      enum FanMode
        Off    = 0
        Low    = 1
        Medium = 2
        High   = 3
        On     = 4 # Deprecated but still supported for legacy compatibility
        Auto   = 5
        Smart  = 6 # Deprecated but still supported for legacy compatibility
      end

      # Fan mode sequence values (indicates which modes are supported)
      enum FanModeSequence
        OffLowMedHigh     = 0 # Fan supports: Off, Low, Medium, High
        OffLowHigh        = 1 # Fan supports: Off, Low, High
        OffLowMedHighAuto = 2 # Fan supports: Off, Low, Medium, High, Auto
        OffLowHighAuto    = 3 # Fan supports: Off, Low, High, Auto
        OffHighAuto       = 4 # Fan supports: Off, High, Auto
        OffHigh           = 5 # Fan supports: Off, High
      end

      # Current fan mode (writable)
      property fan_mode : FanMode

      # Supported fan mode sequence (fixed)
      property fan_mode_sequence : FanModeSequence

      # Desired fan speed percentage (0-100, nullable, writable)
      property percent_setting : UInt8?

      # Current actual fan speed percentage (0-100)
      property percent_current : UInt8

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @fan_mode : FanMode = FanMode::Off,
                     @fan_mode_sequence : FanModeSequence = FanModeSequence::OffLowMedHigh,
                     @percent_setting : UInt8? = 0_u8,
                     @percent_current : UInt8 = 0_u8)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate percent values (0-100)
        if setting = @percent_setting
          raise ArgumentError.new("percent_setting must be between 0 and 100") if setting > 100_u8
        end
        raise ArgumentError.new("percent_current must be between 0 and 100") if @percent_current > 100_u8

        # Validate fan mode is supported by the sequence
        validate_fan_mode(@fan_mode, @fan_mode_sequence)
      end

      def name : String
        "FanControl"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_FAN_MODE),
            "FanMode",
            :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_FAN_MODE_SEQUENCE),
            "FanModeSequence",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PERCENT_SETTING),
            "PercentSetting",
            :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PERCENT_CURRENT),
            "PercentCurrent",
            :uint8,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands in base cluster (Step command is optional feature)
      end

      def read_attribute(attribute_id : UInt32) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_FAN_MODE
          Bytes[@fan_mode.value.to_u8]
        when ATTR_FAN_MODE_SEQUENCE
          Bytes[@fan_mode_sequence.value.to_u8]
        when ATTR_PERCENT_SETTING
          if setting = @percent_setting
            Bytes[setting]
          else
            # Null value - return special null encoding
            # For now, return 0 as the spec says null preserves current value
            Bytes[0_u8]
          end
        when ATTR_PERCENT_CURRENT
          Bytes[@percent_current]
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_FAN_MODE
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1

          mode_value = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if mode_value > 6_u8

          new_mode = FanMode.from_value(mode_value)

          # Validate mode is supported by sequence
          unless mode_supported?(new_mode, @fan_mode_sequence)
            return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end

          old_mode = @fan_mode
          @fan_mode = new_mode

          # When fan mode changes to Off, set percent to 0
          if new_mode == FanMode::Off
            old_percent = @percent_setting
            @percent_setting = 0_u8
            @percent_current = 0_u8
            # Fire percent callback if percent changed
            if old_percent != 0_u8
              @on_percent_changed.try &.call(old_percent, 0_u8)
            end
          end

          # Call callback if registered
          @on_fan_mode_changed.try &.call(old_mode, new_mode)
          increment_version

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_PERCENT_SETTING
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1

          new_percent = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if new_percent > 100_u8

          old_percent = @percent_setting
          @percent_setting = new_percent

          # When percent is set to 0, turn fan off
          if new_percent == 0_u8
            @fan_mode = FanMode::Off
            @percent_current = 0_u8
          else
            # When setting non-zero percent, ensure fan is not off
            if @fan_mode == FanMode::Off
              # Set to a reasonable default mode based on sequence
              @fan_mode = default_on_mode(@fan_mode_sequence)
            end
            # In a real implementation, percent_current would be updated by hardware
            # For now, we'll set it to match the setting
            @percent_current = new_percent
          end

          # Call callback if registered
          @on_percent_changed.try &.call(old_percent, new_percent)
          increment_version

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # Update the current fan speed percentage (read-only attribute updated by implementation)
      def update_percent_current(percent : UInt8)
        raise ArgumentError.new("percent_current must be between 0 and 100") if percent > 100_u8

        old_value = @percent_current
        @percent_current = percent

        if old_value != percent
          increment_version
        end
      end

      # Callback when fan mode changes
      @on_fan_mode_changed : Proc(FanMode, FanMode, Nil)?

      def on_fan_mode_changed(&block : FanMode, FanMode -> Nil)
        @on_fan_mode_changed = block
      end

      # Callback when percent setting changes
      @on_percent_changed : Proc(UInt8?, UInt8, Nil)?

      def on_percent_changed(&block : UInt8?, UInt8 -> Nil)
        @on_percent_changed = block
      end

      # Validate that a fan mode is supported by the given sequence
      private def validate_fan_mode(mode : FanMode, sequence : FanModeSequence)
        unless mode_supported?(mode, sequence)
          raise ArgumentError.new("FanMode #{mode} not supported by FanModeSequence #{sequence}")
        end
      end

      # Check if a fan mode is supported by the given sequence
      private def mode_supported?(mode : FanMode, sequence : FanModeSequence) : Bool
        # Off is always supported
        return true if mode == FanMode::Off

        # Deprecated modes (On, Smart) are allowed for backward compatibility
        return true if mode.in?(FanMode::On, FanMode::Smart)

        case sequence
        when FanModeSequence::OffLowMedHigh
          mode.in?(FanMode::Low, FanMode::Medium, FanMode::High)
        when FanModeSequence::OffLowHigh
          mode.in?(FanMode::Low, FanMode::High)
        when FanModeSequence::OffLowMedHighAuto
          mode.in?(FanMode::Low, FanMode::Medium, FanMode::High, FanMode::Auto)
        when FanModeSequence::OffLowHighAuto
          mode.in?(FanMode::Low, FanMode::High, FanMode::Auto)
        when FanModeSequence::OffHighAuto
          mode.in?(FanMode::High, FanMode::Auto)
        when FanModeSequence::OffHigh
          mode == FanMode::High
        else
          false
        end
      end

      # Get default "on" mode for a given sequence
      private def default_on_mode(sequence : FanModeSequence) : FanMode
        case sequence
        when FanModeSequence::OffLowMedHigh, FanModeSequence::OffLowHigh,
             FanModeSequence::OffLowMedHighAuto, FanModeSequence::OffLowHighAuto
          FanMode::Low
        when FanModeSequence::OffHighAuto, FanModeSequence::OffHigh
          FanMode::High
        else
          FanMode::Low
        end
      end
    end
  end
end
