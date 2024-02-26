module Matter
  module Cluster
    module Definitions
      module AccessControl
        # This value implicitly grants View privileges
        enum EntryPrivilege : UInt8
          # Can read and observe all (except Access Control Cluster and as seen by a non-Proxy)
          View = 1

          # Can read and observe all (as seen by a Proxy)
          ProxyView = 2

          # View privileges, and can perform the primary function of this Node (except Access Control Cluster)
          # This value implicitly grants View privileges
          Operate = 3

          # Operate privileges, and can modify persistent configuration of this Node (except Access Control Cluster)
          # This value implicitly grants Operate & View privileges
          Manage = 4

          # Manage privileges, and can observe and modify the Access Control Cluster
          # This value implicitly grants Manage, Operate, Proxy View & View privileges
          Administer = 5
        end

        enum EntryAuthMode : UInt8
          # Passcode authenticated session
          Pase = 1

          # Certificate authenticated session
          Case = 2

          # Group authenticated session
          Group = 3
        end

        enum ChangeType : UInt8
          # Entry or extension was changed
          Changed = 0

          # Entry or extension was added
          Added = 1

          # Entry or extension was removed
          Removed = 2
        end

        struct Target
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property cluster : DataType::ClusterId?

          @[TLV::Field(tag: 1)]
          property endpoint : DataType::EndpointNumber?

          @[TLV::Field(tag: 2)]
          property device_type : DataType::DeviceTypeId?
        end

        struct Entry
          include TLV::Serializable

          # The privilege field shall specify the level of privilege granted by this Access Control Entry.
          #
          # NOTE The Proxy View privilege is provisional.
          #
          # Each privilege builds upon its predecessor, expanding the set of actions that can be performed upon a Node.
          # Administer is the highest privilege, and is special as it pertains to the administration of privileges
          # itself, via the Access Control Cluster.
          #
          # When a Node is granted a particular privilege, it is also implicitly granted all logically lower privilege
          # levels as well. The following diagram illustrates how the higher privilege levels subsume the lower
          # privilege levels:
          #
          # Figure 39. Access Control Privilege Levels
          #
          # Individual clusters shall define whether attributes are readable, writable, or both readable and writable.
          # Clusters also shall define which privilege is minimally required to be able to perform a particular read or
          # write action on those attributes, or invoke particular commands. Device type specifications may further
          # restrict the privilege required.
          #
          # The Access Control Cluster shall require the Administer privilege to observe and modify the Access Control
          # Cluster itself. The Administer privilege shall NOT be used on Access Control Entries which use the Group
          # auth mode.

          @[TLV::Field(tag: 1)]
          property privilege : EntryPrivilege

          # The AuthMode field shall specify the authentication mode required by this Access Control Entry.

          @[TLV::Field(tag: 2)]
          property auth_mode : EntryAuthMode

          # The subjects field shall specify a list of Subject IDs, to which this Access Control Entry grants access.
          #
          # Device types may impose additional constraints on the minimum number of subjects per Access Control Entry.
          #
          # An attempt to create an entry with more subjects than the node can support shall result in a
          # RESOURCE_EXHAUSTED error and the entry shall NOT be created.
          #
          # Subject ID shall be of type uint64 with semantics depending on the entry’s AuthMode as follows:
          #
          # Subject Semantics
          #
          # An empty subjects list indicates a wildcard; that is, this entry shall grant access to any Node that
          # successfully authenticates via AuthMode. The subjects list shall NOT be empty if the entry’s AuthMode is
          # PASE.
          #
          # The PASE AuthMode is reserved for future use (see Section 6.6.2.8, “Bootstrapping of the Access Control
          # Cluster”). An attempt to write an entry with AuthMode set to PASE shall fail with a status code of
          # CONSTRAINT_ERROR.
          #
          # For PASE authentication, the Passcode ID identifies the required passcode verifier, and shall be 0 for the
          # default commissioning passcode.
          #
          # For CASE authentication, the Subject ID is a distinguished name within the Operational Certificate shared
          # during CASE session establishment, the type of which is determined by its range to be one of:
          #
          #   • a Node ID, which identifies the required source node directly (by ID)
          #
          #   • a CASE Authenticated Tag, which identifies the required source node indirectly (by tag)
          #
          # For Group authentication, the Group ID identifies the required group, as defined in the Group Key Management
          # Cluster.

          @[TLV::Field(tag: 3)]
          property subjects : Array(DataType::SubjectId)?

          # The targets field shall specify a list of AccessControlTargetStruct, which define the clusters on this Node
          # to which this Access Control Entry grants access.
          #
          # Device types may impose additional constraints on the minimum number of targets per Access Control Entry.
          #
          # An attempt to create an entry with more targets than the node can support shall result in a
          # RESOURCE_EXHAUSTED error and the entry shall NOT be created.
          #
          # A single target shall contain at least one field (Cluster, Endpoint, or DeviceType), and shall NOT contain
          # both an Endpoint field and a DeviceType field.
          #
          # A target grants access based on the presence of fields as follows:
          #
          # Target Semantics
          #
          # An empty targets list indicates a wildcard: that is, this entry shall grant access to all cluster instances
          # on all endpoints on this Node.

          @[TLV::Field(tag: 4)]
          property targets : Array(Target)?

          @[TLV::Field(tag: 254)]
          property fabric_index : DataType::FabricIndex
        end

        struct Extension
          include TLV::Serializable

          # This field may be used by manufacturers to store arbitrary TLV-encoded data related to a fabric’s
          #
          # Access Control Entries.
          #
          # The contents shall consist of a top-level anonymous list; each list element shall include a profile-specific
          # tag encoded in fully-qualified form.
          #
          # Administrators may iterate over this list of elements, and interpret selected elements at their discretion.
          # The content of each element is not specified, but may be coordinated among manufacturers at their discretion.

          @[TLV::Field(tag: 1)]
          property data : Slice(UInt8)

          @[TLV::Field(tag: 254)]
          property fabric_index : DataType::FabricIndex
        end

        module Events
          # Body of the AccessControl accessControlEntryChanged event
          struct EntryChanged
            include TLV::Serializable
            # The Node ID of the Administrator that made the change, if the change occurred via a CASE session.
            #
            # Exactly one of AdminNodeID and AdminPasscodeID shall be set, depending on whether the change occurred via a
            # CASE or PASE session; the other shall be null.

            @[TLV::Field(tag: 1)]
            property admin_node_id : DataType::NodeId?

            # The Passcode ID of the Administrator that made the change, if the change occurred via a PASE session.
            # Non-zero values are reserved for future use (see PasscodeId generation in PBKDFParamRequest).
            #
            # Exactly one of AdminNodeID and AdminPasscodeID shall be set, depending on whether the change occurred via a
            # CASE or PASE session; the other shall be null.

            @[TLV::Field(tag: 2)]
            property admin_passcode_id : UInt16?

            # The type of change as appropriate.

            @[TLV::Field(tag: 3)]
            property change_type : ChangeType

            # The latest value of the changed entry.
            #
            # This field SHOULD be set if resources are adequate for it; otherwise it shall be set to NULL if resources
            # are scarce.

            @[TLV::Field(tag: 4)]
            property latest_value : Entry?

            @[TLV::Field(tag: 254)]
            property fabric_index : DataType::FabricIndex
          end

          # Body of the AccessControl accessControlExtensionChanged event
          struct ExtensionChanged
            include TLV::Serializable

            # The Node ID of the Administrator that made the change, if the change occurred via a CASE session.
            #
            # Exactly one of AdminNodeID and AdminPasscodeID shall be set, depending on whether the change occurred via a
            # CASE or PASE session; the other shall be null.

            @[TLV::Field(tag: 1)]
            property admin_node_id : DataType::NodeId?

            # The Passcode ID of the Administrator that made the change, if the change occurred via a PASE session.
            # Non-zero values are reserved for future use (see PasscodeId generation in PBKDFParamRequest).
            #
            # Exactly one of AdminNodeID and AdminPasscodeID shall be set, depending on whether the change occurred via a
            # CASE or PASE session; the other shall be null.

            @[TLV::Field(tag: 2)]
            property admin_passcode_id : UInt16?

            # The type of change as appropriate.

            @[TLV::Field(tag: 3)]
            property change_type : ChangeType

            # The latest value of the changed extension.
            #
            # This field SHOULD be set if resources are adequate for it; otherwise it shall be set to NULL if resources
            # are scarce.

            @[TLV::Field(tag: 4)]
            property latest_value : Extension?

            @[TLV::Field(tag: 254)]
            property fabric_index : DataType::FabricIndex
          end
        end
      end
    end
  end
end
