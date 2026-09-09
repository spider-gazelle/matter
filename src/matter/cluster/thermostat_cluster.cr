require "./cluster"
require "./definitions/thermostat"

module Matter
  module Cluster
    # Thermostat Cluster (0x0201)
    #
    # Provides an interface to thermostat functionality, including configuration
    # of setpoints, scheduling, and mode control.
    #
    # Specification: Matter 1.4 § 4.3
    class ThermostatCluster < Base
      CLUSTER_ID = 0x0201_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        Heating  = 0x01 # HEAT - Heating capability
        Cooling  = 0x02 # COOL - Cooling capability
        Automode = 0x20 # AUTO - Automatic setpoint management
      end

      # System mode values
      enum SystemMode : UInt8
        Off           = 0
        Auto          = 1
        Cool          = 3
        Heat          = 4
        EmergencyHeat = 5
        Precooling    = 6
        FanOnly       = 7
        Dry           = 8
        Sleep         = 9
      end

      # Thermostat running mode
      enum ThermostatRunningMode : UInt8
        Off  = 0
        Cool = 3
        Heat = 4
      end

      # Control sequence of operation
      enum ControlSequenceOfOperation : UInt8
        CoolingOnly                 = 0
        CoolingWithReheat           = 1
        HeatingOnly                 = 2
        HeatingWithReheat           = 3
        CoolingAndHeating           = 4
        CoolingAndHeatingWithReheat = 5
      end

      # Attributes
      ATTR_LOCAL_TEMPERATURE             = 0x0000_u32
      ATTR_OUTDOOR_TEMPERATURE           = 0x0001_u32
      ATTR_ABS_MIN_HEAT_SETPOINT_LIMIT   = 0x0003_u32
      ATTR_ABS_MAX_HEAT_SETPOINT_LIMIT   = 0x0004_u32
      ATTR_ABS_MIN_COOL_SETPOINT_LIMIT   = 0x0005_u32
      ATTR_ABS_MAX_COOL_SETPOINT_LIMIT   = 0x0006_u32
      ATTR_OCCUPIED_COOLING_SETPOINT     = 0x0011_u32
      ATTR_OCCUPIED_HEATING_SETPOINT     = 0x0012_u32
      ATTR_MIN_HEAT_SETPOINT_LIMIT       = 0x0015_u32
      ATTR_MAX_HEAT_SETPOINT_LIMIT       = 0x0016_u32
      ATTR_MIN_COOL_SETPOINT_LIMIT       = 0x0017_u32
      ATTR_MAX_COOL_SETPOINT_LIMIT       = 0x0018_u32
      ATTR_MIN_SETPOINT_DEAD_BAND        = 0x0019_u32
      ATTR_CONTROL_SEQUENCE_OF_OPERATION = 0x001B_u32
      ATTR_SYSTEM_MODE                   = 0x001C_u32
      ATTR_THERMOSTAT_RUNNING_MODE       = 0x001E_u32

      # Commands
      CMD_SETPOINT_RAISE_LOWER = 0x00_u32

      # Default temperature limits (in 0.01°C)
      DEFAULT_ABS_MIN_HEAT =  700_i16 #  7.00°C
      DEFAULT_ABS_MAX_HEAT = 3000_i16 # 30.00°C
      DEFAULT_ABS_MIN_COOL = 1600_i16 # 16.00°C
      DEFAULT_ABS_MAX_COOL = 3200_i16 # 32.00°C

      # Feature map
      property feature_map : Feature

      # Required attributes
      property local_temperature : Int16?

      # Setpoints (in 0.01°C)
      property occupied_cooling_setpoint : Int16
      property occupied_heating_setpoint : Int16

      # Absolute limits (read-only)
      property abs_min_heat_setpoint_limit : Int16
      property abs_max_heat_setpoint_limit : Int16
      property abs_min_cool_setpoint_limit : Int16
      property abs_max_cool_setpoint_limit : Int16

      # Configurable limits
      property min_heat_setpoint_limit : Int16
      property max_heat_setpoint_limit : Int16
      property min_cool_setpoint_limit : Int16
      property max_cool_setpoint_limit : Int16

      # Dead band (in 0.1°C, for Auto mode)
      property min_setpoint_dead_band : Int8

      # Mode control
      property control_sequence_of_operation : ControlSequenceOfOperation
      property system_mode : SystemMode
      property thermostat_running_mode : ThermostatRunningMode

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @feature_map : Feature = Feature::Cooling | Feature::Heating,
                     @local_temperature : Int16? = nil,
                     @occupied_cooling_setpoint : Int16 = 2600_i16,
                     @occupied_heating_setpoint : Int16 = 2000_i16,
                     @abs_min_heat_setpoint_limit : Int16 = DEFAULT_ABS_MIN_HEAT,
                     @abs_max_heat_setpoint_limit : Int16 = DEFAULT_ABS_MAX_HEAT,
                     @abs_min_cool_setpoint_limit : Int16 = DEFAULT_ABS_MIN_COOL,
                     @abs_max_cool_setpoint_limit : Int16 = DEFAULT_ABS_MAX_COOL,
                     @min_heat_setpoint_limit : Int16 = DEFAULT_ABS_MIN_HEAT,
                     @max_heat_setpoint_limit : Int16 = DEFAULT_ABS_MAX_HEAT,
                     @min_cool_setpoint_limit : Int16 = DEFAULT_ABS_MIN_COOL,
                     @max_cool_setpoint_limit : Int16 = DEFAULT_ABS_MAX_COOL,
                     @min_setpoint_dead_band : Int8 = 25_i8,
                     @control_sequence_of_operation : ControlSequenceOfOperation = ControlSequenceOfOperation::CoolingAndHeating,
                     @system_mode : SystemMode = SystemMode::Off,
                     @thermostat_running_mode : ThermostatRunningMode = ThermostatRunningMode::Off)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        validate_setpoint_limits
        validate_system_mode(@system_mode)
      end

      def name : String
        "Thermostat"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_LOCAL_TEMPERATURE),
            "LocalTemperature",
            :int16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CONTROL_SEQUENCE_OF_OPERATION),
            "ControlSequenceOfOperation",
            :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SYSTEM_MODE),
            "SystemMode",
            :uint8,
            writable: true
          ),
        ]

        if @feature_map.cooling?
          attrs.concat([
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_ABS_MIN_COOL_SETPOINT_LIMIT),
              "AbsMinCoolSetpointLimit",
              :int16,
              writable: false
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_ABS_MAX_COOL_SETPOINT_LIMIT),
              "AbsMaxCoolSetpointLimit",
              :int16,
              writable: false
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_OCCUPIED_COOLING_SETPOINT),
              "OccupiedCoolingSetpoint",
              :int16,
              writable: true
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_MIN_COOL_SETPOINT_LIMIT),
              "MinCoolSetpointLimit",
              :int16,
              writable: true
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_MAX_COOL_SETPOINT_LIMIT),
              "MaxCoolSetpointLimit",
              :int16,
              writable: true
            ),
          ])
        end

        if @feature_map.heating?
          attrs.concat([
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_ABS_MIN_HEAT_SETPOINT_LIMIT),
              "AbsMinHeatSetpointLimit",
              :int16,
              writable: false
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_ABS_MAX_HEAT_SETPOINT_LIMIT),
              "AbsMaxHeatSetpointLimit",
              :int16,
              writable: false
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_OCCUPIED_HEATING_SETPOINT),
              "OccupiedHeatingSetpoint",
              :int16,
              writable: true
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_MIN_HEAT_SETPOINT_LIMIT),
              "MinHeatSetpointLimit",
              :int16,
              writable: true
            ),
            AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_MAX_HEAT_SETPOINT_LIMIT),
              "MaxHeatSetpointLimit",
              :int16,
              writable: true
            ),
          ])
        end

        if @feature_map.automode?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_MIN_SETPOINT_DEAD_BAND),
            "MinSetpointDeadBand",
            :int8,
            writable: true
          )
        end

        attrs << AttributeMetadata.new(
          DataType::AttributeId.new(ATTR_THERMOSTAT_RUNNING_MODE),
          "ThermostatRunningMode",
          :uint8,
          writable: false
        )

        attrs
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_SETPOINT_RAISE_LOWER),
            "SetpointRaiseLower"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_LOCAL_TEMPERATURE
          if temp = @local_temperature
            encode_int16(temp)
          else
            nil.to_tlv
          end
        when ATTR_ABS_MIN_HEAT_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.heating?
          encode_int16(@abs_min_heat_setpoint_limit)
        when ATTR_ABS_MAX_HEAT_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.heating?
          encode_int16(@abs_max_heat_setpoint_limit)
        when ATTR_ABS_MIN_COOL_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.cooling?
          encode_int16(@abs_min_cool_setpoint_limit)
        when ATTR_ABS_MAX_COOL_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.cooling?
          encode_int16(@abs_max_cool_setpoint_limit)
        when ATTR_OCCUPIED_COOLING_SETPOINT
          return unsupported_attribute unless @feature_map.cooling?
          encode_int16(@occupied_cooling_setpoint)
        when ATTR_OCCUPIED_HEATING_SETPOINT
          return unsupported_attribute unless @feature_map.heating?
          encode_int16(@occupied_heating_setpoint)
        when ATTR_MIN_HEAT_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.heating?
          encode_int16(@min_heat_setpoint_limit)
        when ATTR_MAX_HEAT_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.heating?
          encode_int16(@max_heat_setpoint_limit)
        when ATTR_MIN_COOL_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.cooling?
          encode_int16(@min_cool_setpoint_limit)
        when ATTR_MAX_COOL_SETPOINT_LIMIT
          return unsupported_attribute unless @feature_map.cooling?
          encode_int16(@max_cool_setpoint_limit)
        when ATTR_MIN_SETPOINT_DEAD_BAND
          return unsupported_attribute unless @feature_map.automode?
          TLV::Any.new(@min_setpoint_dead_band, nil).to_slice
        when ATTR_CONTROL_SEQUENCE_OF_OPERATION
          @control_sequence_of_operation.value.to_u8.to_tlv
        when ATTR_SYSTEM_MODE
          @system_mode.value.to_u8.to_tlv
        when ATTR_THERMOSTAT_RUNNING_MODE
          @thermostat_running_mode.value.to_u8.to_tlv
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_OCCUPIED_COOLING_SETPOINT
          return unsupported_attribute_status unless @feature_map.cooling?
          new_setpoint = decode_i16(value)
          return invalid_data_type unless new_setpoint
          return constraint_error unless new_setpoint >= @min_cool_setpoint_limit && new_setpoint <= @max_cool_setpoint_limit

          old_setpoint = @occupied_cooling_setpoint
          @occupied_cooling_setpoint = new_setpoint
          @on_setpoint_changed.try &.call(:cool, old_setpoint, new_setpoint)
          increment_version_and_notify(ATTR_OCCUPIED_COOLING_SETPOINT)
          success
        when ATTR_OCCUPIED_HEATING_SETPOINT
          return unsupported_attribute_status unless @feature_map.heating?
          new_setpoint = decode_i16(value)
          return invalid_data_type unless new_setpoint
          return constraint_error unless new_setpoint >= @min_heat_setpoint_limit && new_setpoint <= @max_heat_setpoint_limit

          old_setpoint = @occupied_heating_setpoint
          @occupied_heating_setpoint = new_setpoint
          @on_setpoint_changed.try &.call(:heat, old_setpoint, new_setpoint)
          increment_version_and_notify(ATTR_OCCUPIED_HEATING_SETPOINT)
          success
        when ATTR_SYSTEM_MODE
          mode_value = decode_u8(value)
          return invalid_data_type unless mode_value

          begin
            new_mode = SystemMode.from_value(mode_value)
          rescue
            return constraint_error
          end

          unless mode_allowed?(new_mode)
            return constraint_error
          end

          old_mode = @system_mode
          @system_mode = new_mode
          update_running_mode
          @on_system_mode_changed.try &.call(old_mode, new_mode)
          increment_version_and_notify(ATTR_SYSTEM_MODE)
          success
        when ATTR_CONTROL_SEQUENCE_OF_OPERATION
          seq_value = decode_u8(value)
          return invalid_data_type unless seq_value

          begin
            new_seq = ControlSequenceOfOperation.from_value(seq_value)
          rescue
            return constraint_error
          end

          @control_sequence_of_operation = new_seq
          increment_version_and_notify(ATTR_CONTROL_SEQUENCE_OF_OPERATION)
          success
        when ATTR_MIN_HEAT_SETPOINT_LIMIT
          return unsupported_attribute_status unless @feature_map.heating?
          new_limit = decode_i16(value)
          return invalid_data_type unless new_limit
          return constraint_error unless new_limit >= @abs_min_heat_setpoint_limit && new_limit <= @max_heat_setpoint_limit

          @min_heat_setpoint_limit = new_limit
          increment_version_and_notify(ATTR_MIN_HEAT_SETPOINT_LIMIT)
          success
        when ATTR_MAX_HEAT_SETPOINT_LIMIT
          return unsupported_attribute_status unless @feature_map.heating?
          new_limit = decode_i16(value)
          return invalid_data_type unless new_limit
          return constraint_error unless new_limit >= @min_heat_setpoint_limit && new_limit <= @abs_max_heat_setpoint_limit

          @max_heat_setpoint_limit = new_limit
          increment_version_and_notify(ATTR_MAX_HEAT_SETPOINT_LIMIT)
          success
        when ATTR_MIN_COOL_SETPOINT_LIMIT
          return unsupported_attribute_status unless @feature_map.cooling?
          new_limit = decode_i16(value)
          return invalid_data_type unless new_limit
          return constraint_error unless new_limit >= @abs_min_cool_setpoint_limit && new_limit <= @max_cool_setpoint_limit

          @min_cool_setpoint_limit = new_limit
          increment_version_and_notify(ATTR_MIN_COOL_SETPOINT_LIMIT)
          success
        when ATTR_MAX_COOL_SETPOINT_LIMIT
          return unsupported_attribute_status unless @feature_map.cooling?
          new_limit = decode_i16(value)
          return invalid_data_type unless new_limit
          return constraint_error unless new_limit >= @min_cool_setpoint_limit && new_limit <= @abs_max_cool_setpoint_limit

          @max_cool_setpoint_limit = new_limit
          increment_version_and_notify(ATTR_MAX_COOL_SETPOINT_LIMIT)
          success
        when ATTR_MIN_SETPOINT_DEAD_BAND
          return unsupported_attribute_status unless @feature_map.automode?
          dead_band = decode_i8(value)
          return invalid_data_type unless dead_band

          @min_setpoint_dead_band = dead_band
          increment_version_and_notify(ATTR_MIN_SETPOINT_DEAD_BAND)
          success
        else
          super
        end
      end

      def invoke_command(command_id : UInt32, command_data : Bytes) : Bytes | InteractionModel::Status
        case command_id
        when CMD_SETPOINT_RAISE_LOWER
          handle_setpoint_raise_lower(command_data)
        else
          super
        end
      end

      # Update local temperature (typically called from a paired temperature sensor)
      def update_local_temperature(value : Int16?)
        old_value = @local_temperature
        @local_temperature = value

        if old_value != value
          increment_version_and_notify(ATTR_LOCAL_TEMPERATURE)
          update_running_mode
        end
      end

      # Programmatic setpoint update
      def cooling_setpoint=(value : Int16)
        return unless @feature_map.cooling?
        return unless value >= @min_cool_setpoint_limit && value <= @max_cool_setpoint_limit

        old = @occupied_cooling_setpoint
        @occupied_cooling_setpoint = value
        @on_setpoint_changed.try &.call(:cool, old, value) if old != value
        increment_version if old != value
      end

      def heating_setpoint=(value : Int16)
        return unless @feature_map.heating?
        return unless value >= @min_heat_setpoint_limit && value <= @max_heat_setpoint_limit

        old = @occupied_heating_setpoint
        @occupied_heating_setpoint = value
        @on_setpoint_changed.try &.call(:heat, old, value) if old != value
        increment_version if old != value
      end

      # Programmatic mode change
      def system_mode=(mode : SystemMode)
        return unless mode_allowed?(mode)

        old = @system_mode
        @system_mode = mode
        update_running_mode
        @on_system_mode_changed.try &.call(old, mode) if old != mode
        increment_version if old != mode
      end

      # Callbacks
      @on_system_mode_changed : Proc(SystemMode, SystemMode, Nil)?
      @on_setpoint_changed : Proc(Symbol, Int16, Int16, Nil)?

      def on_system_mode_changed(&block : SystemMode, SystemMode -> Nil)
        @on_system_mode_changed = block
      end

      def on_setpoint_changed(&block : Symbol, Int16, Int16 -> Nil)
        @on_setpoint_changed = block
      end

      private def handle_setpoint_raise_lower(command_data : Bytes) : InteractionModel::Status
        request = Definitions::Thermostat::SetpointRaiseLowerRequest.from_slice(command_data)

        # Amount is in 0.1°C steps, convert to 0.01°C
        delta = request.amount.to_i16 * 10_i16

        case request.mode
        when Definitions::Thermostat::SetpointAdjustMode::Heat
          if @feature_map.heating?
            new_setpoint = (@occupied_heating_setpoint + delta).clamp(@min_heat_setpoint_limit, @max_heat_setpoint_limit)
            old = @occupied_heating_setpoint
            @occupied_heating_setpoint = new_setpoint
            @on_setpoint_changed.try &.call(:heat, old, new_setpoint) if old != new_setpoint
          end
        when Definitions::Thermostat::SetpointAdjustMode::Cool
          if @feature_map.cooling?
            new_setpoint = (@occupied_cooling_setpoint + delta).clamp(@min_cool_setpoint_limit, @max_cool_setpoint_limit)
            old = @occupied_cooling_setpoint
            @occupied_cooling_setpoint = new_setpoint
            @on_setpoint_changed.try &.call(:cool, old, new_setpoint) if old != new_setpoint
          end
        when Definitions::Thermostat::SetpointAdjustMode::Both
          if @feature_map.heating?
            new_heat = (@occupied_heating_setpoint + delta).clamp(@min_heat_setpoint_limit, @max_heat_setpoint_limit)
            old_heat = @occupied_heating_setpoint
            @occupied_heating_setpoint = new_heat
            @on_setpoint_changed.try &.call(:heat, old_heat, new_heat) if old_heat != new_heat
          end
          if @feature_map.cooling?
            new_cool = (@occupied_cooling_setpoint + delta).clamp(@min_cool_setpoint_limit, @max_cool_setpoint_limit)
            old_cool = @occupied_cooling_setpoint
            @occupied_cooling_setpoint = new_cool
            @on_setpoint_changed.try &.call(:cool, old_cool, new_cool) if old_cool != new_cool
          end
        end

        increment_version
        success
      end

      private def update_running_mode
        @thermostat_running_mode = case @system_mode
                                   when SystemMode::Cool, SystemMode::Precooling
                                     ThermostatRunningMode::Cool
                                   when SystemMode::Heat, SystemMode::EmergencyHeat
                                     ThermostatRunningMode::Heat
                                   when SystemMode::Auto
                                     # Determine based on temperature vs setpoints
                                     if temp = @local_temperature
                                       if temp > @occupied_cooling_setpoint
                                         ThermostatRunningMode::Cool
                                       elsif temp < @occupied_heating_setpoint
                                         ThermostatRunningMode::Heat
                                       else
                                         ThermostatRunningMode::Off
                                       end
                                     else
                                       ThermostatRunningMode::Off
                                     end
                                   else
                                     ThermostatRunningMode::Off
                                   end
      end

      private def mode_allowed?(mode : SystemMode) : Bool
        case mode
        when SystemMode::Off, SystemMode::FanOnly, SystemMode::Dry, SystemMode::Sleep
          true
        when SystemMode::Cool, SystemMode::Precooling
          @feature_map.cooling?
        when SystemMode::Heat, SystemMode::EmergencyHeat
          @feature_map.heating?
        when SystemMode::Auto
          @feature_map.automode?
        else
          false
        end
      end

      private def validate_setpoint_limits
        if @feature_map.heating?
          raise ArgumentError.new("min_heat_setpoint_limit must be >= abs minimum") if @min_heat_setpoint_limit < @abs_min_heat_setpoint_limit
          raise ArgumentError.new("max_heat_setpoint_limit must be <= abs maximum") if @max_heat_setpoint_limit > @abs_max_heat_setpoint_limit
        end

        if @feature_map.cooling?
          raise ArgumentError.new("min_cool_setpoint_limit must be >= abs minimum") if @min_cool_setpoint_limit < @abs_min_cool_setpoint_limit
          raise ArgumentError.new("max_cool_setpoint_limit must be <= abs maximum") if @max_cool_setpoint_limit > @abs_max_cool_setpoint_limit
        end
      end

      private def validate_system_mode(mode : SystemMode)
        unless mode_allowed?(mode)
          raise ArgumentError.new("SystemMode #{mode} not supported with current features")
        end
      end

      protected def encode_feature_map_global : Bytes
        @feature_map.value.to_tlv
      end

      private def encode_int16(value : Int16) : Bytes
        TLV::Any.new(value, nil).to_slice
      end

      private def unsupported_attribute : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
      end

      private def unsupported_attribute_status : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
      end

      private def invalid_data_type : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
      end

      private def constraint_error : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
      end

      private def success : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end
    end
  end
end
