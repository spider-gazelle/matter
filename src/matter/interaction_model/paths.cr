module Matter
  module InteractionModel
    # Attribute path identifying a specific attribute
    # Encoded as a TLV list per Matter spec (and matter.js/CHIP encodings),
    # and TLV::Serializable decoding is tolerant of list/structure variations.
    # Note: fixed_size: true ensures proper type widths for iOS compatibility.
    #
    # Matter spec allows Boolean `true` as a wildcard indicator for path fields.
    # iOS/Apple controllers send `true` instead of omitting fields for wildcards.
    # We handle this by accepting Bool in the union type and converting to nil.
    @[TLV::ListFormat]
    struct AttributePath
      include TLV::Serializable

      @[TLV::Field(tag: 0, optional: true)]
      property enable_tag_compression : Bool?

      @[TLV::Field(tag: 1, optional: true, fixed_size: true)]
      property node_raw : UInt64 | Nil

      # Internal storage accepts Bool for wildcard indicator from iOS
      @[TLV::Field(tag: 2, fixed_size: true)]
      property endpoint_raw : UInt16 | Bool | Nil

      @[TLV::Field(tag: 3, fixed_size: true)]
      property cluster_raw : UInt32 | Bool | Nil

      @[TLV::Field(tag: 4, fixed_size: true)]
      property attribute_raw : UInt32 | Bool | Nil

      @[TLV::Field(tag: 5, fixed_size: true)]
      property list_index_raw : UInt16 | Bool | Nil

      @[TLV::Field(tag: 6, optional: true, fixed_size: true)]
      property wildcard_path_flags_raw : UInt32 | Nil

      def initialize(
        endpoint : UInt16? = nil,
        cluster : UInt32? = nil,
        attribute : UInt32? = nil,
        list_index : UInt16? = nil,
        *,
        enable_tag_compression : Bool? = nil,
        node : UInt64? = nil,
        wildcard_path_flags : UInt32? = nil,
      )
        @enable_tag_compression = enable_tag_compression
        @node_raw = node
        @endpoint_raw = endpoint
        @cluster_raw = cluster
        @attribute_raw = attribute
        @list_index_raw = list_index
        @wildcard_path_flags_raw = wildcard_path_flags
      end

      def node : UInt64?
        @node_raw
      end

      def wildcard_path_flags : UInt32?
        @wildcard_path_flags_raw
      end

      # Getters that convert Bool (wildcard) to nil
      def endpoint : UInt16?
        value = @endpoint_raw
        value.is_a?(UInt16) ? value : nil
      end

      def cluster : UInt32?
        value = @cluster_raw
        value.is_a?(UInt32) ? value : nil
      end

      def attribute : UInt32?
        value = @attribute_raw
        value.is_a?(UInt32) ? value : nil
      end

      def list_index : UInt16?
        value = @list_index_raw
        value.is_a?(UInt16) ? value : nil
      end

      # Setters for API compatibility
      def endpoint=(value : UInt16?)
        @endpoint_raw = value
      end

      def node=(value : UInt64?)
        @node_raw = value
      end

      def cluster=(value : UInt32?)
        @cluster_raw = value
      end

      def attribute=(value : UInt32?)
        @attribute_raw = value
      end

      def list_index=(value : UInt16?)
        @list_index_raw = value
      end

      def wildcard_path_flags=(value : UInt32?)
        @wildcard_path_flags_raw = value
      end

      # Wildcard path matches all endpoints/clusters/attributes
      def wildcard?
        endpoint.nil? || cluster.nil? || attribute.nil?
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
        endpoint == other.endpoint &&
          cluster == other.cluster &&
          attribute == other.attribute &&
          list_index == other.list_index
      end
    end

    # Command path identifying a specific command
    # Supports both list-form [endpoint, cluster, command] and structure-form {0=>endpoint, 1=>cluster, 2=>command}
    # Note: fixed_size: true ensures proper type widths for iOS compatibility
    @[TLV::ListFormat]
    struct CommandPath
      include TLV::Serializable

      @[TLV::Field(tag: 0, fixed_size: true)]
      property endpoint : UInt16

      @[TLV::Field(tag: 1, fixed_size: true)]
      property cluster : UInt32

      @[TLV::Field(tag: 2, fixed_size: true)]
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
    # Supports both list-form and structure-form
    # Note: fixed_size: true ensures proper type widths for iOS compatibility
    #
    # Matter spec allows Boolean `true` as a wildcard indicator for path fields.
    # Some controllers may send `true` instead of omitting fields for wildcards.
    @[TLV::ListFormat]
    struct EventPath
      include TLV::Serializable

      @[TLV::Field(tag: 0, fixed_size: true)]
      property node_raw : UInt64 | Bool | Nil

      # Internal storage accepts Bool for wildcard indicator from iOS
      @[TLV::Field(tag: 1, fixed_size: true)]
      property endpoint_raw : UInt16 | Bool | Nil

      @[TLV::Field(tag: 2, fixed_size: true)]
      property cluster_raw : UInt32 | Bool | Nil

      @[TLV::Field(tag: 3, fixed_size: true)]
      property event_raw : UInt32 | Bool | Nil

      @[TLV::Field(tag: 4)]
      property? is_urgent : Bool = false

      def initialize(
        node : UInt64? = nil,
        endpoint : UInt16? = nil,
        cluster : UInt32? = nil,
        event : UInt32? = nil,
        @is_urgent : Bool = false,
      )
        @node_raw = node
        @endpoint_raw = endpoint
        @cluster_raw = cluster
        @event_raw = event
      end

      # Getters that convert Bool (wildcard) to nil
      def node : UInt64?
        value = @node_raw
        value.is_a?(UInt64) ? value : nil
      end

      def endpoint : UInt16?
        value = @endpoint_raw
        value.is_a?(UInt16) ? value : nil
      end

      def cluster : UInt32?
        value = @cluster_raw
        value.is_a?(UInt32) ? value : nil
      end

      def event : UInt32?
        value = @event_raw
        value.is_a?(UInt32) ? value : nil
      end

      # Setters for API compatibility
      def node=(value : UInt64?)
        @node_raw = value
      end

      def endpoint=(value : UInt16?)
        @endpoint_raw = value
      end

      def cluster=(value : UInt32?)
        @cluster_raw = value
      end

      def event=(value : UInt32?)
        @event_raw = value
      end

      # Wildcard path matches all endpoints/clusters/events
      def wildcard?
        endpoint.nil? || cluster.nil? || event.nil?
      end

      def to_s : String
        parts = [] of String
        parts << "N:#{node || "*"}"
        parts << "E:#{endpoint || "*"}"
        parts << "C:0x#{(cluster || 0).to_s(16)}" if cluster
        parts << "Evt:0x#{(event || 0).to_s(16)}" if event
        parts << "(urgent)" if is_urgent?
        parts.join("/")
      end

      def ==(other : EventPath) : Bool
        node == other.node &&
          endpoint == other.endpoint &&
          cluster == other.cluster &&
          event == other.event &&
          is_urgent? == other.is_urgent?
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
