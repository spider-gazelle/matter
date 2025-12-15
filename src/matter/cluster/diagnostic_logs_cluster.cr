require "./cluster"

module Matter
  module Cluster
    # Diagnostic Logs Cluster (0x0032)
    #
    # Provides access to device logs for debugging and diagnostics.
    # Required by Apple Home for accessory compatibility.
    #
    # Matter Spec: Core 11.10
    class DiagnosticLogsCluster < Base
      CLUSTER_ID = 0x0032_u32

      # Intent enum - type of log being requested
      enum Intent : UInt8
        EndUserSupport = 0 # Logs for end-user support
        NetworkDiag    = 1 # Network diagnostic logs
        CrashLogs      = 2 # Crash/fault logs
      end

      # Status enum - response status
      enum LogsStatus : UInt8
        Success   = 0 # Logs retrieved successfully
        Exhausted = 1 # No more logs available
        NoLogs    = 2 # No logs of requested type
        Busy      = 3 # Device is busy
        Denied    = 4 # Access denied
      end

      # Transfer Protocol enum
      enum TransferProtocol : UInt8
        ResponsePayload = 0 # Return logs in response
        BDX             = 1 # Use BDX protocol
      end

      # Request struct for RetrieveLogsRequest command
      struct RetrieveLogsRequest
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property intent : UInt8 = 0_u8

        @[TLV::Field(tag: 1)]
        property requested_protocol : UInt8 = 0_u8

        @[TLV::Field(tag: 2)]
        property transfer_file_designator : String?
      end

      # Response struct for RetrieveLogsResponse
      struct RetrieveLogsResponse
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property status : UInt8

        @[TLV::Field(tag: 1)]
        property log_content : Bytes

        def initialize(@status : UInt8, @log_content : Bytes)
        end
      end

      # Command IDs
      CMD_RETRIEVE_LOGS_REQUEST = 0x00_u32

      # Response IDs
      CMD_RETRIEVE_LOGS_RESPONSE = 0x01_u32

      # Global attributes
      CLUSTER_REVISION       = 0xFFFD_u32
      FEATURE_MAP            = 0xFFFC_u32
      ATTRIBUTE_LIST         = 0xFFFB_u32
      ACCEPTED_COMMAND_LIST  = 0xFFF9_u32
      GENERATED_COMMAND_LIST = 0xFFF8_u32

      # Log buffer - stores recent log entries
      @log_buffer : Array(String)
      @max_log_entries : Int32

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @max_log_entries : Int32 = 100,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @log_buffer = [] of String
      end

      def self.cluster_id : UInt32
        CLUSTER_ID
      end

      def name : String
        "DiagnosticLogs"
      end

      def attributes : Array(AttributeMetadata)
        # No mandatory attributes - only global attributes
        [] of AttributeMetadata
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_RETRIEVE_LOGS_REQUEST),
            name: "RetrieveLogsRequest"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when CLUSTER_REVISION
          encode_uint16(1_u16) # DiagnosticLogs cluster revision 1
        when FEATURE_MAP
          encode_uint32(0_u32) # No features
        when ATTRIBUTE_LIST
          encode_attribute_list
        when ACCEPTED_COMMAND_LIST
          encode_command_list([CMD_RETRIEVE_LOGS_REQUEST])
        when GENERATED_COMMAND_LIST
          encode_command_list([CMD_RETRIEVE_LOGS_RESPONSE])
        else
          super
        end
      end

      private def encode_attribute_list : Bytes
        # Global attributes only
        attr_ids = [
          GENERATED_COMMAND_LIST,
          ACCEPTED_COMMAND_LIST,
          ATTRIBUTE_LIST,
          FEATURE_MAP,
          CLUSTER_REVISION,
        ]

        items = attr_ids.map { |id| TLV::Any.new(id, nil, fixed_size: true) }
        TLV::Any.new(items, nil, as_array: true).to_slice
      end

      private def encode_command_list(cmd_ids : Array(UInt32)) : Bytes
        items = cmd_ids.map { |id| TLV::Any.new(id, nil, fixed_size: true) }
        TLV::Any.new(items, nil, as_array: true).to_slice
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_RETRIEVE_LOGS_REQUEST
          handle_retrieve_logs_request(fields)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      private def handle_retrieve_logs_request(fields : Bytes) : Cluster::CommandResponse
        # Parse request using TLV::Serializable
        intent = Intent::EndUserSupport

        begin
          req = RetrieveLogsRequest.from_slice(fields)
          intent = Intent.from_value(req.intent)
        rescue
          # Use defaults
        end

        # Build response
        encode_retrieve_logs_response(intent)
      end

      private def encode_retrieve_logs_response(intent : Intent) : Cluster::CommandResponse
        # Build log content
        log_content = build_log_content(intent)

        status = log_content.empty? ? LogsStatus::NoLogs.value : LogsStatus::Success.value
        response = RetrieveLogsResponse.new(status, log_content.to_slice)

        Cluster::CommandResponse.new(CMD_RETRIEVE_LOGS_RESPONSE, response.to_slice)
      end

      private def build_log_content(intent : Intent) : String
        case intent
        when Intent::EndUserSupport
          # Return recent log entries
          @log_buffer.last(20).join("\n")
        when Intent::NetworkDiag
          # Return network-related info
          "Network diagnostics: Device operational"
        when Intent::CrashLogs
          # Return crash logs (none available)
          ""
        else
          ""
        end
      end

      # Public API: Add a log entry
      def log(message : String)
        timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%S")
        @log_buffer << "[#{timestamp}] #{message}"

        # Trim buffer if too large
        if @log_buffer.size > @max_log_entries
          @log_buffer.shift(@log_buffer.size - @max_log_entries)
        end
      end

      # Public API: Clear logs
      def clear_logs
        @log_buffer.clear
      end
    end
  end
end
