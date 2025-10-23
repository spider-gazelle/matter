module Matter
  module Cluster
    module Definitions
      module OnOff
        enum StartUp : UInt8
          # Set the OnOff attribute to FALSE
          Off = 0

          # Set the OnOff attribute to TRUE
          On = 1

          # If the previous value of the OnOff attribute is equal to FALSE, set the OnOff attribute to TRUE. If the
          # previous value of the OnOff attribute is equal to TRUE, set the OnOff attribute to FALSE (toggle).
          Toggle = 2
        end

        enum EffectIdentifier : UInt8
          DelayedAllOff = 0
          DyingLight    = 1
        end

        # Input to the OnOff offWithEffect command
        struct OffWithEffectRequest
          include TLV::Serializable

          # The EffectIdentifier field specifies the fading effect to use when turning the device off. This field shall
          # contain one of the non-reserved values listed in Values of the EffectIdentifier Field of the OffWithEffect
          # Command.
          @[TLV::Field(tag: 0)]
          property effect_identifier : EffectIdentifier

          # The EffectVariant field is used to indicate which variant of the effect, indicated in the EffectIdentifier
          # field, SHOULD be triggered. If the server does not support the given variant, it shall use the default
          # variant. This field is dependent on the value of the EffectIdentifier field and shall contain one of the
          # non-reserved values listed in Values of the EffectVariant Field of the OffWithEffect Command.
          @[TLV::Field(tag: 1)]
          property effect_variant : UInt8
        end

        # Input to the OnOff onWithTimedOff command
        struct OnWithTimedOffRequest
          include TLV::Serializable
          # The OnOffControl field contains information on how the server is to be operated. This field shall be
          # formatted as illustrated in Format of the OnOffControl Field of the OnWithTimedOff Command.
          #
          # The AcceptOnlyWhenOn sub-field is 1 bit in length and specifies whether the OnWithTimedOff command is to be
          # processed unconditionally or only when the OnOff attribute is equal to TRUE. If this sub-field is set to 1,
          # the OnWithTimedOff command shall only be accepted if the OnOff attribute is equal to TRUE. If this sub-field
          # is set to 0, the OnWithTimedOff command shall be processed unconditionally.
          @[TLV::Field(tag: 0)]
          property on_off_control : UInt8

          # The OnTime field is used to adjust the value of the OnTime attribute.
          @[TLV::Field(tag: 0)]
          property on_time : UInt16

          # The OffWaitTime field is used to adjust the value of the OffWaitTime attribute.
          @[TLV::Field(tag: 0)]
          property off_wait_time : UInt16
        end
      end
    end
  end
end
