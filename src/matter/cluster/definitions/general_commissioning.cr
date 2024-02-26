module Matter
  module Cluster
    module Definitions
      module GeneralCommissioning
        # This enumeration is used by the RegulatoryConfig and LocationCapability attributes to indicate possible radio
        # usage.
        enum RegulatoryLocationType : UInt8
          # Indoor only
          Indoor = 0

          # Outdoor only
          Outdoor = 1

          # Indoor/Outdoor
          IndoorOutdoor = 2
        end

        enum CommissioningError : UInt8
          # No error
          Ok = 0

          # Attempting to set regulatory configuration to a region or indoor/outdoor mode for which the server does not
          # have proper configuration.
          ValueOutsideRange = 1

          # Executed CommissioningComplete outside CASE session.
          InvalidAuthentication = 2

          # Executed CommissioningComplete when there was no active Fail-Safe context.
          NoFailSafe = 3

          # Attempting to arm fail- safe or execute CommissioningComplete from a fabric different than the one
          # associated with the current fail- safe context.
          BusyWithOtherAdmin = 4
        end

        # This structure provides some constant values that may be of use to all commissioners.
        struct BasicCommissioningInformation
          include TLV::Serializable

          # This field shall contain a conservative initial duration (in seconds) to set in the FailSafe for the
          # commissioning flow to complete successfully. This may vary depending on the speed or sleepiness of the
          # Commissionee. This value, if used in the ArmFailSafe command’s ExpiryLengthSeconds field SHOULD allow a
          # Commissioner to proceed with a nominal commissioning without having to-rearm the fail-safe, with some margin.
          @[TLV::Field(tag: 0)]
          property fail_safe_expiry_length_seconds : UInt16

          # This field shall contain a conservative value in seconds denoting the maximum total duration for which a
          # fail safe timer can be re-armed. See Section 11.9.6.2.1, “Fail Safe Context”.
          #
          # The value of this field shall be greater than or equal to the FailSafeExpiryLengthSeconds. Absent additional
          # guidelines, it is RECOMMENDED that the value of this field be aligned with Section 5.4.2.3, “Announcement
          # Duration” and default to 900 seconds.
          @[TLV::Field(tag: 1)]
          property max_cumulative_failsafe_seconds : UInt16
        end

        # Input to the GeneralCommissioning armFailSafe command
        struct ArmFailSafeRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property expiryLengthSeconds : UInt16

          @[TLV::Field(tag: 1)]
          property breadcrumb : UInt64
        end

        struct ArmFailSafeResponse
          include TLV::Serializable

          # This field shall contain the result of the operation, based on the behavior specified in the functional
          # description of the ArmFailSafe command.
          @[TLV::Field(tag: 0)]
          property error_code : CommissioningError

          # See Section 11.9.6.1, “Common fields in General Commissioning cluster responses”.
          @[TLV::Field(tag: 1)]
          property debug_text : String
        end

        # Input to the GeneralCommissioning setRegulatoryConfig command
        struct SetRegularConfigurationRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property new_regulatory_configuration : RegulatoryLocationType

          @[TLV::Field(tag: 1)]
          property country_code : String

          @[TLV::Field(tag: 2)]
          property breadcrumb : UInt64
        end

        # This field shall contain the result of the operation, based on the behavior specified in the functional
        # description of the SetRegulatoryConfig command.
        #
        # See Section 11.9.6.1, “Common fields in General Commissioning cluster responses”.
        struct SetRegulatoryConfigurationResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property error_code : CommissioningError

          @[TLV::Field(tag: 1)]
          property debug_text : String
        end

        # This field shall contain the result of the operation, based on the behavior specified in the functional
        # description of the CommissioningComplete command.
        #
        # See Section 11.9.6.1, “Common fields in General Commissioning cluster responses”.
        struct CommissioningCompleteResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property error_code : CommissioningError

          @[TLV::Field(tag: 1)]
          property debug_text : String
        end
      end
    end
  end
end
