require "./cluster"
require "tlv"
require "log"
require "../datatype/node_id"
require "../datatype/case_authenticated_tag"

module Matter
  module Cluster
    # Access Control Cluster (0x001F)
    #
    # Provides fine-grained access control for Matter devices using
    # Access Control Lists (ACLs).
    #
    # Matter Spec: Core 9.10
    class AccessControlCluster < Base
      Log = ::Log.for("matter.cluster.access_control")

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
        include TLV::Serializable

        @[TLV::Field(tag: 0, optional: true)]
        property cluster : UInt32?

        @[TLV::Field(tag: 1, optional: true)]
        property endpoint : UInt16?

        @[TLV::Field(tag: 2, optional: true)]
        property device_type : UInt32?

        def initialize(@cluster : UInt32? = nil, @endpoint : UInt16? = nil, @device_type : UInt32? = nil)
        end
      end

      # Access Control Entry
      struct AccessControlEntry
        include TLV::Serializable

        @[TLV::Field(tag: 1)]
        property privilege : AccessControlEntryPrivilege

        @[TLV::Field(tag: 2)]
        property auth_mode : AccessControlEntryAuthMode

        @[TLV::Field(tag: 3)]
        property subjects : Array(UInt64) # Node IDs or group IDs

        @[TLV::Field(tag: 4, optional: true)]
        property targets : Array(Target)? # nil means all targets

        # fabric_index is optional during deserialization (client doesn't send it),
        # but required when stored (server fills it in)
        @[TLV::Field(tag: 254, optional: true)]
        property fabric_index : UInt8?

        def initialize(@privilege : AccessControlEntryPrivilege,
                       @auth_mode : AccessControlEntryAuthMode,
                       @subjects : Array(UInt64),
                       @targets : Array(Target)?,
                       fabric_index : UInt8)
          @fabric_index = fabric_index
        end
      end

      # Extension Entry (for future use)
      struct ExtensionEntry
        include TLV::Serializable

        @[TLV::Field(tag: 1)]
        property data : Bytes

        @[TLV::Field(tag: 254)]
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

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_ACL
          encode_acl_list
        when ATTR_EXTENSION
          encode_extension_list
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
          decode_acl_list(value)
        when ATTR_EXTENSION
          decode_extension_list(value)
        else
          super
        end
      end

      # Check if a subject has the required privilege
      # Supports CaseAuthenticatedTag (CAT) subject matching per Matter spec
      def check_access(subject : UInt64, fabric_index : UInt8, privilege : AccessControlEntryPrivilege,
                       cluster : UInt32? = nil, endpoint : UInt16? = nil, device_type : UInt32? = nil) : Bool
        # Find matching ACL entries for this fabric
        matching_entries = @acl.select do |entry|
          entry.fabric_index == fabric_index &&
            entry.subjects.any? { |acl_subject| subject_matches?(acl_subject, subject) }
        end

        # Check if any entry grants sufficient privilege
        matching_entries.any? do |entry|
          # Check privilege level (higher privilege includes lower)
          has_privilege = entry.privilege >= privilege

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

      # Check if a subject (from incoming request) matches an ACL subject
      # Supports CaseAuthenticatedTag (CAT) matching:
      # - For CAT subjects: identity must match, incoming version >= ACL version
      # - For regular NodeIds: exact match required
      private def subject_matches?(acl_subject : UInt64, incoming_subject : UInt64) : Bool
        acl_node = DataType::NodeId.new(acl_subject)
        incoming_node = DataType::NodeId.new(incoming_subject)

        # If both are CAT-encoded, use CAT matching rules
        if acl_node.is_case_authenticated_tag? && incoming_node.is_case_authenticated_tag?
          begin
            acl_cat = acl_node.extract_as_case_authenticated_tag
            incoming_cat = incoming_node.extract_as_case_authenticated_tag

            # CAT matching: identity must match, incoming version >= ACL version
            acl_cat.get_identity_value == incoming_cat.get_identity_value &&
              incoming_cat.get_version >= acl_cat.get_version
          rescue
            # If CAT extraction fails, fall back to exact match
            acl_subject == incoming_subject
          end
        else
          # Regular NodeId: exact match required
          acl_subject == incoming_subject
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

      # Encode ACL list as TLV array
      private def encode_acl_list : Bytes
        # AccessControlEntry has TLV::Serializable, use it directly
        items = @acl.map { |entry| TLV::Any.from_slice(entry.to_slice) }
        TLV::Any.new(items, nil, as_array: true).to_slice
      end

      # Decode ACL list from TLV array
      private def decode_acl_list(value : Bytes) : InteractionModel::Status
        begin
          Log.debug { "decode_acl_list: received #{value.size} bytes: #{value.hexstring}" }

          parsed = TLV::Any.from_slice(value)

          Log.debug { "decode_acl_list: parsed TLV: #{parsed.inspect}" }

          # Extract the array from the parsed data
          # The TLV structure can vary - handle multiple cases
          acl_array = extract_acl_array(parsed)

          Log.debug { "decode_acl_list: extracted #{acl_array.size} ACL entries" }

          new_acl = [] of AccessControlEntry

          acl_array.each_with_index do |entry_value, idx|
            Log.debug { "decode_acl_list: parsing entry #{idx}: #{entry_value.inspect}" }

            # Serialize entry back to bytes and deserialize with from_slice
            entry_bytes = entry_value.to_slice
            entry = AccessControlEntry.from_slice(entry_bytes)
            new_acl << entry
          end

          @acl = new_acl
          increment_version
          Log.info { "decode_acl_list: successfully wrote #{new_acl.size} ACL entries" }
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        rescue ex
          Log.error(exception: ex) { "Failed to decode ACL list" }
          InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
        end
      end

      # Helper to extract ACL array from various TLV structures
      private def extract_acl_array(data : TLV::Any) : Array(TLV::Any)
        value = data.value
        case value
        when Array(TLV::Any)
          # Direct array
          value
        when TLV::Structure
          hash = value
          # Check for "Any" wrapper (anonymous structure)
          if hash.has_key?("Any")
            inner = hash["Any"]
            case inner_val = inner.value
            when Array(TLV::Any)
              inner_val
            when TLV::Structure
              # Nested hash - might contain the array
              inner_hash = inner_val
              if inner_hash.has_key?("Any")
                nested = inner_hash["Any"]
                case nested_val = nested.value
                when Array(TLV::Any)
                  nested_val
                else
                  [inner]
                end
              else
                # Single entry wrapped in hash
                [inner]
              end
            else
              [] of TLV::Any
            end
          else
            # Hash without "Any" - might be a single entry
            [data]
          end
        else
          [] of TLV::Any
        end
      end

      # Encode Extension list as TLV array
      private def encode_extension_list : Bytes
        # ExtensionEntry has TLV::Serializable, use it directly
        items = @extension.map { |entry| TLV::Any.from_slice(entry.to_slice) }
        TLV::Any.new(items, nil, as_array: true).to_slice
      end

      # Decode Extension list from TLV array
      private def decode_extension_list(value : Bytes) : InteractionModel::Status
        begin
          parsed = TLV::Any.from_slice(value)

          # Extract the array from the parsed data
          extension_array = case v = parsed.value
                            when Array
                              v.as(Array(TLV::Any))
                            else
                              # Empty array case
                              [] of TLV::Any
                            end

          new_extension = extension_array.map do |entry_value|
            # Serialize entry back to bytes and deserialize with from_slice
            entry_bytes = entry_value.to_slice
            ExtensionEntry.from_slice(entry_bytes)
          end

          @extension = new_extension
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        rescue ex
          InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
        end
      end

      # Helper: Encode UInt16 as TLV bytes
      private def encode_uint16(value : UInt16) : Bytes
        TLV::Any.new(value, nil).to_slice
      end
    end
  end
end
