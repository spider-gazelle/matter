require "./cluster"
require "./definitions/groups"

module Matter
  module Cluster
    # Groups Cluster Implementation (0x0004)
    # Manages group membership for multicast communication
    class GroupsCluster < Base
      CLUSTER_ID = 0x0004_u32

      # Attribute IDs
      NAME_SUPPORT = 0x0000_u32

      # Command IDs
      CMD_ADD_GROUP                = 0x00_u32
      CMD_VIEW_GROUP               = 0x01_u32
      CMD_GET_GROUP_MEMBERSHIP     = 0x02_u32
      CMD_REMOVE_GROUP             = 0x03_u32
      CMD_REMOVE_ALL_GROUPS        = 0x04_u32
      CMD_ADD_GROUP_IF_IDENTIFYING = 0x05_u32

      # Response IDs
      CMD_ADD_GROUP_RESPONSE            = 0x00_u32
      CMD_VIEW_GROUP_RESPONSE           = 0x01_u32
      CMD_GET_GROUP_MEMBERSHIP_RESPONSE = 0x02_u32
      CMD_REMOVE_GROUP_RESPONSE         = 0x03_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      # Group storage: GroupId => GroupName
      property groups : Hash(UInt16, String)
      property name_support : Bool

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @name_support : Bool = true,
        max_groups : UInt8 = 16_u8,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @groups = Hash(UInt16, String).new
        @max_groups = max_groups
        @attribute_values[NAME_SUPPORT] = encode_uint8(@name_support ? 0x80_u8 : 0x00_u8)
      end

      def name : String
        "Groups"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            id: DataType::AttributeId.new(NAME_SUPPORT),
            name: "NameSupport",
            type: :uint8,
            writable: false,
            default: encode_uint8(0x80_u8) # Bit 7 set = names supported
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(CLUSTER_REVISION),
            name: "ClusterRevision",
            type: :uint16,
            writable: false,
            default: encode_uint16(4_u16)
          ),
          AttributeMetadata.new(
            id: DataType::AttributeId.new(FEATURE_MAP),
            name: "FeatureMap",
            type: :uint32,
            writable: false,
            default: encode_uint32(0_u32)
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ADD_GROUP),
            name: "AddGroup"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_VIEW_GROUP),
            name: "ViewGroup"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_GET_GROUP_MEMBERSHIP),
            name: "GetGroupMembership"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_REMOVE_GROUP),
            name: "RemoveGroup"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_REMOVE_ALL_GROUPS),
            name: "RemoveAllGroups"
          ),
          CommandMetadata.new(
            id: DataType::CommandId.new(CMD_ADD_GROUP_IF_IDENTIFYING),
            name: "AddGroupIfIdentifying"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when NAME_SUPPORT
          encode_uint8(@name_support ? 0x80_u8 : 0x00_u8)
        else
          super(attribute_id)
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Bytes
        case command_id
        when CMD_ADD_GROUP
          # Simplified: extract group_id from first 2 bytes, group_name from rest
          # Real implementation would properly decode TLV
          if fields.size >= 2
            group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
            group_name = fields.size > 2 ? String.new(fields[2..]) : ""

            status = add_group(group_id, group_name)

            # Return AddGroupResponse
            encode_add_group_response(status, group_id)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
          end
        when CMD_VIEW_GROUP
          # Extract group_id
          if fields.size >= 2
            group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
            view_group(group_id)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
          end
        when CMD_GET_GROUP_MEMBERSHIP
          # Simplified: return all groups
          get_group_membership
        when CMD_REMOVE_GROUP
          # Extract group_id
          if fields.size >= 2
            group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
            status = remove_group(group_id)

            # Return RemoveGroupResponse
            encode_remove_group_response(status, group_id)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
          end
        when CMD_REMOVE_ALL_GROUPS
          remove_all_groups
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when CMD_ADD_GROUP_IF_IDENTIFYING
          # Simplified: always add (would check if device is identifying)
          if fields.size >= 2
            group_id = IO::ByteFormat::LittleEndian.decode(UInt16, fields[0, 2])
            group_name = fields.size > 2 ? String.new(fields[2..]) : ""
            add_group(group_id, group_name)
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
          end
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      # Add a group
      private def add_group(group_id : UInt16, group_name : String) : InteractionModel::StatusCode
        if @groups.size >= @max_groups && !@groups.has_key?(group_id)
          return InteractionModel::StatusCode::ResourceExhausted
        end

        @groups[group_id] = group_name
        increment_version
        InteractionModel::StatusCode::Success
      end

      # View a group
      private def view_group(group_id : UInt16) : Bytes
        if group_name = @groups[group_id]?
          # Return ViewGroupResponse with Success
          io = IO::Memory.new
          io.write_byte(InteractionModel::StatusCode::Success.value)
          IO::ByteFormat::LittleEndian.encode(group_id, io)
          io.write(group_name.to_slice)
          io.to_slice
        else
          # Return ViewGroupResponse with NotFound
          io = IO::Memory.new
          io.write_byte(InteractionModel::StatusCode::NotFound.value)
          IO::ByteFormat::LittleEndian.encode(group_id, io)
          io.to_slice
        end
      end

      # Get group membership
      private def get_group_membership : Bytes
        capacity = (@max_groups - @groups.size).to_u8

        # Return GetGroupMembershipResponse
        io = IO::Memory.new
        io.write_byte(capacity)
        io.write_byte(@groups.size.to_u8)
        @groups.keys.each do |group_id|
          IO::ByteFormat::LittleEndian.encode(group_id, io)
        end
        io.to_slice
      end

      # Remove a group
      private def remove_group(group_id : UInt16) : InteractionModel::StatusCode
        if @groups.delete(group_id)
          increment_version
          InteractionModel::StatusCode::Success
        else
          InteractionModel::StatusCode::NotFound
        end
      end

      # Remove all groups
      private def remove_all_groups
        @groups.clear
        increment_version
      end

      # Encode AddGroupResponse
      private def encode_add_group_response(status : InteractionModel::StatusCode, group_id : UInt16) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.to_slice
      end

      # Encode RemoveGroupResponse
      private def encode_remove_group_response(status : InteractionModel::StatusCode, group_id : UInt16) : Bytes
        io = IO::Memory.new
        io.write_byte(status.value)
        IO::ByteFormat::LittleEndian.encode(group_id, io)
        io.to_slice
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
