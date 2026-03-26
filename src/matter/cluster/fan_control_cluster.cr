require "./cluster"

module Matter
  module Cluster
    # Fan Control Cluster (0x0202)
    #
    # Provides an interface to control the speed of a fan, including basic fan mode
    # control and percentage-based speed settings.
    #
    # Features:
    # - MultiSpeed (SPD): Multi-speed fan control with discrete speed levels
    # - Auto (AUTO): Automatic mode support
    # - Rocking (RCK): Rocking movement support
    # - Wind (WND): Wind emulation support
    # - Step (STEP): Step command support for incremental speed changes
    # - AirflowDirection (DIR): Airflow direction attribute
    #
    # Specification: Matter 1.4 § 4.4
    class FanControlCluster < Base
      CLUSTER_ID = 0x0202_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        MultiSpeed       = 0x01 # SPD - Multi-speed fan control
        Auto             = 0x02 # AUTO - Automatic mode support
        Rocking          = 0x04 # RCK - Rocking movement support
        Wind             = 0x08 # WND - Wind emulation support
        Step             = 0x10 # STEP - Step command support
        AirflowDirection = 0x20 # DIR - Airflow direction attribute
      end

      # Attributes - Required
      ATTR_FAN_MODE          = 0x0000_u32
      ATTR_FAN_MODE_SEQUENCE = 0x0001_u32
      ATTR_PERCENT_SETTING   = 0x0002_u32
      ATTR_PERCENT_CURRENT   = 0x0003_u32

      # Attributes - MultiSpeed feature
      ATTR_SPEED_MAX     = 0x0004_u32
      ATTR_SPEED_SETTING = 0x0005_u32
      ATTR_SPEED_CURRENT = 0x0006_u32

      # Attributes - Rocking feature
      ATTR_ROCK_SUPPORT = 0x0007_u32
      ATTR_ROCK_SETTING = 0x0008_u32

      # Attributes - Wind feature
      ATTR_WIND_SUPPORT = 0x0009_u32
      ATTR_WIND_SETTING = 0x000A_u32

      # Attributes - AirflowDirection feature
      ATTR_AIRFLOW_DIRECTION = 0x000B_u32

      # Commands
      CMD_STEP = 0x00_u32

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

      # Step direction for Step command
      enum StepDirection
        Increase = 0
        Decrease = 1
      end

      # Rock support bitmap
      @[Flags]
      enum RockSupport : UInt8
        RockLeftRight = 0x01
        RockUpDown    = 0x02
        RockRound     = 0x04
      end

      # Wind support bitmap
      @[Flags]
      enum WindSupport : UInt8
        SleepWind   = 0x01
        NaturalWind = 0x02
      end

      # Airflow direction values
      enum AirflowDirectionEnum
        Forward = 0
        Reverse = 1
      end

      # Feature map
      property feature_map : Feature

      # Required attributes
      property fan_mode : FanMode
      property fan_mode_sequence : FanModeSequence
      property percent_setting : UInt8?
      property percent_current : UInt8

      # MultiSpeed feature attributes
      property speed_max : UInt8
      property speed_setting : UInt8?
      property speed_current : UInt8

      # Rocking feature attributes
      property rock_support : RockSupport
      property rock_setting : RockSupport

      # Wind feature attributes
      property wind_support : WindSupport
      property wind_setting : WindSupport

      # AirflowDirection feature attribute
      property airflow_direction : AirflowDirectionEnum

      # Step command configuration
      property step_percent : UInt8

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @feature_map : Feature = Feature::None,
                     @fan_mode : FanMode = FanMode::Off,
                     @fan_mode_sequence : FanModeSequence = FanModeSequence::OffLowMedHigh,
                     @percent_setting : UInt8? = 0_u8,
                     @percent_current : UInt8 = 0_u8,
                     # MultiSpeed feature
                     @speed_max : UInt8 = 100_u8,
                     @speed_setting : UInt8? = 0_u8,
                     @speed_current : UInt8 = 0_u8,
                     # Rocking feature
                     @rock_support : RockSupport = RockSupport::None,
                     @rock_setting : RockSupport = RockSupport::None,
                     # Wind feature
                     @wind_support : WindSupport = WindSupport::None,
                     @wind_setting : WindSupport = WindSupport::None,
                     # AirflowDirection feature
                     @airflow_direction : AirflowDirectionEnum = AirflowDirectionEnum::Forward,
                     # Step command step size (percent per step)
                     @step_percent : UInt8 = 25_u8)
        # MultiSpeed is always enabled — percent and speed stay in sync transparently
        @feature_map |= Feature::MultiSpeed

        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate percent values (0-100)
        if setting = @percent_setting
          raise ArgumentError.new("percent_setting must be between 0 and 100") if setting > 100_u8
        end
        raise ArgumentError.new("percent_current must be between 0 and 100") if @percent_current > 100_u8

        # Validate speed values
        raise ArgumentError.new("speed_max must be at least 1") if @speed_max < 1_u8
        if setting = @speed_setting
          raise ArgumentError.new("speed_setting must be <= speed_max") if setting > @speed_max
        end
        raise ArgumentError.new("speed_current must be <= speed_max") if @speed_current > @speed_max

        # Validate fan mode is supported by the sequence
        validate_fan_mode(@fan_mode, @fan_mode_sequence)

        # Auto mode requires Auto feature if used
        if @fan_mode == FanMode::Auto && !@feature_map.auto?
          # Allow it in sequences that support Auto, even without the feature flag
          # The feature flag controls whether Auto behavior is automatic
        end

        # Validate rocking settings against support
        if @feature_map.rocking?
          invalid_rock = @rock_setting.value & ~@rock_support.value
          raise ArgumentError.new("rock_setting contains unsupported modes") if invalid_rock != 0
        end

        # Validate wind settings against support
        if @feature_map.wind?
          invalid_wind = @wind_setting.value & ~@wind_support.value
          raise ArgumentError.new("wind_setting contains unsupported modes") if invalid_wind != 0
        end
      end

      def name : String
        "FanControl"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_FAN_MODE),
            "fanMode",
            :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_FAN_MODE_SEQUENCE),
            "fanModeSequence",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PERCENT_SETTING),
            "percentSetting",
            :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PERCENT_CURRENT),
            "percentCurrent",
            :uint8,
            writable: false
          ),
        ]

        # MultiSpeed feature attributes
        if @feature_map.multi_speed?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SPEED_MAX),
            "speedMax",
            :uint8,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SPEED_SETTING),
            "speedSetting",
            :uint8,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SPEED_CURRENT),
            "speedCurrent",
            :uint8,
            writable: false
          )
        end

        # Rocking feature attributes
        if @feature_map.rocking?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ROCK_SUPPORT),
            "rockSupport",
            :uint8,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ROCK_SETTING),
            "rockSetting",
            :uint8,
            writable: true
          )
        end

        # Wind feature attributes
        if @feature_map.wind?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_WIND_SUPPORT),
            "windSupport",
            :uint8,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_WIND_SETTING),
            "windSetting",
            :uint8,
            writable: true
          )
        end

        # AirflowDirection feature attribute
        if @feature_map.airflow_direction?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_AIRFLOW_DIRECTION),
            "airflowDirection",
            :uint8,
            writable: true
          )
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        cmds = [] of CommandMetadata

        # Step command (Step feature)
        if @feature_map.step?
          cmds << CommandMetadata.new(
            DataType::CommandId.new(CMD_STEP),
            "step"
          )
        end

        cmds
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_FAN_MODE
          @fan_mode.value.to_u8.to_tlv
        when ATTR_FAN_MODE_SEQUENCE
          @fan_mode_sequence.value.to_u8.to_tlv
        when ATTR_PERCENT_SETTING
          if setting = @percent_setting
            setting.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_PERCENT_CURRENT
          @percent_current.to_tlv
        when ATTR_SPEED_MAX
          @speed_max.to_tlv
        when ATTR_SPEED_SETTING
          if setting = @speed_setting
            setting.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_SPEED_CURRENT
          @speed_current.to_tlv
        when ATTR_ROCK_SUPPORT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.rocking?
          @rock_support.value.to_tlv
        when ATTR_ROCK_SETTING
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.rocking?
          @rock_setting.value.to_tlv
        when ATTR_WIND_SUPPORT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.wind?
          @wind_support.value.to_tlv
        when ATTR_WIND_SETTING
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.wind?
          @wind_setting.value.to_tlv
        when ATTR_AIRFLOW_DIRECTION
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.airflow_direction?
          @airflow_direction.value.to_u8.to_tlv
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

          # When fan mode changes to Off, set percent and speed to 0
          if new_mode == FanMode::Off
            old_percent = @percent_setting
            @percent_setting = 0_u8
            @percent_current = 0_u8
            @speed_setting = 0_u8
            @speed_current = 0_u8
            # Fire percent callback if percent changed
            if old_percent != 0_u8
              @on_percent_changed.try &.call(old_percent, 0_u8)
            end
          end

          @on_fan_mode_changed.try &.call(old_mode, new_mode)
          increment_version_and_notify(ATTR_FAN_MODE)

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_PERCENT_SETTING
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1

          new_percent = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if new_percent > 100_u8

          old_percent = @percent_setting
          old_speed = @speed_setting
          @percent_setting = new_percent

          # When percent is set to 0, turn fan off
          if new_percent == 0_u8
            @fan_mode = FanMode::Off
            @percent_current = 0_u8
            @speed_setting = 0_u8
            @speed_current = 0_u8
          else
            # When setting non-zero percent, ensure fan is not off
            if @fan_mode == FanMode::Off
              @fan_mode = default_on_mode(@fan_mode_sequence)
            end
            @percent_current = new_percent

            # Sync speed from percent
            new_speed = percent_to_speed(new_percent)
            @speed_setting = new_speed
            @speed_current = new_speed
          end

          @on_percent_changed.try &.call(old_percent, new_percent)
          if @speed_setting != old_speed
            @on_speed_changed.try &.call(old_speed, @speed_setting || 0_u8)
          end
          increment_version_and_notify(ATTR_PERCENT_SETTING)

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_SPEED_SETTING
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1

          new_speed = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if new_speed > @speed_max

          old_speed = @speed_setting
          old_percent = @percent_setting
          @speed_setting = new_speed
          @speed_current = new_speed

          # Sync percent from speed
          new_percent = speed_to_percent(new_speed)
          @percent_setting = new_percent
          @percent_current = new_percent

          if new_speed == 0_u8
            @fan_mode = FanMode::Off
          elsif @fan_mode == FanMode::Off
            @fan_mode = default_on_mode(@fan_mode_sequence)
          end

          @on_speed_changed.try &.call(old_speed, new_speed)
          if @percent_setting != old_percent
            @on_percent_changed.try &.call(old_percent, new_percent)
          end
          increment_version_and_notify(ATTR_SPEED_SETTING)

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_ROCK_SETTING
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.rocking?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1

          new_setting = value[0]
          # Validate against rock_support
          invalid_bits = new_setting & ~@rock_support.value
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if invalid_bits != 0

          @rock_setting = RockSupport.from_value(new_setting)
          increment_version_and_notify(ATTR_ROCK_SETTING)

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_WIND_SETTING
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.wind?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1

          new_setting = value[0]
          # Validate against wind_support
          invalid_bits = new_setting & ~@wind_support.value
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if invalid_bits != 0

          @wind_setting = WindSupport.from_value(new_setting)
          increment_version_and_notify(ATTR_WIND_SETTING)

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_AIRFLOW_DIRECTION
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.airflow_direction?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1

          direction_value = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if direction_value > 1_u8

          @airflow_direction = AirflowDirectionEnum.from_value(direction_value.to_i)
          increment_version_and_notify(ATTR_AIRFLOW_DIRECTION)

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      def invoke_command(command_id : UInt32, command_data : Bytes) : Bytes | InteractionModel::Status
        case command_id
        when CMD_STEP
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) unless @feature_map.step?
          handle_step_command(command_data)
        else
          super
        end
      end

      protected def encode_feature_map_global : Bytes
        @feature_map.value.to_tlv
      end

      private def handle_step_command(data : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if data.size < 1

        direction = StepDirection.from_value(data[0].to_i)

        # Optional wrap parameter (defaults to false)
        wrap = data.size > 1 && data[1] != 0

        # Optional lowest_off parameter (defaults to true)
        lowest_off = data.size <= 2 || data[2] != 0

        old_percent = @percent_setting
        old_mode = @fan_mode
        current = @percent_current

        case direction
        when StepDirection::Increase
          if current >= 100_u8
            if wrap
              @percent_current = lowest_off ? 0_u8 : 1_u8
              @percent_setting = @percent_current
              if @percent_current == 0_u8
                @fan_mode = FanMode::Off
              end
            end
          else
            # Step size is implementation-defined
            new_percent = Math.min(current.to_u16 + @step_percent, 100_u16).to_u8
            @percent_current = new_percent
            @percent_setting = new_percent
            if @fan_mode == FanMode::Off
              @fan_mode = default_on_mode(@fan_mode_sequence)
            end
          end
        when StepDirection::Decrease
          if current == 0_u8 || (lowest_off && current <= @step_percent)
            if wrap
              @percent_current = 100_u8
              @percent_setting = 100_u8
              if @fan_mode == FanMode::Off
                @fan_mode = default_on_mode(@fan_mode_sequence)
              end
            elsif lowest_off
              @percent_current = 0_u8
              @percent_setting = 0_u8
              @fan_mode = FanMode::Off
            end
          else
            new_percent = current > @step_percent ? current - @step_percent : (lowest_off ? 0_u8 : 1_u8)
            @percent_current = new_percent
            @percent_setting = new_percent
            if new_percent == 0_u8
              @fan_mode = FanMode::Off
            end
          end
        end

        # Sync speed from percent
        new_speed = percent_to_speed(@percent_current)
        @speed_setting = new_speed
        @speed_current = new_speed

        # Fire callbacks if values changed
        if @percent_setting != old_percent
          @on_percent_changed.try &.call(old_percent, @percent_setting || 0_u8)
        end
        if @fan_mode != old_mode
          @on_fan_mode_changed.try &.call(old_mode, @fan_mode)
        end

        increment_version_and_notify(ATTR_PERCENT_SETTING)
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Update the current fan speed percentage (read-only attribute updated by implementation)
      def update_percent_current(percent : UInt8)
        raise ArgumentError.new("percent_current must be between 0 and 100") if percent > 100_u8

        old_value = @percent_current
        @percent_current = percent

        if old_value != percent
          increment_version_and_notify(ATTR_PERCENT_CURRENT)
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

      # Callback when speed setting changes (MultiSpeed feature)
      @on_speed_changed : Proc(UInt8?, UInt8, Nil)?

      def on_speed_changed(&block : UInt8?, UInt8 -> Nil)
        @on_speed_changed = block
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

      # Convert percent (0-100) to speed (0-speed_max)
      private def percent_to_speed(percent : UInt8) : UInt8
        (percent.to_f / 100.0 * @speed_max).round.to_u8
      end

      # Convert speed (0-speed_max) to percent (0-100)
      private def speed_to_percent(speed : UInt8) : UInt8
        (speed.to_f / @speed_max * 100).round.to_u8
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
