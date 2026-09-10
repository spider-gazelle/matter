require "json"
require "log"

require "../storage/base"
require "../session/context"

module Matter
  module Protocol
    # Persistence hooks for `Protocol::MessageHandler` state (CASE sessions and subscriptions).
    module Persistence
      # JSON keys whose string values are secrets and must never reach the logs.
      REDACTED_KEYS = %w[encryption_key decryption_key attestation_challenge]

      REDACTED_VALUE = "<redacted>"

      # Replace the string values of `REDACTED_KEYS` in a JSON document with a placeholder.
      def self.redact(json : String) : String
        REDACTED_KEYS.reduce(json) do |redacted, key|
          redacted.gsub(/"#{key}"\s*:\s*"[^"]*"/, %("#{key}":"#{REDACTED_VALUE}"))
        end
      end

      abstract class Base
        abstract def restore(handler : MessageHandler) : Nil
        abstract def session_established(handler : MessageHandler, session : Session::SecureContext) : Nil
        abstract def session_updated(handler : MessageHandler, session : Session::SecureContext) : Nil
        abstract def session_removed(handler : MessageHandler, session_id : UInt16) : Nil
        abstract def subscription_established(handler : MessageHandler, subscription : MessageHandler::ActiveSubscription) : Nil
        abstract def subscription_removed(handler : MessageHandler, subscription_id : UInt32) : Nil
      end

      # Stores protocol state as JSON strings inside a `Storage::Base`.
      class StorageBackend < Base
        Log = ::Log.for("matter.protocol.persistence")

        SESSION_CONTEXT      = ["protocol"] of String
        SESSION_KEY          = "case_sessions"
        SUBSCRIPTIONS_KEY    = "active_subscriptions"
        NEXT_SUBSCRIPTION_ID = "next_subscription_id"

        def initialize(@storage : Storage::Base)
        end

        def restore(handler : MessageHandler) : Nil
          restore_sessions(handler)
          restore_subscriptions(handler)
        end

        def session_established(handler : MessageHandler, session : Session::SecureContext) : Nil
          return unless session.case_session?

          sessions = load_case_sessions
          sessions[session.session_id.to_s] = session.to_h
          persist_case_sessions(sessions)
        rescue ex
          Log.error(exception: ex) do
            "Failed to persist session #{session.session_id} " \
            "(fabric_index=#{session.fabric_index.inspect} peer_node_id=#{session.peer_node_id.try(&.id).inspect} " \
            "enc_key_bytes=#{session.encryption_key.size} dec_key_bytes=#{session.decryption_key.size} att_challenge_bytes=#{session.attestation_challenge.try(&.size).inspect})"
          end
        end

        def session_updated(handler : MessageHandler, session : Session::SecureContext) : Nil
          return unless session.case_session?

          sessions = load_case_sessions
          sessions[session.session_id.to_s] = session.to_h
          persist_case_sessions(sessions)
        rescue ex
          Log.error(exception: ex) do
            "Failed to update persisted session #{session.session_id} " \
            "(fabric_index=#{session.fabric_index.inspect} peer_node_id=#{session.peer_node_id.try(&.id).inspect} " \
            "local_counter=#{session.local_message_counter} peer_counter=#{session.peer_message_counter.inspect})"
          end
        end

        def session_removed(handler : MessageHandler, session_id : UInt16) : Nil
          sessions = load_case_sessions
          if sessions.delete(session_id.to_s)
            persist_case_sessions(sessions)
          end
        rescue ex
          Log.error(exception: ex) { "Failed to remove persisted session #{session_id} (storage_key=#{SESSION_KEY})" }
        end

        def subscription_established(handler : MessageHandler, subscription : MessageHandler::ActiveSubscription) : Nil
          subs = load_subscriptions
          subs[subscription.subscription_id.to_s] = subscription.to_h
          persist_subscriptions(subs)
          @storage.set(SESSION_CONTEXT, NEXT_SUBSCRIPTION_ID, handler.next_subscription_id)
        rescue ex
          Log.error(exception: ex) do
            "Failed to persist subscription #{subscription.subscription_id} " \
            "(session_id=#{subscription.session.session_id} peer=#{subscription.peer} exchange=#{subscription.exchange_id} paths=#{subscription.attribute_paths.size})"
          end
        end

        def subscription_removed(handler : MessageHandler, subscription_id : UInt32) : Nil
          subs = load_subscriptions
          if subs.delete(subscription_id.to_s)
            persist_subscriptions(subs)
          end
        rescue ex
          Log.error(exception: ex) { "Failed to remove persisted subscription #{subscription_id} (storage_key=#{SUBSCRIPTIONS_KEY})" }
        end

        private def restore_sessions(handler : MessageHandler) : Nil
          stored = load_case_sessions
          return if stored.empty?

          kept = {} of String => Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
          restored = 0
          pruned = 0

          stored.each do |id, session_h|
            begin
              session = Session::SecureContext.from_h(session_h)
              next unless session.case_session?

              fabric_index = session.fabric_index
              if fabric_index && handler.fabric_table.get_fabric(fabric_index)
                handler.sessions[session.session_id] = session
                kept[id] = session_h
                restored += 1
              else
                pruned += 1
              end
            rescue
              pruned += 1
            end
          end

          # If the persisted session list includes stale entries (e.g. sessions for
          # fabrics that no longer exist), drop them to avoid resurrecting broken
          # secure sessions after a reset/decommission.
          if pruned > 0
            persist_case_sessions(kept)
            Log.info { "Pruned #{pruned} persisted CASE session(s)" }
          end

          Log.info { "Restored #{restored} CASE session(s)" } if restored > 0
        rescue ex
          raw = @storage.get(SESSION_CONTEXT, SESSION_KEY)
          raw_value = raw.is_a?(String) ? Persistence.redact(raw) : raw.inspect
          Log.error(exception: ex) { "Failed restoring sessions (stored=#{raw_value})" }
        end

        private def restore_subscriptions(handler : MessageHandler) : Nil
          subs = load_subscriptions_from_storage(handler.sessions)
          return if subs.empty?

          max_id = 0_u32
          subs.each do |subscription_id, sub|
            handler.active_subscriptions[subscription_id] = sub
            max_id = subscription_id if subscription_id > max_id
          end

          handler.next_subscription_id = max_id + 1_u32 if max_id > 0_u32

          if stored = @storage.get(SESSION_CONTEXT, NEXT_SUBSCRIPTION_ID)
            if stored.is_a?(Int64)
              handler.next_subscription_id = {handler.next_subscription_id, stored.to_u32}.max
            elsif stored.is_a?(UInt32)
              handler.next_subscription_id = {handler.next_subscription_id, stored}.max
            end
          end

          Log.info { "Restored #{subs.size} subscription(s) (next=#{handler.next_subscription_id})" }
        rescue ex
          raw = @storage.get(SESSION_CONTEXT, SUBSCRIPTIONS_KEY)
          raw_value = raw.is_a?(String) ? raw : raw.inspect
          Log.error(exception: ex) { "Failed restoring subscriptions (stored=#{raw_value})" }
        end

        private def load_case_sessions : Hash(String, Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool))
          stored = @storage.get(SESSION_CONTEXT, SESSION_KEY)
          return ({} of String => Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)) if !stored.is_a?(String) || stored.empty?

          data = Hash(String, Hash(String, JSON::Any)).from_json(stored)
          sessions = {} of String => Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
          data.each do |id, hash|
            sessions[id] = json_any_hash_to_session_hash(hash)
          end
          sessions
        rescue
          {} of String => Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
        end

        private def persist_case_sessions(sessions : Hash(String, Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool))) : Nil
          @storage.set(SESSION_CONTEXT, SESSION_KEY, sessions.to_json)
        end

        private def load_subscriptions : Hash(String, Hash(String, String | UInt32 | UInt16 | Int64 | Array(Hash(String, UInt32 | UInt16 | Nil))))
          stored = @storage.get(SESSION_CONTEXT, SUBSCRIPTIONS_KEY)
          return ({} of String => Hash(String, String | UInt32 | UInt16 | Int64 | Array(Hash(String, UInt32 | UInt16 | Nil)))) if !stored.is_a?(String) || stored.empty?

          data = Hash(String, Hash(String, JSON::Any)).from_json(stored)
          subs = {} of String => Hash(String, String | UInt32 | UInt16 | Int64 | Array(Hash(String, UInt32 | UInt16 | Nil)))
          data.each do |id, hash|
            subs[id] = json_any_hash_to_subscription_hash(hash)
          end
          subs
        rescue
          {} of String => Hash(String, String | UInt32 | UInt16 | Int64 | Array(Hash(String, UInt32 | UInt16 | Nil)))
        end

        private def persist_subscriptions(subs : Hash(String, Hash(String, String | UInt32 | UInt16 | Int64 | Array(Hash(String, UInt32 | UInt16 | Nil))))) : Nil
          @storage.set(SESSION_CONTEXT, SUBSCRIPTIONS_KEY, subs.to_json)
        end

        private def load_subscriptions_from_storage(
          sessions : Hash(UInt16, Session::SecureContext),
        ) : Hash(UInt32, MessageHandler::ActiveSubscription)
          stored = load_subscriptions
          subs = {} of UInt32 => MessageHandler::ActiveSubscription

          stored.each do |_, sub_h|
            session_id = sub_h["session_id"]?.try(&.as(UInt16)) || 0_u16
            session = sessions[session_id]?
            next unless session

            sub = MessageHandler::ActiveSubscription.from_h(sub_h, session)
            subs[sub.subscription_id] = sub
          rescue
            # Skip invalid entries
          end

          subs
        end

        private def json_any_hash_to_session_hash(h : Hash(String, JSON::Any)) : Hash(String, String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)
          session_h = {} of String => (String | UInt64 | UInt32 | UInt16 | UInt8 | Int64 | Bool)

          h.each do |key, value|
            raw = value.raw
            case raw
            when String
              session_h[key] = raw
            when Int64
              session_h[key] = raw
            when Float64
              session_h[key] = raw.to_i64
            when Bool
              session_h[key] = raw
            else
              # ignore
            end
          end

          session_h
        end

        private def json_any_hash_to_subscription_hash(h : Hash(String, JSON::Any)) : Hash(String, String | UInt32 | UInt16 | Int64 | Array(Hash(String, UInt32 | UInt16 | Nil)))
          sub_h = {} of String => (String | UInt32 | UInt16 | Int64 | Array(Hash(String, UInt32 | UInt16 | Nil)))

          h.each do |key, value|
            if key == "attribute_paths"
              paths_any = value.as_a
              paths = paths_any.map do |path_any|
                path_h_any = path_any.as_h
                converted = {} of String => (UInt32 | UInt16 | Nil)
                path_h_any.each do |path_key, pv_any|
                  pv = pv_any.raw
                  if pv.nil?
                    converted[path_key] = nil
                  else
                    i = pv.as(Int64)
                    case path_key
                    when "endpoint", "list_index"
                      converted[path_key] = i.to_u16
                    else
                      converted[path_key] = i.to_u32
                    end
                  end
                end
                converted
              end
              sub_h[key] = paths
              next
            end

            raw = value.raw
            case raw
            when String
              sub_h[key] = raw
            when Int64
              case key
              when "subscription_id"
                sub_h[key] = raw.to_u32
              when "min_interval", "max_interval", "peer_port", "session_id", "next_exchange_id", "exchange_id"
                sub_h[key] = raw.to_u16
              when "last_report_time"
                sub_h[key] = raw
              else
                # Prefer Int64 for unknown numeric fields
                sub_h[key] = raw
              end
            when Float64
              sub_h[key] = raw.to_i64
            else
              # ignore
            end
          end

          sub_h
        end
      end
    end
  end
end
