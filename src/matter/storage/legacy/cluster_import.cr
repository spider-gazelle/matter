require "./fields"

module Matter
  module Storage
    module Legacy
      # Converts a legacy `cluster_state/endpoint_<n>_cluster_<id>` JSON string
      # into a `clusters/<n>-<id>` document.
      #
      # Most cluster states are copied as parsed (with `null` members dropped);
      # the clusters below carry hex strings or tuple arrays that the new
      # records expect as `Bytes` and objects.
      module ClusterImport
        # Cluster ids with a known legacy `PersistedState`.
        BASIC_INFORMATION                = 40_i64
        ACCESS_CONTROL                   = 31_i64
        GROUP_KEY_MANAGEMENT             = 63_i64
        ON_OFF                           =  6_i64
        LEVEL_CONTROL                    =  8_i64
        GROUPS                           =  4_i64
        SCENES_MANAGEMENT                = 98_i64
        BRIDGED_DEVICE_BASIC_INFORMATION = 57_i64
        USER_LABEL                       = 65_i64

        COPIED_CLUSTERS = {BASIC_INFORMATION, ON_OFF, LEVEL_CONTROL, GROUPS, BRIDGED_DEVICE_BASIC_INFORMATION}

        DATA_VERSION         = "data_version"
        INITIAL_DATA_VERSION = 0_i64

        # AccessControl.
        EXTENSION = "extension"
        DATA_HEX  = "data_hex"
        DATA      = "data"

        # GroupKeyManagement.
        KEY_SETS   = "key_sets"
        EPOCH_KEYS = {"epoch_key0", "epoch_key1", "epoch_key2"}

        # ScenesManagement: `scenes` is an array of `[key, data]` pairs and each
        # extension field set lists `[attribute id, hex value]` pairs.
        SCENES               = "scenes"
        EXTENSION_FIELD_SETS = "extension_field_sets"
        ATTRIBUTES           = "attributes"
        ATTRIBUTE_ID         = "attribute_id"
        VALUE                = "value"
        SCENE_PAIR_SIZE      = 2
        ATTRIBUTE_PAIR_SIZE  = 2

        # UserLabel persisted a bare array of `{label, value}`.
        LABELS = "labels"

        # Returns the converted document, or `nil` when *cluster_id* is unknown.
        def self.convert(cluster_id : Int64, value : Type) : Document?
          case cluster_id
          when ACCESS_CONTROL        then access_control(Fields.compact(JsonParser.object(value)))
          when GROUP_KEY_MANAGEMENT  then group_key_management(Fields.compact(JsonParser.object(value)))
          when SCENES_MANAGEMENT     then scenes_management(Fields.compact(JsonParser.object(value)))
          when USER_LABEL            then user_label(JsonParser.array(value))
          when .in?(COPIED_CLUSTERS) then Fields.compact(JsonParser.object(value))
          end
        end

        private def self.access_control(state : Document) : Document
          Fields.map_objects!(state, EXTENSION) do |entry|
            Fields.hex_to_bytes!(entry, DATA_HEX, DATA)
            entry
          end
          state
        end

        private def self.group_key_management(state : Document) : Document
          key_sets = Fields.object(state, KEY_SETS)
          key_sets.each_key do |fabric_index|
            Fields.map_objects!(key_sets, fabric_index) do |key_set|
              EPOCH_KEYS.each { |key| Fields.hex_to_bytes!(key_set, key) }
              key_set
            end
          end
          state[KEY_SETS] = key_sets
          state
        end

        private def self.scenes_management(state : Document) : Document
          state[SCENES] = Fields.array(state, SCENES).map { |pair| scene(pair).as(Type) }
          state
        end

        # `[{fabric_index, group_id, scene_id}, {transition_time, scene_name, extension_field_sets}]`
        # becomes one object.
        private def self.scene(pair : Type) : Document
          parts = JsonParser.array(pair)
          raise ImportError.new("Field #{SCENES.inspect} entries must be [key, data] pairs") unless parts.size == SCENE_PAIR_SIZE

          scene = JsonParser.object(parts[0]).merge(JsonParser.object(parts[1]))
          Fields.map_objects!(scene, EXTENSION_FIELD_SETS) do |field_set|
            field_set[ATTRIBUTES] = Fields.array(field_set, ATTRIBUTES).map { |attribute| scene_attribute(attribute).as(Type) }
            field_set
          end
          scene
        end

        # `[attribute id, "hex"]` becomes `{attribute_id, value: Bytes}`.
        private def self.scene_attribute(pair : Type) : Document
          parts = JsonParser.array(pair)
          raise ImportError.new("Field #{ATTRIBUTES.inspect} entries must be [id, hex] pairs") unless parts.size == ATTRIBUTE_PAIR_SIZE

          attribute = Document{ATTRIBUTE_ID => parts[0], VALUE => parts[1]}
          Fields.int64(attribute, ATTRIBUTE_ID)
          Fields.hex_to_bytes!(attribute, VALUE)
          attribute
        end

        private def self.user_label(labels : Array(Type)) : Document
          Document{
            LABELS       => labels.map { |label| Fields.compact(JsonParser.object(label)).as(Type) },
            DATA_VERSION => INITIAL_DATA_VERSION,
          }
        end
      end
    end
  end
end
