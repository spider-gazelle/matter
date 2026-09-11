require "./cluster"
require "./definitions/window_covering"

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
      cluster 0x0102, revision: 6

      feature :lift, bit: 0                # LF - Lift/lower control
      feature :tilt, bit: 1                # TL - Tilt control
      feature :position_aware_lift, bit: 2 # PA_LF - Precise lift positioning
      feature :absolute_position, bit: 3   # ABS - Absolute position
      feature :position_aware_tilt, bit: 4 # PA_TL - Precise tilt positioning

      # Fully open and fully closed in the percent100ths attributes
      OPEN_POSITION_PERCENT100THS =      0_u16
      MAX_POSITION_PERCENT100THS  = 10_000_u16

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

      attribute 0x0000, :type, CoveringType, default: CoveringType::Rollershade, fixed: true
      attribute 0x0005, :number_of_actuations_lift, UInt16, default: 0_u16, persist: true, optional: true, requires: :lift
      attribute 0x0006, :number_of_actuations_tilt, UInt16, default: 0_u16, persist: true, optional: true, requires: :tilt
      attribute 0x0007, :config_status, ConfigStatus, default: ConfigStatus::Operational, persist: true
      attribute 0x0008, :current_position_lift_percentage, UInt8, nullable: true, optional: true, requires: {lift: true, position_aware_lift: true}
      attribute 0x0009, :current_position_tilt_percentage, UInt8, nullable: true, optional: true, requires: {tilt: true, position_aware_tilt: true}
      attribute 0x000A, :operational_status, OperationalStatus, default: OperationalStatus::None
      attribute 0x000B, :target_position_lift_percent100ths, UInt16, default: OPEN_POSITION_PERCENT100THS, nullable: true, max: MAX_POSITION_PERCENT100THS, requires: {lift: true, position_aware_lift: true}
      attribute 0x000C, :target_position_tilt_percent100ths, UInt16, default: OPEN_POSITION_PERCENT100THS, nullable: true, max: MAX_POSITION_PERCENT100THS, requires: {tilt: true, position_aware_tilt: true}
      attribute 0x000D, :end_product_type, EndProductType, default: EndProductType::RollerShade, fixed: true
      attribute 0x000E, :current_position_lift_percent100ths, UInt16, default: OPEN_POSITION_PERCENT100THS, nullable: true, persist: true, max: MAX_POSITION_PERCENT100THS, requires: {lift: true, position_aware_lift: true}
      attribute 0x000F, :current_position_tilt_percent100ths, UInt16, default: OPEN_POSITION_PERCENT100THS, nullable: true, persist: true, max: MAX_POSITION_PERCENT100THS, requires: {tilt: true, position_aware_tilt: true}
      attribute 0x0017, :mode, Mode, default: Mode::None, writable: true, write_access: :manage
      attribute 0x001A, :safety_status, UInt16, default: 0_u16, optional: true

      command 0x00, :up_or_open
      command 0x01, :down_or_close
      command 0x02, :stop_motion
      command 0x04, :go_to_lift_value, optional: true, requires: {lift: true, absolute_position: true}
      command 0x05, :go_to_lift_percentage, request: Definitions::WindowCovering::GoToLiftPercentageRequest, requires: {lift: true, position_aware_lift: true}
      command 0x07, :go_to_tilt_value, optional: true, requires: {tilt: true, absolute_position: true}
      command 0x08, :go_to_tilt_percentage, request: Definitions::WindowCovering::GoToTiltPercentageRequest, requires: {tilt: true, position_aware_tilt: true}

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::Lift | Feature::PositionAwareLift,
        covering_type : CoveringType = CoveringType::Rollershade,
        @end_product_type : EndProductType = EndProductType::RollerShade,
      )
        @type = covering_type
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @config_status |= ConfigStatus::LiftPositionAware if @feature_map.lift? && @feature_map.position_aware_lift?
        @config_status |= ConfigStatus::TiltPositionAware if @feature_map.tilt? && @feature_map.position_aware_tilt?
      end

      # ------------------------------------------------------------------------
      # Commands (movement is not simulated; the target moves immediately)
      # ------------------------------------------------------------------------

      def up_or_open : InteractionModel::Status
        move_lift_to(OPEN_POSITION_PERCENT100THS)
      end

      def down_or_close : InteractionModel::Status
        move_lift_to(MAX_POSITION_PERCENT100THS)
      end

      def stop_motion : InteractionModel::Status
        self.operational_status = OperationalStatus::None
        InteractionModel::Status.success
      end

      def go_to_lift_percentage(request : Definitions::WindowCovering::GoToLiftPercentageRequest) : InteractionModel::Status
        percentage = request.lift_percent100ths_value
        return InteractionModel::Status.constraint_error if percentage > MAX_POSITION_PERCENT100THS

        move_lift_to(percentage)
      end

      def go_to_tilt_percentage(request : Definitions::WindowCovering::GoToTiltPercentageRequest) : InteractionModel::Status
        percentage = request.tilt_percent100ths_value
        return InteractionModel::Status.constraint_error if percentage > MAX_POSITION_PERCENT100THS

        self.target_position_tilt_percent100ths = percentage
        self.operational_status = OperationalStatus::GlobalTiltMoving
        InteractionModel::Status.success
      end

      private def move_lift_to(percentage : UInt16) : InteractionModel::Status
        self.target_position_lift_percent100ths = percentage if @feature_map.position_aware_lift?
        self.operational_status = OperationalStatus::GlobalLiftMoving
        InteractionModel::Status.success
      end
    end
  end
end
