module Matter
  module Cluster
    module Definitions
      module ColorControl
        # The value of the ColorControl driftCompensation attribute
        enum DriftCompensation : UInt8
          None                                  = 0
          OtherUnknown                          = 1
          TemperatureMonitoring                 = 2
          OpticalLuminanceMonitoringAndFeedback = 3
          OpticalColorMonitoringAndFeedback     = 4
        end

        # The value of the ColorControl colorMode attribute
        enum ColorMode : UInt8
          CurrentHueAndCurrentSaturation = 0
          CurrentXAndCurrentY            = 1
          ColorTemperatureMireds         = 2
        end

        # The value of the ColorControl enhancedColorMode attribute
        enum EnhancedColorMode : UInt8
          CurrentHueAndCurrentSaturation         = 0
          CurrentXAndCurrentY                    = 1
          ColorTemperatureMireds                 = 2
          EnhancedCurrentHueAndCurrentSaturation = 3
        end

        enum Direction : UInt8
          ShortestDistance = 0
          LongestDistance  = 1
          Up               = 2
          Down             = 3
        end

        enum MoveMode : UInt8
          Stop = 0
          Up   = 1
          Down = 3
        end

        enum StepMode : UInt8
          Up   = 1
          Down = 3
        end

        enum Action : UInt8
          DeActivateTheColorLoop                                              = 0
          ActivateTheColorLoopFromTheValueInTheColorLoopStartEnhancedHueField = 1
          ActivateTheColorLoopFromTheValueOfTheEnhancedCurrentHueAttribute    = 2
        end

        enum ColorLoopSetDirection : UInt8
          DecrementTheHueInTheColorLoop = 0
          IncrementTheHueInTheColorLoop = 1
        end

        # Input to the ColorControl moveToHue command
        struct MoveToHueRequest
          include TLV::Serializable

          # The Hue field specifies the hue to be moved to.
          @[TLV::Field(tag: 0)]
          property hue : UInt8

          # The Direction field shall be one of the non-reserved values in Values of the Direction Field.
          @[TLV::Field(tag: 1)]
          property direction : Direction

          # The TransitionTime field specifies, in 1/10ths of a second, the time that shall be taken to move to the new hue.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl moveHue command
        struct MoveHueRequest
          include TLV::Serializable

          # The MoveMode field shall be one of the non-reserved values in Values of the MoveMode Field. If the MoveMode
          # field is equal to 0 (Stop), the Rate field shall be ignored.
          @[TLV::Field(tag: 0)]
          property move_mode : MoveMode

          # The Rate field specifies the rate of movement in steps per second. A step is a change in the device’s hue of
          # one unit. If the MoveMode field is set to 1 (up) or 3 (down) and the Rate field has a value of zero, the
          # command has no effect and a response command shall be sent in response, with the status code set to
          # INVALID_COMMAND. If the MoveMode field is set to 0 (stop) the Rate field shall be ignored.
          @[TLV::Field(tag: 1)]
          property rate : UInt8

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl stepHue command
        struct StepHueRequest
          include TLV::Serializable

          # The StepMode field shall be one of the non-reserved values in Values of the StepMode Field.
          # Table 50. Values of the StepMode Field
          @[TLV::Field(tag: 0)]
          property step_mode : StepMode

          # The change to be added to (or subtracted from) the current value of the device’s hue.
          @[TLV::Field(tag: 1)]
          property step_size : UInt8

          # The TransitionTime field specifies, in 1/10ths of a second, the time that shall be taken to perform the
          # step. A step is a change in the device’s hue of ‘Step size’ units.
          #
          # Note: Here the TransitionTime data field is of data type uint8, where uint16 is more common for
          # TransitionTime data fields in other clusters / commands.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt8

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl moveToSaturation command
        struct MoveToSaturationRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property saturation : UInt8

          @[TLV::Field(tag: 1)]
          property transition_time : UInt8

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl moveSaturation command
        struct MoveSaturationRequest
          include TLV::Serializable

          # The MoveMode field shall be one of the non-reserved values in Values of the MoveMode Field. If the MoveMode
          # field is equal to 0 (Stop), the Rate field shall be ignored.
          @[TLV::Field(tag: 0)]
          property move_mode : MoveMode

          # The Rate field specifies the rate of movement in steps per second. A step is a change in the device’s
          #
          # saturation of one unit. If the MoveMode field is set to 1 (up) or 3 (down) and the Rate field has a value of
          # zero, the command has no effect and a response command shall be sent in response, with the status code set
          # to INVALID_COMMAND. If the MoveMode field is set to 0 (stop) the Rate field shall be ignored.
          @[TLV::Field(tag: 1)]
          property rate : UInt8

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl stepSaturation command
        struct StepSaturationRequest
          include TLV::Serializable

          # The StepMode field shall be one of the non-reserved values in Values of the StepMode Field.
          @[TLV::Field(tag: 0)]
          property step_mode : StepMode

          # The change to be added to (or subtracted from) the current value of the device’s saturation.
          @[TLV::Field(tag: 1)]
          property step_size : UInt8

          # The TransitionTime field specifies, in 1/10ths of a second, the time that shall be taken to perform the
          # step. A step is a change in the device’s saturation of ‘Step size’ units.
          #
          # Note: Here the TransitionTime data field is of data type uint8, where uint16 is more common for
          # TransitionTime data fields in other clusters / commands.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt8

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl moveToHueAndSaturation command
        struct MoveToHueAndSaturationRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property hue : UInt8

          @[TLV::Field(tag: 1)]
          property saturation : UInt8

          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl moveToColor command
        struct MoveToColorRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property x : UInt16

          @[TLV::Field(tag: 1)]
          property y : UInt16

          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl moveColor command
        struct MoveColorRequest
          include TLV::Serializable

          # The X field specifies the rate of movement in steps per second. A step is a change in the device’s
          # CurrentX attribute of one unit.
          @[TLV::Field(tag: 0)]
          property x : UInt16

          # The Y field specifies the rate of movement in steps per second. A step is a change in the device’s
          # CurrentY attribute of one unit.
          @[TLV::Field(tag: 1)]
          property y : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl stepColor command
        struct StepColorRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property x : UInt16

          @[TLV::Field(tag: 1)]
          property y : UInt16

          # The TransitionTime field specifies, in 1/10ths of a second, the time that shall be taken to perform the color change.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl moveToColorTemperature command
        struct MoveToColorTemperatureRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property color_temperature_mireds : UInt16

          @[TLV::Field(tag: 1)]
          property transition_time : UInt16

          @[TLV::Field(tag: 2)]
          property mask : UInt8

          @[TLV::Field(tag: 3)]
          property override : UInt8
        end

        # Input to the ColorControl moveColorTemperature command
        struct MoveColorTemperatureRequest
          include TLV::Serializable

          # This field is identical to the MoveMode field of the MoveHue command of the Color Control cluster
          #
          # (see sub-clause MoveHue Command). If the MoveMode field is equal to 0 (Stop), the Rate field shall be
          # ignored.
          @[TLV::Field(tag: 0)]
          property move_mode : MoveMode

          # The Rate field specifies the rate of movement in steps per second. A step is a change in the color
          # temperature of a device by one unit. If the MoveMode field is set to 1 (up) or 3 (down) and the Rate field
          # has a value of zero, the command has no effect and a response command shall be sent in response, with the
          # status code set to INVALID_COMMAND. If the MoveMode field is set to 0 (stop) the Rate field shall be ignored.
          @[TLV::Field(tag: 1)]
          property rate : UInt16

          # The ColorTemperatureMinimumMireds field specifies a lower bound on the ColorTemperatureMireds attribute (≡
          # an upper bound on the color temperature in kelvins) for the current move operation
          #
          # ColorTempPhysicalMinMireds ≤ ColorTemperatureMinimumMireds field ≤ ColorTemperatureMireds
          #
          # As such if the move operation takes the ColorTemperatureMireds attribute towards the value of the
          # ColorTemperatureMinimumMireds field it shall be clipped so that the above invariant is satisfied. If the
          # ColorTemperatureMinimumMireds field is set to 0, ColorTempPhysicalMinMireds shall be used as the lower bound
          # for the ColorTemperatureMireds attribute.
          @[TLV::Field(tag: 2)]
          property color_emperature_minimum_mireds : UInt16

          # The ColorTemperatureMaximumMireds field specifies an upper bound on the ColorTemperatureMireds attribute (≡
          # a lower bound on the color temperature in kelvins) for the current move operation
          #
          # ColorTemperatureMireds ≤ ColorTemperatureMaximumMireds field ≤ ColorTempPhysicalMaxMireds
          #
          # As such if the move operation takes the ColorTemperatureMireds attribute towards the value of the
          # ColorTemperatureMaximumMireds field it shall be clipped so that the above invariant is satisfied. If the
          # ColorTemperatureMaximumMireds field is set to 0, ColorTempPhysicalMaxMireds shall be used as the upper bound
          # for the ColorTemperatureMireds attribute.
          @[TLV::Field(tag: 3)]
          property color_emperature_maximum_mireds : UInt16

          @[TLV::Field(tag: 4)]
          property mask : UInt8

          @[TLV::Field(tag: 5)]
          property override : UInt8
        end

        # Input to the ColorControl stepColorTemperature command
        struct StepColorTemperatureRequest
          include TLV::Serializable

          # This field is identical to the StepMode field of the StepHue command of the Color Control cluster (see sub-clause StepHue Command).
          @[TLV::Field(tag: 0)]
          property step_mode : StepMode

          # The StepSize field specifies the change to be added to (or subtracted from) the current value of the device’s color temperature.
          @[TLV::Field(tag: 1)]
          property step_size : UInt16

          # The TransitionTime field specifies, in units of 1/10ths of a second, the time that shall be taken to perform
          # the step. A step is a change to the device’s color temperature of a magnitude corresponding to the StepSize field.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          # The ColorTemperatureMinimumMireds field specifies a lower bound on the ColorTemperatureMireds attribute (≡
          # an upper bound on the color temperature in kelvins) for the current step operation
          #
          # ColorTempPhysicalMinMireds ≤ ColorTemperatureMinimumMireds field ≤ ColorTemperatureMireds
          #
          # As such if the step operation takes the ColorTemperatureMireds attribute towards the value of the Color
          # Temperature Minimum Mireds field it shall be clipped so that the above invariant is satisfied. If the
          # ColorTemperatureMinimumMireds field is set to 0, ColorTempPhysicalMinMireds shall be used as the lower bound
          # for the ColorTemperatureMireds attribute.
          @[TLV::Field(tag: 3)]
          property color_emperature_minimum_mireds : UInt16

          # The ColorTemperatureMaximumMireds field specifies an upper bound on the ColorTemperatureMireds attribute (≡
          # a lower bound on the color temperature in kelvins) for the current step operation
          #
          # ColorTemperatureMireds ≤ ColorTemperatureMaximumMireds field ≤ ColorTempPhysicalMaxMireds
          #
          # As such if the step operation takes the ColorTemperatureMireds attribute towards the value of the
          # ColorTemperatureMaximumMireds field it shall be clipped so that the above invariant is satisfied. If the
          # ColorTemperatureMaximum Mireds field is set to 0, ColorTempPhysicalMaxMireds shall be used as the upper
          # bound for the ColorTemperatureMireds attribute.
          @[TLV::Field(tag: 4)]
          property color_emperature_maximum_mireds : UInt16

          @[TLV::Field(tag: 5)]
          property mask : UInt8

          @[TLV::Field(tag: 6)]
          property override : UInt8
        end

        # Input to the ColorControl enhancedMoveToHue command
        struct EnhancedMoveToHueRequest
          include TLV::Serializable

          # The Hue field specifies the hue to be moved to.
          @[TLV::Field(tag: 0)]
          property enhanced_hue : UInt8

          # The Direction field shall be one of the non-reserved values in Values of the Direction Field.
          @[TLV::Field(tag: 1)]
          property direction : Direction

          # The TransitionTime field specifies, in 1/10ths of a second, the time that shall be taken to move to the new hue.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl enhancedMoveHue command
        struct EnhancedMoveHueRequest
          include TLV::Serializable

          # This field is identical to the MoveMode field of the MoveHue command of the Color Control cluster (see
          # sub-clause MoveHue Command). If the MoveMode field is equal to 0 (Stop), the Rate field shall be ignored.
          @[TLV::Field(tag: 0)]
          property move_mode : MoveMode

          # The Rate field specifies the rate of movement in steps per second. A step is a change in the extended hue of
          # a device by one unit. If the MoveMode field is set to 1 (up) or 3 (down) and the Rate field has a value of
          # zero, the command has no effect and a response command shall be sent in response, with the status code set
          # to INVALID_COMMAND. If the MoveMode field is set to 0 (stop) the Rate field shall be ignored.
          @[TLV::Field(tag: 1)]
          property rate : UInt16

          @[TLV::Field(tag: 2)]
          property mask : UInt8

          @[TLV::Field(tag: 3)]
          property override : UInt8
        end

        # Input to the ColorControl enhancedStepHue command
        struct EnhancedStepHueRequest
          include TLV::Serializable

          # This field is identical to the StepMode field of the StepHue command of the Color Control cluster (see
          # sub-clause StepHue Command).
          @[TLV::Field(tag: 0)]
          property step_mode : StepMode

          # The StepSize field specifies the change to be added to (or subtracted from) the current value of the
          # device’s enhanced hue.
          @[TLV::Field(tag: 1)]
          property step_size : UInt16

          # The TransitionTime field specifies, in units of 1/10ths of a second, the time that shall be taken to perform
          # the step. A step is a change to the device’s enhanced hue of a magnitude corresponding to the StepSize field.
          #
          # Note: Here TransitionTime data field is of data type uint16, while the TransitionTime data field of the
          # StepHue command is of data type uint8.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl enhancedMoveToHueAndSaturation command
        struct EnhancedMoveToHueAndSaturationRequest
          include TLV::Serializable

          # The EnhancedHue field specifies the target extended hue for the lamp.
          @[TLV::Field(tag: 0)]
          property enhanced_hue : UInt16

          # This field is identical to the Saturation field of the MoveToHueAndSaturation command of the Color Control
          # cluster (see sub-clause MoveToHueAndSaturation Command).
          @[TLV::Field(tag: 1)]
          property saturation : UInt8

          # This field is identical to the TransitionTime field of the MoveToHue command of the Color Control cluster
          # (see sub-clause MoveToHueAndSaturation Command).
          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property mask : UInt8

          @[TLV::Field(tag: 4)]
          property override : UInt8
        end

        # Input to the ColorControl colorLoopSet command
        struct ColorLoopSetRequest
          include TLV::Serializable

          # The UpdateFlags field specifies which color loop attributes to update before the color loop is started. This
          # field shall be formatted as illustrated in Format of the UpdateFlags Field of the ColorLoopSet Command.
          #
          # The UpdateAction sub-field is 1 bit in length and specifies whether the device shall adhere to the action
          # field in order to process the command. If this sub-field is set to 1, the device shall adhere to the action
          # field. If this sub-field is set to 0, the device shall ignore the Action field.
          #
          # The UpdateDirection sub-field is 1 bit in length and specifies whether the device shall update the
          # ColorLoopDirection attribute with the Direction field. If this sub-field is set to 1, the device shall
          # update the value of the ColorLoopDirection attribute with the value of the Direction field. If this
          # sub-field is set to 0, the device shall ignore the Direction field.
          #
          # The UpdateTime sub-field is 1 bit in length and specifies whether the device shall update the ColorLoopTime
          # attribute with the Time field. If this sub-field is set to 1, the device shall update the value of the
          # ColorLoopTime attribute with the value of the Time field. If this sub-field is set to 0, the device shall
          # ignore the Time field.
          #
          # The UpdateStartHue sub-field is 1 bit in length and specifies whether the device shall update the
          # ColorLoopStartEnhancedHue attribute with the StartHue field. If this sub-field is set to 1, the device shall
          # update the value of the ColorLoopStartEnhancedHue attribute with the value of the StartHue field. If this
          # sub-field is set to 0, the device shall ignore the StartHue field.
          @[TLV::Field(tag: 0)]
          property update_flag : UInt8

          # The Action field specifies the action to take for the color loop if the UpdateAction sub-field of the
          # UpdateFlags field is set to 1. This field shall be set to one of the non-reserved values listed in Values of
          # the Action Field of the ColorLoopSet Command.
          @[TLV::Field(tag: 1)]
          property action : Action

          # The Direction field specifies the direction for the color loop if the Update Direction field of the
          # UpdateFlags field is set to 1. This field shall be set to one of the non-reserved values listed in Values of
          # the Direction Field of the ColorLoopSet Command.
          @[TLV::Field(tag: 2)]
          property direction : ColorLoopSetDirection

          # The Time field specifies the number of seconds over which to perform a full color loop if the UpdateTime
          # sub-field of the UpdateFlags field is set to 1.
          @[TLV::Field(tag: 3)]
          property time : UInt16

          @[TLV::Field(tag: 4)]
          property start_hue : UInt16

          @[TLV::Field(tag: 5)]
          property mask : UInt8

          @[TLV::Field(tag: 6)]
          property override : UInt8
        end

        # Input to the ColorControl stopMoveStep command
        struct StopMoveStepRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property mask : UInt8

          @[TLV::Field(tag: 1)]
          property override : UInt8
        end
      end
    end
  end
end
