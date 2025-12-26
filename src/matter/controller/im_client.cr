require "log"

require "../interaction_model/paths"
require "../interaction_model/tlv_messages"
require "./client"

module Matter
  module Controller
    class ImClient
      Log = ::Log.for("matter.controller.im")

      MSG_READ_REQUEST    = 0x02_u8
      MSG_REPORT_DATA     = 0x05_u8
      MSG_INVOKE_REQUEST  = 0x08_u8
      MSG_INVOKE_RESPONSE = 0x09_u8

      def initialize(@client : Client, @timeout : Time::Span = 10.seconds)
      end

      def read_attribute(
        session : Session::SecureContext,
        peer : Socket::IPAddress,
        endpoint_id : UInt16,
        cluster_id : UInt32,
        attribute_id : UInt32,
      ) : InteractionModel::ReportDataMessage
        path = InteractionModel::AttributePath.new(
          endpoint: endpoint_id,
          cluster: cluster_id,
          attribute: attribute_id
        )

        request = InteractionModel::ReadRequestMessage.new(
          attribute_requests: [path],
          fabric_filtered: true,
          interaction_model_revision: 12_u8
        )

        payload = request.to_slice
        exchange_id = @client.send_encrypted_request(
          session: session,
          peer: peer,
          protocol_id: Client::PROTOCOL_INTERACTION_MODEL,
          message_type: MSG_READ_REQUEST,
          payload: payload,
          requires_ack: true
        )

        response = @client.wait_for(exchange_id, Client::PROTOCOL_INTERACTION_MODEL, MSG_REPORT_DATA, @timeout)
        raise "IM: timeout waiting for ReportData (exchange=#{exchange_id})" unless response

        InteractionModel::ReportDataMessage.from_slice(response.message.payload.to_slice)
      end

      def invoke(
        session : Session::SecureContext,
        peer : Socket::IPAddress,
        endpoint_id : UInt16,
        cluster_id : UInt32,
        command_id : UInt32,
        fields : Bytes = Bytes.empty,
      ) : InteractionModel::InvokeResponseMessage
        path = InteractionModel::CommandPath.new(
          endpoint: endpoint_id,
          cluster: cluster_id,
          command: command_id
        )

        command_fields = fields.empty? ? nil : TLV::Any.from_slice(fields)
        command = InteractionModel::CommandDataIBTlv.new(command_path: path, command_fields: command_fields)

        request = InteractionModel::InvokeRequestMessage.new(
          invoke_requests: [command],
          suppress_response: false,
          timed_request: false,
          interaction_model_revision: 12_u8
        )

        exchange_id = @client.send_encrypted_request(
          session: session,
          peer: peer,
          protocol_id: Client::PROTOCOL_INTERACTION_MODEL,
          message_type: MSG_INVOKE_REQUEST,
          payload: request.to_slice,
          requires_ack: true
        )

        response = @client.wait_for(exchange_id, Client::PROTOCOL_INTERACTION_MODEL, MSG_INVOKE_RESPONSE, @timeout)
        raise "IM: timeout waiting for InvokeResponse (exchange=#{exchange_id})" unless response

        InteractionModel::InvokeResponseMessage.from_slice(response.message.payload.to_slice)
      end
    end
  end
end
