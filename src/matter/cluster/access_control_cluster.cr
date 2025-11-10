require "./cluster"
require "tlv"
require "log"

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

      def read_attribute(attribute_id : UInt32) : InteractionModel::Status | Bytes
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
          reader = TLV::Reader.new(value)
          data = reader.get

          # Extract the array from the parsed data
          # For arrays, the data should contain "Any" key with the array
          acl_array = if data.has_key?("Any")
                        data["Any"].as(Array(TLV::Value))
                      else
                        # Empty array case
                        [] of TLV::Value
                      end

          new_acl = [] of AccessControlEntry

          acl_array.each do |entry_value|
            entry_hash = entry_value.as(Hash(TLV::Tag, TLV::Value))

            privilege = entry_hash[1_u8].as(UInt8)
            auth_mode = entry_hash[2_u8].as(UInt8)

            # Parse subjects array
            subjects_array = entry_hash[3_u8].as(Array(TLV::Value))
            subjects = subjects_array.map do |s|
              # TLV may encode integers as different sizes based on value
              case s
              when UInt8
                s.to_u64
              when UInt16
                s.to_u64
              when UInt32
                s.to_u64
              when UInt64
                s
              else
                raise "Invalid subject type: #{s.class}"
              end
            end

            # Parse targets array (optional)
            targets = nil.as(Array(Target)?)
            if entry_hash.has_key?(4_u8)
              targets_array = entry_hash[4_u8].as(Array(TLV::Value))
              targets = targets_array.map do |target_value|
                target_hash = target_value.as(Hash(TLV::Tag, TLV::Value))

                # Handle TLV encoding integers as different sizes
                cluster = if target_hash.has_key?(0_u8)
                            case val = target_hash[0_u8]
                            when UInt8  then val.to_u32
                            when UInt16 then val.to_u32
                            when UInt32 then val
                            else             nil
                            end
                          end

                endpoint = if target_hash.has_key?(1_u8)
                             case val = target_hash[1_u8]
                             when UInt8  then val.to_u16
                             when UInt16 then val
                             else             nil
                             end
                           end

                device_type = if target_hash.has_key?(2_u8)
                                case val = target_hash[2_u8]
                                when UInt8  then val.to_u32
                                when UInt16 then val.to_u32
                                when UInt32 then val
                                else             nil
                                end
                              end

                Target.new(cluster, endpoint, device_type)
              end
            end

            fabric_index = entry_hash[254_u8].as(UInt8)

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
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        rescue ex
          Log.error(exception: ex) { "Failed to decode ACL list" }
          InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
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

      # Helper: Encode UInt16 as bytes
      private def encode_uint16(value : UInt16) : Bytes
        io = IO::Memory.new
        io.write_bytes(value, IO::ByteFormat::LittleEndian)
        io.to_slice
      end
    end
  end
end
