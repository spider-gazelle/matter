module Matter
  module Cluster
    module Definitions
      module Thermostat
        enum SetpointAdjustMode : UInt8
          Heat = 0
          Cool = 1
          Both = 2
        end

        # Input to the Thermostat setpointRaiseLower command
        struct SetpointRaiseLowerRequest
          include TLV::Serializable
          @[TLV::Field(tag: 0)]
          property mode : SetpointAdjustMode
          @[TLV::Field(tag: 1)]
          property amount : UInt8
        end

        # This represents a single transition in a Thermostat schedule
        struct ThermostatScheduleTransition
          include TLV::Serializable

          # This field represents the start time of the schedule transition during the associated day. The time will be
          # represented by a 16 bits unsigned integer to designate the minutes since midnight. For example, 6am will be
          # represented by 360 minutes since midnight and 11:30pm will be represented by 1410 minutes since midnight.
          @[TLV::Field(tag: 0)]
          property transition_time : UInt16

          @[TLV::Field(tag: 1)]
          property heat_setpoint : UInt16?

          @[TLV::Field(tag: 2)]
          property cool_setpoint : UInt16?
        end

        # Input to the Thermostat setWeeklySchedule command
        struct SetWeeklyScheduleRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property number_of_transitions_for_sequence : UInt8

          @[TLV::Field(tag: 1)]
          property day_of_week_for_sequence : UInt8

          @[TLV::Field(tag: 2)]
          property mode_for_sequence : UInt8

          @[TLV::Field(tag: 3)]
          property transitions : Array(ThermostatScheduleTransition)
        end

        # Input to the Thermostat getWeeklySchedule command
        struct GetWeeklyScheduleRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property days_to_return : UInt8

          @[TLV::Field(tag: 1)]
          property mode_to_return : UInt8
        end

        struct GetWeeklyScheduleResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property numberOfTransitionsForSequence : UInt8

          @[TLV::Field(tag: 1)]
          property dayOfWeekForSequence : UInt8

          @[TLV::Field(tag: 2)]
          property modeForSequence : UInt8

          @[TLV::Field(tag: 3)]
          property transitions : Array(ThermostatScheduleTransition)
        end
      end
    end
  end
end
