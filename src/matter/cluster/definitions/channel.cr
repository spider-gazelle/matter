module Matter
  module Cluster
    module Definitions
      module Channel
        enum LineupInfoType : UInt8
          # MultiSystemOperator
          Mso = 0
        end

        enum Status : UInt8
          # Command succeeded
          Success = 0

          # More than one equal match for the ChannelInfoStruct passed in.
          MultipleMatches = 1

          # No matches for the ChannelInfoStruct passed in.
          NoMatches = 2
        end

        # This indicates a channel in a channel lineup.
        #
        # While the major and minor numbers in the ChannelInfoStruct support use of ATSC channel format, a lineup may use
        # other formats which can map into these numeric values.
        struct Information
          include TLV::Serializable

          # This shall indicate the channel major number value (for example, using ATSC format). When the channel number
          # is expressed as a string, such as "13.1" or "256", the major number would be 13 or 256, respectively.
          @[TLV::Field(tag: 0)]
          property major_number : UInt16

          # This shall indicate the channel minor number value (for example, using ATSC format). When the channel number
          # is expressed as a string, such as "13.1" or "256", the minor number would be 1 or 0, respectively.
          @[TLV::Field(tag: 1)]
          property minor_number : UInt16

          # This shall indicate the marketing name for the channel, such as “The CW" or "Comedy Central". This field is
          # optional, but SHOULD be provided when known.
          @[TLV::Field(tag: 2)]
          property name : String?

          # This shall indicate the call sign of the channel, such as "PBS". This field is optional, but SHOULD be
          # provided when known.
          @[TLV::Field(tag: 3)]
          property call_sign : String?

          # This shall indicate the local affiliate call sign, such as "KCTS". This field is optional, but SHOULD be
          # provided when known.
          @[TLV::Field(tag: 4)]
          property affiliate_call_sign : String?
        end

        # Input to the Channel changeChannelByNumber command
        struct ChangeChannelByNumberRequest
          include TLV::Serializable

          # This shall indicate the channel major number value (ATSC format) to which the channel should change.
          @[TLV::Field(tag: 0)]
          property major_number : UInt16

          # This shall indicate the channel minor number value (ATSC format) to which the channel should change.
          @[TLV::Field(tag: 1)]
          property minor_number : UInt16
        end

        # Input to the Channel skipChannel command
        struct SkipChannelRequest
          include TLV::Serializable

          # This shall indicate the number of steps to increase (Count is positive) or decrease (Count is negative) the
          # current channel.
          @[TLV::Field(tag: 0)]
          property count : UInt16
        end

        # The Lineup Info allows references to external lineup sources like Gracenote. The combination of OperatorName,
        # LineupName, and PostalCode MUST uniquely identify a lineup.
        struct LineupInfo
          include TLV::Serializable

          # This shall indicate the name of the operator, for example “Comcast”.
          @[TLV::Field(tag: 0)]
          property operator_name : String

          @[TLV::Field(tag: 1)]
          property lineup_name : String?

          @[TLV::Field(tag: 2)]
          property postal_code : String?

          # This shall indicate the type of lineup. This field is optional, but SHOULD be provided when known.
          @[TLV::Field(tag: 3)]
          property lineup_info_type : LineupInfoType
        end

        # Input to the Channel changeChannel command
        struct ChangeChannelRequest
          include TLV::Serializable

          # This shall contain a user-input string to match in order to identify the target channel.
          @[TLV::Field(tag: 0)]
          property match : String
        end

        # This command shall be generated in response to a ChangeChannel command.
        struct ChangeChannelResponse
          include TLV::Serializable

          # This shall indicate the status of the command which resulted in this response.
          @[TLV::Field(tag: 0)]
          property status : Status

          # This shall indicate Optional app-specific data.
          @[TLV::Field(tag: 1)]
          property data : Slice(UInt8)?
        end
      end
    end
  end
end
