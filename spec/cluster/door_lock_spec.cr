require "../spec_helper"

private alias Def = Matter::Cluster::Definitions::DoorLock

private def encode_lock_request(pin : String? = nil) : Bytes
  payload = TLV::Structure.new
  if pin_value = pin
    payload[0_u8] = TLV::Any.new(pin_value.to_slice, 0_u8)
  end
  TLV::Any.new(payload, nil).to_slice
end

private def encode_unlock_with_timeout_request(timeout : UInt16, pin : String? = nil) : Bytes
  payload = TLV::Structure.new
  payload[0_u8] = TLV::Any.new(timeout, 0_u8, fixed_size: true)
  if pin_value = pin
    payload[1_u8] = TLV::Any.new(pin_value.to_slice, 1_u8)
  end
  TLV::Any.new(payload, nil).to_slice
end

describe Matter::Cluster::DoorLockCluster do
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

  describe "initialization" do
    it "creates with expected defaults" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      cluster.cluster_id.id.should eq(0x0101_u32)
      cluster.name.should eq("DoorLock")
      cluster.lock_state.should eq(Def::LockState::Locked)
      cluster.lock_type.should eq(Def::LockType::Deadbolt)
      cluster.actuator_enabled?.should be_true
      cluster.data_version.should eq(0_u32)
    end

    it "includes unbolt command only when unbolting feature is enabled" do
      cluster = Matter::Cluster::DoorLockCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::DoorLockCluster::Feature::PinCredential
      )

      cluster.commands.map(&.id.id).includes?(Matter::Cluster::DoorLockCluster::CMD_UNBOLT_DOOR).should be_false
    end
  end

  describe "lock commands" do
    it "invokes unlock and lock and updates lock state" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      unlock_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNLOCK_DOOR, encode_lock_request)
      unlock_result.should be_a(Matter::InteractionModel::Status)
      unlock_result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.lock_state.should eq(Def::LockState::Unlocked)

      lock_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_LOCK_DOOR, encode_lock_request)
      lock_result.should be_a(Matter::InteractionModel::Status)
      lock_result.as(Matter::InteractionModel::Status).success?.should be_true
      cluster.lock_state.should eq(Def::LockState::Locked)
    end

    it "notifies lockState updates for subscriptions" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      notified_attrs = [] of UInt32
      cluster.on_attribute_changed = ->(_ep : UInt16, _cl : UInt32, attr : UInt32) {
        notified_attrs << attr
      }

      cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNLOCK_DOOR, encode_lock_request)

      notified_attrs.should contain(Matter::Cluster::DoorLockCluster::ATTR_LOCK_STATE)
    end

    it "auto-relocks after unlockWithTimeout" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      result = cluster.invoke_command(
        Matter::Cluster::DoorLockCluster::CMD_UNLOCK_WITH_TIMEOUT,
        encode_unlock_with_timeout_request(1_u16)
      )
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true

      cluster.lock_state.should eq(Def::LockState::Unlocked)
      sleep 1.2.seconds
      cluster.lock_state.should eq(Def::LockState::Locked)
    end

    it "returns UnsupportedCommand for unbolt when feature disabled" do
      cluster = Matter::Cluster::DoorLockCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::DoorLockCluster::Feature::PinCredential
      )

      result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNBOLT_DOOR, encode_lock_request)
      result.should be_a(Matter::InteractionModel::Status)

      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedCommand)
    end
  end

  describe "door position sensor updates" do
    it "updates counters and notifies changed attributes" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      notified_attrs = [] of UInt32
      cluster.on_attribute_changed = ->(_ep : UInt16, _cl : UInt32, attr : UInt32) {
        notified_attrs << attr
      }

      cluster.update_door_state(Def::DoorState::DoorOpen)

      cluster.door_open_events.should eq(1_u32)
      cluster.door_closed_events.should eq(0_u32)
      notified_attrs.should contain(Matter::Cluster::DoorLockCluster::ATTR_DOOR_STATE)
      notified_attrs.should contain(Matter::Cluster::DoorLockCluster::ATTR_DOOR_OPEN_EVENTS)
    end

    it "increments closed counter when transitioning to closed" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      cluster.update_door_state(Def::DoorState::DoorOpen)
      cluster.update_door_state(Def::DoorState::DoorClosed)

      cluster.door_open_events.should eq(1_u32)
      cluster.door_closed_events.should eq(1_u32)
    end
  end

  describe "pin authorization" do
    it "requires pin when RequirePinForRemoteOperation is enabled" do
      cluster = Matter::Cluster::DoorLockCluster.new(
        endpoint_id,
        require_pin_for_remote_operation: true
      )

      result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNLOCK_DOOR, encode_lock_request)
      result.should be_a(Matter::InteractionModel::Status)

      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::Failure)
      status.cluster_status.should eq(Def::StatusCode::InvalidField.value)
    end

    it "accepts default pin for remote operations" do
      cluster = Matter::Cluster::DoorLockCluster.new(
        endpoint_id,
        require_pin_for_remote_operation: true,
        default_pin_code: "2468"
      )

      result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNLOCK_DOOR, encode_lock_request("2468"))
      result.should be_a(Matter::InteractionModel::Status)
      result.as(Matter::InteractionModel::Status).success?.should be_true
    end

    it "enters temporary lockout after too many wrong pin attempts" do
      cluster = Matter::Cluster::DoorLockCluster.new(
        endpoint_id,
        require_pin_for_remote_operation: true,
        default_pin_code: "2468",
        wrong_code_entry_limit: 1_u8,
        user_code_temporary_disable_time: 1_u8
      )

      wrong_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNLOCK_DOOR, encode_lock_request("0000"))
      wrong_status = wrong_result.as(Matter::InteractionModel::Status)
      wrong_status.status.should eq(Matter::InteractionModel::StatusCode::Failure)
      wrong_status.cluster_status.should eq(Def::StatusCode::InvalidField.value)

      locked_out_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNLOCK_DOOR, encode_lock_request("2468"))
      locked_out_status = locked_out_result.as(Matter::InteractionModel::Status)
      locked_out_status.status.should eq(Matter::InteractionModel::StatusCode::Failure)
      locked_out_status.cluster_status.should eq(Def::StatusCode::Failure.value)

      sleep 1.2.seconds
      recovered_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_UNLOCK_DOOR, encode_lock_request("2468"))
      recovered_result.as(Matter::InteractionModel::Status).success?.should be_true
    end
  end

  describe "user and credential commands" do
    it "supports setUser/getUser flow" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      set_user = Def::SetUserRequest.new(
        operation_type: Def::DataOperationType::Add,
        user_index: 2_u16,
        user_name: "Guest",
        user_unique_id: 222_u32,
        user_status: Def::UserStatus::OccupiedEnabled,
        user_type: Def::UserType::UnrestrictedUser,
        credential_rule: Def::CredentialRule::Single
      )

      set_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_SET_USER, set_user.to_slice)
      set_result.should be_a(Matter::InteractionModel::Status)
      set_result.as(Matter::InteractionModel::Status).success?.should be_true

      get_user = Def::GetUserRequest.new(user_index: 2_u16)
      get_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_GET_USER, get_user.to_slice)
      get_result.should be_a(Matter::Cluster::CommandResponse)

      response = get_result.as(Matter::Cluster::CommandResponse)
      response.command_id.should eq(Matter::Cluster::DoorLockCluster::CMD_GET_USER_RESPONSE)

      parsed = Def::GetUserResponse.from_slice(response.data)
      parsed.user_index.should eq(2_u16)
      parsed.user_name.should eq("Guest")
      parsed.user_status.should eq(Def::UserStatus::OccupiedEnabled)
    end

    it "supports setCredential/getCredentialStatus flow" do
      cluster = Matter::Cluster::DoorLockCluster.new(endpoint_id)

      credential = Def::Credential.new(
        credential_type: Def::CredentialType::Pin,
        credential_index: 1_u16
      )

      set_credential = Def::SetCredentialRequest.new(
        operation_type: Def::DataOperationType::Add,
        credential: credential,
        credential_data: "1357".to_slice,
        user_index: 2_u16,
        user_status: Def::UserStatus::OccupiedEnabled,
        user_type: Def::UserType::UnrestrictedUser
      )

      set_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_SET_CREDENTIAL, set_credential.to_slice)
      set_result.should be_a(Matter::Cluster::CommandResponse)

      set_response = Def::SetCredentialResponse.from_slice(set_result.as(Matter::Cluster::CommandResponse).data)
      set_response.status_code.should eq(Def::StatusCode::Success)
      set_response.user_index.should eq(2_u16)

      get_status = Def::GetCredentialStatusRequest.new(credential: credential)
      get_result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_GET_CREDENTIAL_STATUS, get_status.to_slice)
      get_result.should be_a(Matter::Cluster::CommandResponse)

      parsed = Def::GetCredentialStatusResponse.from_slice(get_result.as(Matter::Cluster::CommandResponse).data)
      parsed.credential_exists?.should be_true
      parsed.user_index.should eq(2_u16)
    end

    it "rejects credentials with out-of-range indexes" do
      cluster = Matter::Cluster::DoorLockCluster.new(
        endpoint_id,
        number_of_pin_users_supported: 2_u16
      )

      credential = Def::Credential.new(
        credential_type: Def::CredentialType::Pin,
        credential_index: 3_u16
      )

      request = Def::SetCredentialRequest.new(
        operation_type: Def::DataOperationType::Add,
        credential: credential,
        credential_data: "9999".to_slice,
        user_index: 2_u16,
        user_status: Def::UserStatus::OccupiedEnabled,
        user_type: Def::UserType::UnrestrictedUser
      )

      result = cluster.invoke_command(Matter::Cluster::DoorLockCluster::CMD_SET_CREDENTIAL, request.to_slice)
      result.should be_a(Matter::Cluster::CommandResponse)

      response = Def::SetCredentialResponse.from_slice(result.as(Matter::Cluster::CommandResponse).data)
      response.status_code.should eq(Def::StatusCode::InvalidField)
    end
  end
end
