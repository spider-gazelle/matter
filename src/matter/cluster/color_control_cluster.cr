require "./cluster"
require "./definitions/color_control"

module Matter
  module Cluster
    # Color Control Cluster Implementation (0x0300)
    #
    # Provides color control functionality for RGB and tunable white lights.
    # Supports multiple color modes: Hue/Saturation, XY, and Color Temperature.
    #
    # Features:
    # - HueSaturation (HS): Hue/saturation color specification
    # - EnhancedHue (EHUE): Enhanced 16-bit hue precision
    # - ColorLoop (CL): Color loop functionality
    # - XY: XY color space specification
    # - ColorTemperature (CT): Color temperature control
    #
    # Matter Spec: Application 3.2
    class ColorControlCluster < Base
      CLUSTER_ID = 0x0300_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        HueSaturation    = 0x01 # HS - Hue/saturation color specification
        EnhancedHue      = 0x02 # EHUE - Enhanced 16-bit hue precision
        ColorLoop        = 0x04 # CL - Color loop functionality
        XY               = 0x08 # XY - XY color space specification
        ColorTemperature = 0x10 # CT - Color temperature control
      end

      # Attributes
      ATTR_CURRENT_HUE                    = 0x0000_u32 # HS feature
      ATTR_CURRENT_SATURATION             = 0x0001_u32 # HS feature
      ATTR_REMAINING_TIME                 = 0x0002_u32
      ATTR_CURRENT_X                      = 0x0003_u32 # XY feature
      ATTR_CURRENT_Y                      = 0x0004_u32 # XY feature
      ATTR_DRIFT_COMPENSATION             = 0x0005_u32
      ATTR_COMPENSATION_TEXT              = 0x0006_u32
      ATTR_COLOR_TEMPERATURE_MIREDS       = 0x0007_u32 # CT feature
      ATTR_COLOR_MODE                     = 0x0008_u32
      ATTR_OPTIONS                        = 0x000F_u32
      ATTR_NUMBER_OF_PRIMARIES            = 0x0010_u32
      ATTR_ENHANCED_CURRENT_HUE           = 0x4000_u32 # EHUE feature
      ATTR_ENHANCED_COLOR_MODE            = 0x4001_u32
      ATTR_COLOR_LOOP_ACTIVE              = 0x4002_u32 # CL feature
      ATTR_COLOR_LOOP_DIRECTION           = 0x4003_u32 # CL feature
      ATTR_COLOR_LOOP_TIME                = 0x4004_u32 # CL feature
      ATTR_COLOR_LOOP_START_ENHANCED_HUE  = 0x4005_u32 # CL feature
      ATTR_COLOR_LOOP_STORED_ENHANCED_HUE = 0x4006_u32 # CL feature
      ATTR_COLOR_CAPABILITIES             = 0x400A_u32
      ATTR_COLOR_TEMP_PHYSICAL_MIN_MIREDS = 0x400B_u32 # CT feature
      ATTR_COLOR_TEMP_PHYSICAL_MAX_MIREDS = 0x400C_u32 # CT feature
      ATTR_COUPLE_COLOR_TEMP_TO_LEVEL_MIN = 0x400D_u32 # CT feature (optional)
      ATTR_START_UP_COLOR_TEMPERATURE     = 0x4010_u32 # CT feature (optional)

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      # Commands - HueSaturation feature
      CMD_MOVE_TO_HUE                = 0x00_u32 # HS
      CMD_MOVE_HUE                   = 0x01_u32 # HS
      CMD_STEP_HUE                   = 0x02_u32 # HS
      CMD_MOVE_TO_SATURATION         = 0x03_u32 # HS
      CMD_MOVE_SATURATION            = 0x04_u32 # HS
      CMD_STEP_SATURATION            = 0x05_u32 # HS
      CMD_MOVE_TO_HUE_AND_SATURATION = 0x06_u32 # HS
      # Commands - XY feature
      CMD_MOVE_TO_COLOR = 0x07_u32 # XY
      CMD_MOVE_COLOR    = 0x08_u32 # XY
      CMD_STEP_COLOR    = 0x09_u32 # XY
      # Commands - ColorTemperature feature
      CMD_MOVE_TO_COLOR_TEMPERATURE = 0x0A_u32 # CT
      # Commands - EnhancedHue feature
      CMD_ENHANCED_MOVE_TO_HUE                = 0x40_u32 # EHUE
      CMD_ENHANCED_MOVE_HUE                   = 0x41_u32 # EHUE
      CMD_ENHANCED_STEP_HUE                   = 0x42_u32 # EHUE
      CMD_ENHANCED_MOVE_TO_HUE_AND_SATURATION = 0x43_u32 # EHUE
      # Commands - ColorLoop feature
      CMD_COLOR_LOOP_SET = 0x44_u32 # CL
      # Commands - HS | XY | CT (any color feature)
      CMD_STOP_MOVE_STEP = 0x47_u32
      # Commands - ColorTemperature feature
      CMD_MOVE_COLOR_TEMPERATURE = 0x4B_u32 # CT
      CMD_STEP_COLOR_TEMPERATURE = 0x4C_u32 # CT

      # Feature map
      property feature_map : Feature

      # Base attributes
      property color_mode : Definitions::ColorControl::ColorMode
      property enhanced_color_mode : Definitions::ColorControl::EnhancedColorMode
      property remaining_time : UInt16
      property options : UInt8

      # HueSaturation feature attributes
      property current_hue : UInt8
      property current_saturation : UInt8

      # XY feature attributes
      property current_x : UInt16
      property current_y : UInt16

      # ColorTemperature feature attributes
      property color_temperature_mireds : UInt16
      property color_temp_physical_min_mireds : UInt16
      property color_temp_physical_max_mireds : UInt16
      property couple_color_temp_to_level_min_mireds : UInt16?
      property start_up_color_temperature_mireds : UInt16?

      # EnhancedHue feature attributes
      property enhanced_current_hue : UInt16

      # ColorLoop feature attributes
      property? color_loop_active : Bool
      property color_loop_direction : UInt8
      property color_loop_time : UInt16
      property color_loop_start_enhanced_hue : UInt16
      property color_loop_stored_enhanced_hue : UInt16

      # Callbacks
      @on_color_changed : Proc(Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::HueSaturation | Feature::XY | Feature::ColorTemperature,
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

        # ColorLoop attributes
        @color_loop_active = false
        @color_loop_direction = 0_u8
        @color_loop_time = 25_u16
        @color_loop_start_enhanced_hue = 0x2300_u16
        @color_loop_stored_enhanced_hue = 0_u16

        # Optional CT attributes
        @couple_color_temp_to_level_min_mireds = nil
        @start_up_color_temperature_mireds = nil
      end

      def name : String
        "ColorControl"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [] of AttributeMetadata

        # HueSaturation feature attributes
        if @feature_map.hue_saturation?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_CURRENT_HUE),
            name: "currentHue",
            type: :uint8,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_CURRENT_SATURATION),
            name: "currentSaturation",
            type: :uint8,
            writable: false
          )
        end

        # RemainingTime (optional, present if any color mode)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_REMAINING_TIME),
          name: "remainingTime",
          type: :uint16,
          writable: false,
          optional: true
        )

        # XY feature attributes
        if @feature_map.xy?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_CURRENT_X),
            name: "currentX",
            type: :uint16,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_CURRENT_Y),
            name: "currentY",
            type: :uint16,
            writable: false
          )
        end

        # ColorTemperature feature attributes
        if @feature_map.color_temperature?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_TEMPERATURE_MIREDS),
            name: "colorTemperatureMireds",
            type: :uint16,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_TEMP_PHYSICAL_MIN_MIREDS),
            name: "colorTempPhysicalMinMireds",
            type: :uint16,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_TEMP_PHYSICAL_MAX_MIREDS),
            name: "colorTempPhysicalMaxMireds",
            type: :uint16,
            writable: false
          )
          # Optional CT attributes
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COUPLE_COLOR_TEMP_TO_LEVEL_MIN),
            name: "coupleColorTempToLevelMinMireds",
            type: :uint16,
            writable: false,
            optional: true
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_START_UP_COLOR_TEMPERATURE),
            name: "startUpColorTemperatureMireds",
            type: :uint16,
            writable: true,
            optional: true
          )
        end

        # ColorMode (mandatory)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_COLOR_MODE),
          name: "colorMode",
          type: :uint8,
          writable: false
        )

        # Options (mandatory)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_OPTIONS),
          name: "options",
          type: :uint8,
          writable: true
        )

        # EnhancedHue feature attributes
        if @feature_map.enhanced_hue?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_ENHANCED_CURRENT_HUE),
            name: "enhancedCurrentHue",
            type: :uint16,
            writable: false
          )
        end

        # EnhancedColorMode (mandatory)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_ENHANCED_COLOR_MODE),
          name: "enhancedColorMode",
          type: :uint8,
          writable: false
        )

        # ColorLoop feature attributes
        if @feature_map.color_loop?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_LOOP_ACTIVE),
            name: "colorLoopActive",
            type: :bool,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_LOOP_DIRECTION),
            name: "colorLoopDirection",
            type: :uint8,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_LOOP_TIME),
            name: "colorLoopTime",
            type: :uint16,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_LOOP_START_ENHANCED_HUE),
            name: "colorLoopStartEnhancedHue",
            type: :uint16,
            writable: false
          )
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLOR_LOOP_STORED_ENHANCED_HUE),
            name: "colorLoopStoredEnhancedHue",
            type: :uint16,
            writable: false
          )
        end

        # Global attributes
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(CLUSTER_REVISION),
          name: "clusterRevision",
          type: :uint16,
          writable: false,
          default: 6_u16.to_tlv
        )
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(FEATURE_MAP),
          name: "featureMap",
          type: :uint32,
          writable: false,
          default: @feature_map.value.to_tlv
        )

        attrs
      end

      def commands : Array(CommandMetadata)
        cmds = [] of CommandMetadata

        # HueSaturation feature commands
        if @feature_map.hue_saturation?
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_TO_HUE), name: "moveToHue")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_HUE), name: "moveHue")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_STEP_HUE), name: "stepHue")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_TO_SATURATION), name: "moveToSaturation")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_SATURATION), name: "moveSaturation")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_STEP_SATURATION), name: "stepSaturation")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_TO_HUE_AND_SATURATION), name: "moveToHueAndSaturation")
        end

        # XY feature commands
        if @feature_map.xy?
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_TO_COLOR), name: "moveToColor")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_COLOR), name: "moveColor")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_STEP_COLOR), name: "stepColor")
        end

        # ColorTemperature feature commands
        if @feature_map.color_temperature?
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_TO_COLOR_TEMPERATURE), name: "moveToColorTemperature")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_MOVE_COLOR_TEMPERATURE), name: "moveColorTemperature")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_STEP_COLOR_TEMPERATURE), name: "stepColorTemperature")
        end

        # EnhancedHue feature commands
        if @feature_map.enhanced_hue?
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_ENHANCED_MOVE_TO_HUE), name: "enhancedMoveToHue")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_ENHANCED_MOVE_HUE), name: "enhancedMoveHue")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_ENHANCED_STEP_HUE), name: "enhancedStepHue")
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_ENHANCED_MOVE_TO_HUE_AND_SATURATION), name: "enhancedMoveToHueAndSaturation")
        end

        # ColorLoop feature commands
        if @feature_map.color_loop?
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_COLOR_LOOP_SET), name: "colorLoopSet")
        end

        # StopMoveStep (requires HS | XY | CT)
        if @feature_map.hue_saturation? || @feature_map.xy? || @feature_map.color_temperature?
          cmds << CommandMetadata.new(id: DataType::CommandId.new(CMD_STOP_MOVE_STEP), name: "stopMoveStep")
        end

        cmds
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_CURRENT_HUE
          return unsupported_attribute unless @feature_map.hue_saturation?
          @current_hue.to_tlv
        when ATTR_CURRENT_SATURATION
          return unsupported_attribute unless @feature_map.hue_saturation?
          @current_saturation.to_tlv
        when ATTR_REMAINING_TIME
          @remaining_time.to_tlv
        when ATTR_CURRENT_X
          return unsupported_attribute unless @feature_map.xy?
          @current_x.to_tlv
        when ATTR_CURRENT_Y
          return unsupported_attribute unless @feature_map.xy?
          @current_y.to_tlv
        when ATTR_COLOR_TEMPERATURE_MIREDS
          return unsupported_attribute unless @feature_map.color_temperature?
          @color_temperature_mireds.to_tlv
        when ATTR_COLOR_MODE
          @color_mode.value.to_tlv
        when ATTR_OPTIONS
          @options.to_tlv
        when ATTR_ENHANCED_CURRENT_HUE
          return unsupported_attribute unless @feature_map.enhanced_hue?
          @enhanced_current_hue.to_tlv
        when ATTR_ENHANCED_COLOR_MODE
          @enhanced_color_mode.value.to_tlv
        when ATTR_COLOR_LOOP_ACTIVE
          return unsupported_attribute unless @feature_map.color_loop?
          @color_loop_active.to_tlv
        when ATTR_COLOR_LOOP_DIRECTION
          return unsupported_attribute unless @feature_map.color_loop?
          @color_loop_direction.to_tlv
        when ATTR_COLOR_LOOP_TIME
          return unsupported_attribute unless @feature_map.color_loop?
          @color_loop_time.to_tlv
        when ATTR_COLOR_LOOP_START_ENHANCED_HUE
          return unsupported_attribute unless @feature_map.color_loop?
          @color_loop_start_enhanced_hue.to_tlv
        when ATTR_COLOR_LOOP_STORED_ENHANCED_HUE
          return unsupported_attribute unless @feature_map.color_loop?
          @color_loop_stored_enhanced_hue.to_tlv
        when ATTR_COLOR_TEMP_PHYSICAL_MIN_MIREDS
          return unsupported_attribute unless @feature_map.color_temperature?
          @color_temp_physical_min_mireds.to_tlv
        when ATTR_COLOR_TEMP_PHYSICAL_MAX_MIREDS
          return unsupported_attribute unless @feature_map.color_temperature?
          @color_temp_physical_max_mireds.to_tlv
        when ATTR_COUPLE_COLOR_TEMP_TO_LEVEL_MIN
          return unsupported_attribute unless @feature_map.color_temperature?
          if val = @couple_color_temp_to_level_min_mireds
            val.to_tlv
          else
            encode_null
          end
        when ATTR_START_UP_COLOR_TEMPERATURE
          return unsupported_attribute unless @feature_map.color_temperature?
          if val = @start_up_color_temperature_mireds
            val.to_tlv
          else
            encode_null
          end
        when FEATURE_MAP
          @feature_map.value.to_tlv
        when CLUSTER_REVISION
          6_u16.to_tlv
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_OPTIONS
          if value.size >= 1
            @options = value[0]
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        when ATTR_START_UP_COLOR_TEMPERATURE
          return unsupported_attribute unless @feature_map.color_temperature?
          if value.size >= 2
            @start_up_color_temperature_mireds = IO::ByteFormat::LittleEndian.decode(UInt16, value)
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        # HueSaturation commands
        when CMD_MOVE_TO_HUE
          return unsupported_command unless @feature_map.hue_saturation?
          handle_move_to_hue(fields)
        when CMD_MOVE_HUE
          return unsupported_command unless @feature_map.hue_saturation?
          InteractionModel::Status.new(InteractionModel::StatusCode::Success) # Simplified
        when CMD_STEP_HUE
          return unsupported_command unless @feature_map.hue_saturation?
          handle_step_hue(fields)
        when CMD_MOVE_TO_SATURATION
          return unsupported_command unless @feature_map.hue_saturation?
          handle_move_to_saturation(fields)
        when CMD_MOVE_SATURATION
          return unsupported_command unless @feature_map.hue_saturation?
          InteractionModel::Status.new(InteractionModel::StatusCode::Success) # Simplified
        when CMD_STEP_SATURATION
          return unsupported_command unless @feature_map.hue_saturation?
          handle_step_saturation(fields)
        when CMD_MOVE_TO_HUE_AND_SATURATION
          return unsupported_command unless @feature_map.hue_saturation?
          handle_move_to_hue_and_saturation(fields)
          # XY commands
        when CMD_MOVE_TO_COLOR
          return unsupported_command unless @feature_map.xy?
          handle_move_to_color(fields)
        when CMD_MOVE_COLOR
          return unsupported_command unless @feature_map.xy?
          InteractionModel::Status.new(InteractionModel::StatusCode::Success) # Simplified
        when CMD_STEP_COLOR
          return unsupported_command unless @feature_map.xy?
          handle_step_color(fields)
          # ColorTemperature commands
        when CMD_MOVE_TO_COLOR_TEMPERATURE
          return unsupported_command unless @feature_map.color_temperature?
          handle_move_to_color_temperature(fields)
        when CMD_MOVE_COLOR_TEMPERATURE
          return unsupported_command unless @feature_map.color_temperature?
          InteractionModel::Status.new(InteractionModel::StatusCode::Success) # Simplified
        when CMD_STEP_COLOR_TEMPERATURE
          return unsupported_command unless @feature_map.color_temperature?
          handle_step_color_temperature(fields)
          # EnhancedHue commands
        when CMD_ENHANCED_MOVE_TO_HUE
          return unsupported_command unless @feature_map.enhanced_hue?
          handle_enhanced_move_to_hue(fields)
        when CMD_ENHANCED_MOVE_HUE
          return unsupported_command unless @feature_map.enhanced_hue?
          InteractionModel::Status.new(InteractionModel::StatusCode::Success) # Simplified
        when CMD_ENHANCED_STEP_HUE
          return unsupported_command unless @feature_map.enhanced_hue?
          handle_enhanced_step_hue(fields)
        when CMD_ENHANCED_MOVE_TO_HUE_AND_SATURATION
          return unsupported_command unless @feature_map.enhanced_hue?
          handle_enhanced_move_to_hue_and_saturation(fields)
          # ColorLoop commands
        when CMD_COLOR_LOOP_SET
          return unsupported_command unless @feature_map.color_loop?
          handle_color_loop_set(fields)
          # StopMoveStep
        when CMD_STOP_MOVE_STEP
          unless @feature_map.hue_saturation? || @feature_map.xy? || @feature_map.color_temperature?
            return unsupported_command
          end
          handle_stop_move_step(fields)
        else
          super
        end
      end

      # Command handlers

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

      private def handle_color_loop_set(fields : Bytes) : InteractionModel::Status
        # Simplified color loop set
        @remaining_time = 0_u16
        increment_version
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

      def color_temperature_kelvin=(kelvin : UInt32) : InteractionModel::Status
        mireds = (1_000_000_u32 / kelvin).to_u16
        move_to_color_temperature(mireds)
      end

      # Helper methods
      private def unsupported_attribute : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
      end

      private def unsupported_command : InteractionModel::Status
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
      end

      private def encode_null : Bytes
        TLV::Any.new(nil, nil).to_slice
      end
    end
  end
end
