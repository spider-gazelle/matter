require "log"

require "../debouncer"
require "../storage/backend"
require "../session/context"

module Matter
  module Protocol
    # Persistence hooks for `Protocol::MessageHandler` state (CASE sessions and subscriptions).
    module Persistence
      abstract class Base
        abstract def restore(handler : MessageHandler) : Nil
        abstract def session_established(handler : MessageHandler, session : Session::SecureContext) : Nil
        abstract def session_updated(handler : MessageHandler, session : Session::SecureContext) : Nil
        abstract def session_removed(handler : MessageHandler, session_id : UInt16) : Nil
        abstract def subscription_established(handler : MessageHandler, subscription : MessageHandler::ActiveSubscription) : Nil
        abstract def subscription_removed(handler : MessageHandler, subscription_id : UInt32) : Nil
      end

      # Stores protocol state as documents in a `Storage::Backend`:
      # `sessions/<session_id>`, `subscriptions/<subscription_id>` and the
      # subscription id counter in `device/counters`.
      #
      # Log lines carry ids and counts only; session documents hold keys and
      # are never written to the log.
      class StorageBackend < Base
        Log = ::Log.for("matter.protocol.persistence")

        SESSIONS      = Storage::Collections::SESSIONS
        SUBSCRIPTIONS = Storage::Collections::SUBSCRIPTIONS
        DEVICE        = Storage::Collections::DEVICE

        COUNTERS_ID              = "counters"
        NEXT_SUBSCRIPTION_ID_KEY = "next_subscription_id"

        # When set, `session_updated` (message counters and activity times)
        # defers its write to this debouncer; the owner calls
        # `flush_pending_writes` from the debounced action.
        property write_debouncer : Debouncer?

        @dirty_sessions : Hash(UInt16, Session::SecureContext) = Hash(UInt16, Session::SecureContext).new

        def initialize(@backend : Storage::Backend)
        end

        def restore(handler : MessageHandler) : Nil
          restore_sessions(handler)
          restore_subscriptions(handler)
        end

        def session_established(handler : MessageHandler, session : Session::SecureContext) : Nil
          return unless session.case_session?

          write_session(session)
        rescue ex
          Log.error(exception: ex) { "Failed to persist session #{session.session_id} (fabric_index=#{session.fabric_index.inspect})" }
        end

        def session_updated(handler : MessageHandler, session : Session::SecureContext) : Nil
          return unless session.case_session?

          if debouncer = @write_debouncer
            @dirty_sessions[session.session_id] = session
            debouncer.trigger
          else
            write_session(session)
          end
        rescue ex
          Log.error(exception: ex) { "Failed to update persisted session #{session.session_id} (fabric_index=#{session.fabric_index.inspect})" }
        end

        def session_removed(handler : MessageHandler, session_id : UInt16) : Nil
          @dirty_sessions.delete(session_id)
          @backend.delete(SESSIONS, session_id.to_s)
        rescue ex
          Log.error(exception: ex) { "Failed to remove persisted session #{session_id}" }
        end

        def subscription_established(handler : MessageHandler, subscription : MessageHandler::ActiveSubscription) : Nil
          @backend.transaction do
            @backend.write(SUBSCRIPTIONS, subscription.subscription_id.to_s, subscription.to_record.to_document)
            @backend.write(DEVICE, COUNTERS_ID, Storage::Document{NEXT_SUBSCRIPTION_ID_KEY => handler.next_subscription_id.to_i64})
          end
        rescue ex
          Log.error(exception: ex) do
            "Failed to persist subscription #{subscription.subscription_id} " \
            "(session_id=#{subscription.session.session_id} paths=#{subscription.attribute_paths.size})"
          end
        end

        def subscription_removed(handler : MessageHandler, subscription_id : UInt32) : Nil
          @backend.delete(SUBSCRIPTIONS, subscription_id.to_s)
        rescue ex
          Log.error(exception: ex) { "Failed to remove persisted subscription #{subscription_id}" }
        end

        # Writes every session deferred by `session_updated`.
        def flush_pending_writes : Nil
          return if @dirty_sessions.empty?

          pending = @dirty_sessions.values
          @dirty_sessions.clear
          @backend.transaction do
            pending.each { |session| write_session(session) }
          end
        end

        private def write_session(session : Session::SecureContext) : Nil
          @backend.write(SESSIONS, session.session_id.to_s, session.to_record.to_document)
        end

        # Restores CASE sessions whose fabric still exists; every other stored
        # session (unknown fabric, undecodable document) is deleted so a reset
        # or decommission cannot resurrect a broken secure session.
        private def restore_sessions(handler : MessageHandler) : Nil
          restored = 0
          pruned = 0

          @backend.all(SESSIONS).each do |id, document|
            session = Session::SecureContext.from_record(Session::SecureContext::SessionRecord.from_document(document))
            fabric_index = session.fabric_index

            if session.case_session? && fabric_index && handler.fabric_table.get_fabric(fabric_index)
              handler.sessions[session.session_id] = session
              restored += 1
            else
              @backend.delete(SESSIONS, id)
              pruned += 1
            end
          rescue ex
            Log.warn(exception: ex) { "Pruning persisted session #{id}: cannot be restored" }
            @backend.delete(SESSIONS, id)
            pruned += 1
          end

          Log.info { "Pruned #{pruned} persisted CASE session(s)" } if pruned > 0
          Log.info { "Restored #{restored} CASE session(s)" } if restored > 0
        rescue ex
          Log.error(exception: ex) { "Failed restoring sessions" }
        end

        # Restores subscriptions whose session was restored and removes the
        # rest. The subscription id counter never moves backwards.
        private def restore_subscriptions(handler : MessageHandler) : Nil
          restored = 0
          max_id = 0_u32

          @backend.all(SUBSCRIPTIONS).each do |id, document|
            record = MessageHandler::ActiveSubscription::SubscriptionRecord.from_document(document)
            session = handler.sessions[record.session_id]?
            unless session
              @backend.delete(SUBSCRIPTIONS, id)
              next
            end

            subscription = MessageHandler::ActiveSubscription.from_record(record, session)
            handler.active_subscriptions[subscription.subscription_id] = subscription
            max_id = {max_id, subscription.subscription_id}.max
            restored += 1
          rescue ex
            Log.warn(exception: ex) { "Skipping persisted subscription #{id}: cannot be restored" }
            @backend.delete(SUBSCRIPTIONS, id)
          end

          handler.next_subscription_id = {handler.next_subscription_id, max_id + 1_u32}.max if max_id > 0_u32

          if stored = @backend.read(DEVICE, COUNTERS_ID).try(&.[NEXT_SUBSCRIPTION_ID_KEY]?)
            next_id = Storage::Record.decode(stored, UInt32, NEXT_SUBSCRIPTION_ID_KEY)
            handler.next_subscription_id = {handler.next_subscription_id, next_id}.max
          end

          Log.info { "Restored #{restored} subscription(s) (next=#{handler.next_subscription_id})" } if restored > 0
        rescue ex
          Log.error(exception: ex) { "Failed restoring subscriptions" }
        end
      end
    end
  end
end
