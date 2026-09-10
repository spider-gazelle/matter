require "../../error"

module Matter
  module Storage
    module Legacy
      # Raised when a legacy value does not have the expected shape. Messages
      # name keys only, never values, so they are safe to log.
      class ImportError < StorageError
      end

      # Names used by the pre-refactor storage file: a flat JSON object of
      # `{ "<context>": { "<key>": <value> } }`.
      module Format
        DEVICE_IDENTITY_CONTEXT = "device_identity"
        FABRICS_CONTEXT         = "fabrics"
        PROTOCOL_CONTEXT        = "protocol"
        CLUSTER_STATE_CONTEXT   = "cluster_state"
        BRIDGE_CONTEXT          = "bridge"

        HOSTNAME_KEY      = "commissioning_hostname"
        SERIAL_NUMBER_KEY = "serial_number"
        UNIQUE_ID_KEY     = "unique_id"
        IDENTITY_KEYS     = {HOSTNAME_KEY, SERIAL_NUMBER_KEY, UNIQUE_ID_KEY}

        FABRIC_TABLE_KEY = "fabric_table"

        CASE_SESSIONS_KEY        = "case_sessions"
        ACTIVE_SUBSCRIPTIONS_KEY = "active_subscriptions"
        NEXT_SUBSCRIPTION_ID_KEY = "next_subscription_id"

        BRIDGED_DEVICES_KEY = "bridged_devices"

        # `endpoint_<n>_cluster_<id>`; the captures are the endpoint and cluster id.
        CLUSTER_STATE_KEY = /\Aendpoint_(\d+)_cluster_(\d+)\z/

        # Typed wrapper objects the old JSON backend could emit for values that
        # have no JSON representation: `{"__type__": "<tag>", "value": "<text>"}`.
        TYPE_FIELD  = "__type__"
        VALUE_FIELD = "value"
        BYTES_TYPE  = "bytes"
        BIGINT_TYPE = "bigint"
        UINT64_TYPE = "uint64"

        # The fabric CAT list is comma-joined hex.
        LIST_SEPARATOR = ','
        HEX_BASE       = 16
      end

      # Names of the documents produced by the importer that are not part of
      # the source format.
      module Target
        IDENTITY_ID = "identity"
        COUNTERS_ID = "counters"

        NEXT_SUBSCRIPTION_ID_KEY = "next_subscription_id"
        BRIDGED_DEVICES_ID       = "bridged_devices"

        # Unknown contexts and keys are kept verbatim under
        # `app/legacy-<context>-<key>` as `{"value": <raw value>}`.
        UNKNOWN_ID_PREFIX = "legacy"
        ID_SEPARATOR      = "-"
        RAW_VALUE_KEY     = "value"

        # Characters a document id must not contain are replaced with this.
        NAME_REPLACEMENT        = "_"
        INVALID_NAME_CHARACTERS = /[^A-Za-z0-9_.:-]/
      end
    end
  end
end
