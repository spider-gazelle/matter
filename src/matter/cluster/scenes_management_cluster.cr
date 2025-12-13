require "./cluster"
require "tlv"

module Matter
  module Cluster
    # Scenes Management Cluster Implementation (0x0062)
    #
    # Provides scene storage and recall functionality.
    # This is the Matter 1.4+ replacement for the deprecated Scenes cluster (0x0005).
    #
    # Features:
    # - SceneNames (SN): Store names for scenes
    #
    # Specification: Matter 1.4 § 1.4
    class ScenesManagementCluster < Base
      CLUSTER_ID = 0x0062_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        SceneNames = 0x01 # SN - Store names for scenes
      end

      # Attribute IDs
      ATTR_SCENE_TABLE_SIZE  = 0x0001_u32 # Fixed attribute
      ATTR_FABRIC_SCENE_INFO = 0x0002_u32 # Fabric-scoped list

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP_ATTR = 0xFFFC_u32

      # Command IDs
      CMD_ADD_SCENE            = 0x00_u32
      CMD_VIEW_SCENE           = 0x01_u32
      CMD_REMOVE_SCENE         = 0x02_u32
      CMD_REMOVE_ALL_SCENES    = 0x03_u32
      CMD_STORE_SCENE          = 0x04_u32
      CMD_RECALL_SCENE         = 0x05_u32
      CMD_GET_SCENE_MEMBERSHIP = 0x06_u32
      CMD_COPY_SCENE           = 0x40_u32 # Optional

      # Response IDs
      CMD_ADD_SCENE_RESPONSE            = 0x00_u32
      CMD_VIEW_SCENE_RESPONSE           = 0x01_u32
      CMD_REMOVE_SCENE_RESPONSE         = 0x02_u32
      CMD_REMOVE_ALL_SCENES_RESPONSE    = 0x03_u32
      CMD_STORE_SCENE_RESPONSE          = 0x04_u32
      CMD_GET_SCENE_MEMBERSHIP_RESPONSE = 0x06_u32
      CMD_COPY_SCENE_RESPONSE           = 0x40_u32

      # SceneInfo structure for fabric-scoped scene info
      struct SceneInfo
        property scene_count : UInt8
        property current_scene : UInt8
        property current_group : UInt16
        property scene_valid : Bool
        property remaining_capacity : UInt8
        property fabric_index : UInt8

        def initialize(
          @scene_count = 0_u8,
          @current_scene = 0xFF_u8,
          @current_group = 0_u16,
          @scene_valid = false,
          @remaining_capacity = 16_u8,
          @fabric_index = 1_u8,
        )
        end
      end

      # Extension field set for scene data
      struct ExtensionFieldSet
        property cluster_id : UInt32
        property attribute_value_list : Array(Tuple(UInt32, Bytes))

        def initialize(@cluster_id, @attribute_value_list = [] of Tuple(UInt32, Bytes))
        end
      end

      # Scene data structure
      struct SceneData
        property transition_time : UInt32 # milliseconds
        property scene_name : String
        property extension_field_sets : Array(ExtensionFieldSet)

        def initialize(
          @transition_time = 0_u32,
          @scene_name = "",
          @extension_field_sets = [] of ExtensionFieldSet,
        )
        end
      end

      # Feature map
      property feature_map : Feature

      # Scene storage: {fabric_index, group_id, scene_id} => SceneData
      property scenes : Hash({UInt8, UInt16, UInt8}, SceneData)

      # Per-fabric scene info
      property fabric_scene_info : Hash(UInt8, SceneInfo)

      # Scene table size (total across all fabrics)
      property scene_table_size : UInt16

      # Callback for when scene is recalled
      property on_recall_scene : Proc(UInt16, UInt8, Nil)?

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::SceneNames,
        @scene_table_size : UInt16 = 16_u16,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @scenes = Hash({UInt8, UInt16, UInt8}, SceneData).new
        @fabric_scene_info = Hash(UInt8, SceneInfo).new
      end

      def name : String
        "ScenesManagement"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_SCENE_TABLE_SIZE),
            name: "SceneTableSize",
            type: :uint16,
            writable: false,
            fixed: true
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_FABRIC_SCENE_INFO),
            name: "FabricSceneInfo",
            type: :list,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ADD_SCENE),
            name: "AddScene",
            access: Definitions::AccessControl::EntryPrivilege::Manage
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_VIEW_SCENE),
            name: "ViewScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_REMOVE_SCENE),
            name: "RemoveScene",
            access: Definitions::AccessControl::EntryPrivilege::Manage
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_REMOVE_ALL_SCENES),
            name: "RemoveAllScenes",
            access: Definitions::AccessControl::EntryPrivilege::Manage
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_STORE_SCENE),
            name: "StoreScene",
            access: Definitions::AccessControl::EntryPrivilege::Manage
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_RECALL_SCENE),
            name: "RecallScene"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_GET_SCENE_MEMBERSHIP),
            name: "GetSceneMembership"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_COPY_SCENE),
            name: "CopyScene",
            optional: true,
            access: Definitions::AccessControl::EntryPrivilege::Manage
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_SCENE_TABLE_SIZE
          encode_uint16(@scene_table_size)
        when ATTR_FABRIC_SCENE_INFO
          encode_fabric_scene_info(fabric_index || 1_u8)
        when FEATURE_MAP_ATTR
          encode_uint32(@feature_map.value)
        else
          super(attribute_id, fabric_index)
        end
      end

      protected def encode_cluster_revision_global : Bytes
        encode_uint16(1_u16) # ScenesManagement revision 1
      end

      protected def encode_feature_map_global : Bytes
        encode_uint32(@feature_map.value)
      end

      # Encode FabricSceneInfo as TLV array
      private def encode_fabric_scene_info(fabric_index : UInt8) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Get or create scene info for this fabric
        scene_info = @fabric_scene_info[fabric_index]? || SceneInfo.new(fabric_index: fabric_index)

        writer.start_array(nil)
        # Encode single SceneInfo struct for this fabric
        writer.start_structure(nil)
        writer.put_unsigned_int(0_u8, scene_info.scene_count.to_u32)                  # sceneCount
        writer.put_unsigned_int(1_u8, scene_info.current_scene.to_u32)                # currentScene
        writer.put_unsigned_int(2_u8, scene_info.current_group.to_u32, force_size: 2) # currentGroup (GroupId)
        writer.put(3_u8, scene_info.scene_valid)                                      # sceneValid
        writer.put_unsigned_int(4_u8, scene_info.remaining_capacity.to_u32)           # remainingCapacity
        writer.put_unsigned_int(254_u8, fabric_index.to_u32)                          # fabricIndex
        writer.end_container
        writer.end_container

        io.to_slice
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
          # RecallScene has no response in ScenesManagement
          handle_recall_scene(fields)
        when CMD_GET_SCENE_MEMBERSHIP
          Cluster::CommandResponse.new(CMD_GET_SCENE_MEMBERSHIP_RESPONSE, handle_get_scene_membership(fields))
        when CMD_COPY_SCENE
          Cluster::CommandResponse.new(CMD_COPY_SCENE_RESPONSE, handle_copy_scene(fields))
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      # Parse TLV command fields
      private def parse_command_fields(fields : Bytes) : Hash(UInt8, TLV::Value)?
        return nil if fields.empty?

        begin
          reader = TLV::Reader.new(fields)
          data = reader.get

          if data.is_a?(Hash)
            wrapper = data.as(Hash(TLV::Tag, TLV::Value))
            if wrapper.has_key?("Any")
              inner = wrapper["Any"]
              if inner.is_a?(Hash)
                # Convert TLV::Tag keys to UInt8
                result = {} of UInt8 => TLV::Value
                inner.as(Hash(TLV::Tag, TLV::Value)).each do |k, v|
                  if k.is_a?(UInt8)
                    result[k] = v
                  end
                end
                return result
              end
            end
          end
        rescue
        end
        nil
      end

      # Handle AddScene command
      private def handle_add_scene(fields : Bytes) : Bytes
        parsed = parse_command_fields(fields)
        unless parsed
          return encode_status_response(CMD_ADD_SCENE_RESPONSE, InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end

        group_id = parsed[0_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16
        scene_id = parsed[1_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8
        transition_time = parsed[2_u8]?.try { |v| v.as(Int).to_u32 } || 0_u32
        scene_name = parsed[3_u8]?.try { |v| v.as(String) } || ""

        # Add scene (simplified - using fabric_index 1)
        fabric_index = 1_u8
        key = {fabric_index, group_id, scene_id}

        # Check capacity
        fabric_scenes = @scenes.count { |k, _| k[0] == fabric_index }
        if fabric_scenes >= @scene_table_size && !@scenes.has_key?(key)
          return encode_status_response(CMD_ADD_SCENE_RESPONSE, InteractionModel::StatusCode::ResourceExhausted, group_id, scene_id)
        end

        @scenes[key] = SceneData.new(transition_time, scene_name)
        update_fabric_scene_info(fabric_index)

        encode_status_response(CMD_ADD_SCENE_RESPONSE, InteractionModel::StatusCode::Success, group_id, scene_id)
      end

      # Handle ViewScene command
      private def handle_view_scene(fields : Bytes) : Bytes
        parsed = parse_command_fields(fields)
        unless parsed
          return encode_view_scene_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8, nil)
        end

        group_id = parsed[0_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16
        scene_id = parsed[1_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8

        fabric_index = 1_u8
        key = {fabric_index, group_id, scene_id}

        if scene = @scenes[key]?
          encode_view_scene_response(InteractionModel::StatusCode::Success, group_id, scene_id, scene)
        else
          encode_view_scene_response(InteractionModel::StatusCode::NotFound, group_id, scene_id, nil)
        end
      end

      # Handle RemoveScene command
      private def handle_remove_scene(fields : Bytes) : Bytes
        parsed = parse_command_fields(fields)
        unless parsed
          return encode_status_response(CMD_REMOVE_SCENE_RESPONSE, InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end

        group_id = parsed[0_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16
        scene_id = parsed[1_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8

        fabric_index = 1_u8
        key = {fabric_index, group_id, scene_id}

        if @scenes.delete(key)
          update_fabric_scene_info(fabric_index)
          encode_status_response(CMD_REMOVE_SCENE_RESPONSE, InteractionModel::StatusCode::Success, group_id, scene_id)
        else
          encode_status_response(CMD_REMOVE_SCENE_RESPONSE, InteractionModel::StatusCode::NotFound, group_id, scene_id)
        end
      end

      # Handle RemoveAllScenes command
      private def handle_remove_all_scenes(fields : Bytes) : Bytes
        parsed = parse_command_fields(fields)
        unless parsed
          return encode_remove_all_response(InteractionModel::StatusCode::InvalidCommand, 0_u16)
        end

        group_id = parsed[0_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16

        fabric_index = 1_u8
        @scenes.reject! { |k, _| k[0] == fabric_index && k[1] == group_id }
        update_fabric_scene_info(fabric_index)

        encode_remove_all_response(InteractionModel::StatusCode::Success, group_id)
      end

      # Handle StoreScene command
      private def handle_store_scene(fields : Bytes) : Bytes
        parsed = parse_command_fields(fields)
        unless parsed
          return encode_status_response(CMD_STORE_SCENE_RESPONSE, InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end

        group_id = parsed[0_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16
        scene_id = parsed[1_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8

        fabric_index = 1_u8
        key = {fabric_index, group_id, scene_id}

        # Check capacity
        fabric_scenes = @scenes.count { |k, _| k[0] == fabric_index }
        if fabric_scenes >= @scene_table_size && !@scenes.has_key?(key)
          return encode_status_response(CMD_STORE_SCENE_RESPONSE, InteractionModel::StatusCode::ResourceExhausted, group_id, scene_id)
        end

        @scenes[key] = SceneData.new
        update_fabric_scene_info(fabric_index)

        encode_status_response(CMD_STORE_SCENE_RESPONSE, InteractionModel::StatusCode::Success, group_id, scene_id)
      end

      # Handle RecallScene command
      private def handle_recall_scene(fields : Bytes) : InteractionModel::Status
        parsed = parse_command_fields(fields)
        unless parsed
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
        end

        group_id = parsed[0_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16
        scene_id = parsed[1_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8

        fabric_index = 1_u8
        key = {fabric_index, group_id, scene_id}

        if @scenes.has_key?(key)
          # Update scene info
          info = @fabric_scene_info[fabric_index]? || SceneInfo.new(fabric_index: fabric_index)
          info.current_scene = scene_id
          info.current_group = group_id
          info.scene_valid = true
          @fabric_scene_info[fabric_index] = info

          # Trigger callback
          @on_recall_scene.try(&.call(group_id, scene_id))

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
        end
      end

      # Handle GetSceneMembership command
      private def handle_get_scene_membership(fields : Bytes) : Bytes
        parsed = parse_command_fields(fields)
        unless parsed
          return encode_membership_response(InteractionModel::StatusCode::InvalidCommand, nil, 0_u16, nil)
        end

        group_id = parsed[0_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16

        fabric_index = 1_u8
        scene_list = [] of UInt8
        @scenes.each do |key, _|
          if key[0] == fabric_index && key[1] == group_id
            scene_list << key[2]
          end
        end

        fabric_scenes = @scenes.count { |k, _| k[0] == fabric_index }
        remaining = (@scene_table_size - fabric_scenes).clamp(0, 253).to_u8

        encode_membership_response(InteractionModel::StatusCode::Success, remaining, group_id, scene_list)
      end

      # Handle CopyScene command
      private def handle_copy_scene(fields : Bytes) : Bytes
        parsed = parse_command_fields(fields)
        unless parsed
          return encode_copy_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
        end

        mode = parsed[0_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8
        group_from = parsed[1_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16
        scene_from = parsed[2_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8
        group_to = parsed[3_u8]?.try { |v| v.as(Int).to_u16 } || 0_u16
        scene_to = parsed[4_u8]?.try { |v| v.as(Int).to_u8 } || 0_u8

        fabric_index = 1_u8
        copy_all = (mode & 0x01) != 0

        if copy_all
          # Copy all scenes from group_from to group_to
          @scenes.select { |k, _| k[0] == fabric_index && k[1] == group_from }.each do |key, data|
            new_key = {fabric_index, group_to, key[2]}
            @scenes[new_key] = SceneData.new(data.transition_time, data.scene_name, data.extension_field_sets)
          end
        else
          # Copy single scene
          source_key = {fabric_index, group_from, scene_from}
          if data = @scenes[source_key]?
            dest_key = {fabric_index, group_to, scene_to}
            @scenes[dest_key] = SceneData.new(data.transition_time, data.scene_name, data.extension_field_sets)
          else
            return encode_copy_response(InteractionModel::StatusCode::NotFound, group_from, scene_from)
          end
        end

        update_fabric_scene_info(fabric_index)
        encode_copy_response(InteractionModel::StatusCode::Success, group_from, scene_from)
      end

      # Update fabric scene info after changes
      private def update_fabric_scene_info(fabric_index : UInt8)
        info = @fabric_scene_info[fabric_index]? || SceneInfo.new(fabric_index: fabric_index)
        fabric_scenes = @scenes.count { |k, _| k[0] == fabric_index }
        info.scene_count = fabric_scenes.to_u8
        info.remaining_capacity = (@scene_table_size - fabric_scenes).clamp(0, 253).to_u8
        @fabric_scene_info[fabric_index] = info
        increment_version
      end

      # Response encoding methods using TLV

      private def encode_status_response(response_id : UInt32, status : InteractionModel::StatusCode, group_id : UInt16, scene_id : UInt8) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        writer.start_structure(nil)
        writer.put_unsigned_int(0_u8, status.value.to_u32)            # status
        writer.put_unsigned_int(1_u8, group_id.to_u32, force_size: 2) # groupId
        writer.put_unsigned_int(2_u8, scene_id.to_u32)                # sceneId
        writer.end_container

        io.to_slice
      end

      private def encode_view_scene_response(status : InteractionModel::StatusCode, group_id : UInt16, scene_id : UInt8, scene : SceneData?) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        writer.start_structure(nil)
        writer.put_unsigned_int(0_u8, status.value.to_u32)            # status
        writer.put_unsigned_int(1_u8, group_id.to_u32, force_size: 2) # groupId
        writer.put_unsigned_int(2_u8, scene_id.to_u32)                # sceneId

        if scene && status == InteractionModel::StatusCode::Success
          writer.put_unsigned_int(3_u8, scene.transition_time, force_size: 4) # transitionTime
          writer.put(4_u8, scene.scene_name)                                  # sceneName
          # extensionFieldSetStructs (5) - empty array for now
          writer.start_array(5_u8)
          writer.end_container
        end

        writer.end_container
        io.to_slice
      end

      private def encode_remove_all_response(status : InteractionModel::StatusCode, group_id : UInt16) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        writer.start_structure(nil)
        writer.put_unsigned_int(0_u8, status.value.to_u32)            # status
        writer.put_unsigned_int(1_u8, group_id.to_u32, force_size: 2) # groupId
        writer.end_container

        io.to_slice
      end

      private def encode_membership_response(status : InteractionModel::StatusCode, capacity : UInt8?, group_id : UInt16, scene_list : Array(UInt8)?) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        writer.start_structure(nil)
        writer.put_unsigned_int(0_u8, status.value.to_u32) # status

        if capacity
          writer.put_unsigned_int(1_u8, capacity.to_u32) # capacity
        else
          writer.put(1_u8, nil) # null capacity
        end

        writer.put_unsigned_int(2_u8, group_id.to_u32, force_size: 2) # groupId

        if scene_list && status == InteractionModel::StatusCode::Success
          writer.start_array(3_u8)
          scene_list.each { |s| writer.put_unsigned_int(nil, s.to_u32) }
          writer.end_container
        end

        writer.end_container
        io.to_slice
      end

      private def encode_copy_response(status : InteractionModel::StatusCode, group_from : UInt16, scene_from : UInt8) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        writer.start_structure(nil)
        writer.put_unsigned_int(0_u8, status.value.to_u32)              # status
        writer.put_unsigned_int(1_u8, group_from.to_u32, force_size: 2) # groupIdentifierFrom
        writer.put_unsigned_int(2_u8, scene_from.to_u32)                # sceneIdentifierFrom
        writer.end_container

        io.to_slice
      end

      # Public API

      def scene_count(fabric_index : UInt8 = 1_u8) : Int32
        @scenes.count { |k, _| k[0] == fabric_index }
      end

      def has_scene?(group_id : UInt16, scene_id : UInt8, fabric_index : UInt8 = 1_u8) : Bool
        @scenes.has_key?({fabric_index, group_id, scene_id})
      end

      def invalidate_current_scene(fabric_index : UInt8 = 1_u8)
        if info = @fabric_scene_info[fabric_index]?
          info.scene_valid = false
          @fabric_scene_info[fabric_index] = info
          increment_version
        end
      end
    end
  end
end
