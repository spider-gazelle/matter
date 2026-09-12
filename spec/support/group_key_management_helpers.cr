# Key fixtures shared by the group_key_management_*_spec.cr files.
require "../spec_helper"
require "../../src/matter/cluster/group_key_management"

module Matter::Cluster
  # Helper to create a valid epoch key (16 bytes)
  def self.test_key(value : UInt8 = 0x01) : Bytes
    Bytes.new(16, value)
  end

  # Helper to create a valid key set
  def self.create_key_set(
    id : UInt16 = 1_u16,
    key0 : Bytes? = test_key(0x01),
    time0 : UInt64? = 1000_u64,
    key1 : Bytes? = nil,
    time1 : UInt64? = nil,
    key2 : Bytes? = nil,
    time2 : UInt64? = nil,
  ) : GroupKeyManagement::GroupKeySetStruct
    GroupKeyManagement::GroupKeySetStruct.new(
      group_key_set_id: id,
      group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::TrustFirst,
      epoch_key0: key0,
      epoch_start_time0: time0,
      epoch_key1: key1,
      epoch_start_time1: time1,
      epoch_key2: key2,
      epoch_start_time2: time2,
      group_key_multicast_policy: GroupKeyManagement::GroupKeyMulticastPolicyEnum::PerGroupId
    )
  end
end
