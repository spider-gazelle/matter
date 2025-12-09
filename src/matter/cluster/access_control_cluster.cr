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
        property privilege : UInt8

        @[TLV::Field(tag: 2)]
        property auth_mode : UInt8

        @[TLV::Field(tag: 3)]
        property subjects : Array(UInt64) # Node IDs or group IDs

        @[TLV::Field(tag: 4, optional: true)]
        property targets : Array(Target)? # nil means all targets

        @[TLV::Field(tag: 254)]
        property fabric_index : UInt8

        def initialize(privilege : AccessControlEntryPrivilege,
                       auth_mode : AccessControlEntryAuthMode,
                       @subjects : Array(UInt64),
                       @targets : Array(Target)?,
                       @fabric_index : UInt8)
          @privilege = privilege.value
          @auth_mode = auth_mode.value
        end

        # Helper methods to get enum values
        def privilege_enum : AccessControlEntryPrivilege
          AccessControlEntryPrivilege.from_value(@privilege)
        end

        def auth_mode_enum : AccessControlEntryAuthMode
          AccessControlEntryAuthMode.from_value(@auth_mode)
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
          has_privilege = entry.privilege >= privilege.value

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
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Convert each ACL entry to TLV hash format
        acl_array = @acl.map do |entry|
          entry_hash = {
              1_u8 => entry.privilege,
              2_u8 => entry.auth_mode,
              3_u8 => entry.subjects.map { |s| s.as(TLV::Value) }.as(TLV::Value),
            254_u8 => entry.fabric_index,
          } of TLV::Tag => TLV::Value

          # Add targets if present
          if targets = entry.targets
            targets_array = targets.map do |target|
              target.to_h.as(TLV::Value)
            end
            entry_hash[4_u8] = targets_array.as(TLV::Value)
          end

          entry_hash.as(TLV::Value)
        end

        writer.put(nil, acl_array)
        io.to_slice
      end

      # Decode ACL list from TLV array
      private def decode_acl_list(value : Bytes) : InteractionModel::Status
        begin
          Log.debug { "decode_acl_list: received #{value.size} bytes: #{value.hexstring}" }

          reader = TLV::Reader.new(value)
          data = reader.get

          Log.debug { "decode_acl_list: parsed TLV: #{data.inspect}" }

          # Extract the array from the parsed data
          # The TLV structure can vary - handle multiple cases
          acl_array = extract_acl_array(data)

          Log.debug { "decode_acl_list: extracted #{acl_array.size} ACL entries" }

          new_acl = [] of AccessControlEntry

          acl_array.each_with_index do |entry_value, idx|
            Log.debug { "decode_acl_list: parsing entry #{idx}: #{entry_value.inspect}" }
            entry_hash = entry_value.as(Hash(TLV::Tag, TLV::Value))

            # Handle privilege
            privilege = case val = entry_hash[1_u8]
                        when Int then val.to_u8
                        else          raise "Invalid privilege type: #{val.class}"
                        end

            # Handle auth_mode
            auth_mode = case val = entry_hash[2_u8]
                        when Int then val.to_u8
                        else          raise "Invalid auth_mode type: #{val.class}"
                        end

            # Parse subjects array - may be nil for empty array
            subjects_value = entry_hash[3_u8]?
            subjects = if subjects_value.nil?
                         [] of UInt64
                       else
                         subjects_array = subjects_value.as(Array(TLV::Value))
                         subjects_array.map do |s|
                           case s
                           when Int then s.to_u64
                           else          raise "Invalid subject type: #{s.class}"
                           end
                         end
                       end

            # Parse targets array (optional - nil means all targets)
            targets = nil.as(Array(Target)?)
            if entry_hash.has_key?(4_u8) && (targets_value = entry_hash[4_u8]?)
              if targets_value.is_a?(Array)
                targets_array = targets_value.as(Array(TLV::Value))
                targets = targets_array.map do |target_value|
                  target_hash = target_value.as(Hash(TLV::Tag, TLV::Value))

                  cluster = if target_hash.has_key?(0_u8)
                              case val = target_hash[0_u8]
                              when Int then val.to_u32
                              else          nil
                              end
                            end

                  endpoint = if target_hash.has_key?(1_u8)
                               case val = target_hash[1_u8]
                               when Int then val.to_u16
                               else          nil
                               end
                             end

                  device_type = if target_hash.has_key?(2_u8)
                                  case val = target_hash[2_u8]
                                  when Int then val.to_u32
                                  else          nil
                                  end
                                end

                  Target.new(cluster, endpoint, device_type)
                end
              end
            end

            # Handle fabric_index - may be omitted by client (fabric-scoped attribute)
            fabric_index = if entry_hash.has_key?(254_u8)
                             case val = entry_hash[254_u8]
                             when Int then val.to_u8
                             else          1_u8
                             end
                           else
                             1_u8 # Default to fabric 1 when not provided
                           end

            Log.debug { "decode_acl_list: entry #{idx}: privilege=#{privilege}, auth_mode=#{auth_mode}, subjects=#{subjects}, fabric_index=#{fabric_index}" }

            new_acl << AccessControlEntry.new(
              AccessControlEntryPrivilege.from_value(privilege),
              AccessControlEntryAuthMode.from_value(auth_mode),
              subjects,
              targets,
              fabric_index
            )
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
      private def extract_acl_array(data : TLV::Value) : Array(TLV::Value)
        case data
        when Array
          # Direct array
          data.as(Array(TLV::Value))
        when Hash
          hash = data.as(Hash(TLV::Tag, TLV::Value))
          # Check for "Any" wrapper (anonymous structure)
          if hash.has_key?("Any")
            inner = hash["Any"]
            case inner
            when Array
              inner.as(Array(TLV::Value))
            when Hash
              # Nested hash - might contain the array
              inner_hash = inner.as(Hash(TLV::Tag, TLV::Value))
              if inner_hash.has_key?("Any")
                nested = inner_hash["Any"]
                if nested.is_a?(Array)
                  nested.as(Array(TLV::Value))
                else
                  [inner.as(TLV::Value)]
                end
              else
                # Single entry wrapped in hash
                [inner.as(TLV::Value)]
              end
            else
              [] of TLV::Value
            end
          else
            # Hash without "Any" - might be a single entry
            [data.as(TLV::Value)]
          end
        else
          [] of TLV::Value
        end
      end

      # Encode Extension list as TLV array
      private def encode_extension_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Convert each extension entry to TLV hash format
        extension_array = @extension.map do |entry|
          entry.to_h.as(TLV::Value)
        end

        writer.put(nil, extension_array)
        io.to_slice
      end

      # Decode Extension list from TLV array
      private def decode_extension_list(value : Bytes) : InteractionModel::Status
        begin
          reader = TLV::Reader.new(value)
          data = reader.get

          # Extract the array from the parsed data
          extension_array = if data.has_key?("Any")
                              data["Any"].as(Array(TLV::Value))
                            else
                              # Empty array case
                              [] of TLV::Value
                            end

          new_extension = extension_array.map do |entry_value|
            # Convert entry hash to TLV bytes and parse with ExtensionEntry
            entry_io = IO::Memory.new
            entry_writer = TLV::Writer.new(entry_io)
            entry_writer.put(nil, entry_value)
            ExtensionEntry.new(entry_io.rewind.to_slice)
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
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put(nil, value)
        io.rewind.to_slice
      end
    end
  end
end
