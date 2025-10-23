module Matter
  module Cluster
    module Definitions
      module DiagnosticLogs
        enum Intent : UInt8
          # Logs to be used for end- user support
          #
          # shall indicate that the purpose of the log request is to retrieve logs for the intention of providing
          # support to an end-user.
          EndUserSupport = 0

          # Logs to be used for network diagnostics
          #
          # shall indicate that the purpose of the log request is to diagnose the network(s) for which the Node is
          # currently commissioned (and/or connected) or has previously been commissioned (and/or connected).
          NetworkDiag = 1

          # Obtain crash logs from the Node
          #
          # shall indicate that the purpose of the log request is to retrieve any crash logs that may be present on a
          # Node.
          CrashLogs = 2
        end

        enum TransferProtocol : UInt8
          # Logs to be returned as a response
          #
          # shall be used by a Client to request that logs are transferred using the LogContent attribute of the response
          #
          ResponsePayload = 0

          # Logs to be returned using BDX
          #
          # shall be used by a Client to request that logs are transferred using BDX as defined in BDX Protocol
          Bdx = 1
        end

        enum Status : UInt8
          # Successful transfer of logs
          #
          # shall be used if diagnostic logs will be or are being transferred.
          Success = 0

          # All logs has been transferred
          #
          # shall be used when a BDX session is requested, however, all available logs were provided in a
          #
          # LogContent field.
          Exhausted = 1

          # No logs of the requested type available
          #
          # shall be used if the Node does not currently have any diagnostic logs of the requested type (Intent) to
          # transfer.
          NoLogs = 2

          # Unable to handle request, retry later
          #
          # shall be used if the Node is unable to handle the request (e.g. in the process of another transfer) and the
          # Client SHOULD re-attempt the request later.
          Busy = 3

          # The request is denied, no logs being transferred
          #
          # shall be used if the Node is denying the current transfer of diagnostic logs for any reason.
          Denied = 4
        end

        # Input to the DiagnosticLogs retrieveLogsRequest command
        struct RetrieveLogsRequest
          include TLV::Serializable

          # This field shall indicate why the diagnostic logs are being retrieved from the Node. A Node may utilize this
          # field to selectively determine the logs to transfer.
          @[TLV::Field(tag: 0)]
          property intent : Intent

          # This field shall be used to indicate how the log transfer is to be realized. If the field is set to BDX,
          # then if the receiving Node supports BDX it shall attempt to use BDX to transfer any potential diagnostic
          # logs; if the receiving Node does not support BDX then the Node shall follow the requirements defined for a
          # TransferProtocolEnum of ResponsePayload. If this field is set to ResponsePayload the receiving Node shall
          # only utilize the LogContent field of the RetreiveLogsResponse command to transfer diagnostic log information.
          @[TLV::Field(tag: 1)]
          property requested_protocol : TransferProtocol

          # This field shall be present if the RequestedProtocol is BDX. The TransferFileDesignator shall be set as the
          # File Designator of the BDX transfer if initiated.
          #
          # Effect on Receipt
          #
          # On receipt of this command, the Node shall respond with a RetrieveLogsResponse command.
          #
          # If the RequestedProtocol is set to BDX the Node SHOULD immediately realize the RetrieveLogsResponse command
          # by initiating a BDX Transfer, sending a BDX SendInit message with the File Designator field of the message
          # set to the value of the TransferFileDesignator field of the RetrieveLogsRequest. On reception of a BDX
          # SendAccept message the Node shall send a RetrieveLogsResponse command with a Status field set to Success and
          # proceed with the log transfer over BDX. If a failure StatusReport is received in response to the SendInit
          # message, the Node shall send a RetrieveLogsResponse command with a Status of Denied. In the case where the
          # Node is able to fit the entirety of the requested logs within the LogContent field, the Status field of the
          # RetrieveLogsResponse shall be set to Exhausted and a BDX session shall NOT be initiated.
          #
          # If the RequestedProtocol is set to BDX and either the Node does not support BDX or it is not possible for
          # the Node to establish a BDX session, then the Node shall utilize the LogContent field of the
          # RetrieveLogsResponse command to transfer as much of the current logs as it can fit within the response, and
          # the Status field of the RetrieveLogsResponse shall be set to Exhausted.
          #
          # If the RequestedProtocol is set to ResponsePayload the Node shall utilize the LogContent field of the
          # RetrieveLogsResponse command to transfer as much of the current logs as it can fit within the
          #
          # response, and a BDX session shall NOT be initiated.
          #
          # If the RequestedProtocol is set to BDX and there is no TransferFileDesignator the command shall fail with a
          # Status Code of INVALID_COMMAND.
          #
          # If the Intent and/or the RequestedProtocol arguments contain invalid (out of range) values the command shall
          # fail with a Status Code of INVALID_COMMAND.
          @[TLV::Field(tag: 2)]
          property transfer_file_designator : String?
        end

        # This shall be generated as a response to the RetrieveLogsRequest. The data for this command is shown in the
        # following.
        struct RetrieveLogsResponse
          include TLV::Serializable

          # This field shall indicate the result of an attempt to retrieve diagnostic logs.
          @[TLV::Field(tag: 0)]
          property status : Status

          # This field shall be included in the command if the Status field has a value of Success or Exhausted. A Node
          # SHOULD utilize this field to transfer the newest diagnostic log entries. This field shall be empty if BDX is
          # requested and the Status field has a value of Success.
          @[TLV::Field(tag: 1)]
          property log_content : Slice(UInt8)

          # This field SHOULD be included in the command if the Status field has a value of Success and the Node
          # maintains a wall clock. When included, the UTCTimeStamp field shall contain the value of the oldest log
          # entry in the diagnostic logs that are being transferred.
          @[TLV::Field(tag: 2)]
          property utc_time_stamp : UInt64?

          # This field SHOULD be included in the command if the Status field has a value of Success. When included, the
          # TimeSinceBoot field shall contain the time of the oldest log entry in the diagnostic logs that are being
          # transferred represented by the number of microseconds since the last time the Node went through a reboot.
          @[TLV::Field(tag: 3)]
          property time_since_boot : UInt64?
        end
      end
    end
  end
end
