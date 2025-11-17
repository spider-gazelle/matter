require "./cluster"
require "./definitions/color_control"

module Matter
  module Cluster
    # Color Control Cluster Implementation (0x0300)
    #
    # Provides color control functionality for RGB and tunable white lights.
    # Supports multiple color modes: Hue/Saturation, XY, and Color Temperature.
    #
    # Matter Spec: Application 3.2
    class ColorControlCluster < Base
      CLUSTER_ID = 0x0300_u32

      # Attributes (using ATTR_ prefix for consistency)
      ATTR_CURRENT_HUE                    = 0x0000_u32
      ATTR_CURRENT_SATURATION             = 0x0001_u32
      ATTR_REMAINING_TIME                 = 0x0002_u32
      ATTR_CURRENT_X                      = 0x0003_u32
      ATTR_CURRENT_Y                      = 0x0004_u32
      ATTR_DRIFT_COMPENSATION             = 0x0005_u32
      ATTR_COMPENSATION_TEXT              = 0x0006_u32
      ATTR_COLOR_TEMPERATURE_MIREDS       = 0x0007_u32
      ATTR_COLOR_MODE                     = 0x0008_u32
      ATTR_OPTIONS                        = 0x000F_u32
      ATTR_NUMBER_OF_PRIMARIES            = 0x0010_u32
      ATTR_ENHANCED_CURRENT_HUE           = 0x4000_u32
      ATTR_ENHANCED_COLOR_MODE            = 0x4001_u32
      ATTR_COLOR_LOOP_ACTIVE              = 0x4002_u32
      ATTR_COLOR_LOOP_DIRECTION           = 0x4003_u32
      ATTR_COLOR_LOOP_TIME                = 0x4004_u32
      ATTR_COLOR_LOOP_START_ENHANCED_HUE  = 0x4005_u32
      ATTR_COLOR_LOOP_STORED_ENHANCED_HUE = 0x4006_u32
      ATTR_COLOR_CAPABILITIES             = 0x400A_u32
      ATTR_COLOR_TEMP_PHYSICAL_MIN_MIREDS = 0x400B_u32
      ATTR_COLOR_TEMP_PHYSICAL_MAX_MIREDS = 0x400C_u32
      ATTR_COUPLE_COLOR_TEMP_TO_LEVEL_MIN = 0x400D_u32
      ATTR_START_UP_COLOR_TEMPERATURE     = 0x4010_u32

      # Commands
      CMD_MOVE_TO_HUE                         = 0x00_u32
      CMD_MOVE_HUE                            = 0x01_u32
      CMD_STEP_HUE                            = 0x02_u32
      CMD_MOVE_TO_SATURATION                  = 0x03_u32
      CMD_MOVE_SATURATION                     = 0x04_u32
      CMD_STEP_SATURATION                     = 0x05_u32
      CMD_MOVE_TO_HUE_AND_SATURATION          = 0x06_u32
      CMD_MOVE_TO_COLOR                       = 0x07_u32
      CMD_MOVE_COLOR                          = 0x08_u32
      CMD_STEP_COLOR                          = 0x09_u32
      CMD_MOVE_TO_COLOR_TEMPERATURE           = 0x0A_u32
      CMD_ENHANCED_MOVE_TO_HUE                = 0x40_u32
      CMD_ENHANCED_MOVE_HUE                   = 0x41_u32
      CMD_ENHANCED_STEP_HUE                   = 0x42_u32
      CMD_ENHANCED_MOVE_TO_HUE_AND_SATURATION = 0x43_u32
      CMD_COLOR_LOOP_SET                      = 0x44_u32
      CMD_STOP_MOVE_STEP                      = 0x47_u32
      CMD_MOVE_COLOR_TEMPERATURE              = 0x4B_u32
      CMD_STEP_COLOR_TEMPERATURE              = 0x4C_u32

      # Attribute storage
      property current_hue : UInt8
      property current_saturation : UInt8
      property current_x : UInt16
      property current_y : UInt16
      property color_temperature_mireds : UInt16
      property color_mode : Definitions::ColorControl::ColorMode
      property enhanced_current_hue : UInt16
      property enhanced_color_mode : Definitions::ColorControl::EnhancedColorMode
      property remaining_time : UInt16
      property options : UInt8

      # Color loop state
      property color_loop_active : Bool
      property color_loop_direction : UInt8
      property color_loop_time : UInt16
      property color_loop_start_enhanced_hue : UInt16
      property color_loop_stored_enhanced_hue : UInt16

      # Physical limits
      property color_temp_physical_min_mireds : UInt16
      property color_temp_physical_max_mireds : UInt16

      # Callbacks
      @on_color_changed : Proc(Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @current_hue : UInt8 = 0_u8,
        @current_saturation : UInt8 = 0_u8,
        @current_x : UInt16 = 0_u16,
        @current_y : UInt16 = 0_u16,
        @color_temperature_mireds : UInt16 = 250_u16,
        @color_temp_physical_min_mireds : UInt16 = 147_u16, # ~6800K
        @color_temp_physical_max_mireds : UInt16 = 500_u16, # ~2000K
        @color_mode : Definitions::ColorControl::ColorMode = Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation,
        @options : UInt8 = 0_u8,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @remaining_time = 0_u16
        @enhanced_current_hue = (@current_hue.to_u16 << 8)
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::CurrentHueAndCurrentSaturation
        @color_loop_active = false
        @color_loop_direction = 0_u8
        @color_loop_time = 25_u16
        @color_loop_start_enhanced_hue = 0x2300_u16
        @color_loop_stored_enhanced_hue = 0_u16
      end

      def name : String
        "ColorControl"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CURRENT_HUE),
            "CurrentHue",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CURRENT_SATURATION),
            "CurrentSaturation",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_REMAINING_TIME),
            "RemainingTime",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CURRENT_X),
            "CurrentX",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_CURRENT_Y),
            "CurrentY",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COLOR_TEMPERATURE_MIREDS),
            "ColorTemperatureMireds",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COLOR_MODE),
            "ColorMode",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OPTIONS),
            "Options",
            :uint8,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ENHANCED_CURRENT_HUE),
            "EnhancedCurrentHue",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ENHANCED_COLOR_MODE),
            "EnhancedColorMode",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COLOR_LOOP_ACTIVE),
            "ColorLoopActive",
            :bool,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COLOR_LOOP_DIRECTION),
            "ColorLoopDirection",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COLOR_LOOP_TIME),
            "ColorLoopTime",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COLOR_TEMP_PHYSICAL_MIN_MIREDS),
            "ColorTempPhysicalMinMireds",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_COLOR_TEMP_PHYSICAL_MAX_MIREDS),
            "ColorTempPhysicalMaxMireds",
            :uint16,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_TO_HUE), "MoveToHue"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_HUE), "MoveHue"),
          CommandMetadata.new(DataType::CommandId.new(CMD_STEP_HUE), "StepHue"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_TO_SATURATION), "MoveToSaturation"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_SATURATION), "MoveSaturation"),
          CommandMetadata.new(DataType::CommandId.new(CMD_STEP_SATURATION), "StepSaturation"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_TO_HUE_AND_SATURATION), "MoveToHueAndSaturation"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_TO_COLOR), "MoveToColor"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_COLOR), "MoveColor"),
          CommandMetadata.new(DataType::CommandId.new(CMD_STEP_COLOR), "StepColor"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_TO_COLOR_TEMPERATURE), "MoveToColorTemperature"),
          CommandMetadata.new(DataType::CommandId.new(CMD_MOVE_COLOR_TEMPERATURE), "MoveColorTemperature"),
          CommandMetadata.new(DataType::CommandId.new(CMD_STEP_COLOR_TEMPERATURE), "StepColorTemperature"),
          CommandMetadata.new(DataType::CommandId.new(CMD_ENHANCED_MOVE_TO_HUE), "EnhancedMoveToHue"),
          CommandMetadata.new(DataType::CommandId.new(CMD_ENHANCED_MOVE_HUE), "EnhancedMoveHue"),
          CommandMetadata.new(DataType::CommandId.new(CMD_ENHANCED_STEP_HUE), "EnhancedStepHue"),
          CommandMetadata.new(DataType::CommandId.new(CMD_ENHANCED_MOVE_TO_HUE_AND_SATURATION), "EnhancedMoveToHueAndSaturation"),
          CommandMetadata.new(DataType::CommandId.new(CMD_COLOR_LOOP_SET), "ColorLoopSet"),
          CommandMetadata.new(DataType::CommandId.new(CMD_STOP_MOVE_STEP), "StopMoveStep"),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_CURRENT_HUE
          encode_uint8(@current_hue)
        when ATTR_CURRENT_SATURATION
          encode_uint8(@current_saturation)
        when ATTR_REMAINING_TIME
          encode_uint16(@remaining_time)
        when ATTR_CURRENT_X
          encode_uint16(@current_x)
        when ATTR_CURRENT_Y
          encode_uint16(@current_y)
        when ATTR_COLOR_TEMPERATURE_MIREDS
          encode_uint16(@color_temperature_mireds)
        when ATTR_COLOR_MODE
          encode_uint8(@color_mode.value)
        when ATTR_OPTIONS
          encode_uint8(@options)
        when ATTR_ENHANCED_CURRENT_HUE
          encode_uint16(@enhanced_current_hue)
        when ATTR_ENHANCED_COLOR_MODE
          encode_uint8(@enhanced_color_mode.value)
        when ATTR_COLOR_LOOP_ACTIVE
          encode_bool(@color_loop_active)
        when ATTR_COLOR_LOOP_DIRECTION
          encode_uint8(@color_loop_direction)
        when ATTR_COLOR_LOOP_TIME
          encode_uint16(@color_loop_time)
        when ATTR_COLOR_TEMP_PHYSICAL_MIN_MIREDS
          encode_uint16(@color_temp_physical_min_mireds)
        when ATTR_COLOR_TEMP_PHYSICAL_MAX_MIREDS
          encode_uint16(@color_temp_physical_max_mireds)
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_MOVE_TO_HUE
          handle_move_to_hue(fields)
        when CMD_STEP_HUE
          handle_step_hue(fields)
        when CMD_MOVE_TO_SATURATION
          handle_move_to_saturation(fields)
        when CMD_STEP_SATURATION
          handle_step_saturation(fields)
        when CMD_MOVE_TO_HUE_AND_SATURATION
          handle_move_to_hue_and_saturation(fields)
        when CMD_MOVE_TO_COLOR
          handle_move_to_color(fields)
        when CMD_STEP_COLOR
          handle_step_color(fields)
        when CMD_MOVE_TO_COLOR_TEMPERATURE
          handle_move_to_color_temperature(fields)
        when CMD_STEP_COLOR_TEMPERATURE
          handle_step_color_temperature(fields)
        when CMD_ENHANCED_MOVE_TO_HUE
          handle_enhanced_move_to_hue(fields)
        when CMD_ENHANCED_STEP_HUE
          handle_enhanced_step_hue(fields)
        when CMD_ENHANCED_MOVE_TO_HUE_AND_SATURATION
          handle_enhanced_move_to_hue_and_saturation(fields)
        when CMD_STOP_MOVE_STEP
          handle_stop_move_step(fields)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      # Hue/Saturation Commands

      private def handle_move_to_hue(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 1

        target_hue = fields[0]
        move_to_hue(target_hue)
      end

      private def handle_step_hue(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 2

        step_mode = Definitions::ColorControl::StepMode.from_value(fields[0])
        step_size = fields[1]

        case step_mode
        when Definitions::ColorControl::StepMode::Up
          new_hue = (@current_hue.to_u16 + step_size) % 255
          move_to_hue(new_hue.to_u8)
        when Definitions::ColorControl::StepMode::Down
          new_hue = (@current_hue.to_i16 - step_size) % 255
          new_hue = new_hue < 0 ? 255 + new_hue : new_hue
          move_to_hue(new_hue.to_u8)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
        end
      end

      private def handle_move_to_saturation(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 1

        target_saturation = fields[0]
        move_to_saturation(target_saturation)
      end

      private def handle_step_saturation(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 2

        step_mode = Definitions::ColorControl::StepMode.from_value(fields[0])
        step_size = fields[1]

        case step_mode
        when Definitions::ColorControl::StepMode::Up
          new_sat = [@current_saturation.to_u16 + step_size, 254_u16].min
          move_to_saturation(new_sat.to_u8)
        when Definitions::ColorControl::StepMode::Down
          new_sat = [@current_saturation.to_i16 - step_size, 0_i16].max
          move_to_saturation(new_sat.to_u8)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
        end
      end

      private def handle_move_to_hue_and_saturation(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 2

        target_hue = fields[0]
        target_saturation = fields[1]

        @current_hue = target_hue
        @current_saturation = target_saturation
        @enhanced_current_hue = (target_hue.to_u16 << 8)
        @color_mode = Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::CurrentHueAndCurrentSaturation
        @remaining_time = 0_u16
        increment_version

        @on_color_changed.try &.call

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # XY Color Commands

      private def handle_move_to_color(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 4

        target_x = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
        target_y = IO::ByteFormat::LittleEndian.decode(UInt16, fields[2, 2])

        move_to_color(target_x, target_y)
      end

      private def handle_step_color(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 4

        step_x = IO::ByteFormat::LittleEndian.decode(Int16, fields[0, 2])
        step_y = IO::ByteFormat::LittleEndian.decode(Int16, fields[2, 2])

        new_x = [@current_x.to_i32 + step_x, 0_i32, 65535_i32].sort[1].to_u16
        new_y = [@current_y.to_i32 + step_y, 0_i32, 65535_i32].sort[1].to_u16

        move_to_color(new_x, new_y)
      end

      # Color Temperature Commands

      private def handle_move_to_color_temperature(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 2

        target_mireds = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
        move_to_color_temperature(target_mireds)
      end

      private def handle_step_color_temperature(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 3

        step_mode = Definitions::ColorControl::StepMode.from_value(fields[0])
        step_size = IO::ByteFormat::LittleEndian.decode(UInt16, fields[1, 2])

        case step_mode
        when Definitions::ColorControl::StepMode::Up
          new_mireds = [@color_temperature_mireds.to_u32 + step_size, @color_temp_physical_max_mireds.to_u32].min
          move_to_color_temperature(new_mireds.to_u16)
        when Definitions::ColorControl::StepMode::Down
          new_mireds = [@color_temperature_mireds.to_i32 - step_size, @color_temp_physical_min_mireds.to_i32].max
          move_to_color_temperature(new_mireds.to_u16)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
        end
      end

      # Enhanced Hue Commands

      private def handle_enhanced_move_to_hue(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 2

        target_enhanced_hue = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
        move_to_enhanced_hue(target_enhanced_hue)
      end

      private def handle_enhanced_step_hue(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 3

        step_mode = Definitions::ColorControl::StepMode.from_value(fields[0])
        step_size = IO::ByteFormat::LittleEndian.decode(UInt16, fields[1, 2])

        case step_mode
        when Definitions::ColorControl::StepMode::Up
          new_hue = (@enhanced_current_hue.to_u32 + step_size) % 65536
          move_to_enhanced_hue(new_hue.to_u16)
        when Definitions::ColorControl::StepMode::Down
          new_hue = (@enhanced_current_hue.to_i32 - step_size) % 65536
          new_hue = new_hue < 0 ? 65536 + new_hue : new_hue
          move_to_enhanced_hue(new_hue.to_u16)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
        end
      end

      private def handle_enhanced_move_to_hue_and_saturation(fields : Bytes) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand) if fields.size < 3

        target_enhanced_hue = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
        target_saturation = fields[2]

        @enhanced_current_hue = target_enhanced_hue
        @current_hue = (target_enhanced_hue >> 8).to_u8
        @current_saturation = target_saturation
        @color_mode = Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::EnhancedCurrentHueAndCurrentSaturation
        @remaining_time = 0_u16
        increment_version

        @on_color_changed.try &.call

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def handle_stop_move_step(fields : Bytes) : InteractionModel::Status
        @remaining_time = 0_u16
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Internal color change methods

      private def move_to_hue(new_hue : UInt8) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::Success) if @current_hue == new_hue

        @current_hue = new_hue
        @enhanced_current_hue = (new_hue.to_u16 << 8)
        @color_mode = Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::CurrentHueAndCurrentSaturation
        @remaining_time = 0_u16
        increment_version

        @on_color_changed.try &.call

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def move_to_saturation(new_saturation : UInt8) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::Success) if @current_saturation == new_saturation

        @current_saturation = new_saturation
        @color_mode = Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::CurrentHueAndCurrentSaturation
        @remaining_time = 0_u16
        increment_version

        @on_color_changed.try &.call

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def move_to_color(new_x : UInt16, new_y : UInt16) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::Success) if @current_x == new_x && @current_y == new_y

        @current_x = new_x
        @current_y = new_y
        @color_mode = Definitions::ColorControl::ColorMode::CurrentXAndCurrentY
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::CurrentXAndCurrentY
        @remaining_time = 0_u16
        increment_version

        @on_color_changed.try &.call

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def move_to_color_temperature(new_mireds : UInt16) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::Success) if @color_temperature_mireds == new_mireds

        # Clamp to physical limits
        clamped_mireds = [@color_temp_physical_min_mireds, [new_mireds, @color_temp_physical_max_mireds].min].max

        @color_temperature_mireds = clamped_mireds
        @color_mode = Definitions::ColorControl::ColorMode::ColorTemperatureMireds
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::ColorTemperatureMireds
        @remaining_time = 0_u16
        increment_version

        @on_color_changed.try &.call

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      private def move_to_enhanced_hue(new_enhanced_hue : UInt16) : InteractionModel::Status
        return InteractionModel::Status.new(InteractionModel::StatusCode::Success) if @enhanced_current_hue == new_enhanced_hue

        @enhanced_current_hue = new_enhanced_hue
        @current_hue = (new_enhanced_hue >> 8).to_u8
        @color_mode = Definitions::ColorControl::ColorMode::CurrentHueAndCurrentSaturation
        @enhanced_color_mode = Definitions::ColorControl::EnhancedColorMode::EnhancedCurrentHueAndCurrentSaturation
        @remaining_time = 0_u16
        increment_version

        @on_color_changed.try &.call

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Callback setter
      def on_color_changed(&block : -> Nil)
        @on_color_changed = block
      end

      # Utility methods
      def color_temperature_kelvin : UInt32
        (1_000_000_u32 / @color_temperature_mireds).to_u32
      end

      def set_color_temperature_kelvin(kelvin : UInt32) : InteractionModel::Status
        mireds = (1_000_000_u32 / kelvin).to_u16
        move_to_color_temperature(mireds)
      end
    end
  end
end
