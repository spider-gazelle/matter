require "./cluster"

module Matter
  module Cluster
    # Access Control Cluster (0x001F)
    #
    # Provides fine-grained access control for Matter devices using
    # Access Control Lists (ACLs).
    #
    # Matter Spec: Core 9.10
    class AccessControlCluster < Base
      CLUSTER_ID = 0x001F_u32

      # Access Control Entry Privilege Levels
      enum AccessControlEntryPrivilege : UInt8
        View       = 1 # Can read attributes
        ProxyView  = 2 # Can read and observe
        Operate    = 3 # Can read and invoke commands
        Manage     = 4 # Can read, write, and invoke commands
        Administer = 5 # Full control including ACL management
      end

      # Access Control Entry Auth Mode
      enum AccessControlEntryAuthMode : UInt8
        PASE  = 1 # PASE authentication (commissioning)
        CASE  = 2 # CASE authentication (operational)
        Group = 3 # Group authentication
      end

      # Attributes
      ATTR_ACL                               = 0x0000_u32
      ATTR_EXTENSION                         = 0x0001_u32
      ATTR_SUBJECTS_PER_ACCESS_CONTROL_ENTRY = 0x0002_u32
      ATTR_TARGETS_PER_ACCESS_CONTROL_ENTRY  = 0x0003_u32
      ATTR_ACCESS_CONTROL_ENTRIES_PER_FABRIC = 0x0004_u32

      # Target structure (endpoint, cluster, or device type)
      struct Target
        property cluster : UInt32?
        property endpoint : UInt16?
        property device_type : UInt32?

        def initialize(@cluster : UInt32?, @endpoint : UInt16?, @device_type : UInt32?)
        end
      end

      # Access Control Entry
      struct AccessControlEntry
        property privilege : AccessControlEntryPrivilege
        property auth_mode : AccessControlEntryAuthMode
        property subjects : Array(UInt64) # Node IDs or group IDs
        property targets : Array(Target)? # nil means all targets
        property fabric_index : UInt8

        def initialize(@privilege : AccessControlEntryPrivilege,
                       @auth_mode : AccessControlEntryAuthMode,
                       @subjects : Array(UInt64),
                       @targets : Array(Target)?,
                       @fabric_index : UInt8)
        end
      end

      # Extension Entry (for future use)
      struct ExtensionEntry
        property data : Bytes
        property fabric_index : UInt8

        def initialize(@data : Bytes, @fabric_index : UInt8)
        end
      end

      # Attribute storage
      property acl : Array(AccessControlEntry)
      property extension : Array(ExtensionEntry)
      property subjects_per_access_control_entry : UInt16
      property targets_per_access_control_entry : UInt16
      property access_control_entries_per_fabric : UInt16

      def initialize(endpoint_id : DataType::EndpointNumber)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        @acl = [] of AccessControlEntry
        @extension = [] of ExtensionEntry
        @subjects_per_access_control_entry = 4_u16
        @targets_per_access_control_entry = 3_u16
        @access_control_entries_per_fabric = 4_u16
      end

      def name : String
        "AccessControl"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACL),
            "ACL",
            :list,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_EXTENSION),
            "Extension",
            :list,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SUBJECTS_PER_ACCESS_CONTROL_ENTRY),
            "SubjectsPerAccessControlEntry",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_TARGETS_PER_ACCESS_CONTROL_ENTRY),
            "TargetsPerAccessControlEntry",
            :uint16,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACCESS_CONTROL_ENTRIES_PER_FABRIC),
            "AccessControlEntriesPerFabric",
            :uint16,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        # No commands defined for Access Control cluster
        [] of CommandMetadata
      end

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_ACL
          # TODO: Encode ACL list as TLV
          Bytes.new(0)
        when ATTR_EXTENSION
          # TODO: Encode extension list as TLV
          Bytes.new(0)
        when ATTR_SUBJECTS_PER_ACCESS_CONTROL_ENTRY
          encode_uint16(@subjects_per_access_control_entry)
        when ATTR_TARGETS_PER_ACCESS_CONTROL_ENTRY
          encode_uint16(@targets_per_access_control_entry)
        when ATTR_ACCESS_CONTROL_ENTRIES_PER_FABRIC
          encode_uint16(@access_control_entries_per_fabric)
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_ACL
          # TODO: Parse and update ACL list from TLV
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_EXTENSION
          # TODO: Parse and update extension list from TLV
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # Check if a subject has the required privilege
      def check_access(subject : UInt64, fabric_index : UInt8, privilege : AccessControlEntryPrivilege,
                       cluster : UInt32? = nil, endpoint : UInt16? = nil, device_type : UInt32? = nil) : Bool
        # Find matching ACL entries for this fabric
        matching_entries = @acl.select do |entry|
          entry.fabric_index == fabric_index &&
            entry.subjects.includes?(subject)
        end

        # Check if any entry grants sufficient privilege
        matching_entries.any? do |entry|
          # Check privilege level (higher privilege includes lower)
          has_privilege = entry.privilege.value >= privilege.value

          # Check target matching
          has_target_access = if targets = entry.targets
                                targets.any? do |target|
                                  (!target.cluster || target.cluster == cluster) &&
                                    (!target.endpoint || target.endpoint == endpoint) &&
                                    (!target.device_type || target.device_type == device_type)
                                end
                              else
                                true # nil targets means all targets
                              end

          has_privilege && has_target_access
        end
      end

      # Helper: Get ACL entries for a specific fabric
      def get_acl_for_fabric(fabric_index : UInt8) : Array(AccessControlEntry)
        @acl.select { |entry| entry.fabric_index == fabric_index }
      end

      # Helper: Remove all ACL entries for a fabric
      def remove_fabric_acl(fabric_index : UInt8) : Nil
        @acl.reject! { |entry| entry.fabric_index == fabric_index }
        increment_version
      end

      # Helper: Encode UInt16 as bytes
      private def encode_uint16(value : UInt16) : Bytes
        io = IO::Memory.new
        io.write_bytes(value, IO::ByteFormat::LittleEndian)
        io.to_slice
      end
    end
  end
end
