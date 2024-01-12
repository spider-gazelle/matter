module Matter
  module Cluster
    module Definitions
      module AudioOutput
        # The type of output, expressed as an enum, with the following values:
        enum OutputType : UInt8
          # HDMI
          Hdmi      = 0
          Bt        = 1
          Optical   = 2
          Headphone = 3
          Internal  = 4
          Other     = 5
        end

        # This contains information about an output.
        struct OutputInformation
          include TLV::Serializable

          # This shall indicate the unique index into the list of outputs.
          @[TLV::Field(tag: 0)]
          property index : UInt8

          # This shall indicate the type of output
          @[TLV::Field(tag: 1)]
          property output_type : OutputType

          # The device defined and user editable output name, such as “Soundbar”, “Speakers”. This field may be blank,
          # but SHOULD be provided when known.
          @[TLV::Field(tag: 2)]
          property name : String
        end

        # Input to the AudioOutput selectOutput command
        struct SelectOutputRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property index : UInt8
        end

        # Input to the AudioOutput renameOutput command
        struct RenameOutputRequest
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
