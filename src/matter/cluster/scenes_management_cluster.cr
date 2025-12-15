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

    # TLV-serializable SceneInfo for FabricSceneInfo attribute
    struct SceneInfoTlv
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property scene_count : UInt8

      @[TLV::Field(tag: 1)]
      property current_scene : UInt8

      @[TLV::Field(tag: 2)]
      property current_group : UInt16

      @[TLV::Field(tag: 3)]
      property scene_valid : Bool

      @[TLV::Field(tag: 4)]
      property remaining_capacity : UInt8

      @[TLV::Field(tag: 254)]
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

    # Standard scene status response (AddScene, RemoveScene, StoreScene)
    struct SceneStatusResponse
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property status : UInt8

      @[TLV::Field(tag: 1)]
      property group_id : UInt16

      @[TLV::Field(tag: 2)]
      property scene_id : UInt8

      def initialize(@status : UInt8, @group_id : UInt16, @scene_id : UInt8)
      end
    end

    # ViewScene response
    struct ViewSceneResponseTlv
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property status : UInt8

      @[TLV::Field(tag: 1)]
      property group_id : UInt16

      @[TLV::Field(tag: 2)]
      property scene_id : UInt8

      @[TLV::Field(tag: 3, optional: true)]
      property transition_time : UInt32?

      @[TLV::Field(tag: 4, optional: true)]
      property scene_name : String?

      @[TLV::Field(tag: 5, optional: true)]
      property extension_field_sets : Array(TLV::Any)?

      def initialize(
        @status : UInt8,
        @group_id : UInt16,
        @scene_id : UInt8,
        @transition_time : UInt32? = nil,
        @scene_name : String? = nil,
        @extension_field_sets : Array(TLV::Any)? = nil,
      )
      end
    end

    # RemoveAllScenes response
    struct RemoveAllScenesResponse
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property status : UInt8

      @[TLV::Field(tag: 1)]
      property group_id : UInt16

      def initialize(@status : UInt8, @group_id : UInt16)
      end
    end

    # GetSceneMembership response
    struct GetSceneMembershipResponse
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property status : UInt8

      @[TLV::Field(tag: 1, optional: true)]
      property capacity : UInt8?

      @[TLV::Field(tag: 2)]
      property group_id : UInt16

      @[TLV::Field(tag: 3, optional: true)]
      property scene_list : Array(UInt8)?

      def initialize(
        @status : UInt8,
        @group_id : UInt16,
        @capacity : UInt8? = nil,
        @scene_list : Array(UInt8)? = nil,
      )
      end
    end

    # CopyScene response
    struct CopySceneResponse
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property status : UInt8

      @[TLV::Field(tag: 1)]
      property group_identifier_from : UInt16

      @[TLV::Field(tag: 2)]
      property scene_identifier_from : UInt8

      def initialize(@status : UInt8, @group_identifier_from : UInt16, @scene_identifier_from : UInt8)
      end
    end

    # Command request structs

    struct AddSceneRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property group_id : UInt16

      @[TLV::Field(tag: 1)]
      property scene_id : UInt8

      @[TLV::Field(tag: 2)]
      property transition_time : UInt32

      @[TLV::Field(tag: 3, optional: true)]
      property scene_name : String?

      @[TLV::Field(tag: 4, optional: true)]
      property extension_field_sets : Array(TLV::Any)?
    end

    struct ViewSceneRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property group_id : UInt16

      @[TLV::Field(tag: 1)]
      property scene_id : UInt8
    end

    struct RemoveSceneRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property group_id : UInt16

      @[TLV::Field(tag: 1)]
      property scene_id : UInt8
    end

    struct RemoveAllScenesRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property group_id : UInt16
    end

    struct StoreSceneRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property group_id : UInt16

      @[TLV::Field(tag: 1)]
      property scene_id : UInt8
    end

    struct RecallSceneRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property group_id : UInt16

      @[TLV::Field(tag: 1)]
      property scene_id : UInt8

      @[TLV::Field(tag: 2, optional: true)]
      property transition_time : UInt32?
    end

    struct GetSceneMembershipRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property group_id : UInt16
    end

    struct CopySceneRequest
      include TLV::Serializable

      @[TLV::Field(tag: 0)]
      property mode : UInt8

      @[TLV::Field(tag: 1)]
      property group_identifier_from : UInt16

      @[TLV::Field(tag: 2)]
      property scene_identifier_from : UInt8

      @[TLV::Field(tag: 3)]
      property group_identifier_to : UInt16

      @[TLV::Field(tag: 4)]
      property scene_identifier_to : UInt8
    end

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
        # Get or create scene info for this fabric
        scene_info = @fabric_scene_info[fabric_index]? || SceneInfo.new(fabric_index: fabric_index)

        tlv_info = SceneInfoTlv.new(
          scene_count: scene_info.scene_count,
          current_scene: scene_info.current_scene,
          current_group: scene_info.current_group,
          scene_valid: scene_info.scene_valid,
          remaining_capacity: scene_info.remaining_capacity,
          fabric_index: fabric_index
        )

        # Wrap in array
        TLV::Any.new([TLV::Any.from_slice(tlv_info.to_slice)], nil, as_array: true).to_slice
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

      # Handle AddScene command
      private def handle_add_scene(fields : Bytes) : Bytes
        req = AddSceneRequest.from_slice(fields)

        fabric_index = 1_u8
        key = {fabric_index, req.group_id, req.scene_id}

        # Check capacity
        fabric_scenes = @scenes.count { |k, _| k[0] == fabric_index }
        if fabric_scenes >= @scene_table_size && !@scenes.has_key?(key)
          return encode_status_response(InteractionModel::StatusCode::ResourceExhausted, req.group_id, req.scene_id)
        end

        @scenes[key] = SceneData.new(req.transition_time, req.scene_name || "")
        update_fabric_scene_info(fabric_index)

        encode_status_response(InteractionModel::StatusCode::Success, req.group_id, req.scene_id)
      rescue
        encode_status_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
      end

      # Handle ViewScene command
      private def handle_view_scene(fields : Bytes) : Bytes
        req = ViewSceneRequest.from_slice(fields)

        fabric_index = 1_u8
        key = {fabric_index, req.group_id, req.scene_id}

        if scene = @scenes[key]?
          encode_view_scene_response(InteractionModel::StatusCode::Success, req.group_id, req.scene_id, scene)
        else
          encode_view_scene_response(InteractionModel::StatusCode::NotFound, req.group_id, req.scene_id, nil)
        end
      rescue
        encode_view_scene_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8, nil)
      end

      # Handle RemoveScene command
      private def handle_remove_scene(fields : Bytes) : Bytes
        req = RemoveSceneRequest.from_slice(fields)

        fabric_index = 1_u8
        key = {fabric_index, req.group_id, req.scene_id}

        if @scenes.delete(key)
          update_fabric_scene_info(fabric_index)
          encode_status_response(InteractionModel::StatusCode::Success, req.group_id, req.scene_id)
        else
          encode_status_response(InteractionModel::StatusCode::NotFound, req.group_id, req.scene_id)
        end
      rescue
        encode_status_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
      end

      # Handle RemoveAllScenes command
      private def handle_remove_all_scenes(fields : Bytes) : Bytes
        req = RemoveAllScenesRequest.from_slice(fields)

        fabric_index = 1_u8
        @scenes.reject! { |k, _| k[0] == fabric_index && k[1] == req.group_id }
        update_fabric_scene_info(fabric_index)

        encode_remove_all_response(InteractionModel::StatusCode::Success, req.group_id)
      rescue
        encode_remove_all_response(InteractionModel::StatusCode::InvalidCommand, 0_u16)
      end

      # Handle StoreScene command
      private def handle_store_scene(fields : Bytes) : Bytes
        req = StoreSceneRequest.from_slice(fields)

        fabric_index = 1_u8
        key = {fabric_index, req.group_id, req.scene_id}

        # Check capacity
        fabric_scenes = @scenes.count { |k, _| k[0] == fabric_index }
        if fabric_scenes >= @scene_table_size && !@scenes.has_key?(key)
          return encode_status_response(InteractionModel::StatusCode::ResourceExhausted, req.group_id, req.scene_id)
        end

        @scenes[key] = SceneData.new
        update_fabric_scene_info(fabric_index)

        encode_status_response(InteractionModel::StatusCode::Success, req.group_id, req.scene_id)
      rescue
        encode_status_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
      end

      # Handle RecallScene command
      private def handle_recall_scene(fields : Bytes) : InteractionModel::Status
        req = RecallSceneRequest.from_slice(fields)

        fabric_index = 1_u8
        key = {fabric_index, req.group_id, req.scene_id}

        if @scenes.has_key?(key)
          # Update scene info
          info = @fabric_scene_info[fabric_index]? || SceneInfo.new(fabric_index: fabric_index)
          info.current_scene = req.scene_id
          info.current_group = req.group_id
          info.scene_valid = true
          @fabric_scene_info[fabric_index] = info

          # Trigger callback
          @on_recall_scene.try(&.call(req.group_id, req.scene_id))

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
        end
      rescue
        InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
      end

      # Handle GetSceneMembership command
      private def handle_get_scene_membership(fields : Bytes) : Bytes
        req = GetSceneMembershipRequest.from_slice(fields)

        fabric_index = 1_u8
        scene_list = [] of UInt8
        @scenes.each do |key, _|
          if key[0] == fabric_index && key[1] == req.group_id
            scene_list << key[2]
          end
        end

        fabric_scenes = @scenes.count { |k, _| k[0] == fabric_index }
        remaining = (@scene_table_size - fabric_scenes).clamp(0, 253).to_u8

        encode_membership_response(InteractionModel::StatusCode::Success, remaining, req.group_id, scene_list)
      rescue
        encode_membership_response(InteractionModel::StatusCode::InvalidCommand, nil, 0_u16, nil)
      end

      # Handle CopyScene command
      private def handle_copy_scene(fields : Bytes) : Bytes
        req = CopySceneRequest.from_slice(fields)

        fabric_index = 1_u8
        copy_all = (req.mode & 0x01) != 0

        if copy_all
          # Copy all scenes from group_from to group_to
          @scenes.select { |k, _| k[0] == fabric_index && k[1] == req.group_identifier_from }.each do |key, data|
            new_key = {fabric_index, req.group_identifier_to, key[2]}
            @scenes[new_key] = SceneData.new(data.transition_time, data.scene_name, data.extension_field_sets)
          end
        else
          # Copy single scene
          source_key = {fabric_index, req.group_identifier_from, req.scene_identifier_from}
          if data = @scenes[source_key]?
            dest_key = {fabric_index, req.group_identifier_to, req.scene_identifier_to}
            @scenes[dest_key] = SceneData.new(data.transition_time, data.scene_name, data.extension_field_sets)
          else
            return encode_copy_response(InteractionModel::StatusCode::NotFound, req.group_identifier_from, req.scene_identifier_from)
          end
        end

        update_fabric_scene_info(fabric_index)
        encode_copy_response(InteractionModel::StatusCode::Success, req.group_identifier_from, req.scene_identifier_from)
      rescue
        encode_copy_response(InteractionModel::StatusCode::InvalidCommand, 0_u16, 0_u8)
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

      # Response encoding methods using TLV::Serializable

      private def encode_status_response(status : InteractionModel::StatusCode, group_id : UInt16, scene_id : UInt8) : Bytes
        SceneStatusResponse.new(status.value, group_id, scene_id).to_slice
      end

      private def encode_view_scene_response(status : InteractionModel::StatusCode, group_id : UInt16, scene_id : UInt8, scene : SceneData?) : Bytes
        if scene && status == InteractionModel::StatusCode::Success
          ViewSceneResponseTlv.new(
            status: status.value,
            group_id: group_id,
            scene_id: scene_id,
            transition_time: scene.transition_time,
            scene_name: scene.scene_name,
            extension_field_sets: [] of TLV::Any
          ).to_slice
        else
          ViewSceneResponseTlv.new(
            status: status.value,
            group_id: group_id,
            scene_id: scene_id
          ).to_slice
        end
      end

      private def encode_remove_all_response(status : InteractionModel::StatusCode, group_id : UInt16) : Bytes
        RemoveAllScenesResponse.new(status.value, group_id).to_slice
      end

      private def encode_membership_response(status : InteractionModel::StatusCode, capacity : UInt8?, group_id : UInt16, scene_list : Array(UInt8)?) : Bytes
        list = if scene_list && status == InteractionModel::StatusCode::Success
                 scene_list
               else
                 nil
               end
        GetSceneMembershipResponse.new(
          status: status.value,
          group_id: group_id,
          capacity: capacity,
          scene_list: list
        ).to_slice
      end

      private def encode_copy_response(status : InteractionModel::StatusCode, group_from : UInt16, scene_from : UInt8) : Bytes
        CopySceneResponse.new(status.value, group_from, scene_from).to_slice
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
