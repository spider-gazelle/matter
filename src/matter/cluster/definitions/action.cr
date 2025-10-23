module Matter
  module Cluster
    module Definitions
      module Action
        enum Type : UInt8
          # Use this only when none of the other values applies
          Other = 0

          # Bring the endpoints into a certain state
          #
          # Can be used to set a static state of the associated endpoints (typically using InstantAction or
          # InstantActionWithTransition), or to bring these endpoints into a more dynamic state (typically using
          # StartAction), where the endpoints would e.g. gradually cycle through certain colors for a pleasing effect. A
          # voice controller could use "set" (to map to InstantAction) or "play" (to map to StartAction) to trigger such actions.
          Scene = 1

          # A sequence of states with a certain time pattern
          #
          # Indicates an action which involves a sequence of events/states of the associated endpoints, such as a
          # wake-up experience.
          Sequence = 2

          # Control an automation (e.g. motion sensor controlling lights)
          #
          # Indications an automation (e.g. a motion sensor controlling lights, an alarm system) which can bee.g.
          # started, stopped, paused, resumed. Example: see example 3.
          Automation = 3

          # Sequence that will run when something doesn’t happen
          #
          # Indicates some action which the server will execute when a certain condition (which normally does not
          # happen) is not met.
          #
          # Example: lock the doors when the server’s system has detected no one is at home while the doors are in the
          # 'unlocked' state.
          Exception = 4

          # Use the endpoints to send a message to user
          #
          # Indicates an action that can be triggered (e.g. by InstantAction) to notify the user.
          Notification = 5

          # Higher priority notification
          #
          # Similar to Notification but with a higher priority (and might override other endpoint states which
          # Type=Notification would not override).
          Alarm = 6
        end

        # Note that some of these states are applicable only for certain actions, as determined by their SupportedCommands.
        enum State : UInt8
          # The action is not active
          Inactive = 0

          # The action is active
          Active = 1

          # The action has been paused
          Paused = 2

          # The action has been disabled
          Disabled = 3
        end

        # The Room and Zone values are provided for the cases where a user (or the system on behalf of the user) has
        # created logical grouping of the endpoints (e.g. bridged devices) based on location.
        enum EndpointListType : UInt8
          # Another group of endpoints
          #
          # This value is provided for the case of an endpoint list which is tied specifically to this action i.e. not
          # independently created by the user. For Type=Other the Name may be empty. A Matter controller would typically
          # not use this for anything else than just to know which endpoints would be affected by the action.
          Other = 0

          # User-configured group of endpoints where an endpoint can be in only one room
          #
          # Is used for the situation where an endpoint can only be part of one such rooms (e.g. physical mapping).
          # Using these exposed logical groups, a Matter controller who has a similar grouping concept can use it to
          # place each endpoint (bridged device) in the right room automatically, without user having to redo that setup
          # for each device in each system - both at first contact and upon later updates to the endpoints (e.g. user
          # adds a bridged device or creates a new room).
          Room = 1

          # User-configured group of endpoints where an endpoint can be in any number of zones
          #
          # Is a more general concept where an endpoint can be part of multiple zones, e.g. a light in the living
          #
          # room can be part of the "reading corner" zone (subset of the lights in the living room) but also part of the
          # "downstairs" zone which contains all the lights on a floor, e.g. combining living room, kitchen and hallway.
          # This indicates that a user has defined this list of endpoints as something they logically would like to
          # control as a group, so Matter controllers could provide the user with a way to do as such.
          Zone = 2
        end

        enum Error
          # Other reason not listed in the row(s) below
          Unknown = 0

          # The action was interrupted by another command or interaction
          Interrupted = 1
        end

        # This data type holds the details of a single action, and contains the data fields below.
        struct Base
          include TLV::Serializable

          # This field shall provide an unique identifier used to identify an action.
          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          # This field shall indicate the name (as assigned by the user or automatically by the server) associated with
          # this action. This can be used for identifying the action to the user by the client. Example: "my colorful
          # scene".
          @[TLV::Field(tag: 1)]
          property name : String

          # This field shall indicate the type of action. The value of Type of an action, along with its
          # SupportedCommands can be used by the client in its UX or logic to determine how to present or use such
          # action. See ActionTypeEnum for details and examples.
          @[TLV::Field(tag: 2)]
          property type : Type

          # This field shall provide a reference to the associated endpoint list, which specifies the endpoints on this
          # Node which will be impacted by this ActionID.
          @[TLV::Field(tag: 3)]
          property endpoint_list_id : UInt16

          # This field is a bitmap which shall be used to indicate which of the cluster’s commands are sup
          #
          # ported for this particular action, with a bit set to 1 for each supported command according to the table
          # below. Other bits shall be set to 0.
          @[TLV::Field(tag: 4)]
          property supported_commands : UInt16

          # This field shall indicate the current state of this action.
          @[TLV::Field(tag: 5)]
          property state : State
        end

        # This data type holds the details of a single endpoint list, which relates to a set of endpoints that have some
        # logical relation, and contains the data fields below.
        #
        # This field shall provide an unique identifier used to identify the endpoint list.
        #
        # This field shall indicate the name (as assigned by the user or automatically by the server) associated with the
        # set of endpoints in this list. This can be used for identifying the action to the user by the client. Example:
        # "living room".
        #
        # This field shall indicate the type of endpoint list, see EndpointListTypeEnum.
        struct EndpointList
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property endpoint_list_id : UInt16

          @[TLV::Field(tag: 1)]
          property name : String

          @[TLV::Field(tag: 2)]
          property type : EndpointListType

          # This field shall provide a list of endpoint numbers.
          @[TLV::Field(tag: 3)]
          property endpoints : Array(DataType::EndpointNumber)
        end

        # Input to the Actions instantAction command
        struct InstantRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32
        end

        # Input to the Actions instantActionWithTransition command
        struct InstantWithTransitionRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?

          # This field shall indicate the transition time in 1/10th of seconds.
          @[TLV::Field(tag: 2)]
          property transition_time : UInt16
        end

        # Input to the Actions startAction command
        struct StartRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?
        end

        # Input to the Actions startActionWithDuration command
        struct StartWithDurationRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?

          # This field shall indicate the requested duration in seconds.
          @[TLV::Field(tag: 2)]
          property duration : UInt32
        end

        # Input to the Actions stopAction command
        struct StopRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?
        end

        # Input to the Actions pauseAction command
        struct PauseRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?
        end

        # Input to the Actions pauseActionWithDuration command
        struct PauseWithDurationRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?

          @[TLV::Field(tag: 2)]
          property duration : UInt32
        end

        # Input to the Actions resumeAction command
        struct ResumeRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?
        end

        # Input to the Actions enableAction command
        struct EnableRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?
        end

        # Input to the Actions enableActionWithDuration command
        struct EnableWithDurationRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?

          @[TLV::Field(tag: 2)]
          property duration : UInt32
        end

        # Input to the Actions disableAction command
        struct DisableRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?
        end

        # Input to the Actions disableActionWithDuration command
        struct DisableWithDurationRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property action_id : UInt16

          @[TLV::Field(tag: 1)]
          property invoke_id : UInt32?

          @[TLV::Field(tag: 2)]
          property duration : UInt32
        end

        module Events
          # Body of the Actions stateChanged event
          struct StateChangedEvent
            include TLV::Serializable

            # This field shall be set to the InvokeID which was provided to the most recent command referencing this
            # ActionID.
            @[TLV::Field(tag: 0)]
            property invoke_id : UInt32

            # This field shall be set to state that the action has changed to.
            @[TLV::Field(tag: 1)]
            property state : State
          end

          # Body of the Actions actionFailed event
          struct FailedEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property action_id : UInt16

            @[TLV::Field(tag: 1)]
            property invoke_id : UInt32

            @[TLV::Field(tag: 2)]
            property state : State

            # This field shall be set to indicate the reason for non-successful progress of the action.
            @[TLV::Field(tag: 3)]
            property error : Error
          end
        end
      end
    end
  end
end
