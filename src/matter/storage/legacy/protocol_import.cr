require "./fields"

module Matter
  module Storage
    module Legacy
      # Converts entries of the legacy `protocol/case_sessions` and
      # `protocol/active_subscriptions` JSON strings into `sessions/<id>` and
      # `subscriptions/<id>` documents.
      module ProtocolImport
        # Legacy session field names.
        SESSION_ID               = "session_id"
        PEER_SESSION_ID          = "peer_session_id"
        SESSION_TYPE             = "session_type"
        ENCRYPTION_KEY           = "encryption_key"
        DECRYPTION_KEY           = "decryption_key"
        IS_INITIATOR             = "is_initiator"
        IS_CASE                  = "is_case"
        LOCAL_MESSAGE_COUNTER    = "local_message_counter"
        PEER_MESSAGE_COUNTER     = "peer_message_counter"
        HAS_PEER_MESSAGE_COUNTER = "has_peer_message_counter"
        CREATION_TIME            = "creation_time"
        LAST_ACTIVITY_TIME       = "last_activity_time"
        PEER_NODE_ID             = "peer_node_id"
        LOCAL_NODE_ID            = "local_node_id"
        ATTESTATION_CHALLENGE    = "attestation_challenge"
        FABRIC_INDEX             = "fabric_index"

        # Target session field names that differ from the legacy ones.
        INITIATOR        = "initiator"
        CASE_SESSION     = "case_session"
        CREATED_AT       = "created_at"
        LAST_ACTIVITY_AT = "last_activity_at"

        # Legacy stored `Session::SessionType#value`; the new documents store
        # the member name.
        SESSION_TYPE_NAMES = {
          0_i64 => "Unsecured",
          1_i64 => "Unicast",
          2_i64 => "Group",
        }

        # Legacy subscription field names.
        SUBSCRIPTION_ID  = "subscription_id"
        MIN_INTERVAL     = "min_interval"
        MAX_INTERVAL     = "max_interval"
        PEER_ADDRESS     = "peer_address"
        PEER_PORT        = "peer_port"
        EXCHANGE_ID      = "exchange_id"
        NEXT_EXCHANGE_ID = "next_exchange_id"
        LAST_REPORT_TIME = "last_report_time"
        ATTRIBUTE_PATHS  = "attribute_paths"

        # Target subscription field names that differ from the legacy ones.
        LAST_REPORT_AT = "last_report_at"

        def self.convert_session(legacy : Document) : Document
          session = Document{
            SESSION_ID            => Fields.int64(legacy, SESSION_ID),
            PEER_SESSION_ID       => Fields.int64(legacy, PEER_SESSION_ID),
            SESSION_TYPE          => session_type_name(Fields.int64(legacy, SESSION_TYPE)),
            ENCRYPTION_KEY        => Fields.hex(legacy, ENCRYPTION_KEY),
            DECRYPTION_KEY        => Fields.hex(legacy, DECRYPTION_KEY),
            INITIATOR             => Fields.bool(legacy, IS_INITIATOR),
            CASE_SESSION          => Fields.bool(legacy, IS_CASE),
            LOCAL_MESSAGE_COUNTER => Fields.int64(legacy, LOCAL_MESSAGE_COUNTER),
          }
          if legacy.has_key?(HAS_PEER_MESSAGE_COUNTER) ? Fields.bool(legacy, HAS_PEER_MESSAGE_COUNTER) : legacy.has_key?(PEER_MESSAGE_COUNTER)
            session[PEER_MESSAGE_COUNTER] = Fields.int64(legacy, PEER_MESSAGE_COUNTER)
          end
          if peer_node_id = Fields.integer?(legacy, PEER_NODE_ID)
            session[PEER_NODE_ID] = peer_node_id
          end
          if local_node_id = Fields.integer?(legacy, LOCAL_NODE_ID)
            session[LOCAL_NODE_ID] = local_node_id
          end
          if challenge = Fields.hex?(legacy, ATTESTATION_CHALLENGE)
            session[ATTESTATION_CHALLENGE] = challenge
          end
          if fabric_index = Fields.int64?(legacy, FABRIC_INDEX)
            session[FABRIC_INDEX] = fabric_index
          end
          session[CREATED_AT] = Fields.unix_time(legacy, CREATION_TIME)
          session[LAST_ACTIVITY_AT] = Fields.unix_time(legacy, LAST_ACTIVITY_TIME)
          session
        end

        def self.convert_subscription(legacy : Document) : Document
          exchange_id = Fields.int64?(legacy, EXCHANGE_ID) || Fields.int64(legacy, NEXT_EXCHANGE_ID)
          paths = Fields.array(legacy, ATTRIBUTE_PATHS).map { |path| Fields.compact(JsonParser.object(path)).as(Type) }

          Document{
            SUBSCRIPTION_ID => Fields.int64(legacy, SUBSCRIPTION_ID),
            MIN_INTERVAL    => Fields.int64(legacy, MIN_INTERVAL),
            MAX_INTERVAL    => Fields.int64(legacy, MAX_INTERVAL),
            PEER_ADDRESS    => Fields.string(legacy, PEER_ADDRESS),
            PEER_PORT       => Fields.int64(legacy, PEER_PORT),
            SESSION_ID      => Fields.int64(legacy, SESSION_ID),
            EXCHANGE_ID     => exchange_id,
            LAST_REPORT_AT  => Fields.unix_time(legacy, LAST_REPORT_TIME),
            ATTRIBUTE_PATHS => paths,
          }
        end

        private def self.session_type_name(value : Int64) : String
          SESSION_TYPE_NAMES[value]? || raise ImportError.new("Field #{SESSION_TYPE.inspect} is not a known session type")
        end
      end
    end
  end
end
