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
      cluster 0x0032, revision: 1

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
        property intent : Intent

        @[TLV::Field(tag: 1)]
        property requested_protocol : TransferProtocol

        @[TLV::Field(tag: 2)]
        property transfer_file_designator : String?

        def initialize(@intent : Intent, @requested_protocol : TransferProtocol = TransferProtocol::ResponsePayload, @transfer_file_designator : String? = nil)
        end
      end

      # Response struct for RetrieveLogsResponse
      struct RetrieveLogsResponse
        include TLV::Serializable

        @[TLV::Field(tag: 0)]
        property status : LogsStatus

        @[TLV::Field(tag: 1)]
        property log_content : Bytes

        def initialize(@status : LogsStatus, @log_content : Bytes)
        end
      end

      CMD_RETRIEVE_LOGS_RESPONSE = 0x01_u32

      command 0x00, :retrieve_logs_request, request: RetrieveLogsRequest, response: RetrieveLogsResponse, response_id: CMD_RETRIEVE_LOGS_RESPONSE

      # Number of recent entries returned for end-user support.
      END_USER_SUPPORT_ENTRIES = 20

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

      # Logs are always returned in the response payload; BDX is not offered.
      def retrieve_logs_request(request : RetrieveLogsRequest) : RetrieveLogsResponse
        log_content = build_log_content(request.intent)
        status = log_content.empty? ? LogsStatus::NoLogs : LogsStatus::Success
        RetrieveLogsResponse.new(status, log_content.to_slice)
      end

      private def build_log_content(intent : Intent) : String
        case intent
        in Intent::EndUserSupport
          # Return recent log entries
          @log_buffer.last(END_USER_SUPPORT_ENTRIES).join("\n")
        in Intent::NetworkDiag
          # Return network-related info
          "Network diagnostics: Device operational"
        in Intent::CrashLogs
          # Return crash logs (none available)
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
