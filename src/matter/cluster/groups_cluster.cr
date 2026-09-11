require "./cluster"
require "tlv"
require "./definitions/groups"

module Matter
  module Cluster
    # Groups Cluster Implementation (0x0004)
    # Manages group membership for multicast communication
    #
    # Features:
    # - GroupNames (GN): Store names for groups
    #
    # Specification: Matter 1.4 § 1.3
    class GroupsCluster < Base
      cluster 0x0004, revision: 4, persist_state: false

      feature :group_names, bit: 0 # GN - Store names for groups

      @[Flags]
      enum NameSupport : UInt8
        GroupNames = 0x01
      end

      # Group 0 is reserved and names are bounded in UTF-8 bytes (Matter 1.4 §1.3.7.1).
      GROUP_ID_MIN          = 1_u16
      GROUP_NAME_MAX_LENGTH =    16
      DEFAULT_MAX_GROUPS    = 16_u8

      attribute 0x0000, :name_support, NameSupport, default: NameSupport::None

      command 0x00, :add_group, request: Definitions::Groups::AddGroupRequest, response: Definitions::Groups::AddGroupResponse
      command 0x01, :view_group, request: Definitions::Groups::ViewGroupRequest, response: Definitions::Groups::ViewGroupResponse
      command 0x02, :get_group_membership, request: Definitions::Groups::GetGroupMembershipRequest, response: Definitions::Groups::GetGroupMembershipResponse
      command 0x03, :remove_group, request: Definitions::Groups::RemoveGroupRequest, response: Definitions::Groups::RemoveGroupResponse
      command 0x04, :remove_all_groups
      command 0x05, :add_group_if_identifying, request: Definitions::Groups::AddGroupIfIdentifyingRequest

      # Group storage: GroupId => GroupName
      property groups : Hash(UInt16, String)

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::GroupNames,
        @max_groups : UInt8 = DEFAULT_MAX_GROUPS,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @groups = Hash(UInt16, String).new
        @name_support = @feature_map.group_names? ? NameSupport::GroupNames : NameSupport::None
      end

      # ------------------------------------------------------------------------
      # Commands
      # ------------------------------------------------------------------------

      def add_group(request : Definitions::Groups::AddGroupRequest) : Definitions::Groups::AddGroupResponse
        status = store_group(request.group_id.id, request.group_name)
        Definitions::Groups::AddGroupResponse.new(status, request.group_id)
      end

      def view_group(request : Definitions::Groups::ViewGroupRequest) : Definitions::Groups::ViewGroupResponse
        group_id = request.group_id.id
        group_name = @groups[group_id]?
        status = if !valid_group_id?(group_id)
                   InteractionModel::StatusCode::ConstraintError
                 elsif group_name
                   InteractionModel::StatusCode::Success
                 else
                   InteractionModel::StatusCode::NotFound
                 end
        Definitions::Groups::ViewGroupResponse.new(status, request.group_id, group_name || "")
      end

      def get_group_membership(request : Definitions::Groups::GetGroupMembershipRequest) : Definitions::Groups::GetGroupMembershipResponse
        requested = request.group_list.map(&.id)
        members = @groups.keys.select { |id| requested.empty? || requested.includes?(id) }.map { |id| DataType::GroupId.new(id) }
        capacity = (@max_groups - @groups.size).to_u8
        Definitions::Groups::GetGroupMembershipResponse.new(capacity, members)
      end

      def remove_group(request : Definitions::Groups::RemoveGroupRequest) : Definitions::Groups::RemoveGroupResponse
        status = delete_group(request.group_id.id)
        Definitions::Groups::RemoveGroupResponse.new(status, request.group_id)
      end

      def remove_all_groups : InteractionModel::Status
        @groups.clear
        increment_version
        InteractionModel::Status.success
      end

      # No response struct is defined for this command, so the outcome is the command status.
      def add_group_if_identifying(request : Definitions::Groups::AddGroupIfIdentifyingRequest) : InteractionModel::Status
        InteractionModel::Status.new(store_group(request.group_id.id, request.group_name))
      end

      private def valid_group_id?(group_id : UInt16) : Bool
        group_id >= GROUP_ID_MIN
      end

      private def store_group(group_id : UInt16, group_name : String) : InteractionModel::StatusCode
        unless valid_group_id?(group_id) && group_name.bytesize <= GROUP_NAME_MAX_LENGTH
          return InteractionModel::StatusCode::ConstraintError
        end
        if @groups.size >= @max_groups && !@groups.has_key?(group_id)
          return InteractionModel::StatusCode::ResourceExhausted
        end

        @groups[group_id] = group_name
        increment_version
        InteractionModel::StatusCode::Success
      end

      private def delete_group(group_id : UInt16) : InteractionModel::StatusCode
        return InteractionModel::StatusCode::ConstraintError unless valid_group_id?(group_id)
        if @groups.delete(group_id)
          increment_version
          InteractionModel::StatusCode::Success
        else
          InteractionModel::StatusCode::NotFound
        end
      end

      # ------------------------------------------------------------------------
      # Persistence support
      # ------------------------------------------------------------------------

      private struct PersistedState
        include Storage::Record

        getter groups : Hash(UInt16, String)
        getter data_version : UInt32

        def initialize(
          @groups : Hash(UInt16, String),
          @data_version : UInt32,
        )
        end
      end

      def save_state : Storage::Document?
        PersistedState.new(@groups, @data_version).to_document
      end

      def restore_state(document : Storage::Document) : Nil
        state = PersistedState.from_document(document)
        @groups = state.groups
        @data_version = state.data_version
      rescue ex
        Log.warn(exception: ex) { "Groups restore_state failed; starting fresh" }
      end

      # Public API
      def member_of?(group_id : UInt16) : Bool
        @groups.has_key?(group_id)
      end

      def group_count : Int32
        @groups.size
      end
    end
  end
end
