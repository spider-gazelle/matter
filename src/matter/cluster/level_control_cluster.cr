require "log"
require "./cluster"

module Matter
  module Cluster
    # Level Control Cluster Implementation (0x0008)
    #
    # Provides level control (dimming) functionality for lights, volume controls,
    # blinds, and other devices with adjustable levels.
    #
    # Features:
    # - OnOff (OO): Dependency with the On/Off cluster
    # - Lighting (LT): Lighting control interface (affects level semantics)
    # - Frequency (FQ): Frequency control support (provisional)
    #
    # Matter Spec: Application 1.6
    class LevelControlCluster < Base
      Log = ::Log.for("matter.cluster.level_control")

      cluster 0x0008, revision: 6

      feature :on_off, bit: 0    # OO - Dependency with On/Off cluster
      feature :lighting, bit: 1  # LT - Lighting control interface
      feature :frequency, bit: 2 # FQ - Frequency control (provisional)

      # Bounds of the CurrentLevel attribute
      LOWEST_LEVEL  =   0_u8
      HIGHEST_LEVEL = 254_u8

      enum MoveMode : UInt8
        Up   = 0
        Down = 1
      end

      enum StepMode : UInt8
        Up   = 0
        Down = 1
      end

      # Input to the LevelControl moveToLevel command
      struct MoveToLevelRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property level : UInt8

        @[TLV::Field(tag: 1, optional: false)]
        property transition_time : UInt16?

        @[TLV::Field(tag: 2)]
        property mask : UInt8

        @[TLV::Field(tag: 3)]
        property override : UInt8

        def initialize(@level : UInt8, @transition_time : UInt16?, @mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl move command
      struct MoveRequest
        include TLV::Serializable

        # The MoveMode field shall be one of the non-reserved values in Values of the MoveMode Field.
        @[TLV::Field(tag: 0)]
        property move_mode : MoveMode

        # The Rate field specifies the rate of movement in units per second. The actual rate of movement SHOULD be as
        # close to this rate as the device is able. If the Rate field is equal to null, then the value in
        # DefaultMoveRate attribute shall be used. However, if the Rate field is equal to null and the DefaultMoveRate
        # attribute is not supported, or if the Rate field is equal to null and the value of the DefaultMoveRate
        # attribute is equal to null, then the device SHOULD move as fast as it is able. If the device is not able to
        # move at a variable rate, this field may be disregarded.
        @[TLV::Field(tag: 1, optional: false)]
        property rate : UInt8?

        @[TLV::Field(tag: 2)]
        property mask : UInt8

        @[TLV::Field(tag: 3)]
        property override : UInt8

        def initialize(@move_mode : MoveMode, @rate : UInt8?, @mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl step command
      struct StepRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property step_mode : StepMode

        @[TLV::Field(tag: 1)]
        property step_size : UInt8

        @[TLV::Field(tag: 2, optional: false)]
        property transition_time : UInt16?

        @[TLV::Field(tag: 3)]
        property mask : UInt8

        @[TLV::Field(tag: 4)]
        property override : UInt8

        def initialize(@step_mode : StepMode, @step_size : UInt8, @transition_time : UInt16?, @mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl stop command
      struct StopRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property mask : UInt8

        @[TLV::Field(tag: 1)]
        property override : UInt8

        def initialize(@mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl moveToLevelWithOnOff command
      struct MoveToLevelWithOnOffRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property level : UInt8

        @[TLV::Field(tag: 1, optional: false)]
        property transition_time : UInt16?

        @[TLV::Field(tag: 2)]
        property mask : UInt8

        @[TLV::Field(tag: 3)]
        property override : UInt8

        def initialize(@level : UInt8, @transition_time : UInt16?, @mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl moveWithOnOff command
      struct MoveWithOnOffRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property move_mode : MoveMode

        @[TLV::Field(tag: 1, optional: false)]
        property rate : UInt8?

        @[TLV::Field(tag: 2)]
        property mask : UInt8

        @[TLV::Field(tag: 3)]
        property override : UInt8

        def initialize(@move_mode : MoveMode, @rate : UInt8?, @mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl stepWithOnOff command
      struct StepWithOnOffRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property step_mode : StepMode

        @[TLV::Field(tag: 1)]
        property step_size : UInt8

        @[TLV::Field(tag: 2, optional: false)]
        property transition_time : UInt16?

        @[TLV::Field(tag: 3)]
        property mask : UInt8

        @[TLV::Field(tag: 4)]
        property override : UInt8

        def initialize(@step_mode : StepMode, @step_size : UInt8, @transition_time : UInt16?, @mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl stopWithOnOff command
      struct StopWithOnOffRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property mask : UInt8

        @[TLV::Field(tag: 1)]
        property override : UInt8

        def initialize(@mask : UInt8, @override : UInt8)
        end
      end

      # Input to the LevelControl moveToClosestFrequency command
      struct MoveToClosestFrequencyRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property frequency : UInt16

        def initialize(@frequency : UInt16)
        end
      end

      attribute 0x0000, :current_level, UInt8, default: LOWEST_LEVEL, persist: true, min: LOWEST_LEVEL, max: HIGHEST_LEVEL
      attribute 0x0001, :remaining_time, UInt16, default: 0_u16, persist: true, requires: :lighting
      attribute 0x0002, :min_level, UInt8, default: LOWEST_LEVEL, persist: true, optional: true
      attribute 0x0003, :max_level, UInt8, default: HIGHEST_LEVEL, persist: true, optional: true
      attribute 0x0004, :current_frequency, UInt16, default: 0_u16, persist: true, requires: :frequency
      attribute 0x0005, :min_frequency, UInt16, default: 0_u16, persist: true, requires: :frequency
      attribute 0x0006, :max_frequency, UInt16, default: 0_u16, persist: true, requires: :frequency
      attribute 0x000F, :options, UInt8, default: 0_u8, writable: true
      attribute 0x0010, :on_off_transition_time, UInt16, default: 0_u16, writable: true, optional: true, requires: :lighting
      attribute 0x0011, :on_level, UInt8, nullable: true, writable: true, optional: true
      attribute 0x0012, :on_transition_time, UInt16, nullable: true, writable: true, optional: true, requires: :lighting
      attribute 0x0013, :off_transition_time, UInt16, nullable: true, writable: true, optional: true, requires: :lighting
      attribute 0x0014, :default_move_rate, UInt8, nullable: true, writable: true, optional: true, requires: :lighting
      attribute 0x4000, :start_up_current_level, UInt8, nullable: true, writable: true, requires: :lighting

      # OnLevel must lie within the level range the device reports.
      before_write :on_level do |level|
        InteractionModel::Status.constraint_error if level && !(@min_level..@max_level).includes?(level)
      end

      command 0x00, :move_to_level, request: MoveToLevelRequest
      command 0x01, :move, request: MoveRequest
      command 0x02, :step, request: StepRequest
      command 0x03, :stop, request: StopRequest
      command 0x04, :move_to_level_with_on_off, request: MoveToLevelWithOnOffRequest, requires: :on_off
      command 0x05, :move_with_on_off, request: MoveWithOnOffRequest, requires: :on_off
      command 0x06, :step_with_on_off, request: StepWithOnOffRequest, requires: :on_off
      command 0x07, :stop_with_on_off, request: StopWithOnOffRequest, requires: :on_off
      command 0x08, :move_to_closest_frequency, request: MoveToClosestFrequencyRequest, requires: :frequency

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @current_level : UInt8 = LOWEST_LEVEL,
        @min_level : UInt8 = LOWEST_LEVEL,
        @max_level : UInt8 = HIGHEST_LEVEL,
        @on_level : UInt8? = nil,
        @options : UInt8 = 0_u8,
        @feature_map : Feature = Feature::OnOff | Feature::Lighting,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      # ------------------------------------------------------------------------
      # Commands (transitions are instant; no transition manager yet)
      # ------------------------------------------------------------------------

      def move_to_level(request : MoveToLevelRequest) : InteractionModel::Status
        transition_to(request.level)
      end

      def move(request : MoveRequest) : InteractionModel::Status
        move_towards(request.move_mode)
      end

      def step(request : StepRequest) : InteractionModel::Status
        step_by(request.step_mode, request.step_size)
      end

      def stop(request : StopRequest) : InteractionModel::Status
        halt
      end

      def move_to_level_with_on_off(request : MoveToLevelWithOnOffRequest) : InteractionModel::Status
        transition_to(request.level)
      end

      def move_with_on_off(request : MoveWithOnOffRequest) : InteractionModel::Status
        move_towards(request.move_mode)
      end

      def step_with_on_off(request : StepWithOnOffRequest) : InteractionModel::Status
        step_by(request.step_mode, request.step_size)
      end

      def stop_with_on_off(request : StopWithOnOffRequest) : InteractionModel::Status
        halt
      end

      def move_to_closest_frequency(request : MoveToClosestFrequencyRequest) : InteractionModel::Status
        self.current_frequency = request.frequency.clamp(@min_frequency, @max_frequency)
        InteractionModel::Status.success
      end

      private def move_towards(mode : MoveMode) : InteractionModel::Status
        case mode
        when .up?
          transition_to(@max_level)
        when .down?
          transition_to(@min_level)
        else
          InteractionModel::Status.invalid_command
        end
      end

      private def step_by(mode : StepMode, step_size : UInt8) : InteractionModel::Status
        case mode
        when .up?
          target = @current_level.to_u16 + step_size
          transition_to([target, @max_level.to_u16].min.to_u8)
        when .down?
          target = @current_level.to_i16 - step_size
          transition_to([target, @min_level.to_i16].max.to_u8)
        else
          InteractionModel::Status.invalid_command
        end
      end

      private def halt : InteractionModel::Status
        self.remaining_time = 0_u16
        InteractionModel::Status.success
      end

      # Moves to *level* clamped to the supported range; instant for now.
      private def transition_to(level : UInt8) : InteractionModel::Status
        self.current_level = level.clamp(@min_level, @max_level)
        self.remaining_time = 0_u16
        InteractionModel::Status.success
      end

      # Called with the previous and the new level whenever CurrentLevel changes
      def on_level_changed(&block : UInt8, UInt8 -> Nil) : Nil
        on_current_level_changed(&block)
      end

      # ------------------------------------------------------------------------
      # Public Interface
      # ------------------------------------------------------------------------

      def level=(level : UInt8) : UInt8
        transition_to(level)
        level
      end

      # level as a percentage 0.0 - 100.0
      def level=(level : Float)
        range = @max_level - @min_level
        level = ((level.clamp(0.0, 100.0) / 100.0) * range.to_f).round(:ties_away).to_u8 + @min_level
        transition_to(level)
        level
      end
    end
  end
end
