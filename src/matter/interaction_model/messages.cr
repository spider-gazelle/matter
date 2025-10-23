require "./status_code"
require "./paths"

module Matter
  module InteractionModel
    # Read request for attributes
    struct ReadRequest
      property attribute_requests : Array(AttributePath)
      property event_requests : Array(EventPath)
      property event_filters : Array(EventFilter)?
      property fabric_filtered : Bool
      property data_version_filters : Hash(ConcreteAttributePath, DataVersion)?

      def initialize(
        @attribute_requests : Array(AttributePath) = [] of AttributePath,
        @event_requests : Array(EventPath) = [] of EventPath,
        @event_filters : Array(EventFilter)? = nil,
        @fabric_filtered : Bool = true,
        @data_version_filters : Hash(ConcreteAttributePath, DataVersion)? = nil
      )
      end
    end

    # Event filter for read requests
    struct EventFilter
      property node_id : UInt64?
      property event_min : UInt64?

      def initialize(@node_id : UInt64? = nil, @event_min : UInt64? = nil)
      end
    end

    # Attribute data in a read/subscribe/report response
    struct AttributeData
      property path : AttributePath
      property data_version : DataVersion
      property value : Bytes # TLV-encoded value

      def initialize(@path : AttributePath, @data_version : DataVersion, @value : Bytes)
      end
    end

    # Attribute status in a read/write response
    struct AttributeStatus
      property path : AttributePath
      property status : Status

      def initialize(@path : AttributePath, @status : Status)
      end
    end

    # Read response with attribute data
    struct ReadResponse
      property attribute_reports : Array(AttributeData)
      property attribute_status : Array(AttributeStatus)
      property more_chunks : Bool
      property suppress_response : Bool

      def initialize(
        @attribute_reports : Array(AttributeData) = [] of AttributeData,
        @attribute_status : Array(AttributeStatus) = [] of AttributeStatus,
        @more_chunks : Bool = false,
        @suppress_response : Bool = false
      )
      end
    end

    # Write request for attributes
    struct WriteRequest
      property write_requests : Array(AttributeWriteRequest)
      property timed_request : Bool
      property suppress_response : Bool
      property more_chunked_messages : Bool

      def initialize(
        @write_requests : Array(AttributeWriteRequest) = [] of AttributeWriteRequest,
        @timed_request : Bool = false,
        @suppress_response : Bool = false,
        @more_chunked_messages : Bool = false
      )
      end
    end

    # Single attribute write in a write request
    struct AttributeWriteRequest
      property path : AttributePath
      property data_version : DataVersion?
      property value : Bytes # TLV-encoded value

      def initialize(
        @path : AttributePath,
        @value : Bytes,
        @data_version : DataVersion? = nil
      )
      end
    end

    # Write response with status for each write
    struct WriteResponse
      property write_responses : Array(AttributeStatus)

      def initialize(@write_responses : Array(AttributeStatus) = [] of AttributeStatus)
      end
    end

    # Command invocation request
    struct InvokeRequest
      property invoke_requests : Array(CommandDataIB)
      property timed_request : Bool
      property suppress_response : Bool

      def initialize(
        @invoke_requests : Array(CommandDataIB) = [] of CommandDataIB,
        @timed_request : Bool = false,
        @suppress_response : Bool = false
      )
      end
    end

    # Command data in an invoke request
    struct CommandDataIB
      property path : CommandPath
      property fields : Bytes # TLV-encoded command fields

      def initialize(@path : CommandPath, @fields : Bytes)
      end
    end

    # Command response data
    struct CommandResponse
      property path : CommandPath
      property fields : Bytes # TLV-encoded response fields

      def initialize(@path : CommandPath, @fields : Bytes)
      end
    end

    # Command status in a response
    struct CommandStatus
      property path : CommandPath
      property status : Status

      def initialize(@path : CommandPath, @status : Status)
      end
    end

    # Invoke response with command results
    struct InvokeResponse
      property invoke_responses : Array(CommandResponse)
      property invoke_status : Array(CommandStatus)
      property suppress_response : Bool
      property more_chunked_messages : Bool

      def initialize(
        @invoke_responses : Array(CommandResponse) = [] of CommandResponse,
        @invoke_status : Array(CommandStatus) = [] of CommandStatus,
        @suppress_response : Bool = false,
        @more_chunked_messages : Bool = false
      )
      end
    end

    # Subscribe request for attributes and events
    struct SubscribeRequest
      property attribute_requests : Array(AttributePath)
      property event_requests : Array(EventPath)
      property event_filters : Array(EventFilter)?
      property fabric_filtered : Bool
      property min_interval_floor : UInt16
      property max_interval_ceiling : UInt16
      property keep_subscriptions : Bool
      property data_version_filters : Hash(ConcreteAttributePath, DataVersion)?

      def initialize(
        @attribute_requests : Array(AttributePath) = [] of AttributePath,
        @event_requests : Array(EventPath) = [] of EventPath,
        @event_filters : Array(EventFilter)? = nil,
        @fabric_filtered : Bool = true,
        @min_interval_floor : UInt16 = 0_u16,
        @max_interval_ceiling : UInt16 = 3600_u16,
        @keep_subscriptions : Bool = false,
        @data_version_filters : Hash(ConcreteAttributePath, DataVersion)? = nil
      )
      end
    end

    # Subscribe response confirming subscription
    struct SubscribeResponse
      property subscription_id : UInt32
      property min_interval : UInt16
      property max_interval : UInt16

      def initialize(
        @subscription_id : UInt32,
        @min_interval : UInt16,
        @max_interval : UInt16
      )
      end
    end

    # Report data for subscriptions (attribute changes, events)
    struct ReportData
      property subscription_id : UInt32?
      property attribute_reports : Array(AttributeData)
      property event_reports : Array(EventData)
      property more_chunks : Bool
      property suppress_response : Bool

      def initialize(
        @subscription_id : UInt32? = nil,
        @attribute_reports : Array(AttributeData) = [] of AttributeData,
        @event_reports : Array(EventData) = [] of EventData,
        @more_chunks : Bool = false,
        @suppress_response : Bool = false
      )
      end
    end

    # Event data in a report
    struct EventData
      property path : EventPath
      property event_number : UInt64
      property priority : EventPriority
      property timestamp : UInt64
      property data : Bytes # TLV-encoded event data

      def initialize(
        @path : EventPath,
        @event_number : UInt64,
        @priority : EventPriority,
        @timestamp : UInt64,
        @data : Bytes
      )
      end
    end

    # Event priority levels
    enum EventPriority : UInt8
      Debug    = 0
      Info     = 1
      Critical = 2
    end
  end
end
