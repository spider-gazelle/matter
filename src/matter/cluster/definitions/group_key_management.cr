module Matter
  module Cluster
    module Definitions
      module GroupKeyManagement
        enum GroupKeySecurityPolicy : UInt8
          # Message counter synchronization using trust-first
          TrustFirst = 0

          # Message counter synchronization using cache-and-sync
          CacheAndSync = 1
        end

        enum GroupKeyMulticastPolicy : UInt8
          # Indicates filtering of multicast messages for a specific Group ID
          #
          # The 16-bit Group Identifier of the Multicast Address shall be the Group ID of the group.
          PerGroupId = 0

          # Indicates not filtering of multicast messages
          #
          # The 16-bit Group Identifier of the Multicast Address shall be 0xFFFF.
          AllNodes = 1
        end

        struct GroupKeyMap
          include TLV::Serializable

          # This field uniquely identifies the group within the scope of the given Fabric.
          @[TLV::Field(tag: 1)]
          property group_id : DataType::GroupId

          # This field references the set of group keys that generate operational group keys for use with this
          #
          # group, as specified in Section 4.15.3.5.1, “Group Key Set ID”.
          #
          # A GroupKeyMapStruct shall NOT accept GroupKeySetID of 0, which is reserved for the IPK.
          @[TLV::Field(tag: 2)]
          property group_key_set_id : UInt16

          @[TLV::Field(tag: 254)]
          property fabric_index : DataType::FabricIndex
        end

        # This field uniquely identifies the group within the scope of the given Fabric.
        struct GroupInformationMap
          include TLV::Serializable

          @[TLV::Field(tag: 1)]
          property group_id : DataType::GroupId

          # This field provides the list of Endpoint IDs on the Node to which messages to this group shall be forwarded.
          @[TLV::Field(tag: 2)]
          property endpoints : Array(DataType::EndpointNumber)

          # This field provides a name for the group. This field shall contain the last GroupName written for a given
          # GroupId on any Endpoint via the Groups cluster.
          @[TLV::Field(tag: 3)]
          property group_name : String?

          @[TLV::Field(tag: 254)]
          property fabric_index : DataType::FabricIndex
        end

        # This field shall provide the fabric-unique index for the associated group key set, as specified in Section
        # 4.15.3.5.1, “Group Key Set ID”.
        struct GroupKeySet
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_key_set_id : UInt16

          # This field shall provide the security policy for an operational group key set.
          #
          # When CacheAndSync is not supported in the FeatureMap of this cluster, any action attempting to set
          # CacheAndSync in the GroupKeySecurityPolicy field shall fail with an INVALID_COMMAND error.
          @[TLV::Field(tag: 1)]
          property group_key_security_policy : GroupKeySecurityPolicy

          # This field, if not null, shall be the root credential used in the derivation of an operational group key for
          # epoch slot 0 of the given group key set. If EpochKey0 is not null, EpochStartTime0 shall NOT be null.
          @[TLV::Field(tag: 2)]
          property epoch_key0 : Slice(UInt8)?

          # This field, if not null, shall define when EpochKey0 becomes valid as specified by Section 4.15.3, “Epoch
          # Keys”. Units are absolute UTC time in microseconds encoded using the epoch-us representation.
          @[TLV::Field(tag: 3)]
          property epoch_start_time0 : UInt64?

          # This field, if not null, shall be the root credential used in the derivation of an operational group key for
          # epoch slot 1 of the given group key set. If EpochKey1 is not null, EpochStartTime1 shall NOT be null.
          @[TLV::Field(tag: 4)]
          property epoch_key1 : Slice(UInt8)?

          # This field, if not null, shall define when EpochKey1 becomes valid as specified by Section 4.15.3, “Epoch
          # Keys”. Units are absolute UTC time in microseconds encoded using the epoch-us representation.
          @[TLV::Field(tag: 5)]
          property epoch_start_time1 : UInt64?

          # This field, if not null, shall be the root credential used in the derivation of an operational group key for
          # epoch slot 2 of the given group key set. If EpochKey2 is not null, EpochStartTime2 shall NOT be null.
          @[TLV::Field(tag: 6)]
          property epoch_key2 : Slice(UInt8)?

          # This field, if not null, shall define when EpochKey2 becomes valid as specified by Section 4.15.3, “Epoch
          # Keys”. Units are absolute UTC time in microseconds encoded using the epoch-us representation.
          @[TLV::Field(tag: 7)]
          property epoch_start_time2 : UInt64?

          # This field specifies how the IPv6 Multicast Address shall be formed for groups using this operational group
          # key set.
          #
          # The PerGroupID method maximizes filtering of multicast messages, so that receiving nodes receive only
          # multicast messages for groups to which they are subscribed.
          #
          # The AllNodes method minimizes the number of multicast addresses to which a receiver node needs to subscribe.
          #
          # NOTE Support for GroupKeyMulticastPolicy is provisional. Correct default behavior is that implied by value
          # PerGroupID.
          @[TLV::Field(tag: 8)]
          property group_key_multicast_policy : GroupKeyMulticastPolicy
        end

        # Input to the GroupKeyManagement keySetWrite command
        struct KeySetWriteRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_key_set : GroupKeySet
        end

        # Input to the GroupKeyManagement keySetRead command
        struct KeySetReadRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_key_set_id : UInt16
        end

        # This command shall be generated in response to the KeySetRead command, if a valid Group Key Set was found. It
        # shall contain the configuration of the requested Group Key Set, with the EpochKey0, EpochKey1 and EpochKey2 key
        # contents replaced by null.
        struct KeySetReadResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_key_set : GroupKeySet
        end

        # Input to the GroupKeyManagement keySetRemove command
        struct KeySetRemoveRequest
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_key_set_id : UInt16
        end

        # This command shall be generated in response to KeySetReadAllIndices and it shall contain the list of
        # GroupKeySetID for all Group Key Sets associated with the scoped Fabric.
        #
        # GroupKeySetIDs
        #
        # This field references the set of group keys that generate operational group keys for use with the accessing
        # fabric.
        #
        # Each entry in GroupKeySetIDs is a GroupKeySetID field.
        struct KeySetReadAllIndicesResponse
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property group_key_set_ids : Array(UInt16)
        end
      end
    end
  end
end
