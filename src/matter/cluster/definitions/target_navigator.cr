module Matter
  module Cluster
    module Definitions
      module TargetNavigator
        enum StatusCode : UInt8
          # Command succeeded
          Success = 0

          # Requested target was not found in the TargetList
          TargetNotFound = 1

          # Target request is not allowed in current state.
          NotAllowed = 2
        end

        # This indicates an object describing the navigable target.
        struct TargetInformation
          include TLV::Serializable

          # An unique id within the TargetList.
          @[TLV::Field(tag: 0)]
          property identifier : UInt8

          # A name string for the TargetInfoStruct.
          @[TLV::Field(tag: 1)]
          property name : String
        end

        # Input to the TargetNavigator navigateTarget command
        struct NavigateTargetRequest
          include TLV::Serializable

          # This shall indicate the Identifier for the target for UX navigation. The Target shall be an Identifier value
          # contained within one of the TargetInfoStruct objects in the TargetList attribute list.
          @[TLV::Field(tag: 0)]
          property target : UInt8

          # This shall indicate Optional app-specific data.
          @[TLV::Field(tag: 1)]
          property data : String?
        end

        # This command shall be generated in response to NavigateTarget command.
        struct NavigateTargetResponse
          include TLV::Serializable

          # This shall indicate the of the command.
          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          # This shall indicate Optional app-specific data.
          @[TLV::Field(tag: 1)]
          property data : String?
        end
      end
    end
  end
end
