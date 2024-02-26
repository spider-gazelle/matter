module Matter
  module Cluster
    module Definitions
      module Scenes
        alias StatusCode = Protocol::Interaction::StatusCode

        # This data type indicates a combination of an identifier and the value of an attribute.
        struct AttributeValuePair
          include TLV::Serializable

          # This field shall be present or not present, for all instances in the Scenes cluster. If this field is not
          # present, then the data type of AttributeValue shall be determined by the order and data type defined in the
          # cluster specification. Otherwise the data type of AttributeValue shall be the data type of the attribute
          # indicated by AttributeID.
          @[TLV::Field(tag: 0)]
          property attribute_id : DataType::AttributeId

          # This is the attribute value as part of an extension field set. See AttributeID to determine the data type
          # for this field.
          @[TLV::Field(tag: 1)]
          property attribute_value : TLV::Value
        end

        # This data type indicates for a given cluster a set of attributes and their values. Only attributes which have
        # the "S" designation in the Quality column of the cluster specification shall be used in the AttributeValueList
        # field.
        struct ExtensionFieldSet
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property cluster_id : DataType::ClusterId

          @[TLV::Field(tag: 1)]
          property attribute_value_list : Array(AttributeValuePair)
        end

        # Input to the Scenes addScene command
        struct AddSceneRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 1)]
          property scene_id : UInt8

          @[TLV::Field(tag: 2)]
          property transition_time : UInt16

          @[TLV::Field(tag: 3)]
          property scene_name : String

          @[TLV::Field(tag: 4)]
          property extension_field_sets : ExtensionFieldSet
        end

        struct AddSceneResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 2)]
          property scene_id : UInt8
        end

        struct ViewSceneRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 1)]
          property scene_id : UInt8
        end

        struct ViewSceneResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 2)]
          property scene_id : UInt8

          @[TLV::Field(tag: 3)]
          property transition_time : UInt16

          @[TLV::Field(tag: 4)]
          property scene_name : String?

          @[TLV::Field(tag: 5)]
          property extension_field_sets : Array(ExtensionFieldSet)?
        end

        struct RemoveSceneRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 1)]
          property scene_id : UInt8
        end

        # Input to the Scenes removeScene command
        struct RemoveSceneRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 1)]
          property scene_id : UInt8
        end

        struct RemoveSceneResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 2)]
          property scene_id : UInt8
        end

        struct RemoveAllScenesRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_id : DataType::GroupId
        end

        struct RemoveAllScenesResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property group_id : DataType::GroupId
        end

        struct StoreSceneRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 1)]
          property scene_id : UInt8
        end

        struct StoreSceneResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 2)]
          property scene_id : UInt8
        end

        # Input to the Scenes recallScene command
        struct RecallSceneRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 1)]
          property scene_id : UInt8

          @[TLV::Field(tag: 2)]
          property transition_time : UInt16?
        end

        # The fields of the get scene membership response command have the following semantics:
        #
        # The Capacity field shall contain the remaining capacity of the Scene Table of the server (for all groups). The
        # following values apply:
        #
        #   • 0 - No further scenes may be added.
        #
        #   • 0 < Capacity < 0xfe - Capacity holds the number of scenes that may be added.
        #
        #   • 0xfe - At least 1 further scene may be added (exact number is unknown).
        #
        #   • null - It is unknown if any further scenes may be added.
        #
        # The Status field shall contain SUCCESS or ILLEGAL_COMMAND (the endpoint is not a member of the group) as
        # appropriate.
        #
        # The GroupID field shall be set to the corresponding field of the received GetSceneMembership command.
        #
        # If the status is not SUCCESS then the SceneList field shall be omitted, else the SceneList field shall contain
        # the identifiers of all the scenes in the Scene Table with the corresponding Group ID.
        #
        # Zigbee: If the total number of scenes associated with this Group ID will cause the maximum payload length of a
        # frame to be exceeded, then the SceneList field shall contain only as many scenes as will fit.
        struct GetSceneMembershipResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          @[TLV::Field(tag: 1)]
          property capacity : UInt8?

          @[TLV::Field(tag: 2)]
          property group_id : DataType::GroupId

          @[TLV::Field(tag: 3)]
          property sceneList : Array(UInt8)?
        end

        # Input to the Scenes copyScene command
        struct CopySceneRequest
          include TLV::Serializable

          # The Mode field contains information of how the scene copy is to proceed. This field shall be formatted as
          # illustrated in Format of the Mode Field of the CopyScene Command.
          #
          # The CopyAllScenes subfield is 1-bit in length and indicates whether all scenes are to be copied. If this
          # value is set to 1, all scenes are to be copied and the SceneIdentifierFrom and SceneIdentifierTo fields
          # shall be ignored. Otherwise this field is set to 0.
          @[TLV::Field(tag: 0)]
          property mode : UInt8

          # The GroupIdentifierFrom field specifies the identifier of the group from which the scene is to be copied.
          # Together with the SceneIdentifierFrom field, this field uniquely identifies the scene to copy from the Scene
          # Table.
          @[TLV::Field(tag: 1)]
          property group_identifier_from : DataType::GroupId

          # The SceneIdentifierFrom field specifies the identifier of the scene from which the scene is to be copied.
          # Together with the GroupIdentifierFrom field, this field uniquely identifies the scene to copy from the Scene
          # Table.
          @[TLV::Field(tag: 2)]
          property scene_identifier_from : UInt8

          # The GroupIdentifierTo field specifies the identifier of the group to which the scene is to be copied.
          # Together with the SceneIdentifierTo field, this field uniquely identifies the scene to copy to the Scene
          # Table.
          @[TLV::Field(tag: 3)]
          property group_identifier_to : DataType::GroupId

          # The SceneIdentifierTo field specifies the identifier of the scene to which the scene is to be copied.
          # Together with the GroupIdentifierTo field, this field uniquely identifies the scene to copy to the Scene
          # Table.
          @[TLV::Field(tag: 4)]
          property scene_identifier_to : UInt8
        end

        struct CopySceneResponse
          include TLV::Serializable

          # The Status field contains the status of the copy scene attempt. This field shall be set to one of the
          # non-reserved values listed in Values of the Status Field of the CopySceneResponse Command.
          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          # The GroupIdentifierFrom field specifies the identifier of the group from which the scene was copied, as
          # specified in the CopyScene command. Together with the SceneIdentifierFrom field, this field uniquely
          # identifies the scene that was copied from the Scene Table.
          @[TLV::Field(tag: 1)]
          property group_identifier_from : DataType::GroupId

          # The SceneIdentifierFrom field is specifies the identifier of the scene from which the scene was copied, as
          # specified in the CopyScene command. Together with the GroupIdentifierFrom field, this field uniquely
          # identifies the scene that was copied from the Scene Table.
          @[TLV::Field(tag: 2)]
          property scene_identifier_from : UInt8
        end
      end
    end
  end
end
