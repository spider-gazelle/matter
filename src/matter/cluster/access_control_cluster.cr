require "./cluster"
require "tlv"
require "json"
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

      struct PersistedTarget
        include JSON::Serializable

        getter cluster : UInt32?
        getter endpoint : UInt16?
        getter device_type : UInt32?

        def initialize(@cluster : UInt32?, @endpoint : UInt16?, @device_type : UInt32?)
        end
      end

      struct PersistedAclEntry
        include JSON::Serializable

        getter privilege : UInt8
        getter auth_mode : UInt8
        getter subjects : Array(UInt64)
        getter targets : Array(PersistedTarget)?
        getter fabric_index : UInt8?

        def initialize(
          @privilege : UInt8,
          @auth_mode : UInt8,
          @subjects : Array(UInt64),
          @targets : Array(PersistedTarget)?,
          @fabric_index : UInt8?,
        )
        end
      end

      struct PersistedExtensionEntry
        include JSON::Serializable

        getter data_hex : String
        getter fabric_index : UInt8

        def initialize(@data_hex : String, @fabric_index : UInt8)
        end
      end

      struct PersistedState
        include JSON::Serializable

        getter data_version : UInt32
        getter acl : Array(PersistedAclEntry)
        getter extension : Array(PersistedExtensionEntry)

        def initialize(
          @data_version : UInt32,
          @acl : Array(PersistedAclEntry),
          @extension : Array(PersistedExtensionEntry),
        )
        end
      end

      def save_state : String?
        PersistedState.new(
          data_version: @data_version,
          acl: @acl.map do |entry|
            PersistedAclEntry.new(
              privilege: entry.privilege.value,
              auth_mode: entry.auth_mode.value,
              subjects: entry.subjects,
              targets: entry.targets.try do |targets|
                targets.map { |t| PersistedTarget.new(t.cluster, t.endpoint, t.device_type) }
              end,
              fabric_index: entry.fabric_index
            )
          end,
          extension: @extension.map do |entry|
            PersistedExtensionEntry.new(entry.data.hexstring, entry.fabric_index)
          end
        ).to_json
      rescue ex
        Log.error(exception: ex) { "save_state failed (acl_entries=#{@acl.size} extension_entries=#{@extension.size})" }
        nil
      end

      def restore_state(json : String) : Nil
        state = PersistedState.from_json(json)
        @data_version = state.data_version

        @acl = state.acl.compact_map do |entry|
          idx = entry.fabric_index
          unless idx
            Log.warn { "restore_state: skipping ACL entry without fabric_index" }
            next
          end

          privilege = AccessControlEntryPrivilege.from_value?(entry.privilege)
          auth_mode = AccessControlEntryAuthMode.from_value?(entry.auth_mode)
          unless privilege && auth_mode
            Log.warn { "restore_state: skipping ACL entry with invalid enums (privilege=#{entry.privilege} auth_mode=#{entry.auth_mode})" }
            next
          end

          targets = entry.targets.try do |targets|
            targets.map { |t| Target.new(cluster: t.cluster, endpoint: t.endpoint, device_type: t.device_type) }
          end

          AccessControlEntry.new(
            privilege: privilege,
            auth_mode: auth_mode,
            subjects: entry.subjects,
            targets: targets,
            fabric_index: idx
          )
        end

        @extension = state.extension.compact_map do |entry|
          begin
            ExtensionEntry.new(entry.data_hex.hexbytes, entry.fabric_index)
          rescue ex
            Log.warn(exception: ex) { "restore_state: skipping extension entry with invalid data_hex (fabric_index=#{entry.fabric_index} data_hex=#{entry.data_hex})" }
            next
          end
        end
      rescue ex
        Log.error(exception: ex) { "restore_state failed (json_bytes=#{json.bytesize})" }
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
          # ACL is fabric-sensitive; only return entries for the requesting fabric.
          if fabric_index
            @acl.select { |entry| entry.fabric_index == fabric_index }.to_tlv
          else
            @acl.to_tlv
          end
        when ATTR_EXTENSION
          if fabric_index
            @extension.select { |entry| entry.fabric_index == fabric_index }.to_tlv
          else
            @extension.to_tlv
          end
        when ATTR_SUBJECTS_PER_ACCESS_CONTROL_ENTRY
          @subjects_per_access_control_entry.to_tlv
        when ATTR_TARGETS_PER_ACCESS_CONTROL_ENTRY
          @targets_per_access_control_entry.to_tlv
        when ATTR_ACCESS_CONTROL_ENTRIES_PER_FABRIC
          @access_control_entries_per_fabric.to_tlv
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
                       cluster : UInt32? = nil, endpoint : UInt16? = nil, device_type : UInt32? = nil,
                       auth_mode : AccessControlEntryAuthMode = AccessControlEntryAuthMode::CASE) : Bool
        # Find matching ACL entries for this fabric
        matching_entries = @acl.select do |entry|
          entry.fabric_index == fabric_index &&
            entry.auth_mode == auth_mode &&
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

      # Convenience wrapper for the generated cluster metadata privilege enum.
      def check_access(subject : UInt64, fabric_index : UInt8, privilege : Definitions::AccessControl::EntryPrivilege,
                       cluster : UInt32? = nil, endpoint : UInt16? = nil, device_type : UInt32? = nil,
                       auth_mode : Definitions::AccessControl::EntryAuthMode = Definitions::AccessControl::EntryAuthMode::Case) : Bool
        check_access(
          subject: subject,
          fabric_index: fabric_index,
          privilege: AccessControlEntryPrivilege.from_value(privilege.value),
          cluster: cluster,
          endpoint: endpoint,
          device_type: device_type,
          auth_mode: AccessControlEntryAuthMode.from_value(auth_mode.value)
        )
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

      # Decode ACL list from TLV array
      private def decode_acl_list(value : Bytes) : InteractionModel::Status
        begin
          fabric_index = request_fabric_index

          Log.debug { "decode_acl_list: received #{value.size} bytes" }
          Log.trace { "decode_acl_list: value_hex=#{value.hexstring}" }

          parsed = TLV::Any.from_slice(value)

          Log.trace { "decode_acl_list: parsed TLV: #{parsed.inspect}" }

          # Extract the array from the parsed data
          # The TLV structure can vary - handle multiple cases
          acl_array = extract_acl_array(parsed)

          Log.debug { "decode_acl_list: extracted #{acl_array.size} ACL entries" }

          new_acl = [] of AccessControlEntry

          acl_array.each_with_index do |entry_value, idx|
            Log.debug { "decode_acl_list: parsing entry #{idx}" }
            Log.trace { "decode_acl_list: entry #{idx} TLV: #{entry_value.inspect}" }

            # Serialize entry back to bytes and deserialize with from_slice
            entry_bytes = entry_value.to_slice
            entry = AccessControlEntry.from_slice(entry_bytes)
            entry.fabric_index ||= fabric_index
            new_acl << entry
          end

          if fabric_index
            # ACL is fabric-scoped; only replace entries for the requesting fabric.
            @acl.reject! { |entry| entry.fabric_index == fabric_index }
            @acl.concat(new_acl)
          else
            # Unit tests and some tooling call `write_attribute` directly without setting request context.
            # In that case, behave like a full replace and keep any FabricIndex values provided in the TLV.
            @acl = new_acl
          end

          increment_version
          Log.debug { "decode_acl_list: wrote #{new_acl.size} ACL entries" }
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        rescue ex
          Log.error(exception: ex) { "Failed to decode ACL list (bytes=#{value.hexstring})" }
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

      # Decode Extension list from TLV array
      private def decode_extension_list(value : Bytes) : InteractionModel::Status
        begin
          fabric_index = request_fabric_index

          Log.debug { "decode_extension_list: received #{value.size} bytes" }
          Log.trace { "decode_extension_list: value_hex=#{value.hexstring}" }

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
            entry = ExtensionEntry.from_slice(entry_bytes)
            entry.fabric_index = fabric_index if fabric_index
            entry
          end

          if fabric_index
            @extension.reject! { |entry| entry.fabric_index == fabric_index }
            @extension.concat(new_extension)
          else
            @extension = new_extension
          end

          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        rescue ex
          Log.error(exception: ex) { "Failed to decode extension list (bytes=#{value.hexstring})" }
          InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
        end
      end
    end
  end
end
