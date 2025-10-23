module Matter
  module InteractionModel
    # Attribute path identifying a specific attribute
    struct AttributePath
      property endpoint : UInt16?
      property cluster : UInt32?
      property attribute : UInt32?
      property list_index : UInt16?

      def initialize(
        @endpoint : UInt16? = nil,
        @cluster : UInt32? = nil,
        @attribute : UInt32? = nil,
        @list_index : UInt16? = nil,
      )
      end

      # Wildcard path matches all endpoints/clusters/attributes
      def wildcard?
        @endpoint.nil? || @cluster.nil? || @attribute.nil?
      end

      # Concrete path specifies a single attribute
      def concrete?
        !wildcard?
      end

      def to_s : String
        parts = [] of String
        parts << "E:#{endpoint || "*"}"
        parts << "C:0x#{(cluster || 0).to_s(16)}" if cluster
        parts << "A:0x#{(attribute || 0).to_s(16)}" if attribute
        parts << "[#{list_index}]" if list_index
        parts.join("/")
      end

      def ==(other : AttributePath) : Bool
        @endpoint == other.endpoint &&
          @cluster == other.cluster &&
          @attribute == other.attribute &&
          @list_index == other.list_index
      end
    end

    # Command path identifying a specific command
    struct CommandPath
      property endpoint : UInt16
      property cluster : UInt32
      property command : UInt32

      def initialize(@endpoint : UInt16, @cluster : UInt32, @command : UInt32)
      end

      def to_s : String
        "E:#{endpoint}/C:0x#{cluster.to_s(16)}/Cmd:0x#{command.to_s(16)}"
      end

      def ==(other : CommandPath) : Bool
        @endpoint == other.endpoint &&
          @cluster == other.cluster &&
          @command == other.command
      end
    end

    # Event path identifying a specific event
    struct EventPath
      property endpoint : UInt16?
      property cluster : UInt32?
      property event : UInt32?
      property is_urgent : Bool

      def initialize(
        @endpoint : UInt16? = nil,
        @cluster : UInt32? = nil,
        @event : UInt32? = nil,
        @is_urgent : Bool = false,
      )
      end

      # Wildcard path matches all endpoints/clusters/events
      def wildcard?
        @endpoint.nil? || @cluster.nil? || @event.nil?
      end

      def to_s : String
        parts = [] of String
        parts << "E:#{endpoint || "*"}"
        parts << "C:0x#{(cluster || 0).to_s(16)}" if cluster
        parts << "Evt:0x#{(event || 0).to_s(16)}" if event
        parts << "(urgent)" if is_urgent
        parts.join("/")
      end

      def ==(other : EventPath) : Bool
        @endpoint == other.endpoint &&
          @cluster == other.cluster &&
          @event == other.event &&
          @is_urgent == other.is_urgent
      end
    end

    # Data version for optimistic concurrency control
    alias DataVersion = UInt32

    # Concrete attribute path with data version
    struct ConcreteAttributePath
      property endpoint : UInt16
      property cluster : UInt32
      property attribute : UInt32
      property list_index : UInt16?

      def initialize(
        @endpoint : UInt16,
        @cluster : UInt32,
        @attribute : UInt32,
        @list_index : UInt16? = nil,
      )
      end

      def to_path : AttributePath
        AttributePath.new(@endpoint, @cluster, @attribute, @list_index)
      end

      def to_s : String
        to_path.to_s
      end

      def ==(other : ConcreteAttributePath) : Bool
        @endpoint == other.endpoint &&
          @cluster == other.cluster &&
          @attribute == other.attribute &&
          @list_index == other.list_index
      end
    end
  end
end
