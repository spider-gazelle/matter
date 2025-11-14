require "tlv"
require "./paths"
require "./status_code"

module Matter
  module InteractionModel
    # TLV-serializable IM message structures matching matter.js schemas

    # AttributeDataIB - per matter.js TlvAttributeReportData
    struct AttributeDataIB
      include TLV::Serializable

      # Tag 0: DataVersion (optional)
      @[TLV::Field(tag: 0, optional: true)]
      property data_version : UInt32?

      # Tag 1: Path
      @[TLV::Field(tag: 1)]
      property path : AttributePath

      # Tag 2: Data (TLV::Value - the actual attribute value)
      @[TLV::Field(tag: 2)]
      property data : TLV::Value

      def initialize(@path : AttributePath, @data : TLV::Value, @data_version : UInt32? = nil)
      end
    end

    # StatusIB - status code structure
    struct StatusIB
      include TLV::Serializable

      # Tag 0: Status code
      @[TLV::Field(tag: 0)]
      property status : UInt8

      # Tag 1: Cluster-specific status (optional)
      @[TLV::Field(tag: 1, optional: true)]
      property cluster_status : UInt8?

      def initialize(@status : UInt8, @cluster_status : UInt8? = nil)
      end
    end

    # AttributeStatusIB - attribute with status (on error)
    struct AttributeStatusIB
      include TLV::Serializable

      # Tag 0: Path
      @[TLV::Field(tag: 0)]
      property path : AttributePath

      # Tag 1: Status
      @[TLV::Field(tag: 1)]
      property status : StatusIB

      def initialize(@path : AttributePath, @status : StatusIB)
      end
    end

    # AttributeReportIB - wrapper for either data or status
    struct AttributeReportIB
      include TLV::Serializable

      # Tag 0: AttributeDataIB (optional - present on success)
      @[TLV::Field(tag: 0, optional: true)]
      property attribute_data : AttributeDataIB?

      # Tag 1: AttributeStatusIB (optional - present on error)
      @[TLV::Field(tag: 1, optional: true)]
      property attribute_status : AttributeStatusIB?

      def initialize(@attribute_data : AttributeDataIB? = nil, @attribute_status : AttributeStatusIB? = nil)
      end
    end

    # ReportDataMessage - the actual ReadResponse/ReportData message
    # Per matter.js TlvDataReportForSend
    struct ReportDataMessage
      include TLV::Serializable

      # Tag 0: SubscriptionId (optional, only for subscriptions)
      @[TLV::Field(tag: 0, optional: true)]
      property subscription_id : UInt32?

      # Tag 1: AttributeReports (array of AttributeReportIB)
      @[TLV::Field(tag: 1, optional: true)]
      property attribute_reports : Array(TLV::Value)?

      # Tag 2: EventReports (optional, array)
      @[TLV::Field(tag: 2, optional: true)]
      property event_reports : Array(TLV::Value)?

      # Tag 3: MoreChunkedMessages (optional)
      @[TLV::Field(tag: 3, optional: true)]
      property more_chunked_messages : Bool?

      # Tag 4: SuppressResponse (optional)
      @[TLV::Field(tag: 4, optional: true)]
      property suppress_response : Bool?

      # Tag 0xFF: InteractionModelRevision (REQUIRED!)
      @[TLV::Field(tag: 0xFF)]
      property interaction_model_revision : UInt8

      def initialize(
        @subscription_id = nil,
        @attribute_reports = nil,
        @event_reports = nil,
        @more_chunked_messages = nil,
        @suppress_response = nil,
        @interaction_model_revision = 12_u8
      )
      end
    end
  end
end
