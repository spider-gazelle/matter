module Matter
  module Cluster
    module Definitions
      module MediaInput
        enum InputType : UInt8
          # Indicates content not coming from a physical input.
          Internal  =  0
          Aux       =  1
          Coax      =  2
          Composite =  3
          Hdmi      =  4
          Input     =  5
          Line      =  6
          Optical   =  7
          Video     =  8
          Scart     =  9
          Usb       = 10
          Other     = 11
        end

        # This contains information about an input.
        struct InputInformation
          include TLV::Serializable

          # This shall indicate the unique index into the list of Inputs.
          @[TLV::Field(tag: 0)]
          property index : UInt8

          # This shall indicate the type of input
          @[TLV::Field(tag: 1)]
          property inputType : InputType

          # This shall indicate the input name, such as “HDMI 1”. This field may be blank, but SHOULD be provided when
          # known.
          @[TLV::Field(tag: 2)]
          property name : String

          # This shall indicate the user editable input description, such as “Living room Playstation”. This field may
          # be blank, but SHOULD be provided when known.
          @[TLV::Field(tag: 3)]
          property description : String
        end

        # Input to the MediaInput selectInput command
        struct SelectInputRequest
          include TLV::Serializable

          # This shall indicate the index field of the InputInfoStruct from the InputList attribute in which to change
          # to.
          @[TLV::Field(tag: 0)]
          property index : UInt8
        end

        # Input to the MediaInput renameInput command
        struct RenameInputRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property index : UInt8

          @[TLV::Field(tag: 1)]
          property name : String
        end
      end
    end
  end
end
