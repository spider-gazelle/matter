module Matter
  module Cluster
    module Definitions
      module LevelControl
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

          @[TLV::Field(tag: 1)]
          property transition_time : UInt16

          @[TLV::Field(tag: 2)]
          property mask : UInt8

          @[TLV::Field(tag: 3)]
          property override : UInt8
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
          @[TLV::Field(tag: 1)]
          property rate : UInt8

          @[TLV::Field(tag: 2)]
          property mask : UInt8

          @[TLV::Field(tag: 3)]
          property override : UInt8
        end

        # Input to the LevelControl step command
        struct StepRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property step_mode : StepMode

          @[TLV::Field(tag: 1)]
          property step_size : UInt8

          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the LevelControl stop command
        struct StopRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property mask : UInt8

          @[TLV::Field(tag: 1)]
          property override : UInt8
        end

        # Input to the LevelControl moveToLevelWithOnOff command
        struct MoveToLevelWithOnOffRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property level : UInt8

          @[TLV::Field(tag: 1)]
          property transition_time : UInt16

          @[TLV::Field(tag: 2)]
          property mask : UInt8

          @[TLV::Field(tag: 3)]
          property override : UInt8
        end

        # Input to the LevelControl moveWithOnOff command
        struct MoveWithOnOffRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property move_mode : MoveMode

          @[TLV::Field(tag: 1)]
          property rate : UInt8

          @[TLV::Field(tag: 2)]
          property mask : UInt8

          @[TLV::Field(tag: 3)]
          property override : UInt8
        end

        # Input to the LevelControl stepWithOnOff command
        struct StepWithOnOffRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property step_mode : StepMode

          @[TLV::Field(tag: 1)]
          property step_size : UInt8

          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the LevelControl stopWithOnOff command
        struct StopWithOnOffRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property mask : UInt8

          @[TLV::Field(tag: 1)]
          property override : UInt8
        end

        # Input to the LevelControl moveToClosestFrequency command
        struct MoveToClosestFrequencyRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property frequency : UInt16
        end
      end
    end
  end
end