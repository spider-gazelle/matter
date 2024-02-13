module Matter
  module Cluster
    module Definitions
      module Identify
        enum Type : UInt8
          # No presentation.
          None = 0

          # Light output of a lighting product.
          LightOutput = 1

          # Typically a small LED.
          VisibleIndicator = 2

          AudibleBeep = 3

          # Presentation will be visible on display screen.
          Display = 4

          # Presentation will be conveyed by actuator functionality such as through a window blind operation or in-wall
          # relay.
          Actuator = 5
        end

        enum EffectIdentifier : UInt8
          # e.g., Light is turned on/off once.
          Blink = 0

          # e.g., Light is turned on/off over 1 second and repeated 15 times.
          Breathe = 1

          # e.g., Colored light turns green for 1 second; non-colored light flashes twice.
          Okay = 2

          # e.g., Colored light turns orange for 8 seconds; non-colored light switches to the maximum brightness for
          # 0.5s and then minimum brightness for 7.5s.
          ChannelChange = 11

          # Complete the current effect sequence before terminating. e.g., if in the middle of a breathe effect (as
          # above), first complete the current 1s breathe effect and then terminate the effect.
          FinishEffect = 254

          # Terminate the effect as soon as possible.
          StopEffect = 255
        end

        enum EffectVariant : UInt8
          Default = 0
        end

        # Input to the Identify identify command
        struct Request
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property identify_time : UInt16
        end

        # Input to the Identify triggerEffect command
        struct TriggerEffectRequest
          include TLV::Serializable

          # This field specifies the identify effect to use. All values of the EffectIdentifier shall be supported.
          # Implementors may deviate from the example light effects in the table below, but they SHOULD indicate during
          # testing how they handle each effect.
          #
          # This field shall contain one of the non-reserved values listed below.
          #
          # Table 3. Values of the EffectIdentifier Field of the TriggerEffect Command
          @[TLV::Field(tag: 0)]
          property effect_identifier : EffectIdentifier

          # This field is used to indicate which variant of the effect, indicated in the EffectIdentifier field, SHOULD
          # be triggered. If a device does not support the given variant, it shall use the default variant. This field
          # shall contain one of the values listed below:
          #
          # Table 4. Values of the EffectVariant Field of the TriggerEffect Command
          @[TLV::Field(tag: 1)]
          property effect_variany : EffectVariant
        end

        # This command is generated in response to receiving an IdentifyQuery command, see IdentifyQuery Command, in the
        # case that the device is currently identifying itself.
        struct IdentifyQueryResponse
          include TLV::Serializable

          # This field contains the current value of the IdentifyTime attribute, and specifies the length of time, in
          # seconds, that the device will continue to identify itself.
          @[TLV::Field(tag: 0)]
          property timeout : UInt16
        end


      end
    end
  end
end
