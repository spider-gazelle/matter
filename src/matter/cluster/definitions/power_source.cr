module Matter
  module Cluster
    module Definitions
      module PowerSource
        enum WiredFault : UInt8
          # The Node detects an unspecified fault on this wired power source.
          Unspecified = 0

          # The Node detects the supplied voltage is above maximum supported value for this wired power source.
          OverVoltage = 1

          # The Node detects the supplied voltage is below maximum supported value for this wired power source.
          UnderVoltage = 2
        end

        enum BatteryChargeFault : UInt8
          # The Node detects an unspecified fault on this battery source.
          Unspecified = 0

          # The Node detects the ambient temperature is above the nominal range for this battery source.
          AmbientTooHot = 1

          # The Node detects the ambient temperature is below the nominal range for this battery source.
          AmbientTooCold = 2

          # The Node detects the temperature of this battery source is above the nominal range.
          BatteryTooHot = 3

          # The Node detects the temperature of this battery source is below the nominal range.
          BatteryTooCold = 4

          # The Node detects this battery source is not present.
          BatteryAbsent = 5

          # The Node detects this battery source is over voltage.
          BatteryOverVoltage = 6

          # The Node detects this battery source is under voltage.
          BatteryUnderVoltage = 7

          # The Node detects the charger for this battery source is over voltage.
          ChargerOverVoltage = 8

          # The Node detects the charger for this battery source is under voltage.
          ChargerUnderVoltage = 9

          # The Node detects a charging safety timeout for this battery source.
          SafetyTimeout = 10
        end

        enum Fault : UInt8
          # The Node detects an unspecified fault on this battery power source.
          Unspecified = 0

          # The Node detects the temperature of this battery power source is above ideal operating conditions.
          OverTemp = 1

          # The Node detects the temperature of this battery power source is below ideal operating conditions.
          UnderTemp = 2
        end

        module Events
          # Body of the PowerSource wiredFaultChange event
          struct TlvWiredFaultChangeEvent
            include TLV::Serializable

            # This field shall represent the set of faults currently detected, as per Section 11.7.6.11,
            # “ActiveWiredFaults Attribute”.
            @[TLV::Field(tag: 0)]
            property current : Array(WiredFault)

            # This field shall represent the set of faults detected prior to this change event, as per Section 11.7.6.11,
            # “ActiveWiredFaults Attribute”.
            @[TLV::Field(tag: 1)]
            property previous : Array(WiredFault)
          end

          # Body of the PowerSource batFaultChange event
          struct BatteryFaultChangeEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property current : Array(Fault)

            @[TLV::Field(tag: 1)]
            property previous : Array(Fault)
          end

          # Body of the PowerSource batChargeFaultChange event
          struct BatteryChargeFaultChangeEvent
            include TLV::Serializable
            @[TLV::Field(tag: 0)]
            property current : Array(BatteryChargeFault)

            @[TLV::Field(tag: 1)]
            property previous : Array(BatteryChargeFault)
          end
        end
      end
    end
  end
end
