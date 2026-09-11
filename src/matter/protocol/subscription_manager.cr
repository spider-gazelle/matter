require "log"
require "socket"

require "../codec/message_codec"
require "../interaction_model/paths"
require "../interaction_model/tlv_messages"
require "../node"
require "../session/context"
require "./im_handler"
require "./response_sender"
require "./session_registry"
require "./subscription"

module Matter
  module Protocol
    # Drives subscriptions: the chunked priming report, the SubscribeResponse
    # that completes the handshake, and every report a cluster change raises
    # afterwards.
    #
    # Reports originate on arbitrary fibers - a cluster callback, a device
    # timer, an endpoint added at runtime - so every method here runs inside
    # `SessionRegistry#synchronize`, the same lock inbound message handling
    # takes.
    class SubscriptionManager
      Log = ::Log.for("matter.protocol.subscription_manager")

      # An exchange with chunks still to send, waiting for the controller to
      # acknowledge the chunk in flight.
      abstract class PendingChunks
        getter peer : Socket::IPAddress
        getter session : Session::SecureContext
        getter remaining_chunks : Array(Bytes)

        def initialize(@peer, @session, @remaining_chunks)
        end

        # Takes the next chunk off the queue, or `nil` when none are left.
        def next_chunk : Bytes?
          @remaining_chunks.shift?
        end

        def more_chunks? : Bool
          !@remaining_chunks.empty?
        end
      end

      # A ReadRequest whose response did not fit in one message.
      class PendingRead < PendingChunks
      end

      # A SubscribeRequest whose priming report is still being delivered. The
      # subscription becomes active once the last chunk is acknowledged.
      class PendingSubscription < PendingChunks
        getter subscription_id : UInt32
        getter min_interval : UInt16
        getter max_interval : UInt16
        getter attribute_paths : Array(InteractionModel::AttributePath)

        def initialize(
          @subscription_id,
          @min_interval,
          @max_interval,
          @attribute_paths,
          peer : Socket::IPAddress,
          session : Session::SecureContext,
          remaining_chunks : Array(Bytes),
        )
          super(peer, session, remaining_chunks)
        end
      end

      # Keyed by exchange id: one controller exchange carries one ladder.
      @pending_subscriptions : Hash(UInt16, PendingSubscription) = {} of UInt16 => PendingSubscription
      @pending_reads : Hash(UInt16, PendingRead) = {} of UInt16 => PendingRead

      def initialize(
        @registry : SessionRegistry,
        @node : Node,
        @sender : ResponseSender,
      )
      end

      # Tracks a subscription whose priming report has begun, so the
      # controller's acknowledgement can carry it to completion.
      def await_subscription(exchange_id : UInt16, pending : PendingSubscription) : Nil
        @registry.synchronize { @pending_subscriptions[exchange_id] = pending }
      end

      # Tracks a read response with chunks still to send.
      def await_read(exchange_id : UInt16, pending : PendingRead) : Nil
        @registry.synchronize { @pending_reads[exchange_id] = pending }
      end

      # Advances the chunked exchange *exchange_id*, returning whether it was
      # one of ours.
      #
      # A controller acknowledges each ReportData chunk with either a
      # StatusResponse or - as iOS does - a bare MRP StandaloneAck. Both mean
      # the same thing here: send the next chunk, or finish. *trigger* is the
      # message that acknowledged, and is what the next message answers.
      def advance(exchange_id : UInt16, trigger : Codec::MessageCodec::Message, success : Bool = true) : Bool
        @registry.synchronize do
          if pending = @pending_subscriptions[exchange_id]?
            unless success
              @pending_subscriptions.delete(exchange_id)
              Log.warn { "Subscription #{pending.subscription_id} aborted: peer rejected a ReportData chunk" }
              return true
            end

            if chunk = pending.next_chunk
              Log.debug { "Subscription #{pending.subscription_id}: sending next chunk (#{pending.remaining_chunks.size} remaining)" }
              send_chunk(pending, trigger, chunk)
            else
              @pending_subscriptions.delete(exchange_id)
              complete_subscription(pending, trigger, exchange_id)
            end

            return true
          end

          if pending = @pending_reads[exchange_id]?
            unless success
              @pending_reads.delete(exchange_id)
              Log.warn { "Read response aborted: peer rejected a ReportData chunk (exchange=#{exchange_id})" }
              return true
            end

            if chunk = pending.next_chunk
              Log.debug { "Read response: sending next chunk (#{pending.remaining_chunks.size} remaining)" }
              send_chunk(pending, trigger, chunk)
            end
            @pending_reads.delete(exchange_id) unless pending.more_chunks?

            return true
          end

          false
        end
      end

      # Reports one changed attribute to every subscription watching it.
      def notify(endpoint_id : UInt16, cluster_id : UInt32, attribute_id : UInt32) : Nil
        notify_batched([{endpoint_id, cluster_id, attribute_id}])
      end

      # Reports a batch of changed attributes, one ReportData per subscription.
      #
      # Batching matters: controllers (iOS especially) throttle a device that
      # sends a report per attribute during a burst of changes.
      def notify_batched(attributes : Array(Tuple(UInt16, UInt32, UInt32))) : Nil
        return if attributes.empty?

        @registry.synchronize do
          subscriptions = @registry.active_subscriptions
          Log.debug { "notify_batched: #{attributes.size} attribute(s), active=#{subscriptions.size}" }
          return if subscriptions.empty?

          subscriptions.each_value do |subscription|
            reports = collect_reports(subscription, attributes)
            next if reports.empty?

            Log.debug { "Sending batched subscription update: subscription_id=#{subscription.subscription_id}, peer=#{subscription.peer}, reports=#{reports.size}" }
            payload = IMHandler.encode_report_data(reports, subscription.subscription_id)
            Log.trace { "Subscription update ReportData TLV (#{payload.size} bytes): #{payload.hexstring}" }

            @sender.send_report(subscription.session, subscription.peer, payload)
            subscription.last_report_time = Time.utc
          end
        end
      end

      # The reports *subscription* wants out of *attributes*, read at the
      # subscriber's fabric.
      private def collect_reports(
        subscription : ActiveSubscription,
        attributes : Array(Tuple(UInt16, UInt32, UInt32)),
      ) : Array(InteractionModel::AttributeReportIB)
        reports = [] of InteractionModel::AttributeReportIB

        attributes.each do |(endpoint_id, cluster_id, attribute_id)|
          next unless subscription.matches?(endpoint_id, cluster_id, attribute_id)

          cluster = @node.clusters[{endpoint_id, cluster_id}]?
          unless cluster
            Log.warn { "Subscription update skipped: cluster not found (endpoint=#{endpoint_id}, cluster=0x#{cluster_id.to_s(16)})" }
            next
          end

          value = cluster.read_attribute(attribute_id, subscription.session.fabric_index)
          unless value.is_a?(TLV::Any)
            Log.warn { "Subscription update skipped: read_attribute returned #{value.class} (endpoint=#{endpoint_id}, cluster=0x#{cluster_id.to_s(16)}, attr=0x#{attribute_id.to_s(16)})" }
            next
          end

          attribute_data = InteractionModel::AttributeDataIB.new(
            path: InteractionModel::AttributePath.new(endpoint: endpoint_id, cluster: cluster_id, attribute: attribute_id),
            data: value,
            data_version: cluster.data_version
          )
          reports << InteractionModel::AttributeReportIB.new(attribute_data: attribute_data)
        end

        reports
      end

      private def send_chunk(pending : PendingChunks, trigger : Codec::MessageCodec::Message, chunk : Bytes) : Nil
        @sender.send_im_response(
          original_msg: trigger,
          peer: pending.peer,
          session: pending.session,
          message_type: InteractionModel::MessageType::ReportData.value,
          payload: chunk
        )
      end

      # Answers the last acknowledgement with the SubscribeResponse and moves
      # the subscription into the registry, where reports find it.
      private def complete_subscription(
        pending : PendingSubscription,
        trigger : Codec::MessageCodec::Message,
        exchange_id : UInt16,
      ) : Nil
        Log.debug { "All ReportData chunks sent for subscription #{pending.subscription_id}; sending SubscribeResponse" }

        payload = IMHandler.encode_subscribe_response(pending.subscription_id, pending.max_interval)
        Log.trace { "Encoded SubscribeResponse TLV (#{payload.size} bytes): #{payload.hexstring}" }

        @sender.send_im_response(
          original_msg: trigger,
          peer: pending.peer,
          session: pending.session,
          message_type: InteractionModel::MessageType::SubscribeResponse.value,
          payload: payload
        )

        @registry.add_subscription(ActiveSubscription.new(
          subscription_id: pending.subscription_id,
          min_interval: pending.min_interval,
          max_interval: pending.max_interval,
          peer: pending.peer,
          session: pending.session,
          attribute_paths: pending.attribute_paths,
          exchange_id: exchange_id
        ))
      end
    end
  end
end
