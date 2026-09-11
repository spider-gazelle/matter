require "time"
require "./cluster"
require "./definitions/door_lock"

module Matter
  module Cluster
    # Door Lock Cluster (0x0101)
    #
    # Provides remote lock/unlock control plus user/credential management for a lock.
    # This implementation focuses on robust server-side behavior for the most commonly
    # used Door Lock attributes and commands, including feature-gated command support.
    class DoorLockCluster < Base
      cluster 0x0101, revision: 9

      alias Def = Definitions::DoorLock

      feature :pin_credential, bit: 0
      feature :rfid_credential, bit: 1
      feature :finger_credentials, bit: 2
      feature :week_day_access_schedules, bit: 4
      feature :door_position_sensor, bit: 5
      feature :face_credentials, bit: 6
      feature :credential_over_the_air_access, bit: 7
      feature :user, bit: 8
      feature :year_day_access_schedules, bit: 10
      feature :holiday_schedules, bit: 11
      feature :unbolting, bit: 12
      feature :aliro_provisioning, bit: 13
      feature :aliro_bleuwb, bit: 14

      enum LedSettings : UInt8
        NoLedSignal = 0
        LedSignal1  = 1
        LedSignal2  = 2
      end

      enum SoundVolume : UInt8
        Silent = 0
        Low    = 1
        Medium = 2
        High   = 3
      end

      # Wildcard indexes clearing every user / schedule / credential
      ALL_USERS     = 0xFFFE_u16
      ALL_SCHEDULES =    0xFE_u8

      # The programming PIN occupies credential index zero
      PROGRAMMING_PIN_INDEX = 0_u16

      # Lowest accepted values of the credential policy attributes
      MIN_WRONG_CODE_ENTRY_LIMIT =  1_u8
      MIN_TEMPORARY_DISABLE_TIME =  1_u8
      MIN_EXPIRING_USER_TIMEOUT  = 1_u16

      # Every bit of LocalProgrammingFeatures set
      ALL_LOCAL_PROGRAMMING_FEATURES = 0xFF_u8

      # CredentialRulesSupport with the Single rule
      CREDENTIAL_RULE_SINGLE = 0x01_u8

      # Capacity defaults
      DEFAULT_USERS_SUPPORTED           = 50_u16
      DEFAULT_SCHEDULES_SUPPORTED       =   5_u8
      DEFAULT_CREDENTIALS_PER_USER      =   5_u8
      DEFAULT_MAX_PIN_CODE_LENGTH       =   8_u8
      DEFAULT_MIN_PIN_CODE_LENGTH       =   4_u8
      DEFAULT_MAX_RFID_CODE_LENGTH      =  20_u8
      DEFAULT_MIN_RFID_CODE_LENGTH      =   4_u8
      DEFAULT_WRONG_CODE_ENTRY_LIMIT    =   3_u8
      DEFAULT_TEMPORARY_DISABLE_SECONDS =  30_u8
      DEFAULT_EXPIRING_USER_TIMEOUT     = 10_u16
      DEFAULT_LANGUAGE                  = "en"
      DEFAULT_PIN_CODE                  = "1234"

      attribute 0x0000, :lock_state, Def::LockState, nullable: true, default: Def::LockState::Locked
      attribute 0x0001, :lock_type, Def::LockType, default: Def::LockType::Deadbolt
      attribute 0x0002, :actuator_enabled, Bool, default: true
      attribute 0x0003, :door_state, Def::DoorState, nullable: true, default: Def::DoorState::DoorClosed, optional: true, requires: :door_position_sensor
      attribute 0x0004, :door_open_events, UInt32, default: 0_u32, writable: true, write_access: :manage, optional: true, requires: :door_position_sensor
      attribute 0x0005, :door_closed_events, UInt32, default: 0_u32, writable: true, write_access: :manage, optional: true, requires: :door_position_sensor
      attribute 0x0006, :open_period, UInt16, default: 0_u16, writable: true, write_access: :manage, optional: true, requires: :door_position_sensor
      attribute 0x0011, :number_of_total_users_supported, UInt16, default: DEFAULT_USERS_SUPPORTED, fixed: true, requires: :user
      attribute 0x0012, :number_of_pin_users_supported, UInt16, default: DEFAULT_USERS_SUPPORTED, fixed: true, requires: :pin_credential
      attribute 0x0013, :number_of_rfid_users_supported, UInt16, default: DEFAULT_USERS_SUPPORTED, fixed: true, requires: :rfid_credential
      attribute 0x0014, :number_of_week_day_schedules_supported_per_user, UInt8, default: DEFAULT_SCHEDULES_SUPPORTED, fixed: true, requires: :week_day_access_schedules
      attribute 0x0015, :number_of_year_day_schedules_supported_per_user, UInt8, default: DEFAULT_SCHEDULES_SUPPORTED, fixed: true, requires: :year_day_access_schedules
      attribute 0x0016, :number_of_holiday_schedules_supported, UInt8, default: DEFAULT_SCHEDULES_SUPPORTED, fixed: true, requires: :holiday_schedules
      attribute 0x0017, :max_pin_code_length, UInt8, default: DEFAULT_MAX_PIN_CODE_LENGTH, fixed: true, requires: :pin_credential
      attribute 0x0018, :min_pin_code_length, UInt8, default: DEFAULT_MIN_PIN_CODE_LENGTH, fixed: true, requires: :pin_credential
      attribute 0x0019, :max_rfid_code_length, UInt8, default: DEFAULT_MAX_RFID_CODE_LENGTH, fixed: true, requires: :rfid_credential
      attribute 0x001A, :min_rfid_code_length, UInt8, default: DEFAULT_MIN_RFID_CODE_LENGTH, fixed: true, requires: :rfid_credential
      attribute 0x001B, :credential_rules_support, UInt8, default: CREDENTIAL_RULE_SINGLE, fixed: true, requires: :user
      attribute 0x001C, :number_of_credentials_supported_per_user, UInt8, default: DEFAULT_CREDENTIALS_PER_USER, fixed: true, requires: :user
      attribute 0x0021, :language, String, default: DEFAULT_LANGUAGE, writable: true, write_access: :manage, optional: true
      attribute 0x0022, :led_settings, LedSettings, default: LedSettings::NoLedSignal, writable: true, write_access: :manage, optional: true
      attribute 0x0023, :auto_relock_time, UInt32, default: 0_u32, writable: true, write_access: :manage, optional: true
      attribute 0x0024, :sound_volume, SoundVolume, default: SoundVolume::Medium, writable: true, write_access: :manage, optional: true
      attribute 0x0025, :operating_mode, Def::OperatingMode, default: Def::OperatingMode::Normal, writable: true, write_access: :manage
      attribute 0x0026, :supported_operating_modes, UInt16, default: 0_u16, fixed: true
      attribute 0x0027, :default_configuration_register, UInt16, default: 0_u16, optional: true
      attribute 0x0028, :enable_local_programming, Bool, default: true, writable: true, write_access: :administer, optional: true
      attribute 0x0029, :enable_one_touch_locking, Bool, default: true, writable: true, write_access: :manage, optional: true
      attribute 0x002A, :enable_inside_status_led, Bool, default: true, writable: true, write_access: :manage, optional: true
      attribute 0x002B, :enable_privacy_mode_button, Bool, default: true, writable: true, write_access: :manage, optional: true
      attribute 0x002C, :local_programming_features, UInt8, default: ALL_LOCAL_PROGRAMMING_FEATURES, writable: true, write_access: :administer, optional: true
      attribute 0x0030, :wrong_code_entry_limit, UInt8, default: DEFAULT_WRONG_CODE_ENTRY_LIMIT, writable: true, write_access: :administer, min: MIN_WRONG_CODE_ENTRY_LIMIT, requires: [:pin_credential, :rfid_credential]
      attribute 0x0031, :user_code_temporary_disable_time, UInt8, default: DEFAULT_TEMPORARY_DISABLE_SECONDS, writable: true, write_access: :administer, min: MIN_TEMPORARY_DISABLE_TIME, requires: [:pin_credential, :rfid_credential]
      attribute 0x0032, :send_pin_over_the_air, Bool, default: true, writable: true, write_access: :administer, optional: true, requires: {pin_credential: true, user: false}
      attribute 0x0033, :require_pin_for_remote_operation, Bool, default: false, writable: true, write_access: :administer, requires: {pin_credential: true, credential_over_the_air_access: true}
      attribute 0x0035, :expiring_user_timeout, UInt16, default: DEFAULT_EXPIRING_USER_TIMEOUT, writable: true, write_access: :administer, min: MIN_EXPIRING_USER_TIMEOUT, optional: true, requires: :user

      command 0x00, :lock_door, request: Def::LockDoorRequest, timed: true
      command 0x01, :unlock_door, request: Def::UnlockDoorRequest, timed: true
      command 0x03, :unlock_with_timeout, request: Def::UnlockWithTimeoutRequest, timed: true, optional: true
      command 0x0B, :set_week_day_schedule, request: Def::SetWeekDayScheduleRequest, access: :administer, requires: :week_day_access_schedules
      command 0x0C, :get_week_day_schedule, request: Def::GetWeekDayScheduleRequest, response: Def::GetWeekDayScheduleResponse, access: :administer, requires: :week_day_access_schedules
      command 0x0D, :clear_week_day_schedule, request: Def::ClearWeekDayScheduleRequest, access: :administer, requires: :week_day_access_schedules
      command 0x0E, :set_year_day_schedule, request: Def::SetYearDayScheduleRequest, access: :administer, requires: :year_day_access_schedules
      command 0x0F, :get_year_day_schedule, request: Def::GetYearDayScheduleRequest, response: Def::GetYearDayScheduleResponse, access: :administer, requires: :year_day_access_schedules
      command 0x10, :clear_year_day_schedule, request: Def::ClearYearDayScheduleRequest, access: :administer, requires: :year_day_access_schedules
      command 0x11, :set_holiday_schedule, request: Def::SetHolidayScheduleRequest, access: :administer, requires: :holiday_schedules
      command 0x12, :get_holiday_schedule, request: Def::GetHolidayScheduleRequest, response: Def::GetHolidayScheduleResponse, access: :administer, requires: :holiday_schedules
      command 0x13, :clear_holiday_schedule, request: Def::ClearHolidayScheduleRequest, access: :administer, requires: :holiday_schedules
      command 0x1A, :set_user, request: Def::SetUserRequest, access: :administer, timed: true, requires: :user
      command 0x1B, :get_user, request: Def::GetUserRequest, response: Def::GetUserResponse, response_id: 0x1C, access: :administer, requires: :user
      command 0x1D, :clear_user, request: Def::ClearUserRequest, access: :administer, timed: true, requires: :user
      command 0x22, :set_credential, request: Def::SetCredentialRequest, response: Def::SetCredentialResponse, response_id: 0x23, access: :administer, timed: true, requires: :user
      command 0x24, :get_credential_status, request: Def::GetCredentialStatusRequest, response: Def::GetCredentialStatusResponse, response_id: 0x25, access: :administer, requires: :user
      command 0x26, :clear_credential, request: Def::ClearCredentialRequest, access: :administer, timed: true, requires: :user
      command 0x27, :unbolt_door, request: Def::UnboltDoorRequest, timed: true, requires: :unbolting

      event 0x00, :door_lock_alarm, priority: :critical
      event 0x01, :door_state_change, priority: :critical
      event 0x02, :lock_operation, priority: :critical
      event 0x03, :lock_operation_error, priority: :critical
      event 0x04, :lock_user_change, priority: :info

      private struct UserRecord
        property user_index : UInt16
        property user_name : String
        property user_unique_id : UInt32
        property user_status : Def::UserStatus
        property user_type : Def::UserType
        property credential_rule : Def::CredentialRule
        property credentials : Array(Def::Credential)
        property creator_fabric_index : UInt8?
        property last_modified_fabric_index : UInt8?

        def initialize(
          @user_index : UInt16,
          @user_name : String,
          @user_unique_id : UInt32,
          @user_status : Def::UserStatus,
          @user_type : Def::UserType,
          @credential_rule : Def::CredentialRule,
          @credentials : Array(Def::Credential) = [] of Def::Credential,
          @creator_fabric_index : UInt8? = nil,
          @last_modified_fabric_index : UInt8? = nil,
        )
        end
      end

      private struct CredentialRecord
        property credential : Def::Credential
        property credential_data : Bytes
        property user_index : UInt16?
        property creator_fabric_index : UInt8?
        property last_modified_fabric_index : UInt8?

        def initialize(
          @credential : Def::Credential,
          @credential_data : Bytes,
          @user_index : UInt16? = nil,
          @creator_fabric_index : UInt8? = nil,
          @last_modified_fabric_index : UInt8? = nil,
        )
        end
      end

      private record WeekDaySchedule, week_day : UInt8, start_hour : UInt8, start_minute : UInt8, end_hour : UInt8, end_minute : UInt8
      private record YearDaySchedule, local_start_time : UInt32, local_end_time : UInt32
      private record HolidaySchedule, local_start_time : UInt32, local_end_time : UInt32, operating_mode : Def::OperatingMode

      @users = {} of UInt16 => UserRecord
      @credentials = {} of Tuple(UInt8, UInt16) => CredentialRecord
      @week_day_schedules = {} of Tuple(UInt16, UInt8) => WeekDaySchedule
      @year_day_schedules = {} of Tuple(UInt16, UInt8) => YearDaySchedule
      @holiday_schedules = {} of UInt8 => HolidaySchedule

      @failed_remote_pin_attempts : UInt8 = 0_u8
      @lockout_until : Time? = nil
      @relock_generation : UInt64 = 0_u64

      getter default_pin_code : String

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::DoorPositionSensor | Feature::PinCredential | Feature::CredentialOverTheAirAccess | Feature::User | Feature::Unbolting,
        @lock_state : Def::LockState? = Def::LockState::Locked,
        @lock_type : Def::LockType = Def::LockType::Deadbolt,
        @actuator_enabled : Bool = true,
        @door_state : Def::DoorState? = Def::DoorState::DoorClosed,
        @language : String = DEFAULT_LANGUAGE,
        @led_settings : LedSettings = LedSettings::NoLedSignal,
        @auto_relock_time : UInt32 = 0_u32,
        @sound_volume : SoundVolume = SoundVolume::Medium,
        @operating_mode : Def::OperatingMode = Def::OperatingMode::Normal,
        @supported_operating_modes : UInt16 = 0_u16,
        @default_configuration_register : UInt16 = 0_u16,
        @enable_local_programming : Bool = true,
        @enable_one_touch_locking : Bool = true,
        @enable_inside_status_led : Bool = true,
        @enable_privacy_mode_button : Bool = true,
        @local_programming_features : UInt8 = ALL_LOCAL_PROGRAMMING_FEATURES,
        @number_of_total_users_supported : UInt16 = DEFAULT_USERS_SUPPORTED,
        @number_of_pin_users_supported : UInt16 = DEFAULT_USERS_SUPPORTED,
        @number_of_rfid_users_supported : UInt16 = DEFAULT_USERS_SUPPORTED,
        @number_of_week_day_schedules_supported_per_user : UInt8 = DEFAULT_SCHEDULES_SUPPORTED,
        @number_of_year_day_schedules_supported_per_user : UInt8 = DEFAULT_SCHEDULES_SUPPORTED,
        @number_of_holiday_schedules_supported : UInt8 = DEFAULT_SCHEDULES_SUPPORTED,
        @max_pin_code_length : UInt8 = DEFAULT_MAX_PIN_CODE_LENGTH,
        @min_pin_code_length : UInt8 = DEFAULT_MIN_PIN_CODE_LENGTH,
        @max_rfid_code_length : UInt8 = DEFAULT_MAX_RFID_CODE_LENGTH,
        @min_rfid_code_length : UInt8 = DEFAULT_MIN_RFID_CODE_LENGTH,
        @credential_rules_support : UInt8 = CREDENTIAL_RULE_SINGLE,
        @number_of_credentials_supported_per_user : UInt8 = DEFAULT_CREDENTIALS_PER_USER,
        @wrong_code_entry_limit : UInt8 = DEFAULT_WRONG_CODE_ENTRY_LIMIT,
        @user_code_temporary_disable_time : UInt8 = DEFAULT_TEMPORARY_DISABLE_SECONDS,
        @send_pin_over_the_air : Bool = true,
        @require_pin_for_remote_operation : Bool = false,
        @expiring_user_timeout : UInt16 = DEFAULT_EXPIRING_USER_TIMEOUT,
        @default_pin_code : String = DEFAULT_PIN_CODE,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        raise ArgumentError.new("credentialOverTheAirAccess requires pinCredential") if @feature_map.credential_over_the_air_access? && !@feature_map.pin_credential?
        raise ArgumentError.new("user schedules require user feature") if (@feature_map.week_day_access_schedules? || @feature_map.year_day_access_schedules? || @feature_map.holiday_schedules?) && !@feature_map.user?
        raise ArgumentError.new("min_pin_code_length must be <= max_pin_code_length") if @min_pin_code_length > @max_pin_code_length
        raise ArgumentError.new("min_rfid_code_length must be <= max_rfid_code_length") if @min_rfid_code_length > @max_rfid_code_length
        raise ArgumentError.new("wrong_code_entry_limit must be >= 1") if @wrong_code_entry_limit < MIN_WRONG_CODE_ENTRY_LIMIT
        raise ArgumentError.new("user_code_temporary_disable_time must be >= 1") if @user_code_temporary_disable_time < MIN_TEMPORARY_DISABLE_TIME

        if @feature_map.user?
          # Keep a default programming user slot for easier integration testing.
          @users[1_u16] = UserRecord.new(
            user_index: 1_u16,
            user_name: "Admin",
            user_unique_id: 1_u32,
            user_status: Def::UserStatus::OccupiedEnabled,
            user_type: Def::UserType::ProgrammingUser,
            credential_rule: Def::CredentialRule::Single,
            credentials: [] of Def::Credential,
            creator_fabric_index: @request_fabric_index,
            last_modified_fabric_index: @request_fabric_index
          )
        end
      end

      # ------------------------------------------------------------------------
      # Lock commands
      # ------------------------------------------------------------------------

      def lock_door(request : Def::LockDoorRequest) : InteractionModel::Status
        lock(pin: pin_from_slice(request.pin_code))
      end

      def unlock_door(request : Def::UnlockDoorRequest) : InteractionModel::Status
        unlock(pin: pin_from_slice(request.pin_code))
      end

      def unlock_with_timeout(request : Def::UnlockWithTimeoutRequest) : InteractionModel::Status
        unlock_with_timeout(request.timeout, pin: pin_from_slice(request.pin_code))
      end

      def unbolt_door(request : Def::UnboltDoorRequest) : InteractionModel::Status
        unbolt(pin: pin_from_slice(request.pin_code))
      end

      # ------------------------------------------------------------------------
      # Public API for local application logic
      # ------------------------------------------------------------------------

      def lock(pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        cancel_pending_relock
        self.lock_state = Def::LockState::Locked
        InteractionModel::Status.success
      end

      def unlock(pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        self.lock_state = Def::LockState::Unlocked
        schedule_relock(@auto_relock_time)
        InteractionModel::Status.success
      end

      def unlock_with_timeout(timeout_seconds : UInt16, pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        self.lock_state = Def::LockState::Unlocked
        schedule_relock(timeout_seconds.to_u32)
        InteractionModel::Status.success
      end

      def unbolt(pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.unsupported_command unless @feature_map.unbolting?
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        self.lock_state = Def::LockState::Unlatched
        schedule_relock(@auto_relock_time)
        InteractionModel::Status.success
      end

      def locked? : Bool
        @lock_state == Def::LockState::Locked
      end

      def unlocked? : Bool
        @lock_state == Def::LockState::Unlocked
      end

      def unlatched? : Bool
        @lock_state == Def::LockState::Unlatched
      end

      # Records a door position change and counts the open / close events; the
      # counters move before DoorState so its callback sees them updated.
      def update_door_state(new_state : Def::DoorState?) : Nil
        return unless @feature_map.door_position_sensor?
        return if @door_state == new_state

        case new_state
        when Def::DoorState::DoorOpen
          self.door_open_events = @door_open_events + 1_u32
        when Def::DoorState::DoorClosed
          self.door_closed_events = @door_closed_events + 1_u32
        end

        self.door_state = new_state
      end

      # ------------------------------------------------------------------------
      # Schedule commands
      # ------------------------------------------------------------------------

      def set_week_day_schedule(request : Def::SetWeekDayScheduleRequest) : InteractionModel::Status # ameba:disable Naming/AccessorMethodName
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_user_index?(request.user_index)
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_week_day_schedule_index?(request.week_day_index)
        return InteractionModel::Status.cluster_failure(Def::StatusCode::NotFound) unless @users.has_key?(request.user_index)

        @week_day_schedules[{request.user_index, request.week_day_index}] = WeekDaySchedule.new(
          request.week_day,
          request.start_hour,
          request.start_minute,
          request.end_hour,
          request.end_minute
        )
        increment_version
        InteractionModel::Status.success
      end

      def get_week_day_schedule(request : Def::GetWeekDayScheduleRequest) : Def::GetWeekDayScheduleResponse
        if !valid_user_index?(request.user_index) || !valid_week_day_schedule_index?(request.week_day_index)
          return week_day_schedule_response(request, Def::StatusCode::InvalidField)
        end

        if schedule = @week_day_schedules[{request.user_index, request.week_day_index}]?
          week_day_schedule_response(request, Def::StatusCode::Success, schedule)
        else
          week_day_schedule_response(request, Def::StatusCode::NotFound)
        end
      end

      def clear_week_day_schedule(request : Def::ClearWeekDayScheduleRequest) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_user_index?(request.user_index)
        unless request.week_day_index == ALL_SCHEDULES || valid_week_day_schedule_index?(request.week_day_index)
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField)
        end

        if request.week_day_index == ALL_SCHEDULES
          @week_day_schedules.keys.select { |(user_index, _)| user_index == request.user_index }.each do |key|
            @week_day_schedules.delete(key)
          end
        else
          @week_day_schedules.delete({request.user_index, request.week_day_index})
        end

        increment_version
        InteractionModel::Status.success
      end

      def set_year_day_schedule(request : Def::SetYearDayScheduleRequest) : InteractionModel::Status # ameba:disable Naming/AccessorMethodName
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_user_index?(request.user_index)
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_year_day_schedule_index?(request.year_day_index)
        return InteractionModel::Status.cluster_failure(Def::StatusCode::NotFound) unless @users.has_key?(request.user_index)
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) if request.local_start_time >= request.local_end_time

        @year_day_schedules[{request.user_index, request.year_day_index}] = YearDaySchedule.new(
          request.local_start_time,
          request.local_end_time
        )
        increment_version
        InteractionModel::Status.success
      end

      def get_year_day_schedule(request : Def::GetYearDayScheduleRequest) : Def::GetYearDayScheduleResponse
        if !valid_user_index?(request.user_index) || !valid_year_day_schedule_index?(request.year_day_index)
          return year_day_schedule_response(request, Def::StatusCode::InvalidField)
        end

        if schedule = @year_day_schedules[{request.user_index, request.year_day_index}]?
          year_day_schedule_response(request, Def::StatusCode::Success, schedule)
        else
          year_day_schedule_response(request, Def::StatusCode::NotFound)
        end
      end

      def clear_year_day_schedule(request : Def::ClearYearDayScheduleRequest) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_user_index?(request.user_index)
        unless request.year_day_index == ALL_SCHEDULES || valid_year_day_schedule_index?(request.year_day_index)
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField)
        end

        if request.year_day_index == ALL_SCHEDULES
          @year_day_schedules.keys.select { |(user_index, _)| user_index == request.user_index }.each do |key|
            @year_day_schedules.delete(key)
          end
        else
          @year_day_schedules.delete({request.user_index, request.year_day_index})
        end

        increment_version
        InteractionModel::Status.success
      end

      def set_holiday_schedule(request : Def::SetHolidayScheduleRequest) : InteractionModel::Status # ameba:disable Naming/AccessorMethodName
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_holiday_schedule_index?(request.holiday_index)
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) if request.local_start_time >= request.local_end_time

        @holiday_schedules[request.holiday_index] = HolidaySchedule.new(
          request.local_start_time,
          request.local_end_time,
          request.operating_mode
        )
        increment_version
        InteractionModel::Status.success
      end

      def get_holiday_schedule(request : Def::GetHolidayScheduleRequest) : Def::GetHolidayScheduleResponse
        return holiday_schedule_response(request, Def::StatusCode::InvalidField) unless valid_holiday_schedule_index?(request.holiday_index)

        if schedule = @holiday_schedules[request.holiday_index]?
          holiday_schedule_response(request, Def::StatusCode::Success, schedule)
        else
          holiday_schedule_response(request, Def::StatusCode::NotFound)
        end
      end

      def clear_holiday_schedule(request : Def::ClearHolidayScheduleRequest) : InteractionModel::Status
        unless request.holiday_index == ALL_SCHEDULES || valid_holiday_schedule_index?(request.holiday_index)
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField)
        end

        if request.holiday_index == ALL_SCHEDULES
          @holiday_schedules.clear
        else
          @holiday_schedules.delete(request.holiday_index)
        end

        increment_version
        InteractionModel::Status.success
      end

      # ------------------------------------------------------------------------
      # User commands
      # ------------------------------------------------------------------------

      def set_user(request : Def::SetUserRequest) : InteractionModel::Status # ameba:disable Naming/AccessorMethodName
        return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_user_index?(request.user_index)

        case request.operation_type
        when Def::DataOperationType::Add
          return InteractionModel::Status.cluster_failure(Def::StatusCode::Occupied) if @users.has_key?(request.user_index)
          if @users.size >= @number_of_total_users_supported
            return InteractionModel::Status.cluster_failure(Def::StatusCode::ResourceExhausted)
          end

          @users[request.user_index] = UserRecord.new(
            user_index: request.user_index,
            user_name: request.user_name || "",
            user_unique_id: request.user_unique_id || request.user_index.to_u32,
            user_status: request.user_status || Def::UserStatus::OccupiedEnabled,
            user_type: request.user_type || Def::UserType::UnrestrictedUser,
            credential_rule: request.credential_rule || Def::CredentialRule::Single,
            credentials: [] of Def::Credential,
            creator_fabric_index: @request_fabric_index,
            last_modified_fabric_index: @request_fabric_index
          )
        when Def::DataOperationType::Modify
          unless user = @users[request.user_index]?
            return InteractionModel::Status.cluster_failure(Def::StatusCode::NotFound)
          end

          if user_name = request.user_name
            user.user_name = user_name
          end

          if user_unique_id = request.user_unique_id
            user.user_unique_id = user_unique_id
          end

          if user_status = request.user_status
            user.user_status = user_status
          end

          if user_type = request.user_type
            user.user_type = user_type
          end

          if credential_rule = request.credential_rule
            user.credential_rule = credential_rule
          end

          user.last_modified_fabric_index = @request_fabric_index
          @users[request.user_index] = user
        when Def::DataOperationType::Clear
          clear_user_record(request.user_index)
        else
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField)
        end

        increment_version
        InteractionModel::Status.success
      end

      def get_user(request : Def::GetUserRequest) : Def::GetUserResponse
        return vacant_user_response(request.user_index, nil) unless valid_user_index?(request.user_index)

        next_user = @users.keys.select { |index| index > request.user_index }.sort!.first?

        if user = @users[request.user_index]?
          Def::GetUserResponse.new(
            user_index: user.user_index,
            user_name: user.user_name,
            user_unique_id: user.user_unique_id,
            user_status: user.user_status,
            user_type: user.user_type,
            credential_rule: user.credential_rule,
            credentials: user.credentials.empty? ? nil : user.credentials,
            creator_fabric_index: fabric_index_from_u8(user.creator_fabric_index),
            last_modified_fabric_index: fabric_index_from_u8(user.last_modified_fabric_index),
            next_user_index: next_user
          )
        else
          vacant_user_response(request.user_index, next_user)
        end
      end

      def clear_user(request : Def::ClearUserRequest) : InteractionModel::Status
        if request.user_index == ALL_USERS
          @users.keys.each { |user_index| clear_user_record(user_index) }
        else
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_user_index?(request.user_index)
          clear_user_record(request.user_index)
        end

        increment_version
        InteractionModel::Status.success
      end

      # ------------------------------------------------------------------------
      # Credential commands
      # ------------------------------------------------------------------------

      def set_credential(request : Def::SetCredentialRequest) : Def::SetCredentialResponse # ameba:disable Naming/AccessorMethodName
        if (user_index = request.user_index) && !valid_user_index?(user_index)
          return set_credential_response(request, Def::StatusCode::InvalidField)
        end

        credential_key = credential_key(request.credential)

        if error = validate_credential_input(request.credential, request.credential_data)
          return set_credential_response(request, error)
        end

        created_user_index : UInt16? = nil

        case request.operation_type
        when Def::DataOperationType::Add
          if @credentials.has_key?(credential_key)
            status = Def::StatusCode::Occupied
          else
            if user_index = request.user_index
              if @users.size >= @number_of_total_users_supported && !@users.has_key?(user_index)
                return set_credential_response(request, Def::StatusCode::ResourceExhausted)
              end

              ensure_user_exists(user_index, request.user_status, request.user_type)
              unless @users.has_key?(user_index)
                return set_credential_response(request, Def::StatusCode::ResourceExhausted)
              end

              if user = @users[user_index]?
                if !credential_belongs_to_user?(user, request.credential) && user.credentials.size >= @number_of_credentials_supported_per_user
                  return set_credential_response(request, Def::StatusCode::ResourceExhausted)
                end
              end
            end

            record = CredentialRecord.new(
              credential: request.credential,
              credential_data: request.credential_data,
              user_index: request.user_index,
              creator_fabric_index: @request_fabric_index,
              last_modified_fabric_index: @request_fabric_index
            )
            @credentials[credential_key] = record
            add_credential_to_user(record)
            created_user_index = request.user_index
            status = Def::StatusCode::Success
          end
        when Def::DataOperationType::Modify
          if existing = @credentials[credential_key]?
            remove_credential_from_user(existing)

            existing.credential_data = request.credential_data
            if new_user_index = request.user_index
              ensure_user_exists(new_user_index, request.user_status, request.user_type)
              unless @users.has_key?(new_user_index)
                add_credential_to_user(existing)
                return set_credential_response(request, Def::StatusCode::ResourceExhausted)
              end

              if user = @users[new_user_index]?
                if !credential_belongs_to_user?(user, request.credential) && user.credentials.size >= @number_of_credentials_supported_per_user
                  add_credential_to_user(existing)
                  return set_credential_response(request, Def::StatusCode::ResourceExhausted)
                end
              end
              existing.user_index = new_user_index
            end
            existing.last_modified_fabric_index = @request_fabric_index
            @credentials[credential_key] = existing
            add_credential_to_user(existing)
            status = Def::StatusCode::Success
          else
            status = Def::StatusCode::NotFound
          end
        when Def::DataOperationType::Clear
          if existing = @credentials.delete(credential_key)
            remove_credential_from_user(existing)
            status = Def::StatusCode::Success
          else
            status = Def::StatusCode::NotFound
          end
        else
          status = Def::StatusCode::InvalidField
        end

        increment_version if status == Def::StatusCode::Success

        set_credential_response(request, status, created_user_index)
      end

      def get_credential_status(request : Def::GetCredentialStatusRequest) : Def::GetCredentialStatusResponse
        unless credential_index_supported?(request.credential)
          return Def::GetCredentialStatusResponse.new(
            credential_exists: false,
            user_index: nil,
            creator_fabric_index: nil,
            last_modified_fabric_index: nil,
            next_credential_index: nil
          )
        end

        next_index = next_occupied_credential_index(request.credential.credential_type, request.credential.credential_index)

        if credential = @credentials[credential_key(request.credential)]?
          Def::GetCredentialStatusResponse.new(
            credential_exists: true,
            user_index: credential.user_index,
            creator_fabric_index: fabric_index_from_u8(credential.creator_fabric_index),
            last_modified_fabric_index: fabric_index_from_u8(credential.last_modified_fabric_index),
            next_credential_index: next_index
          )
        else
          Def::GetCredentialStatusResponse.new(
            credential_exists: false,
            user_index: nil,
            creator_fabric_index: nil,
            last_modified_fabric_index: nil,
            next_credential_index: next_index
          )
        end
      end

      def clear_credential(request : Def::ClearCredentialRequest) : InteractionModel::Status
        if credential = request.credential
          unless credential.credential_index == ALL_USERS || credential_index_supported?(credential)
            return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField)
          end

          if credential.credential_index == ALL_USERS
            keys_to_clear = @credentials.keys.select { |(type, _)| type == credential.credential_type.value.to_u8 }
            keys_to_clear.each do |key|
              if existing = @credentials.delete(key)
                remove_credential_from_user(existing)
              end
            end
          else
            key = credential_key(credential)
            if existing = @credentials.delete(key)
              remove_credential_from_user(existing)
            end
          end
        else
          @credentials.values.each do |record|
            remove_credential_from_user(record)
          end
          @credentials.clear
        end

        increment_version
        InteractionModel::Status.success
      end

      # ------------------------------------------------------------------------
      # Response builders
      # ------------------------------------------------------------------------

      private def week_day_schedule_response(request : Def::GetWeekDayScheduleRequest, status : Def::StatusCode, schedule : WeekDaySchedule? = nil) : Def::GetWeekDayScheduleResponse
        Def::GetWeekDayScheduleResponse.new(
          week_day_index: request.week_day_index,
          user_index: request.user_index,
          status_code: status,
          week_day: schedule.try(&.week_day) || 0_u8,
          start_hour: schedule.try(&.start_hour) || 0_u8,
          start_minute: schedule.try(&.start_minute) || 0_u8,
          end_hour: schedule.try(&.end_hour) || 0_u8,
          end_minute: schedule.try(&.end_minute) || 0_u8
        )
      end

      private def year_day_schedule_response(request : Def::GetYearDayScheduleRequest, status : Def::StatusCode, schedule : YearDaySchedule? = nil) : Def::GetYearDayScheduleResponse
        Def::GetYearDayScheduleResponse.new(
          year_day_index: request.year_day_index,
          user_index: request.user_index,
          status_code: status,
          local_start_time: schedule.try(&.local_start_time) || 0_u32,
          local_end_time: schedule.try(&.local_end_time) || 0_u32
        )
      end

      private def holiday_schedule_response(request : Def::GetHolidayScheduleRequest, status : Def::StatusCode, schedule : HolidaySchedule? = nil) : Def::GetHolidayScheduleResponse
        Def::GetHolidayScheduleResponse.new(
          holiday_index: request.holiday_index,
          status_code: status,
          local_start_time: schedule.try(&.local_start_time) || 0_u32,
          local_end_time: schedule.try(&.local_end_time) || 0_u32,
          operating_mode: schedule.try(&.operating_mode) || Def::OperatingMode::Normal
        )
      end

      private def vacant_user_response(user_index : UInt16, next_user_index : UInt16?) : Def::GetUserResponse
        Def::GetUserResponse.new(
          user_index: user_index,
          user_name: nil,
          user_unique_id: nil,
          user_status: Def::UserStatus::Available,
          user_type: nil,
          credential_rule: nil,
          credentials: nil,
          creator_fabric_index: nil,
          last_modified_fabric_index: nil,
          next_user_index: next_user_index
        )
      end

      private def set_credential_response(request : Def::SetCredentialRequest, status : Def::StatusCode, user_index : UInt16? = nil) : Def::SetCredentialResponse
        Def::SetCredentialResponse.new(
          status_code: status,
          user_index: user_index,
          next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
        )
      end

      # ------------------------------------------------------------------------
      # Remote operation policy
      # ------------------------------------------------------------------------

      private def remote_control_allowed? : Bool
        return false unless @actuator_enabled
        return false if @operating_mode.no_remote_lock_unlock? || @operating_mode.privacy?
        return false if lockout_active

        true
      end

      private def lockout_active : Bool
        if until_time = @lockout_until
          return Time.utc < until_time
        end

        false
      end

      private def authorize_remote_operation(pin : String?) : InteractionModel::Status?
        requires_pin = @feature_map.pin_credential? && @feature_map.credential_over_the_air_access? && @require_pin_for_remote_operation

        if requires_pin
          pin_value = pin
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless pin_value
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) if pin_value.empty?

          unless valid_pin?(pin_value)
            record_failed_pin_attempt
            return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField)
          end
          clear_failed_pin_state
          return
        end

        if pin && !pin.empty? && @feature_map.pin_credential?
          unless valid_pin?(pin)
            record_failed_pin_attempt
            return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField)
          end
          clear_failed_pin_state
        end

        nil
      end

      private def valid_pin?(pin : String) : Bool
        pin_matches_credential = @credentials.values.any? do |credential|
          credential.credential.credential_type.pin? && String.new(credential.credential_data) == pin
        end

        return true if pin_matches_credential
        pin == @default_pin_code
      end

      private def record_failed_pin_attempt : Nil
        if @failed_remote_pin_attempts < UInt8::MAX
          @failed_remote_pin_attempts = @failed_remote_pin_attempts &+ 1_u8
        end

        if @failed_remote_pin_attempts >= @wrong_code_entry_limit
          @failed_remote_pin_attempts = 0_u8
          @lockout_until = Time.utc + @user_code_temporary_disable_time.seconds
        end
      end

      private def clear_failed_pin_state : Nil
        @failed_remote_pin_attempts = 0_u8
        @lockout_until = nil
      end

      # Relocks after *after_seconds* unless a later lock operation superseded it
      private def schedule_relock(after_seconds : UInt32) : Nil
        return if after_seconds == 0_u32

        @relock_generation = @relock_generation &+ 1_u64
        generation = @relock_generation

        spawn do
          sleep after_seconds.seconds
          next unless generation == @relock_generation

          self.lock_state = Def::LockState::Locked
        end
      end

      private def cancel_pending_relock : Nil
        @relock_generation = @relock_generation &+ 1_u64
      end

      # ------------------------------------------------------------------------
      # User / credential tables
      # ------------------------------------------------------------------------

      private def ensure_user_exists(user_index : UInt16, status : Def::UserStatus?, user_type : Def::UserType?) : Nil
        return if @users.has_key?(user_index)
        return unless valid_user_index?(user_index)
        return if @users.size >= @number_of_total_users_supported

        @users[user_index] = UserRecord.new(
          user_index: user_index,
          user_name: "",
          user_unique_id: user_index.to_u32,
          user_status: status || Def::UserStatus::OccupiedEnabled,
          user_type: user_type || Def::UserType::UnrestrictedUser,
          credential_rule: Def::CredentialRule::Single,
          credentials: [] of Def::Credential,
          creator_fabric_index: @request_fabric_index,
          last_modified_fabric_index: @request_fabric_index
        )
      end

      private def clear_user_record(user_index : UInt16) : Nil
        @users.delete(user_index)

        @credentials.keys.select { |key| @credentials[key]?.try(&.user_index) == user_index }.each do |key|
          @credentials.delete(key)
        end

        @week_day_schedules.keys.select { |(target_user, _)| target_user == user_index }.each { |key| @week_day_schedules.delete(key) }
        @year_day_schedules.keys.select { |(target_user, _)| target_user == user_index }.each { |key| @year_day_schedules.delete(key) }
      end

      private def credential_belongs_to_user?(user : UserRecord, credential : Def::Credential) : Bool
        user.credentials.any? do |existing|
          existing.credential_type == credential.credential_type && existing.credential_index == credential.credential_index
        end
      end

      private def add_credential_to_user(record : CredentialRecord) : Nil
        return unless user_index = record.user_index
        return unless user = @users[user_index]?

        unless credential_belongs_to_user?(user, record.credential)
          user.credentials << record.credential
          user.last_modified_fabric_index = @request_fabric_index
          @users[user_index] = user
        end
      end

      private def remove_credential_from_user(record : CredentialRecord) : Nil
        return unless user_index = record.user_index
        return unless user = @users[user_index]?

        user.credentials = user.credentials.reject do |credential|
          credential.credential_type == record.credential.credential_type && credential.credential_index == record.credential.credential_index
        end
        user.last_modified_fabric_index = @request_fabric_index

        @users[user_index] = user
      end

      private def validate_credential_input(credential : Def::Credential, credential_data : Bytes) : Def::StatusCode?
        return Def::StatusCode::InvalidField unless credential_index_supported?(credential)

        case credential.credential_type
        when Def::CredentialType::ProgrammingPin
          return Def::StatusCode::InvalidField unless @feature_map.pin_credential?
          return Def::StatusCode::InvalidField unless credential.credential_index == PROGRAMMING_PIN_INDEX
          return Def::StatusCode::InvalidField if credential_data.empty?
        when Def::CredentialType::Pin
          return Def::StatusCode::InvalidField unless @feature_map.pin_credential?
          return Def::StatusCode::InvalidField unless credential_data.size.in?(@min_pin_code_length..@max_pin_code_length)
        when Def::CredentialType::Rfid
          return Def::StatusCode::InvalidField unless @feature_map.rfid_credential?
          return Def::StatusCode::InvalidField unless credential_data.size.in?(@min_rfid_code_length..@max_rfid_code_length)
        when Def::CredentialType::Fingerprint, Def::CredentialType::FingerVein
          return Def::StatusCode::InvalidField unless @feature_map.finger_credentials?
        when Def::CredentialType::Face
          return Def::StatusCode::InvalidField unless @feature_map.face_credentials?
        when Def::CredentialType::AliroCredentialIssuerKey,
             Def::CredentialType::AliroEvictableEndpointKey,
             Def::CredentialType::AliroNonEvictableEndpointKey
          return Def::StatusCode::InvalidField unless @feature_map.aliro_provisioning?
        else
          return Def::StatusCode::InvalidField
        end

        nil
      end

      private def credential_key(credential : Def::Credential) : Tuple(UInt8, UInt16)
        {credential.credential_type.value.to_u8, credential.credential_index}
      end

      private def next_available_credential_index(type : Def::CredentialType, current_index : UInt16) : UInt16?
        max_index = max_credential_index(type)
        index = current_index + 1

        while index <= max_index
          return index unless @credentials.has_key?({type.value.to_u8, index})
          index += 1
        end

        nil
      end

      private def next_occupied_credential_index(type : Def::CredentialType, current_index : UInt16) : UInt16?
        @credentials.keys
          .select { |(credential_type, credential_index)| credential_type == type.value.to_u8 && credential_index > current_index }
          .min_of?(&.[1])
      end

      private def max_credential_index(type : Def::CredentialType) : UInt16
        case type
        when Def::CredentialType::Pin
          @number_of_pin_users_supported
        when Def::CredentialType::Rfid
          @number_of_rfid_users_supported
        else
          @number_of_total_users_supported
        end
      end

      private def valid_user_index?(user_index : UInt16) : Bool
        user_index >= 1_u16 && user_index <= @number_of_total_users_supported
      end

      private def valid_week_day_schedule_index?(schedule_index : UInt8) : Bool
        schedule_index >= 1_u8 && schedule_index <= @number_of_week_day_schedules_supported_per_user
      end

      private def valid_year_day_schedule_index?(schedule_index : UInt8) : Bool
        schedule_index >= 1_u8 && schedule_index <= @number_of_year_day_schedules_supported_per_user
      end

      private def valid_holiday_schedule_index?(schedule_index : UInt8) : Bool
        schedule_index >= 1_u8 && schedule_index <= @number_of_holiday_schedules_supported
      end

      private def credential_index_supported?(credential : Def::Credential) : Bool
        return false unless credential_type_supported?(credential.credential_type)
        return credential.credential_index == PROGRAMMING_PIN_INDEX if credential.credential_type.programming_pin?

        max = max_credential_index(credential.credential_type)
        credential.credential_index >= 1_u16 && credential.credential_index <= max
      end

      private def credential_type_supported?(credential_type : Def::CredentialType) : Bool
        case credential_type
        when Def::CredentialType::ProgrammingPin, Def::CredentialType::Pin
          @feature_map.pin_credential?
        when Def::CredentialType::Rfid
          @feature_map.rfid_credential?
        when Def::CredentialType::Fingerprint, Def::CredentialType::FingerVein
          @feature_map.finger_credentials?
        when Def::CredentialType::Face
          @feature_map.face_credentials?
        when Def::CredentialType::AliroCredentialIssuerKey,
             Def::CredentialType::AliroEvictableEndpointKey,
             Def::CredentialType::AliroNonEvictableEndpointKey
          @feature_map.aliro_provisioning?
        else
          false
        end
      end

      private def pin_from_slice(pin_slice : Slice(UInt8)?) : String?
        return unless pin_slice
        String.new(pin_slice)
      end

      private def fabric_index_from_u8(index : UInt8?) : DataType::FabricIndex?
        return unless index
        DataType::FabricIndex.new(index)
      end
    end
  end
end
