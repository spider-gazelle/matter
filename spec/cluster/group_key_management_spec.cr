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

  describe GroupKeyManagement do
    describe "initialization" do
      it "creates cluster with default settings" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        cluster.max_groups_per_fabric.should eq(12)
        cluster.max_group_keys_per_fabric.should eq(3)
        cluster.feature_map.should eq(GroupKeyManagement::Feature::None)
      end

      it "creates cluster with custom settings" do
        cluster = GroupKeyManagement.new(
          Matter::DataType::EndpointNumber.new(0_u16),
          max_groups_per_fabric: 20_u16,
          max_group_keys_per_fabric: 5_u16
        )
        cluster.max_groups_per_fabric.should eq(20)
        cluster.max_group_keys_per_fabric.should eq(5)
      end

      it "starts with empty key sets" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        response = cluster.handle_key_set_read_all_indices(fabric_index: 1)
        response.group_key_set_i_ds.should be_empty
      end

      it "starts with empty group key map" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        cluster.group_key_map(fabric_index: 1).should be_empty
      end

      it "starts with empty group table" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        cluster.group_table(fabric_index: 1).should be_empty
      end
    end

    describe "GroupKeySetStruct validation" do
      it "accepts valid key set with single epoch key" do
        key_set = Cluster.create_key_set(id: 1_u16, key0: Cluster.test_key, time0: 1000_u64)
        key_set.validate!
      end

      it "accepts valid key set with multiple epoch keys in order" do
        key_set = Cluster.create_key_set(
          id: 1_u16,
          key0: Cluster.test_key(0x01), time0: 1000_u64,
          key1: Cluster.test_key(0x02), time1: 2000_u64,
          key2: Cluster.test_key(0x03), time2: 3000_u64
        )
        key_set.validate!
      end

      it "rejects epoch key with wrong length" do
        key_set = GroupKeyManagement::GroupKeySetStruct.new(
          group_key_set_id: 1_u16,
          group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::TrustFirst,
          epoch_key0: Bytes.new(15), # Wrong length
          epoch_start_time0: 1000_u64
        )
        expect_raises(ArgumentError, /must be exactly 16 bytes/) do
          key_set.validate!
        end
      end

      it "rejects key without matching start time" do
        key_set = GroupKeyManagement::GroupKeySetStruct.new(
          group_key_set_id: 1_u16,
          group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::TrustFirst,
          epoch_key0: Cluster.test_key,
          epoch_start_time0: nil # Missing time
        )
        expect_raises(ArgumentError, /must both be set or both be null/) do
          key_set.validate!
        end
      end

      it "rejects start time without matching key" do
        key_set = GroupKeyManagement::GroupKeySetStruct.new(
          group_key_set_id: 1_u16,
          group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::TrustFirst,
          epoch_key0: nil,
          epoch_start_time0: 1000_u64 # Has time but no key
        )
        expect_raises(ArgumentError, /must both be set or both be null/) do
          key_set.validate!
        end
      end

      it "rejects epoch start time of 0" do
        key_set = GroupKeyManagement::GroupKeySetStruct.new(
          group_key_set_id: 1_u16,
          group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::TrustFirst,
          epoch_key0: Cluster.test_key,
          epoch_start_time0: 0_u64
        )
        expect_raises(ArgumentError, /cannot be 0/) do
          key_set.validate!
        end
      end

      it "rejects unordered epoch start times" do
        key_set = Cluster.create_key_set(
          id: 1_u16,
          key0: Cluster.test_key(0x01), time0: 3000_u64, # Out of order
          key1: Cluster.test_key(0x02), time1: 2000_u64,
          key2: Cluster.test_key(0x03), time2: 1000_u64
        )
        expect_raises(ArgumentError, /must be strictly ordered/) do
          key_set.validate!
        end
      end

      it "rejects equal epoch start times" do
        key_set = Cluster.create_key_set(
          id: 1_u16,
          key0: Cluster.test_key(0x01), time0: 1000_u64,
          key1: Cluster.test_key(0x02), time1: 1000_u64 # Same as time0
        )
        expect_raises(ArgumentError, /must be strictly ordered/) do
          key_set.validate!
        end
      end

      it "rejects CacheAndSync security policy" do
        key_set = GroupKeyManagement::GroupKeySetStruct.new(
          group_key_set_id: 1_u16,
          group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::CacheAndSync,
          epoch_key0: Cluster.test_key,
          epoch_start_time0: 1000_u64
        )
        expect_raises(ArgumentError, /Only TrustFirst security policy/) do
          key_set.validate!
        end
      end

      it "rejects AllNodes multicast policy" do
        key_set = GroupKeyManagement::GroupKeySetStruct.new(
          group_key_set_id: 1_u16,
          group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::TrustFirst,
          epoch_key0: Cluster.test_key,
          epoch_start_time0: 1000_u64,
          group_key_multicast_policy: GroupKeyManagement::GroupKeyMulticastPolicyEnum::AllNodes
        )
        expect_raises(ArgumentError, /Only PerGroupId multicast policy/) do
          key_set.validate!
        end
      end
    end

    describe "KeySetWrite command" do
      it "creates a new key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        key_set = Cluster.create_key_set(id: 1_u16)
        cmd = GroupKeyManagement::KeySetWriteRequest.new(key_set)

        cluster.handle_key_set_write(cmd, fabric_index: 1)

        response = cluster.handle_key_set_read_all_indices(fabric_index: 1)
        response.group_key_set_i_ds.should eq([1_u16])
      end

      it "updates an existing key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Create initial key set
        key_set1 = Cluster.create_key_set(id: 1_u16, key0: Cluster.test_key(0x01), time0: 1000_u64)
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(key_set1),
          fabric_index
        )

        # Update with new key
        key_set2 = Cluster.create_key_set(id: 1_u16, key0: Cluster.test_key(0x02), time0: 2000_u64)
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(key_set2),
          fabric_index
        )

        # Should still have only one key set
        response = cluster.handle_key_set_read_all_indices(fabric_index)
        response.group_key_set_i_ds.should eq([1_u16])

        # Read should return updated key set (times visible, keys redacted)
        read_response = cluster.handle_key_set_read(
          GroupKeyManagement::KeySetReadRequest.new(1_u16),
          fabric_index
        )
        read_response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.epoch_start_time0.should eq(2000_u64)
      end

      it "enforces max_group_keys_per_fabric limit" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16), max_group_keys_per_fabric: 2_u16)
        fabric_index = 1_u8

        # Create two key sets (should succeed)
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 2_u16)),
          fabric_index
        )

        # Third key set should fail
        error = expect_raises(Matter::ClusterError, /Cannot exceed max_group_keys_per_fabric/) do
          cluster.handle_key_set_write(
            GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 3_u16)),
            fabric_index
          )
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::ResourceExhausted)
      end

      it "allows updating without counting against limit" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16), max_group_keys_per_fabric: 2_u16)
        fabric_index = 1_u8

        # Create two key sets
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 2_u16)),
          fabric_index
        )

        # Update one of them (should succeed)
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(
            Cluster.create_key_set(id: 1_u16, key0: Cluster.test_key(0xFF), time0: 5000_u64)
          ),
          fabric_index
        )
      end

      it "rejects invalid key set structure" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        invalid_key_set = GroupKeyManagement::GroupKeySetStruct.new(
          group_key_set_id: 1_u16,
          group_key_security_policy: GroupKeyManagement::GroupKeySecurityPolicyEnum::TrustFirst,
          epoch_key0: Bytes.new(10), # Wrong size
          epoch_start_time0: 1000_u64
        )

        expect_raises(ArgumentError, /must be exactly 16 bytes/) do
          cluster.handle_key_set_write(
            GroupKeyManagement::KeySetWriteRequest.new(invalid_key_set),
            fabric_index: 1
          )
        end
      end

      it "creates IPK key set (ID 0)" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        ipk_key_set = Cluster.create_key_set(id: 0_u16)
        cmd = GroupKeyManagement::KeySetWriteRequest.new(ipk_key_set)

        cluster.handle_key_set_write(cmd, fabric_index: 1)

        response = cluster.handle_key_set_read_all_indices(fabric_index: 1)
        response.group_key_set_i_ds.should eq([0_u16])
      end
    end

    describe "KeySetRead command" do
      it "reads existing key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8
        key_set = Cluster.create_key_set(id: 1_u16, key0: Cluster.test_key(0xAA), time0: 1234_u64)

        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(key_set),
          fabric_index
        )

        response = cluster.handle_key_set_read(
          GroupKeyManagement::KeySetReadRequest.new(1_u16),
          fabric_index
        )
        response.should_not be_nil
        response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.group_key_set_id.should eq(1_u16)
        response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.epoch_start_time0.should eq(1234_u64)
      end

      it "returns nil for non-existent key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        response = cluster.handle_key_set_read(
          GroupKeyManagement::KeySetReadRequest.new(99_u16),
          fabric_index: 1
        )
        response.should be_nil
      end

      it "sanitizes key material in response" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8
        key_set = Cluster.create_key_set(
          id: 1_u16,
          key0: Cluster.test_key(0xAA), time0: 1000_u64,
          key1: Cluster.test_key(0xBB), time1: 2000_u64
        )

        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(key_set),
          fabric_index
        )

        response = cluster.handle_key_set_read(
          GroupKeyManagement::KeySetReadRequest.new(1_u16),
          fabric_index
        )
        response.should_not be_nil

        # Key material should be nil (sanitized)
        response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.epoch_key0.should be_nil
        response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.epoch_key1.should be_nil
        response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.epoch_key2.should be_nil

        # But start times should be present
        response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.epoch_start_time0.should eq(1000_u64)
        response.as(GroupKeyManagement::KeySetReadResponse).group_key_set.epoch_start_time1.should eq(2000_u64)
      end

      it "isolates fabrics" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        # Create key set in fabric 1
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index: 1
        )

        # Should not be visible from fabric 2
        response = cluster.handle_key_set_read(
          GroupKeyManagement::KeySetReadRequest.new(1_u16),
          fabric_index: 2
        )
        response.should be_nil
      end
    end

    describe "KeySetRemove command" do
      it "removes existing key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Create key set
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )

        # Remove it
        cluster.handle_key_set_remove(
          GroupKeyManagement::KeySetRemoveRequest.new(1_u16),
          fabric_index
        )

        # Should no longer exist
        response = cluster.handle_key_set_read_all_indices(fabric_index)
        response.group_key_set_i_ds.should be_empty
      end

      it "protects IPK (key set 0) from removal" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Create IPK
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 0_u16)),
          fabric_index
        )

        # Attempt to remove it (should fail)
        error = expect_raises(Matter::ClusterError, /Cannot remove key set 0/) do
          cluster.handle_key_set_remove(
            GroupKeyManagement::KeySetRemoveRequest.new(0_u16),
            fabric_index
          )
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)

        # IPK should still exist
        response = cluster.handle_key_set_read_all_indices(fabric_index)
        response.group_key_set_i_ds.should eq([0_u16])
      end

      it "raises error for non-existent key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        error = expect_raises(Matter::ClusterError, /Key set 99 not found/) do
          cluster.handle_key_set_remove(
            GroupKeyManagement::KeySetRemoveRequest.new(99_u16),
            fabric_index: 1
          )
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::NotFound)
      end

      it "cascades to group key map entries" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Create key set
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )

        # Add group key map entries
        cluster.add_group_key_map(group_id: 100_u16, group_key_set_id: 1_u16, fabric_index: fabric_index)
        cluster.add_group_key_map(group_id: 200_u16, group_key_set_id: 1_u16, fabric_index: fabric_index)
        cluster.group_key_map(fabric_index).size.should eq(2)

        # Remove key set
        cluster.handle_key_set_remove(
          GroupKeyManagement::KeySetRemoveRequest.new(1_u16),
          fabric_index
        )

        # Group key map entries should be removed
        cluster.group_key_map(fabric_index).should be_empty
      end

      it "only removes mappings for the specific fabric" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        # Create key sets in two fabrics
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index: 1
        )
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index: 2
        )

        # Add mappings in both fabrics
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index: 1)
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index: 2)

        # Remove key set from fabric 1
        cluster.handle_key_set_remove(
          GroupKeyManagement::KeySetRemoveRequest.new(1_u16),
          fabric_index: 1
        )

        # Fabric 1 should have no mappings
        cluster.group_key_map(fabric_index: 1).should be_empty

        # Fabric 2 should still have its mapping
        cluster.group_key_map(fabric_index: 2).size.should eq(1)
      end
    end

    describe "KeySetReadAllIndices command" do
      it "returns empty array when no key sets exist" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        response = cluster.handle_key_set_read_all_indices(fabric_index: 1)
        response.group_key_set_i_ds.should be_empty
      end

      it "returns all key set IDs for fabric" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16), max_group_keys_per_fabric: 10_u16)
        fabric_index = 1_u8

        # Create multiple key sets
        [0_u16, 1_u16, 5_u16, 10_u16].each do |id|
          cluster.handle_key_set_write(
            GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: id)),
            fabric_index
          )
        end

        response = cluster.handle_key_set_read_all_indices(fabric_index)
        response.group_key_set_i_ds.should eq([0_u16, 1_u16, 5_u16, 10_u16])
      end

      it "returns sorted key set IDs" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16), max_group_keys_per_fabric: 10_u16)
        fabric_index = 1_u8

        # Create key sets in non-sequential order
        [10_u16, 1_u16, 5_u16, 0_u16].each do |id|
          cluster.handle_key_set_write(
            GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: id)),
            fabric_index
          )
        end

        response = cluster.handle_key_set_read_all_indices(fabric_index)
        response.group_key_set_i_ds.should eq([0_u16, 1_u16, 5_u16, 10_u16])
      end

      it "isolates fabrics" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        # Create key sets in different fabrics
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index: 1
        )
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 2_u16)),
          fabric_index: 2
        )

        # Each fabric should only see its own key sets
        response1 = cluster.handle_key_set_read_all_indices(fabric_index: 1)
        response1.group_key_set_i_ds.should eq([1_u16])

        response2 = cluster.handle_key_set_read_all_indices(fabric_index: 2)
        response2.group_key_set_i_ds.should eq([2_u16])
      end
    end

    describe "group key map operations" do
      it "adds group key map entry" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Create key set
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )

        # Add mapping
        cluster.add_group_key_map(group_id: 100_u16, group_key_set_id: 1_u16, fabric_index: fabric_index)

        entries = cluster.group_key_map(fabric_index)
        entries.size.should eq(1)
        entries[0].group_id.should eq(100_u16)
        entries[0].group_key_set_id.should eq(1_u16)
      end

      it "updates existing group key map entry" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Create two key sets
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 2_u16)),
          fabric_index
        )

        # Add mapping
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)

        # Update mapping to different key set
        cluster.add_group_key_map(100_u16, 2_u16, fabric_index)

        entries = cluster.group_key_map(fabric_index)
        entries.size.should eq(1)                    # Still only one entry
        entries[0].group_key_set_id.should eq(2_u16) # Updated
      end

      it "rejects group ID 0" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )

        error = expect_raises(Matter::ClusterError, /Group ID 0 is invalid/) do
          cluster.add_group_key_map(0_u16, 1_u16, fabric_index)
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end

      it "rejects non-existent key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        error = expect_raises(Matter::ClusterError, /Key set 99 does not exist/) do
          cluster.add_group_key_map(100_u16, 99_u16, fabric_index: 1)
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::NotFound)
      end

      it "enforces max_groups_per_fabric limit" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16), max_groups_per_fabric: 2_u16)
        fabric_index = 1_u8

        # Create key set
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )

        # Add two groups (should succeed)
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)
        cluster.add_group_key_map(200_u16, 1_u16, fabric_index)

        # Third group should fail
        error = expect_raises(Matter::ClusterError, /Cannot exceed max_groups_per_fabric/) do
          cluster.add_group_key_map(300_u16, 1_u16, fabric_index)
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::ResourceExhausted)
      end

      it "removes group key map entry" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)

        cluster.remove_group_key_map(100_u16, fabric_index)

        cluster.group_key_map(fabric_index).should be_empty
      end

      it "isolates fabrics" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        # Create key sets in different fabrics
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index: 1
        )
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index: 2
        )

        # Add mappings in both fabrics with same group ID
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index: 1)
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index: 2)

        # Each fabric should only see its own mapping
        cluster.group_key_map(fabric_index: 1).size.should eq(1)
        cluster.group_key_map(fabric_index: 2).size.should eq(1)
      end
    end

    describe "group table operations" do
      it "adds group to table" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Setup: key set + mapping
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)

        # Add group
        cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: "Test Group", fabric_index: fabric_index)

        groups = cluster.group_table(fabric_index)
        groups.size.should eq(1)
        groups[0].group_id.should eq(100_u16)
        groups[0].endpoints.should eq([1_u16])
        groups[0].group_name.should eq("Test Group")
      end

      it "adds endpoint to existing group" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Setup
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)

        # Add group with first endpoint
        cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: "Test", fabric_index: fabric_index)

        # Add second endpoint
        cluster.add_group(100_u16, endpoint_id: 2_u16, group_name: nil, fabric_index: fabric_index)

        groups = cluster.group_table(fabric_index)
        groups.size.should eq(1)
        groups[0].endpoints.should eq([1_u16, 2_u16])
      end

      it "rejects group without key map entry" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        error = expect_raises(Matter::ClusterError, /has no key map entry/) do
          cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: nil, fabric_index: fabric_index)
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::NotFound)
      end

      it "enforces max_groups_per_fabric limit" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16), max_groups_per_fabric: 2_u16)
        fabric_index = 1_u8

        # Setup key set
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )

        # Add two groups (should succeed)
        [100_u16, 200_u16].each do |group_id|
          cluster.add_group_key_map(group_id, 1_u16, fabric_index)
          cluster.add_group(group_id, endpoint_id: 1_u16, group_name: nil, fabric_index: fabric_index)
        end

        # Third group should fail when adding key map
        error = expect_raises(Matter::ClusterError, /Cannot exceed max_groups_per_fabric/) do
          cluster.add_group_key_map(300_u16, 1_u16, fabric_index)
        end
        error.status.should eq(Matter::InteractionModel::StatusCode::ResourceExhausted)
      end

      it "removes endpoint from group" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Setup
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)
        cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: nil, fabric_index: fabric_index)
        cluster.add_group(100_u16, endpoint_id: 2_u16, group_name: nil, fabric_index: fabric_index)

        # Remove one endpoint
        cluster.remove_group(100_u16, endpoint_id: 1_u16, fabric_index: fabric_index)

        groups = cluster.group_table(fabric_index)
        groups.size.should eq(1)
        groups[0].endpoints.should eq([2_u16])
      end

      it "removes group when last endpoint removed" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Setup
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)
        cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: nil, fabric_index: fabric_index)

        # Remove last endpoint
        cluster.remove_group(100_u16, endpoint_id: 1_u16, fabric_index: fabric_index)

        cluster.group_table(fabric_index).should be_empty
      end

      it "isolates fabrics" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        # Setup two fabrics
        [1_u8, 2_u8].each do |fabric_index|
          cluster.handle_key_set_write(
            GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
            fabric_index
          )
          cluster.add_group_key_map(100_u16, 1_u16, fabric_index)
          cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: "Fabric #{fabric_index}", fabric_index: fabric_index)
        end

        # Each fabric should only see its own group
        groups1 = cluster.group_table(fabric_index: 1)
        groups1.size.should eq(1)
        groups1[0].group_name.should eq("Fabric 1")

        groups2 = cluster.group_table(fabric_index: 2)
        groups2.size.should eq(1)
        groups2[0].group_name.should eq("Fabric 2")
      end
    end

    describe "fabric management" do
      it "removes all data for fabric" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Create comprehensive data
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)
        cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: nil, fabric_index: fabric_index)

        # Remove fabric
        cluster.remove_fabric(fabric_index)

        # All data should be gone
        cluster.handle_key_set_read_all_indices(fabric_index).group_key_set_i_ds.should be_empty
        cluster.group_key_map(fabric_index).should be_empty
        cluster.group_table(fabric_index).should be_empty
      end

      it "only removes data for specified fabric" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))

        # Create data in two fabrics
        [1_u8, 2_u8].each do |fabric_index|
          cluster.handle_key_set_write(
            GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
            fabric_index
          )
          cluster.add_group_key_map(100_u16, 1_u16, fabric_index)
          cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: nil, fabric_index: fabric_index)
        end

        # Remove fabric 1
        cluster.remove_fabric(fabric_index: 1)

        # Fabric 1 should be empty
        cluster.handle_key_set_read_all_indices(fabric_index: 1).group_key_set_i_ds.should be_empty

        # Fabric 2 should still have data
        cluster.handle_key_set_read_all_indices(fabric_index: 2).group_key_set_i_ds.should eq([1_u16])
        cluster.group_key_map(fabric_index: 2).size.should eq(1)
        cluster.group_table(fabric_index: 2).size.should eq(1)
      end
    end

    describe "helper methods" do
      it "checks group existence" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8

        # Setup
        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(Cluster.create_key_set(id: 1_u16)),
          fabric_index
        )
        cluster.add_group_key_map(100_u16, 1_u16, fabric_index)
        cluster.add_group(100_u16, endpoint_id: 1_u16, group_name: nil, fabric_index: fabric_index)

        cluster.group_exists?(100_u16, fabric_index).should be_true
        cluster.group_exists?(999_u16, fabric_index).should be_false
      end

      it "retrieves key set with actual key material" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        fabric_index = 1_u8
        key_bytes = Cluster.test_key(0xAA)
        key_set = Cluster.create_key_set(id: 1_u16, key0: key_bytes, time0: 1000_u64)

        cluster.handle_key_set_write(
          GroupKeyManagement::KeySetWriteRequest.new(key_set),
          fabric_index
        )

        # get_key_set should return actual keys (for crypto operations)
        retrieved = cluster.get_key_set(1_u16, fabric_index)
        retrieved.should_not be_nil
        retrieved.as(GroupKeyManagement::GroupKeySetStruct).epoch_key0.should eq(key_bytes)
      end

      it "returns nil for non-existent key set" do
        cluster = GroupKeyManagement.new(Matter::DataType::EndpointNumber.new(0_u16))
        retrieved = cluster.get_key_set(99_u16, fabric_index: 1)
        retrieved.should be_nil
      end
    end
  end
end
