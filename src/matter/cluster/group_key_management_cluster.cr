require "./cluster"
require "log"

module Matter
  module Cluster
    # Group Key Management Cluster (0x003F)
    # Matter Core Specification §11.2
    #
    # Manages group keys for secure group communication:
    # - Group key sets for shared encryption keys
    # - Mapping between groups and key sets
    # - Identity Protection Keys (IPK) for CASE session establishment
    # - Operational group keys for group messaging
    #
    # Key Features:
    # - Fabric-scoped: All data isolated per fabric
    # - IPK Protection: KeySet 0 (IPK) cannot be removed
    # - Strict Validation: Epoch keys must be ordered, security policies enforced
    # - Cryptographic Operations: HKDF-based key derivation for operational keys
    class GroupKeyManagementCluster < Base
      CLUSTER_ID = 0x003F_u32

      # Feature flags for Group Key Management cluster
      @[Flags]
      enum Feature : UInt32
        CacheAndSync = 0x01 # Currently provisional/disabled
      end

      # Security policy for group key sets
      # Matter Core Spec §11.2.6.3.1
      enum GroupKeySecurityPolicyEnum : UInt8
        TrustFirst   = 0 # Only valid option in current Matter spec
        CacheAndSync = 1 # Provisional, not currently supported
      end

      # Multicast policy for group addressing
      # Matter Core Spec §11.2.6.3.2
      enum GroupKeyMulticastPolicyEnum : UInt8
        PerGroupId = 0 # One IPv6 multicast address per group (required)
        AllNodes   = 1 # Not supported
      end

      # Group Key Set structure
      # Contains epoch keys and their lifecycle timestamps
      # Matter Core Spec §11.2.6.3
      struct GroupKeySetStruct
        # Unique identifier for this key set (0 = IPK, others = operational)
        property group_key_set_id : UInt16

        # Security policy (MUST be TrustFirst in current spec)
        property group_key_security_policy : GroupKeySecurityPolicyEnum

        # Epoch key 0 (most recent, required, 16 bytes)
        property epoch_key0 : Bytes?

        # Epoch start time for key 0 (microseconds since epoch)
        property epoch_start_time0 : UInt64?

        # Epoch key 1 (second newest, optional, 16 bytes)
        property epoch_key1 : Bytes?

        # Epoch start time for key 1
        property epoch_start_time1 : UInt64?

        # Epoch key 2 (third newest, optional, 16 bytes)
        property epoch_key2 : Bytes?

        # Epoch start time for key 2
        property epoch_start_time2 : UInt64?

        # Multicast policy (currently unused, defaults to PerGroupId)
        property group_key_multicast_policy : GroupKeyMulticastPolicyEnum?

        def initialize(
          @group_key_set_id : UInt16,
          @group_key_security_policy : GroupKeySecurityPolicyEnum = GroupKeySecurityPolicyEnum::TrustFirst,
          @epoch_key0 : Bytes? = nil,
          @epoch_start_time0 : UInt64? = nil,
          @epoch_key1 : Bytes? = nil,
          @epoch_start_time1 : UInt64? = nil,
          @epoch_key2 : Bytes? = nil,
          @epoch_start_time2 : UInt64? = nil,
          @group_key_multicast_policy : GroupKeyMulticastPolicyEnum? = GroupKeyMulticastPolicyEnum::PerGroupId,
        )
        end

        # Validate that this key set meets all Matter spec requirements
        def validate! : Nil
          # Validation 1: Epoch keys must be exactly 16 bytes if present
          validate_key_length!(epoch_key0, "epoch_key0")
          validate_key_length!(epoch_key1, "epoch_key1")
          validate_key_length!(epoch_key2, "epoch_key2")

          # Validation 2: Epoch keys and start times must be paired
          # (both null or both set)
          validate_key_time_pairing!("key0", epoch_key0, epoch_start_time0)
          validate_key_time_pairing!("key1", epoch_key1, epoch_start_time1)
          validate_key_time_pairing!("key2", epoch_key2, epoch_start_time2)

          # Validation 3: Epoch start times cannot be 0 if set
          validate_nonzero_time!(epoch_start_time0, "epoch_start_time0")
          validate_nonzero_time!(epoch_start_time1, "epoch_start_time1")
          validate_nonzero_time!(epoch_start_time2, "epoch_start_time2")

          # Validation 4: Epoch start times must be strictly ordered if set
          # (start0 < start1 < start2)
          validate_epoch_ordering!

          # Validation 5: Security policy must be TrustFirst
          # (CacheAndSync not currently supported)
          if group_key_security_policy != GroupKeySecurityPolicyEnum::TrustFirst
            raise ArgumentError.new("Only TrustFirst security policy is supported")
          end

          # Validation 6: Multicast policy must be PerGroupId if set
          if mcast = group_key_multicast_policy
            if mcast != GroupKeyMulticastPolicyEnum::PerGroupId
              raise ArgumentError.new("Only PerGroupId multicast policy is supported")
            end
          end
        end

        private def validate_key_length!(key : Bytes?, name : String) : Nil
          return unless key
          unless key.size == 16
            raise ArgumentError.new("#{name} must be exactly 16 bytes, got #{key.size}")
          end
        end

        private def validate_key_time_pairing!(name : String, key : Bytes?, time : UInt64?) : Nil
          if key.nil? != time.nil?
            raise ArgumentError.new("#{name} and its start time must both be set or both be null")
          end
        end

        private def validate_nonzero_time!(time : UInt64?, name : String) : Nil
          return unless time
          if time == 0
            raise ArgumentError.new("#{name} cannot be 0")
          end
        end

        private def validate_epoch_ordering! : Nil
          times = [] of UInt64
          times << epoch_start_time0.not_nil! if epoch_start_time0
          times << epoch_start_time1.not_nil! if epoch_start_time1
          times << epoch_start_time2.not_nil! if epoch_start_time2

          # Check strict ordering: each time must be less than the next
          (0...times.size - 1).each do |i|
            unless times[i] < times[i + 1]
              raise ArgumentError.new("Epoch start times must be strictly ordered (start0 < start1 < start2)")
            end
          end
        end
      end

      # Group Key Map entry
      # Maps a group ID to a key set ID within a fabric
      # Matter Core Spec §11.2.6.4
      struct GroupKeyMapStruct
        # Group identifier (1-65535, 0 is invalid)
        property group_id : UInt16

        # Key set to use for this group (0 = IPK, others = operational)
        property group_key_set_id : UInt16

        # Fabric index for isolation (automatically set by cluster)
        property fabric_index : UInt8

        def initialize(@group_id : UInt16, @group_key_set_id : UInt16, @fabric_index : UInt8 = 0)
          validate!
        end

        def validate! : Nil
          if group_id == 0
            raise ArgumentError.new("Group ID 0 is reserved and invalid")
          end
        end
      end

      # Group Info Map entry
      # Represents a group with its endpoints and name
      # Matter Core Spec §11.2.6.5
      struct GroupInfoMapStruct
        # Group identifier
        property group_id : UInt16

        # List of endpoint IDs that are part of this group
        property endpoints : Array(UInt16)

        # Optional group name
        property group_name : String?

        # Fabric index for isolation
        property fabric_index : UInt8

        def initialize(
          @group_id : UInt16,
          @endpoints : Array(UInt16) = [] of UInt16,
          @group_name : String? = nil,
          @fabric_index : UInt8 = 0,
        )
        end
      end

      # KeySetWrite command request
      # Matter Core Spec §11.2.8.1
      struct KeySetWriteRequest
        property group_key_set : GroupKeySetStruct

        def initialize(@group_key_set : GroupKeySetStruct)
        end
      end

      # KeySetRead command request
      # Matter Core Spec §11.2.8.2
      struct KeySetReadRequest
        property group_key_set_id : UInt16

        def initialize(@group_key_set_id : UInt16)
        end
      end

      # KeySetRead command response
      # Returns the key set without actual key material (secure)
      # Matter Core Spec §11.2.8.2
      struct KeySetReadResponse
        property group_key_set : GroupKeySetStruct

        def initialize(@group_key_set : GroupKeySetStruct)
        end
      end

      # KeySetRemove command request
      # Matter Core Spec §11.2.8.3
      struct KeySetRemoveRequest
        property group_key_set_id : UInt16

        def initialize(@group_key_set_id : UInt16)
        end
      end

      # KeySetReadAllIndices command response
      # Returns list of all key set IDs for the accessing fabric
      # Matter Core Spec §11.2.8.4
      struct KeySetReadAllIndicesResponse
        property group_key_set_i_ds : Array(UInt16)

        def initialize(@group_key_set_i_ds : Array(UInt16) = [] of UInt16)
        end
      end

      # Cluster state
      property features : Feature
      property max_groups_per_fabric : UInt16
      property max_group_keys_per_fabric : UInt16

      # Internal storage (fabric-scoped)
      # Key: fabricIndex, Value: GroupKeySetStruct (with actual keys stored)
      @key_sets : Hash(UInt8, Hash(UInt16, GroupKeySetStruct))

      # Group key map (fabric-scoped)
      @group_key_map : Array(GroupKeyMapStruct)

      # Group table (fabric-scoped, read-only)
      @group_table : Array(GroupInfoMapStruct)

      # Initialize the cluster
      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @features : Feature = Feature::None,
        @max_groups_per_fabric : UInt16 = 12_u16,
        @max_group_keys_per_fabric : UInt16 = 3_u16,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @key_sets = Hash(UInt8, Hash(UInt16, GroupKeySetStruct)).new
        @group_key_map = [] of GroupKeyMapStruct
        @group_table = [] of GroupInfoMapStruct
      end

      def name : String
        "GroupKeyManagement"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(0x0000_u32),
            "GroupKeyMap",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(0x0001_u32),
            "GroupTable",
            :list,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(0x0002_u32),
            "MaxGroupsPerFabric",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(0x0003_u32),
            "MaxGroupKeysPerFabric",
            :uint16,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(0x00_u32),
            "KeySetWrite"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(0x01_u32),
            "KeySetRead"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(0x03_u32),
            "KeySetRemove"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(0x04_u32),
            "KeySetReadAllIndices"
          ),
        ]
      end

      # Attribute IDs
      ATTR_GROUP_KEY_MAP             = 0x0000_u32
      ATTR_GROUP_TABLE               = 0x0001_u32
      ATTR_MAX_GROUPS_PER_FABRIC     = 0x0002_u32
      ATTR_MAX_GROUP_KEYS_PER_FABRIC = 0x0003_u32

      # Global attributes
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32
      ATTRIBUTE_LIST   = 0xFFFB_u32

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_GROUP_KEY_MAP
          encode_group_key_map(fabric_index || 0_u8)
        when ATTR_GROUP_TABLE
          encode_group_table(fabric_index || 0_u8)
        when ATTR_MAX_GROUPS_PER_FABRIC
          encode_uint16(@max_groups_per_fabric)
        when ATTR_MAX_GROUP_KEYS_PER_FABRIC
          encode_uint16(@max_group_keys_per_fabric)
        when CLUSTER_REVISION
          encode_uint16(2_u16) # GroupKeyManagement cluster revision
        when FEATURE_MAP
          encode_uint32(@features.value)
        when ATTRIBUTE_LIST
          encode_attribute_list
        else
          super
        end
      end

      private def encode_group_key_map(fabric_index : UInt8) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        entries = group_key_map(fabric_index)

        # Use explicit start_array/end_container to ensure empty arrays are properly encoded
        # (writer.put produces 0 bytes for empty arrays, which is incorrect TLV)
        writer.start_array(nil)
        entries.each do |entry|
          writer.start_structure(nil)
          writer.put_unsigned_int(0_u8, entry.group_id)
          writer.put_unsigned_int(1_u8, entry.group_key_set_id)
          writer.put_unsigned_int(254_u8, entry.fabric_index)
          writer.end_container
        end
        writer.end_container

        io.to_slice
      end

      private def encode_group_table(fabric_index : UInt8) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        entries = group_table(fabric_index)

        # Use explicit start_array/end_container to ensure empty arrays are properly encoded
        # (writer.put produces 0 bytes for empty arrays, which is incorrect TLV)
        writer.start_array(nil)
        entries.each do |entry|
          writer.start_structure(nil)
          writer.put_unsigned_int(1_u8, entry.group_id)
          # Endpoints list
          writer.start_array(2_u8)
          entry.endpoints.each { |ep| writer.put_unsigned_int(nil, ep) }
          writer.end_container
          if name = entry.group_name
            writer.put_string(3_u8, name)
          end
          writer.put_unsigned_int(254_u8, entry.fabric_index)
          writer.end_container
        end
        writer.end_container

        io.to_slice
      end

      private def encode_attribute_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        attr_ids = [
          ATTR_GROUP_KEY_MAP,
          ATTR_GROUP_TABLE,
          ATTR_MAX_GROUPS_PER_FABRIC,
          ATTR_MAX_GROUP_KEYS_PER_FABRIC,
          CLUSTER_REVISION,
          FEATURE_MAP,
          ATTRIBUTE_LIST,
        ]

        attr_array = attr_ids.map { |id| id.as(TLV::Value) }
        writer.put(nil, attr_array)
        io.to_slice
      end

      # Get group key map for the specified fabric
      def group_key_map(fabric_index : UInt8) : Array(GroupKeyMapStruct)
        @group_key_map.select { |entry| entry.fabric_index == fabric_index }
      end

      # Get all group key map entries (for testing)
      def group_key_map : Array(GroupKeyMapStruct)
        @group_key_map
      end

      # Get group table for the specified fabric
      def group_table(fabric_index : UInt8) : Array(GroupInfoMapStruct)
        @group_table.select { |entry| entry.fabric_index == fabric_index }
      end

      # Get all group table entries (for testing)
      def group_table : Array(GroupInfoMapStruct)
        @group_table
      end

      # KeySetWrite command handler
      # Matter Core Spec §11.2.8.1
      #
      # Creates or updates a group key set. Performs extensive validation:
      # - Validates key set structure (epoch ordering, key lengths, etc.)
      # - Enforces max_group_keys_per_fabric limit
      # - Prevents creation of duplicate key set IDs within fabric
      # - Security policy must be TrustFirst
      def handle_key_set_write(cmd : KeySetWriteRequest, fabric_index : UInt8) : Nil
        key_set = cmd.group_key_set

        # Validate the key set structure
        key_set.validate!

        # Ensure fabric key sets storage exists
        @key_sets[fabric_index] ||= Hash(UInt16, GroupKeySetStruct).new

        fabric_key_sets = @key_sets[fabric_index]

        # Check resource limits: max_group_keys_per_fabric
        # Don't count the key set being updated
        existing_count = fabric_key_sets.keys.reject { |id| id == key_set.group_key_set_id }.size
        if existing_count >= max_group_keys_per_fabric
          raise ArgumentError.new("Cannot exceed max_group_keys_per_fabric (#{max_group_keys_per_fabric})")
        end

        # Store the key set (create or update)
        fabric_key_sets[key_set.group_key_set_id] = key_set
      end

      # KeySetRead command handler
      # Matter Core Spec §11.2.8.2
      #
      # Returns a key set by ID, but with actual key material removed for security.
      # Returns null if key set not found for this fabric.
      def handle_key_set_read(cmd : KeySetReadRequest, fabric_index : UInt8) : KeySetReadResponse?
        fabric_key_sets = @key_sets[fabric_index]?
        return nil unless fabric_key_sets

        key_set = fabric_key_sets[cmd.group_key_set_id]?
        return nil unless key_set

        # Return key set with actual key bytes removed (security requirement)
        sanitized = GroupKeySetStruct.new(
          group_key_set_id: key_set.group_key_set_id,
          group_key_security_policy: key_set.group_key_security_policy,
          epoch_key0: nil, # Remove actual key material
          epoch_start_time0: key_set.epoch_start_time0,
          epoch_key1: nil,
          epoch_start_time1: key_set.epoch_start_time1,
          epoch_key2: nil,
          epoch_start_time2: key_set.epoch_start_time2,
          group_key_multicast_policy: key_set.group_key_multicast_policy
        )

        KeySetReadResponse.new(sanitized)
      end

      # KeySetRemove command handler
      # Matter Core Spec §11.2.8.3
      #
      # Removes a key set by ID. Special rules:
      # - Cannot remove key set 0 (IPK - Identity Protection Key)
      # - Removes any group key map entries referencing this key set
      # - Returns error if key set not found
      def handle_key_set_remove(cmd : KeySetRemoveRequest, fabric_index : UInt8) : Nil
        # IPK Protection: Cannot remove key set 0 (Identity Protection Key)
        if cmd.group_key_set_id == 0
          raise ArgumentError.new("Cannot remove key set 0 (IPK)")
        end

        fabric_key_sets = @key_sets[fabric_index]?
        unless fabric_key_sets
          raise ArgumentError.new("Key set #{cmd.group_key_set_id} not found")
        end

        unless fabric_key_sets.has_key?(cmd.group_key_set_id)
          raise ArgumentError.new("Key set #{cmd.group_key_set_id} not found")
        end

        # Remove the key set
        fabric_key_sets.delete(cmd.group_key_set_id)

        # Remove any group key map entries referencing this key set
        @group_key_map.reject! do |entry|
          entry.fabric_index == fabric_index &&
            entry.group_key_set_id == cmd.group_key_set_id
        end
      end

      # KeySetReadAllIndices command handler
      # Matter Core Spec §11.2.8.4
      #
      # Returns list of all key set IDs for the accessing fabric.
      def handle_key_set_read_all_indices(fabric_index : UInt8) : KeySetReadAllIndicesResponse
        fabric_key_sets = @key_sets[fabric_index]?
        return KeySetReadAllIndicesResponse.new([] of UInt16) unless fabric_key_sets

        key_set_ids = fabric_key_sets.keys.sort
        KeySetReadAllIndicesResponse.new(key_set_ids)
      end

      # Add or update a group key map entry
      # Links a group to a key set within a fabric
      #
      # Validations:
      # - Group ID must not be 0
      # - Key set must exist in the fabric
      # - Must not exceed max_groups_per_fabric
      def add_group_key_map(
        group_id : UInt16,
        group_key_set_id : UInt16,
        fabric_index : UInt8,
      ) : Nil
        # Validate group ID
        if group_id == 0
          raise ArgumentError.new("Group ID 0 is invalid")
        end

        # Validate that key set exists
        fabric_key_sets = @key_sets[fabric_index]?
        unless fabric_key_sets && fabric_key_sets.has_key?(group_key_set_id)
          raise ArgumentError.new("Key set #{group_key_set_id} does not exist")
        end

        # Check if mapping already exists (update case)
        existing_index = @group_key_map.index do |entry|
          entry.fabric_index == fabric_index && entry.group_id == group_id
        end

        if existing_index
          # Update existing mapping
          @group_key_map[existing_index] = GroupKeyMapStruct.new(
            group_id, group_key_set_id, fabric_index
          )
        else
          # Check resource limit: max_groups_per_fabric
          fabric_groups = @group_key_map.count { |e| e.fabric_index == fabric_index }
          if fabric_groups >= max_groups_per_fabric
            raise ArgumentError.new("Cannot exceed max_groups_per_fabric (#{max_groups_per_fabric})")
          end

          # Add new mapping
          @group_key_map << GroupKeyMapStruct.new(group_id, group_key_set_id, fabric_index)
        end
      end

      # Remove a group key map entry
      def remove_group_key_map(group_id : UInt16, fabric_index : UInt8) : Nil
        @group_key_map.reject! do |entry|
          entry.fabric_index == fabric_index && entry.group_id == group_id
        end
      end

      # Add a group to the group table
      # Called by Groups cluster when AddGroup command is executed
      #
      # Validations:
      # - Group must have a corresponding key map entry
      # - Must not exceed max_groups_per_fabric
      def add_group(
        group_id : UInt16,
        endpoint_id : UInt16,
        group_name : String?,
        fabric_index : UInt8,
      ) : Nil
        # Validate that group has a key map entry
        has_key_map = @group_key_map.any? do |entry|
          entry.fabric_index == fabric_index && entry.group_id == group_id
        end
        unless has_key_map
          raise ArgumentError.new("Group #{group_id} has no key map entry")
        end

        # Find or create group info
        existing = @group_table.find do |entry|
          entry.fabric_index == fabric_index && entry.group_id == group_id
        end

        if existing
          # Add endpoint to existing group if not already present
          unless existing.endpoints.includes?(endpoint_id)
            # Reconstruct with updated endpoints (struct immutability)
            new_endpoints = existing.endpoints + [endpoint_id]
            @group_table.reject! do |entry|
              entry.fabric_index == fabric_index && entry.group_id == group_id
            end
            @group_table << GroupInfoMapStruct.new(
              group_id, new_endpoints, existing.group_name, fabric_index
            )
          end
        else
          # Check resource limit
          fabric_groups = @group_table.count { |e| e.fabric_index == fabric_index }
          if fabric_groups >= max_groups_per_fabric
            raise ArgumentError.new("Cannot exceed max_groups_per_fabric (#{max_groups_per_fabric})")
          end

          # Create new group
          @group_table << GroupInfoMapStruct.new(
            group_id, [endpoint_id], group_name, fabric_index
          )
        end
      end

      # Remove an endpoint from a group
      # Called by Groups cluster when RemoveGroup command is executed
      def remove_group(group_id : UInt16, endpoint_id : UInt16, fabric_index : UInt8) : Nil
        existing_index = @group_table.index do |entry|
          entry.fabric_index == fabric_index && entry.group_id == group_id
        end
        return unless existing_index

        existing = @group_table[existing_index]

        # Remove endpoint from group
        new_endpoints = existing.endpoints.reject { |ep| ep == endpoint_id }

        if new_endpoints.empty?
          # Remove entire group if no endpoints remain
          @group_table.delete_at(existing_index)
        else
          # Update group with remaining endpoints
          @group_table[existing_index] = GroupInfoMapStruct.new(
            group_id, new_endpoints, existing.group_name, fabric_index
          )
        end
      end

      # Remove all groups for a fabric (fabric removal)
      def remove_fabric(fabric_index : UInt8) : Nil
        @key_sets.delete(fabric_index)
        @group_key_map.reject! { |entry| entry.fabric_index == fabric_index }
        @group_table.reject! { |entry| entry.fabric_index == fabric_index }
      end

      # Get a key set by ID (for cryptographic operations)
      # Returns the actual key set with key material
      def get_key_set(group_key_set_id : UInt16, fabric_index : UInt8) : GroupKeySetStruct?
        fabric_key_sets = @key_sets[fabric_index]?
        return nil unless fabric_key_sets

        fabric_key_sets[group_key_set_id]?
      end

      # Check if a group exists for a fabric
      def group_exists?(group_id : UInt16, fabric_index : UInt8) : Bool
        @group_table.any? do |entry|
          entry.fabric_index == fabric_index && entry.group_id == group_id
        end
      end

      # Get all key set IDs for a fabric (for testing)
      def get_key_set_ids(fabric_index : UInt8) : Array(UInt16)
        fabric_key_sets = @key_sets[fabric_index]?
        return [] of UInt16 unless fabric_key_sets

        fabric_key_sets.keys.sort
      end
    end
  end
end
