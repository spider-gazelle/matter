require "./cluster"

module Matter
  module Cluster
    # Window Covering Cluster Implementation (0x0102)
    #
    # Provides control for various types of window coverings such as blinds,
    # shades, curtains, etc.
    #
    # Matter Specification: Core 1.4 § 5.3 - Window Covering Cluster
    #
    # Features:
    # - Lift (LF): Supports lift/lower position control
    # - Tilt (TL): Supports tilt control
    # - PositionAwareLift (PA_LF): Supports precise lift positioning
    # - AbsolutePosition (ABS): Supports absolute position control
    # - PositionAwareTilt (PA_TL): Supports precise tilt positioning
    class WindowCoveringCluster < Base
      CLUSTER_ID = 0x0102_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        Lift              = 0x01 # LF - Lift/lower control
        Tilt              = 0x02 # TL - Tilt control
        PositionAwareLift = 0x04 # PA_LF - Precise lift positioning
        AbsolutePosition  = 0x08 # ABS - Absolute position
        PositionAwareTilt = 0x10 # PA_TL - Precise tilt positioning
      end

      # WindowCoveringType enum
      enum CoveringType : UInt8
        Rollershade               =   0
        Rollershade2Motor         =   1
        RollershadeExterior       =   2
        RollershadeExterior2Motor =   3
        Drapery                   =   4
        Awning                    =   5
        Shutter                   =   6
        TiltBlindTiltOnly         =   7
        TiltBlindLiftAndTilt      =   8
        ProjectorScreen           =   9
        Unknown                   = 255
      end

      # EndProductType enum
      enum EndProductType : UInt8
        RollerShade               =   0
        RomanShade                =   1
        BalloonShade              =   2
        WovenWood                 =   3
        PleatedShade              =   4
        CellularShade             =   5
        LayeredShade              =   6
        LayeredShade2D            =   7
        SheerShade                =   8
        TiltOnlyInteriorBlind     =   9
        InteriorBlind             =  10
        VerticalBlindStripCurtain =  11
        InteriorVenetianBlind     =  12
        ExteriorVenetianBlind     =  13
        LateralLeftCurtain        =  14
        LateralRightCurtain       =  15
        CentralCurtain            =  16
        RollerShutter             =  17
        ExteriorVerticalScreen    =  18
        AwningTerracePatio        =  19
        AwningVerticalScreen      =  20
        TiltOnlyPergola           =  21
        SwingingShutter           =  22
        SlidingShutter            =  23
        Unknown                   = 255
      end

      # OperationalStatus bitmap
      @[Flags]
      enum OperationalStatus : UInt8
        GlobalLiftMoving = 0x03 # Bits 0-1: Lift movement
        GlobalTiltMoving = 0x0C # Bits 2-3: Tilt movement
        GlobalReserved   = 0x30 # Bits 4-5: Reserved
      end

      # ConfigStatus bitmap
      @[Flags]
      enum ConfigStatus : UInt8
        Operational           = 0x01
        OnlineReserved        = 0x02
        LiftMovementReversed  = 0x04
        LiftPositionAware     = 0x08
        TiltPositionAware     = 0x10
        LiftEncoderControlled = 0x20
        TiltEncoderControlled = 0x40
      end

      # Mode bitmap
      @[Flags]
      enum Mode : UInt8
        MotorDirectionReversed = 0x01
        CalibrationMode        = 0x02
        MaintenanceMode        = 0x04
        LedFeedback            = 0x08
      end

      # Attribute IDs
      ATTR_TYPE                                = 0x0000_u32
      ATTR_PHYSICAL_CLOSED_LIMIT_LIFT          = 0x0001_u32
      ATTR_PHYSICAL_CLOSED_LIMIT_TILT          = 0x0002_u32
      ATTR_CURRENT_POSITION_LIFT               = 0x0003_u32
      ATTR_CURRENT_POSITION_TILT               = 0x0004_u32
      ATTR_NUMBER_OF_ACTUATIONS_LIFT           = 0x0005_u32
      ATTR_NUMBER_OF_ACTUATIONS_TILT           = 0x0006_u32
      ATTR_CONFIG_STATUS                       = 0x0007_u32
      ATTR_CURRENT_POSITION_LIFT_PERCENTAGE    = 0x0008_u32
      ATTR_CURRENT_POSITION_TILT_PERCENTAGE    = 0x0009_u32
      ATTR_OPERATIONAL_STATUS                  = 0x000A_u32
      ATTR_TARGET_POSITION_LIFT_PERCENT100THS  = 0x000B_u32
      ATTR_TARGET_POSITION_TILT_PERCENT100THS  = 0x000C_u32
      ATTR_END_PRODUCT_TYPE                    = 0x000D_u32
      ATTR_CURRENT_POSITION_LIFT_PERCENT100THS = 0x000E_u32
      ATTR_CURRENT_POSITION_TILT_PERCENT100THS = 0x000F_u32
      ATTR_INSTALLED_OPEN_LIMIT_LIFT           = 0x0010_u32
      ATTR_INSTALLED_CLOSED_LIMIT_LIFT         = 0x0011_u32
      ATTR_INSTALLED_OPEN_LIMIT_TILT           = 0x0012_u32
      ATTR_INSTALLED_CLOSED_LIMIT_TILT         = 0x0013_u32
      ATTR_MODE                                = 0x0017_u32
      ATTR_SAFETY_STATUS                       = 0x001A_u32

      # Command IDs
      CMD_UP_OR_OPEN            = 0x00_u32
      CMD_DOWN_OR_CLOSE         = 0x01_u32
      CMD_STOP_MOTION           = 0x02_u32
      CMD_GO_TO_LIFT_VALUE      = 0x04_u32
      CMD_GO_TO_LIFT_PERCENTAGE = 0x05_u32
      CMD_GO_TO_TILT_VALUE      = 0x07_u32
      CMD_GO_TO_TILT_PERCENTAGE = 0x08_u32

      CLUSTER_REVISION = 5_u16

      property feature_map : Feature
      property covering_type : CoveringType
      property end_product_type : EndProductType
      property config_status : ConfigStatus
      property operational_status : OperationalStatus
      property mode : Mode

      # Lift properties
      property current_position_lift_percentage : UInt8?
      property current_position_lift_percent100ths : UInt16?
      property target_position_lift_percent100ths : UInt16?
      property number_of_actuations_lift : UInt16?

      # Tilt properties
      property current_position_tilt_percentage : UInt8?
      property current_position_tilt_percent100ths : UInt16?
      property target_position_tilt_percent100ths : UInt16?
      property number_of_actuations_tilt : UInt16?

      # Safety status
      property safety_status : UInt16?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::Lift | Feature::PositionAwareLift,
        @covering_type : CoveringType = CoveringType::Rollershade,
        @end_product_type : EndProductType = EndProductType::RollerShade,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @config_status = ConfigStatus::Operational
        @operational_status = OperationalStatus::None
        @mode = Mode::None

        # Initialize lift attributes if Lift feature is enabled
        if @feature_map.includes?(Feature::Lift)
          @current_position_lift_percentage = nil
          @number_of_actuations_lift = 0_u16

          if @feature_map.includes?(Feature::PositionAwareLift)
            @current_position_lift_percent100ths = 0_u16
            @target_position_lift_percent100ths = 0_u16
            @config_status = @config_status | ConfigStatus::LiftPositionAware
          end
        end

        # Initialize tilt attributes if Tilt feature is enabled
        if @feature_map.includes?(Feature::Tilt)
          @current_position_tilt_percentage = nil
          @number_of_actuations_tilt = 0_u16

          if @feature_map.includes?(Feature::PositionAwareTilt)
            @current_position_tilt_percent100ths = 0_u16
            @target_position_tilt_percent100ths = 0_u16
            @config_status = @config_status | ConfigStatus::TiltPositionAware
          end
        end
      end

      def name : String
        "WindowCovering"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [] of AttributeMetadata

        # Type (mandatory, fixed)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_TYPE),
          name: "type",
          type: :uint8,
          writable: false,
          fixed: true
        )

        # ConfigStatus (mandatory)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_CONFIG_STATUS),
          name: "configStatus",
          type: :uint8,
          writable: false
        )

        # OperationalStatus (mandatory)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_OPERATIONAL_STATUS),
          name: "operationalStatus",
          type: :uint8,
          writable: false
        )

        # EndProductType (mandatory, fixed)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_END_PRODUCT_TYPE),
          name: "endProductType",
          type: :uint8,
          writable: false,
          fixed: true
        )

        # Mode (mandatory, writable)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_MODE),
          name: "mode",
          type: :uint8,
          writable: true
        )

        # Lift-related attributes
        if @feature_map.includes?(Feature::Lift)
          # NumberOfActuationsLift (optional)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_NUMBER_OF_ACTUATIONS_LIFT),
            name: "numberOfActuationsLift",
            type: :uint16,
            writable: false,
            optional: true
          )

          if @feature_map.includes?(Feature::PositionAwareLift)
            # CurrentPositionLiftPercent100ths (mandatory with PA_LF)
            attrs << AttributeMetadata.new(
              id: DataType::AttributeId.new(ATTR_CURRENT_POSITION_LIFT_PERCENT100THS),
              name: "currentPositionLiftPercent100ths",
              type: :uint16,
              writable: false
            )

            # TargetPositionLiftPercent100ths (mandatory with PA_LF)
            attrs << AttributeMetadata.new(
              id: DataType::AttributeId.new(ATTR_TARGET_POSITION_LIFT_PERCENT100THS),
              name: "targetPositionLiftPercent100ths",
              type: :uint16,
              writable: false
            )

            # CurrentPositionLiftPercentage (optional)
            attrs << AttributeMetadata.new(
              id: DataType::AttributeId.new(ATTR_CURRENT_POSITION_LIFT_PERCENTAGE),
              name: "currentPositionLiftPercentage",
              type: :uint8,
              writable: false,
              optional: true
            )
          end
        end

        # Tilt-related attributes
        if @feature_map.includes?(Feature::Tilt)
          # NumberOfActuationsTilt (optional)
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_NUMBER_OF_ACTUATIONS_TILT),
            name: "numberOfActuationsTilt",
            type: :uint16,
            writable: false,
            optional: true
          )

          if @feature_map.includes?(Feature::PositionAwareTilt)
            # CurrentPositionTiltPercent100ths (mandatory with PA_TL)
            attrs << AttributeMetadata.new(
              id: DataType::AttributeId.new(ATTR_CURRENT_POSITION_TILT_PERCENT100THS),
              name: "currentPositionTiltPercent100ths",
              type: :uint16,
              writable: false
            )

            # TargetPositionTiltPercent100ths (mandatory with PA_TL)
            attrs << AttributeMetadata.new(
              id: DataType::AttributeId.new(ATTR_TARGET_POSITION_TILT_PERCENT100THS),
              name: "targetPositionTiltPercent100ths",
              type: :uint16,
              writable: false
            )

            # CurrentPositionTiltPercentage (optional)
            attrs << AttributeMetadata.new(
              id: DataType::AttributeId.new(ATTR_CURRENT_POSITION_TILT_PERCENTAGE),
              name: "currentPositionTiltPercentage",
              type: :uint8,
              writable: false,
              optional: true
            )
          end
        end

        # SafetyStatus (optional)
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_SAFETY_STATUS),
          name: "safetyStatus",
          type: :uint16,
          writable: false,
          optional: true
        )

        # Global attributes
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(GLOBAL_CLUSTER_REVISION),
          name: "clusterRevision",
          type: :uint16,
          writable: false,
          default: CLUSTER_REVISION.to_tlv
        )

        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(GLOBAL_FEATURE_MAP),
          name: "featureMap",
          type: :uint32,
          writable: false,
          default: @feature_map.value.to_tlv
        )

        attrs
      end

      def commands : Array(CommandMetadata)
        cmds = [] of CommandMetadata

        # UpOrOpen (mandatory)
        cmds << CommandMetadata.new(
          id: DataType::CommandId.new(CMD_UP_OR_OPEN),
          name: "upOrOpen"
        )

        # DownOrClose (mandatory)
        cmds << CommandMetadata.new(
          id: DataType::CommandId.new(CMD_DOWN_OR_CLOSE),
          name: "downOrClose"
        )

        # StopMotion (mandatory)
        cmds << CommandMetadata.new(
          id: DataType::CommandId.new(CMD_STOP_MOTION),
          name: "stopMotion"
        )

        # GoToLiftPercentage (mandatory with LF & PA_LF)
        if @feature_map.includes?(Feature::Lift) && @feature_map.includes?(Feature::PositionAwareLift)
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_GO_TO_LIFT_PERCENTAGE),
            name: "goToLiftPercentage"
          )
        end

        # GoToTiltPercentage (mandatory with TL & PA_TL)
        if @feature_map.includes?(Feature::Tilt) && @feature_map.includes?(Feature::PositionAwareTilt)
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_GO_TO_TILT_PERCENTAGE),
            name: "goToTiltPercentage"
          )
        end

        cmds
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_TYPE
          @covering_type.value.to_tlv
        when ATTR_CONFIG_STATUS
          @config_status.value.to_tlv
        when ATTR_OPERATIONAL_STATUS
          @operational_status.value.to_tlv
        when ATTR_END_PRODUCT_TYPE
          @end_product_type.value.to_tlv
        when ATTR_MODE
          @mode.value.to_tlv
        when ATTR_CURRENT_POSITION_LIFT_PERCENTAGE
          if val = @current_position_lift_percentage
            val.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_CURRENT_POSITION_LIFT_PERCENT100THS
          if val = @current_position_lift_percent100ths
            val.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_TARGET_POSITION_LIFT_PERCENT100THS
          if val = @target_position_lift_percent100ths
            val.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_NUMBER_OF_ACTUATIONS_LIFT
          (@number_of_actuations_lift || 0_u16).to_tlv
        when ATTR_SAFETY_STATUS
          if val = @safety_status
            val.to_tlv
          else
            nil.to_tlv
          end
        when GLOBAL_FEATURE_MAP
          @feature_map.value.to_tlv
        else
          super
        end
      end

      protected def handle_write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_MODE
          if mode = decode_u8(value)
            @mode = Mode.from_value(mode)
            increment_version
            InteractionModel::Status.success
          else
            InteractionModel::Status.invalid_data_type
          end
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_UP_OR_OPEN
          handle_up_or_open
        when CMD_DOWN_OR_CLOSE
          handle_down_or_close
        when CMD_STOP_MOTION
          handle_stop_motion
        when CMD_GO_TO_LIFT_PERCENTAGE
          handle_go_to_lift_percentage(fields)
        else
          super
        end
      end

      private def handle_up_or_open
        # Move to fully open position (0%)
        if @feature_map.includes?(Feature::PositionAwareLift)
          @target_position_lift_percent100ths = 0_u16
        end
        @operational_status = OperationalStatus::GlobalLiftMoving
        increment_version
        InteractionModel::Status.success
      end

      private def handle_down_or_close
        # Move to fully closed position (100%)
        if @feature_map.includes?(Feature::PositionAwareLift)
          @target_position_lift_percent100ths = 10000_u16 # 100.00%
        end
        @operational_status = OperationalStatus::GlobalLiftMoving
        increment_version
        InteractionModel::Status.success
      end

      private def handle_stop_motion
        @operational_status = OperationalStatus::None
        increment_version
        InteractionModel::Status.success
      end

      private def handle_go_to_lift_percentage(fields : Bytes)
        # Parse percentage from TLV
        if fields.size >= 2
          percentage = IO::ByteFormat::LittleEndian.decode(UInt16, fields)
          if percentage <= 10000 # 0.00% to 100.00%
            @target_position_lift_percent100ths = percentage
            @operational_status = OperationalStatus::GlobalLiftMoving
            increment_version
            return InteractionModel::Status.success
          end
        end
        InteractionModel::Status.constraint_error
      end

      # NOTE: Attributes are returned as TLV-encoded bytes (use `value.to_tlv`).
    end
  end
end
