require "./cluster"
require "./definitions/scenes"

module Matter
  module Cluster
    # Scenes Cluster Implementation (0x0005)
    # Provides scene storage and recall functionality
    #
    # Features:
    # - SceneNames (SN): Store names for scenes
    #
    # Specification: Matter 1.4 § 1.4
    class ScenesCluster < Base
      CLUSTER_ID = 0x0005_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        SceneNames = 0x01 # SN - Store names for scenes
      end

      # Attribute IDs
      SCENE_COUNT        = 0x0000_u32
      CURRENT_SCENE      = 0x0001_u32
      CURRENT_GROUP      = 0x0002_u32
      SCENE_VALID        = 0x0003_u32
      NAME_SUPPORT       = 0x0004_u32
      LAST_CONFIGURED_BY = 0x0005_u32

      # Command IDs
      CMD_ADD_SCENE            = 0x00_u32
      CMD_VIEW_SCENE           = 0x01_u32
      CMD_REMOVE_SCENE         = 0x02_u32
      CMD_REMOVE_ALL_SCENES    = 0x03_u32
      CMD_STORE_SCENE          = 0x04_u32
      CMD_RECALL_SCENE         = 0x05_u32
      CMD_GET_SCENE_MEMBERSHIP = 0x06_u32
      CMD_COPY_SCENE           = 0x40_u32

      # Response IDs
      CMD_ADD_SCENE_RESPONSE            = 0x00_u32
      CMD_VIEW_SCENE_RESPONSE           = 0x01_u32
      CMD_REMOVE_SCENE_RESPONSE         = 0x02_u32
      CMD_REMOVE_ALL_SCENES_RESPONSE    = 0x03_u32
      CMD_STORE_SCENE_RESPONSE          = 0x04_u32
      CMD_GET_SCENE_MEMBERSHIP_RESPONSE = 0x06_u32
      CMD_COPY_SCENE_RESPONSE           = 0x40_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP_ATTR = 0xFFFC_u32

      # Scene data structure
      struct SceneData
        property transition_time : UInt16
        property scene_name : String
        property extension_field_sets : Array(Definitions::Scenes::ExtensionFieldSet)

        def initialize(@transition_time, @scene_name, @extension_field_sets)
        end
      end

      # Feature map
      property feature_map : Feature

      # Scene storage: {group_id, scene_id} => SceneData
      property scenes : Hash({UInt16, UInt8}, SceneData)
      property current_scene : UInt8
      property current_group : UInt16
      property scene_valid : Bool

      # Callback for when scene is recalled
      property on_recall_scene : Proc(UInt16, UInt8, Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::SceneNames,
        max_scenes : UInt8 = 16_u8,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @scenes = Hash({UInt16, UInt8}, SceneData).new
        @max_scenes = max_scenes
        @current_scene = 0_u8
        @current_group = 0_u16
        @scene_valid = false

        @attribute_values[SCENE_COUNT] = encode_uint8(0_u8)
        @attribute_values[CURRENT_SCENE] = encode_uint8(@current_scene)
        @attribute_values[CURRENT_GROUP] = encode_uint16(@current_group)
        @attribute_values[SCENE_VALID] = encode_bool(@scene_valid)
        @attribute_values[NAME_SUPPORT] = encode_uint8(@feature_map.scene_names? ? 0x80_u8 : 0x00_u8)
      end

      # Backward compatibility
      def name_support : Bool
        @feature_map.scene_names?
      end

      def name : String
        "Scenes"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(SCENE_COUNT),
            name: "sceneCount",
            type: :uint8,
            writable: false,
            default: encode_uint8(0_u8)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CURRENT_SCENE),
            name: "currentScene",
            type: :uint8,
            writable: false,
            default: encode_uint8(0_u8)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CURRENT_GROUP),
            name: "currentGroup",
            type: :uint16,
            writable: false,
            default: encode_uint16(0_u16)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(SCENE_VALID),
            name: "sceneValid",
            type: :bool,
            writable: false,
            default: encode_bool(false)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(NAME_SUPPORT),
            name: "nameSupport",
            type: :uint8,
            writable: false,
            default: encode_uint8(@feature_map.scene_names? ? 0x80_u8 : 0x00_u8)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLUSTER_REVISION),
            name: "clusterRevision",
            type: :uint16,
            writable: false,
            default: encode_uint16(4_u16)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(FEATURE_MAP_ATTR),
            name: "featureMap",
            type: :uint32,
            writable: false,
            default: encode_uint32(@feature_map.value)
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ADD_SCENE),
            name: "addScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_VIEW_SCENE),
            name: "viewScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_REMOVE_SCENE),
            name: "removeScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_REMOVE_ALL_SCENES),
            name: "removeAllScenes"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STORE_SCENE),
            name: "storeScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_RECALL_SCENE),
            name: "recallScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_GET_SCENE_MEMBERSHIP),
            name: "getSceneMembership"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_COPY_SCENE),
            name: "copyScene"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when SCENE_COUNT
          encode_uint8(@scenes.size.to_u8)
        when CURRENT_SCENE
          encode_uint8(@current_scene)
        when CURRENT_GROUP
          encode_uint16(@current_group)
        when SCENE_VALID
          encode_bool(@scene_valid)
        when NAME_SUPPORT
          encode_uint8(@feature_map.scene_names? ? 0x80_u8 : 0x00_u8)
        when FEATURE_MAP_ATTR
          encode_uint32(@feature_map.value)
        else
          super(attribute_id)
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_ADD_SCENE
          Cluster::CommandResponse.new(CMD_ADD_SCENE_RESPONSE, handle_add_scene(fields))
        when CMD_VIEW_SCENE
          Cluster::CommandResponse.new(CMD_VIEW_SCENE_RESPONSE, handle_view_scene(fields))
        when CMD_REMOVE_SCENE
          Cluster::CommandResponse.new(CMD_REMOVE_SCENE_RESPONSE, handle_remove_scene(fields))
        when CMD_REMOVE_ALL_SCENES
          Cluster::CommandResponse.new(CMD_REMOVE_ALL_SCENES_RESPONSE, handle_remove_all_scenes(fields))
        when CMD_STORE_SCENE
          Cluster::CommandResponse.new(CMD_STORE_SCENE_RESPONSE, handle_store_scene(fields))
        when CMD_RECALL_SCENE
          # RecallScene has no response - return success status
          handle_recall_scene(fields)
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when CMD_GET_SCENE_MEMBERSHIP
          Cluster::CommandResponse.new(CMD_GET_SCENE_MEMBERSHIP_RESPONSE, handle_get_scene_membership(fields))
        when CMD_COPY_SCENE
          Cluster::CommandResponse.new(CMD_COPY_SCENE_RESPONSE, handle_copy_scene(fields))
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      # Add a scene to the scene table
      private def handle_add_scene(fields : Bytes) : Bytes
        # Simplified: parse basic fields from bytes
        # Real implementation would use TLV decoding
        if fields.size >= 5
          group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
          scene_id = fields[2]
          transition_time = IO::ByteFormat::LittleEndian.decode(UInt16, fields[3, 2])
          scene_name = fields.size > 5 ? String.new(fields[5..]) : ""

          status = add_scene(group_id, scene_id, transition_time, scene_name, [] of Definitions::Scenes::ExtensionFieldSet)
          encode_add_scene_response(status, group_id, scene_id)
        else
          encode_add_scene_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end
      end

      # View a scene from the scene table
      private def handle_view_scene(fields : Bytes) : Bytes
        if fields.size >= 3
          group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
          scene_id = fields[2]
          view_scene(group_id, scene_id)
        else
          encode_view_scene_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8, 0_u16, "", nil)
        end
      end

      # Remove a scene from the scene table
      private def handle_remove_scene(fields : Bytes) : Bytes
        if fields.size >= 3
          group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
          scene_id = fields[2]
          status = remove_scene(group_id, scene_id)
          encode_remove_scene_response(status, group_id, scene_id)
        else
          encode_remove_scene_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end
      end

      # Remove all scenes for a group
      private def handle_remove_all_scenes(fields : Bytes) : Bytes
        if fields.size >= 2
          group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
          status = remove_all_scenes(group_id)
          encode_remove_all_scenes_response(status, group_id)
        else
          encode_remove_all_scenes_response(InteractionModel::StatusCode::InvalidCommand, 0_u16)
        end
      end

      # Store current state as a scene
      private def handle_store_scene(fields : Bytes) : Bytes
        if fields.size >= 3
          group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
          scene_id = fields[2]

          # Simplified: store empty scene (would capture cluster states in real implementation)
          status = store_scene(group_id, scene_id)
          encode_store_scene_response(status, group_id, scene_id)
        else
          encode_store_scene_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end
      end

      # Recall a scene from the scene table
      private def handle_recall_scene(fields : Bytes) : InteractionModel::Status
        if fields.size >= 3
          group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
          scene_id = fields[2]

          status = recall_scene(group_id, scene_id)
          InteractionModel::Status.new(status)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
        end
      end

      # Get scene membership for a group
      private def handle_get_scene_membership(fields : Bytes) : Bytes
        if fields.size >= 2
          group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
          get_scene_membership(group_id)
        else
          encode_get_scene_membership_response(
            InteractionModel::StatusCode::InvalidCommand,
            nil,
            0_u16,
            nil
          )
        end
      end

      # Copy a scene
      private def handle_copy_scene(fields : Bytes) : Bytes
        if fields.size >= 7
          mode = fields[0]
          group_id_from = IO::ByteFormat::LittleEndian.decode(UInt16, fields[1, 2])
          scene_id_from = fields[3]
          group_id_to = IO::ByteFormat::LittleEndian.decode(UInt16, fields[4, 2])
          scene_id_to = fields[6]

          status = copy_scene(mode, group_id_from, scene_id_from, group_id_to, scene_id_to)
          encode_copy_scene_response(status, group_id_from, scene_id_from)
        else
          encode_copy_scene_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end
      end

      # Internal methods

      private def add_scene(
        group_id : UInt16,
        scene_id : UInt8,
        transition_time : UInt16,
        scene_name : String,
        extension_field_sets : Array(Definitions::Scenes::ExtensionFieldSet),
      ) : InteractionModel::StatusCode
        key = {group_id, scene_id}

        # Check capacity
        if @scenes.size >= @max_scenes && !@scenes.has_key?(key)
          return InteractionModel::StatusCode::ResourceExhausted
        end

        @scenes[key] = SceneData.new(transition_time, scene_name, extension_field_sets)
        update_scene_count
        InteractionModel::StatusCode::Success
      end

      private def view_scene(group_id : UInt16, scene_id : UInt8) : Bytes
        if scene_data = @scenes[{group_id, scene_id}]?
          encode_view_scene_response(
            InteractionModel::StatusCode::Success,
            group_id,
            scene_id,
            scene_data.transition_time,
            scene_data.scene_name,
            scene_data.extension_field_sets
          )
        else
          encode_view_scene_response(
            InteractionModel::StatusCode::NotFound,
            group_id,
            scene_id,
            0_u16,
            "",
            nil
          )
        end
      end

      private def remove_scene(group_id : UInt16, scene_id : UInt8) : InteractionModel::StatusCode
        if @scenes.delete({group_id, scene_id})
          update_scene_count

          # Invalidate current scene if it was removed
          if @current_group == group_id && @current_scene == scene_id
            @scene_valid = false
            @attribute_values[SCENE_VALID] = encode_bool(@scene_valid)
            increment_version
          end

          InteractionModel::StatusCode::Success
        else
          InteractionModel::StatusCode::NotFound
        end
      end

      private def remove_all_scenes(group_id : UInt16) : InteractionModel::StatusCode
        # Remove all scenes for this group
        removed_any = false
        @scenes.keys.each do |key|
          if key[0] == group_id
            @scenes.delete(key)
            removed_any = true
          end
        end

        if removed_any
          update_scene_count

          # Invalidate current scene if it was in this group
          if @current_group == group_id
            @scene_valid = false
            @attribute_values[SCENE_VALID] = encode_bool(@scene_valid)
            increment_version
          end
        end

        InteractionModel::StatusCode::Success
      end

      private def store_scene(group_id : UInt16, scene_id : UInt8) : InteractionModel::StatusCode
        # Simplified: store empty scene
        # Real implementation would capture current cluster states
        key = {group_id, scene_id}

        # Check capacity
        if @scenes.size >= @max_scenes && !@scenes.has_key?(key)
          return InteractionModel::StatusCode::ResourceExhausted
        end

        @scenes[key] = SceneData.new(0_u16, "", [] of Definitions::Scenes::ExtensionFieldSet)
        update_scene_count
        InteractionModel::StatusCode::Success
      end

      private def recall_scene(group_id : UInt16, scene_id : UInt8) : InteractionModel::StatusCode
        if scene_data = @scenes[{group_id, scene_id}]?
          # Update current scene tracking
          @current_group = group_id
          @current_scene = scene_id
          @scene_valid = true

          @attribute_values[CURRENT_GROUP] = encode_uint16(@current_group)
          @attribute_values[CURRENT_SCENE] = encode_uint8(@current_scene)
          @attribute_values[SCENE_VALID] = encode_bool(@scene_valid)
          increment_version

          # Trigger callback
          @on_recall_scene.try(&.call(group_id, scene_id))

          InteractionModel::StatusCode::Success
        else
          InteractionModel::StatusCode::NotFound
        end
      end

      private def get_scene_membership(group_id : UInt16) : Bytes
        capacity = (@max_scenes - @scenes.size).to_u8

        # Find all scenes for this group
        scene_list = [] of UInt8
        @scenes.keys.each do |key|
          if key[0] == group_id
            scene_list << key[1]
          end
        end

        encode_get_scene_membership_response(
          InteractionModel::StatusCode::Success,
          capacity,
          group_id,
          scene_list
        )
      end

      private def copy_scene(
        mode : UInt8,
        group_id_from : UInt16,
        scene_id_from : UInt8,
        group_id_to : UInt16,
        scene_id_to : UInt8,
      ) : InteractionModel::StatusCode
        copy_all = (mode & 0x01) != 0

        if copy_all
          # Copy all scenes from one group to another
          scenes_to_copy = @scenes.select { |key, _| key[0] == group_id_from }

          scenes_to_copy.each do |key, scene_data|
            new_key = {group_id_to, key[1]}

            # Check capacity
            if @scenes.size >= @max_scenes && !@scenes.has_key?(new_key)
              return InteractionModel::StatusCode::ResourceExhausted
            end

            @scenes[new_key] = SceneData.new(
              scene_data.transition_time,
              scene_data.scene_name,
              scene_data.extension_field_sets
            )
          end
        else
          # Copy single scene
          if scene_data = @scenes[{group_id_from, scene_id_from}]?
            new_key = {group_id_to, scene_id_to}

            # Check capacity
            if @scenes.size >= @max_scenes && !@scenes.has_key?(new_key)
              return InteractionModel::StatusCode::ResourceExhausted
            end

            @scenes[new_key] = SceneData.new(
              scene_data.transition_time,
              scene_data.scene_name,
              scene_data.extension_field_sets
            )
          else
            return InteractionModel::StatusCode::NotFound
          end
        end

        update_scene_count
        InteractionModel::StatusCode::Success
      end

      private def update_scene_count
        @attribute_values[SCENE_COUNT] = encode_uint8(@scenes.size.to_u8)
        increment_version
      end

      # Response encoding methods

      private def encode_add_scene_response(status : InteractionModel::StatusCode, group_id : UInt16, scene_id : UInt8) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.write_byte(scene_id)
        io.to_slice
      end

      private def encode_view_scene_response(
        status : InteractionModel::StatusCode,
        group_id : UInt16,
        scene_id : UInt8,
        transition_time : UInt16,
        scene_name : String,
        extension_field_sets : Array(Definitions::Scenes::ExtensionFieldSet)?,
      ) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.write_byte(scene_id)

        if status == InteractionModel::StatusCode::Success
          IO::ByteFormat::LittleEndian.encode(transition_time, io)
          io.write(scene_name.to_slice)
        end

        io.to_slice
      end

      private def encode_remove_scene_response(status : InteractionModel::StatusCode, group_id : UInt16, scene_id : UInt8) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.write_byte(scene_id)
        io.to_slice
      end

      private def encode_remove_all_scenes_response(status : InteractionModel::StatusCode, group_id : UInt16) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.to_slice
      end

      private def encode_store_scene_response(status : InteractionModel::StatusCode, group_id : UInt16, scene_id : UInt8) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.write_byte(scene_id)
        io.to_slice
      end

      private def encode_get_scene_membership_response(
        status : InteractionModel::StatusCode,
        capacity : UInt8?,
        group_id : UInt16,
        scene_list : Array(UInt8)?,
      ) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)

        if capacity
          io.write_byte(capacity)
        else
          io.write_byte(0xFF_u8) # null
        end

        IO::ByteFormat::LittleEndian.encode(group_id, io)

        if scene_list
          io.write_byte(scene_list.size.to_u8)
          scene_list.each do |scene_id|
            io.write_byte(scene_id)
          end
        else
          io.write_byte(0_u8) # Empty list
        end

        io.to_slice
      end

      private def encode_copy_scene_response(status : InteractionModel::StatusCode, group_id_from : UInt16, scene_id_from : UInt8) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id_from, io)
        io.write_byte(scene_id_from)
        io.to_slice
      end

      # Public API

      def scene_count : Int32
        @scenes.size
      end

      def has_scene?(group_id : UInt16, scene_id : UInt8) : Bool
        @scenes.has_key?({group_id, scene_id})
      end

      def invalidate_current_scene
        @scene_valid = false
        @attribute_values[SCENE_VALID] = encode_bool(@scene_valid)
        increment_version
      end
    end
  end
end
