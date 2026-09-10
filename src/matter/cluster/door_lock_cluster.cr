require "time"
require "json"
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
      CLUSTER_ID = 0x0101_u32

      alias Def = Definitions::DoorLock

      @[Flags]
      enum Feature : UInt32
        PinCredential              = 0x0001
        RfidCredential             = 0x0002
        FingerCredentials          = 0x0004
        WeekDayAccessSchedules     = 0x0010
        DoorPositionSensor         = 0x0020
        FaceCredentials            = 0x0040
        CredentialOverTheAirAccess = 0x0080
        User                       = 0x0100
        YearDayAccessSchedules     = 0x0400
        HolidaySchedules           = 0x0800
        Unbolting                  = 0x1000
        AliroProvisioning          = 0x2000
        AliroBleuwb                = 0x4000
      end

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

      # Required attributes
      ATTR_LOCK_STATE       = 0x0000_u32
      ATTR_LOCK_TYPE        = 0x0001_u32
      ATTR_ACTUATOR_ENABLED = 0x0002_u32

      # Door Position Sensor feature attributes
      ATTR_DOOR_STATE         = 0x0003_u32
      ATTR_DOOR_OPEN_EVENTS   = 0x0004_u32
      ATTR_DOOR_CLOSED_EVENTS = 0x0005_u32
      ATTR_OPEN_PERIOD        = 0x0006_u32

      # User / credential / schedule capability attributes
      ATTR_NUMBER_OF_TOTAL_USERS_SUPPORTED                 = 0x0011_u32
      ATTR_NUMBER_OF_PIN_USERS_SUPPORTED                   = 0x0012_u32
      ATTR_NUMBER_OF_RFID_USERS_SUPPORTED                  = 0x0013_u32
      ATTR_NUMBER_OF_WEEK_DAY_SCHEDULES_SUPPORTED_PER_USER = 0x0014_u32
      ATTR_NUMBER_OF_YEAR_DAY_SCHEDULES_SUPPORTED_PER_USER = 0x0015_u32
      ATTR_NUMBER_OF_HOLIDAY_SCHEDULES_SUPPORTED           = 0x0016_u32
      ATTR_MAX_PIN_CODE_LENGTH                             = 0x0017_u32
      ATTR_MIN_PIN_CODE_LENGTH                             = 0x0018_u32
      ATTR_MAX_RFID_CODE_LENGTH                            = 0x0019_u32
      ATTR_MIN_RFID_CODE_LENGTH                            = 0x001A_u32
      ATTR_CREDENTIAL_RULES_SUPPORT                        = 0x001B_u32
      ATTR_NUMBER_OF_CREDENTIALS_SUPPORTED_PER_USER        = 0x001C_u32

      # Base optional attributes
      ATTR_LANGUAGE                       = 0x0021_u32
      ATTR_LED_SETTINGS                   = 0x0022_u32
      ATTR_AUTO_RELOCK_TIME               = 0x0023_u32
      ATTR_SOUND_VOLUME                   = 0x0024_u32
      ATTR_OPERATING_MODE                 = 0x0025_u32
      ATTR_SUPPORTED_OPERATING_MODES      = 0x0026_u32
      ATTR_DEFAULT_CONFIGURATION_REGISTER = 0x0027_u32
      ATTR_ENABLE_LOCAL_PROGRAMMING       = 0x0028_u32
      ATTR_ENABLE_ONE_TOUCH_LOCKING       = 0x0029_u32
      ATTR_ENABLE_INSIDE_STATUS_LED       = 0x002A_u32
      ATTR_ENABLE_PRIVACY_MODE_BUTTON     = 0x002B_u32
      ATTR_LOCAL_PROGRAMMING_FEATURES     = 0x002C_u32

      # Optional credential policy attributes
      ATTR_WRONG_CODE_ENTRY_LIMIT           = 0x0030_u32
      ATTR_USER_CODE_TEMPORARY_DISABLE_TIME = 0x0031_u32
      ATTR_SEND_PIN_OVER_THE_AIR            = 0x0032_u32
      ATTR_REQUIRE_PIN_FOR_REMOTE_OPERATION = 0x0033_u32
      ATTR_EXPIRING_USER_TIMEOUT            = 0x0035_u32

      # Commands
      CMD_LOCK_DOOR           = 0x00_u32
      CMD_UNLOCK_DOOR         = 0x01_u32
      CMD_UNLOCK_WITH_TIMEOUT = 0x03_u32

      CMD_SET_WEEK_DAY_SCHEDULE   = 0x0B_u32
      CMD_GET_WEEK_DAY_SCHEDULE   = 0x0C_u32
      CMD_CLEAR_WEEK_DAY_SCHEDULE = 0x0D_u32
      CMD_SET_YEAR_DAY_SCHEDULE   = 0x0E_u32
      CMD_GET_YEAR_DAY_SCHEDULE   = 0x0F_u32
      CMD_CLEAR_YEAR_DAY_SCHEDULE = 0x10_u32
      CMD_SET_HOLIDAY_SCHEDULE    = 0x11_u32
      CMD_GET_HOLIDAY_SCHEDULE    = 0x12_u32
      CMD_CLEAR_HOLIDAY_SCHEDULE  = 0x13_u32

      CMD_SET_USER          = 0x1A_u32
      CMD_GET_USER          = 0x1B_u32
      CMD_GET_USER_RESPONSE = 0x1C_u32
      CMD_CLEAR_USER        = 0x1D_u32

      CMD_SET_CREDENTIAL                 = 0x22_u32
      CMD_SET_CREDENTIAL_RESPONSE        = 0x23_u32
      CMD_GET_CREDENTIAL_STATUS          = 0x24_u32
      CMD_GET_CREDENTIAL_STATUS_RESPONSE = 0x25_u32
      CMD_CLEAR_CREDENTIAL               = 0x26_u32

      CMD_UNBOLT_DOOR = 0x27_u32

      # Events
      EVT_DOOR_LOCK_ALARM      = 0x00_u32
      EVT_DOOR_STATE_CHANGE    = 0x01_u32
      EVT_LOCK_OPERATION       = 0x02_u32
      EVT_LOCK_OPERATION_ERROR = 0x03_u32
      EVT_LOCK_USER_CHANGE     = 0x04_u32

      CLUSTER_REVISION =      9_u16
      ALL_USERS        = 0xFFFE_u16
      ALL_SCHEDULES    =    0xFE_u8

      property feature_map : Feature
      property lock_state : Def::LockState?
      property lock_type : Def::LockType
      property? actuator_enabled : Bool

      property door_state : Def::DoorState?
      property door_open_events : UInt32
      property door_closed_events : UInt32
      property open_period : UInt16

      property language : String
      property led_settings : LedSettings
      property auto_relock_time : UInt32
      property sound_volume : SoundVolume
      property operating_mode : Def::OperatingMode
      property supported_operating_modes : UInt16
      property default_configuration_register : UInt16
      property? enable_local_programming : Bool
      property? enable_one_touch_locking : Bool
      property? enable_inside_status_led : Bool
      property? enable_privacy_mode_button : Bool
      property local_programming_features : UInt8

      property number_of_total_users_supported : UInt16
      property number_of_pin_users_supported : UInt16
      property number_of_rfid_users_supported : UInt16
      property number_of_week_day_schedules_supported_per_user : UInt8
      property number_of_year_day_schedules_supported_per_user : UInt8
      property number_of_holiday_schedules_supported : UInt8
      property max_pin_code_length : UInt8
      property min_pin_code_length : UInt8
      property max_rfid_code_length : UInt8
      property min_rfid_code_length : UInt8
      property credential_rules_support : UInt8
      property number_of_credentials_supported_per_user : UInt8

      property wrong_code_entry_limit : UInt8
      property user_code_temporary_disable_time : UInt8
      property? send_pin_over_the_air : Bool
      property? require_pin_for_remote_operation : Bool
      property expiring_user_timeout : UInt16

      @on_lock_state_changed : Proc(Def::LockState?, Def::LockState?, Nil)?
      @on_door_state_changed : Proc(Def::DoorState?, Def::DoorState?, Nil)?

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
      @default_pin_code : String

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @feature_map : Feature = Feature::DoorPositionSensor | Feature::PinCredential | Feature::CredentialOverTheAirAccess | Feature::User | Feature::Unbolting,
        @lock_state : Def::LockState? = Def::LockState::Locked,
        @lock_type : Def::LockType = Def::LockType::Deadbolt,
        @actuator_enabled : Bool = true,
        @door_state : Def::DoorState? = Def::DoorState::DoorClosed,
        @language : String = "en",
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
        @local_programming_features : UInt8 = 0xFF_u8,
        @number_of_total_users_supported : UInt16 = 50_u16,
        @number_of_pin_users_supported : UInt16 = 50_u16,
        @number_of_rfid_users_supported : UInt16 = 50_u16,
        @number_of_week_day_schedules_supported_per_user : UInt8 = 5_u8,
        @number_of_year_day_schedules_supported_per_user : UInt8 = 5_u8,
        @number_of_holiday_schedules_supported : UInt8 = 5_u8,
        @max_pin_code_length : UInt8 = 8_u8,
        @min_pin_code_length : UInt8 = 4_u8,
        @max_rfid_code_length : UInt8 = 20_u8,
        @min_rfid_code_length : UInt8 = 4_u8,
        @credential_rules_support : UInt8 = 0x01_u8,
        @number_of_credentials_supported_per_user : UInt8 = 5_u8,
        @wrong_code_entry_limit : UInt8 = 3_u8,
        @user_code_temporary_disable_time : UInt8 = 30_u8,
        @send_pin_over_the_air : Bool = true,
        @require_pin_for_remote_operation : Bool = false,
        @expiring_user_timeout : UInt16 = 10_u16,
        default_pin_code : String = "1234",
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        raise ArgumentError.new("credentialOverTheAirAccess requires pinCredential") if @feature_map.credential_over_the_air_access? && !@feature_map.pin_credential?
        raise ArgumentError.new("user schedules require user feature") if (@feature_map.week_day_access_schedules? || @feature_map.year_day_access_schedules? || @feature_map.holiday_schedules?) && !@feature_map.user?
        raise ArgumentError.new("min_pin_code_length must be <= max_pin_code_length") if @min_pin_code_length > @max_pin_code_length
        raise ArgumentError.new("min_rfid_code_length must be <= max_rfid_code_length") if @min_rfid_code_length > @max_rfid_code_length
        raise ArgumentError.new("wrong_code_entry_limit must be >= 1") if @wrong_code_entry_limit < 1_u8
        raise ArgumentError.new("user_code_temporary_disable_time must be >= 1") if @user_code_temporary_disable_time < 1_u8

        @door_open_events = 0_u32
        @door_closed_events = 0_u32
        @open_period = 0_u16

        @default_pin_code = default_pin_code

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

      def name : String
        "DoorLock"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_LOCK_STATE), "LockState", :uint8, writable: false),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_LOCK_TYPE), "LockType", :uint8, writable: false),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_ACTUATOR_ENABLED), "ActuatorEnabled", :bool, writable: false),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_LANGUAGE), "Language", :string, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_LED_SETTINGS), "LedSettings", :uint8, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_AUTO_RELOCK_TIME), "AutoRelockTime", :uint32, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_SOUND_VOLUME), "SoundVolume", :uint8, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_OPERATING_MODE), "OperatingMode", :uint8, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_SUPPORTED_OPERATING_MODES), "SupportedOperatingModes", :uint16, writable: false, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_DEFAULT_CONFIGURATION_REGISTER), "DefaultConfigurationRegister", :uint16, writable: false, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_ENABLE_LOCAL_PROGRAMMING), "EnableLocalProgramming", :bool, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_ENABLE_ONE_TOUCH_LOCKING), "EnableOneTouchLocking", :bool, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_ENABLE_INSIDE_STATUS_LED), "EnableInsideStatusLed", :bool, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_ENABLE_PRIVACY_MODE_BUTTON), "EnablePrivacyModeButton", :bool, writable: true, optional: true),
          AttributeMetadata.new(DataType::AttributeId.new(ATTR_LOCAL_PROGRAMMING_FEATURES), "LocalProgrammingFeatures", :uint8, writable: true, optional: true),
        ]

        if @feature_map.door_position_sensor?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_DOOR_STATE), "DoorState", :uint8, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_DOOR_OPEN_EVENTS), "DoorOpenEvents", :uint32, writable: true, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_DOOR_CLOSED_EVENTS), "DoorClosedEvents", :uint32, writable: true, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_OPEN_PERIOD), "OpenPeriod", :uint16, writable: true, optional: true)
        end

        if @feature_map.user?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_NUMBER_OF_TOTAL_USERS_SUPPORTED), "NumberOfTotalUsersSupported", :uint16, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_CREDENTIAL_RULES_SUPPORT), "CredentialRulesSupport", :uint8, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_NUMBER_OF_CREDENTIALS_SUPPORTED_PER_USER), "NumberOfCredentialsSupportedPerUser", :uint8, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_EXPIRING_USER_TIMEOUT), "ExpiringUserTimeout", :uint16, writable: true, optional: true)
        end

        if @feature_map.pin_credential?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_NUMBER_OF_PIN_USERS_SUPPORTED), "NumberOfPinUsersSupported", :uint16, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_MAX_PIN_CODE_LENGTH), "MaxPinCodeLength", :uint8, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_MIN_PIN_CODE_LENGTH), "MinPinCodeLength", :uint8, writable: false, optional: true)
        end

        if @feature_map.rfid_credential?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_NUMBER_OF_RFID_USERS_SUPPORTED), "NumberOfRfidUsersSupported", :uint16, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_MAX_RFID_CODE_LENGTH), "MaxRfidCodeLength", :uint8, writable: false, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_MIN_RFID_CODE_LENGTH), "MinRfidCodeLength", :uint8, writable: false, optional: true)
        end

        if @feature_map.week_day_access_schedules?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_NUMBER_OF_WEEK_DAY_SCHEDULES_SUPPORTED_PER_USER), "NumberOfWeekDaySchedulesSupportedPerUser", :uint8, writable: false, optional: true)
        end

        if @feature_map.year_day_access_schedules?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_NUMBER_OF_YEAR_DAY_SCHEDULES_SUPPORTED_PER_USER), "NumberOfYearDaySchedulesSupportedPerUser", :uint8, writable: false, optional: true)
        end

        if @feature_map.holiday_schedules?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_NUMBER_OF_HOLIDAY_SCHEDULES_SUPPORTED), "NumberOfHolidaySchedulesSupported", :uint8, writable: false, optional: true)
        end

        if @feature_map.pin_credential? || @feature_map.rfid_credential?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_WRONG_CODE_ENTRY_LIMIT), "WrongCodeEntryLimit", :uint8, writable: true, optional: true)
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_USER_CODE_TEMPORARY_DISABLE_TIME), "UserCodeTemporaryDisableTime", :uint8, writable: true, optional: true)
        end

        if @feature_map.pin_credential? && !@feature_map.user?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_SEND_PIN_OVER_THE_AIR), "SendPinOverTheAir", :bool, writable: true, optional: true)
        end

        if @feature_map.pin_credential? && @feature_map.credential_over_the_air_access?
          attrs << AttributeMetadata.new(DataType::AttributeId.new(ATTR_REQUIRE_PIN_FOR_REMOTE_OPERATION), "RequirePinForRemoteOperation", :bool, writable: true, optional: true)
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        command_list = [
          CommandMetadata.new(DataType::CommandId.new(CMD_LOCK_DOOR), "LockDoor"),
          CommandMetadata.new(DataType::CommandId.new(CMD_UNLOCK_DOOR), "UnlockDoor"),
          CommandMetadata.new(DataType::CommandId.new(CMD_UNLOCK_WITH_TIMEOUT), "UnlockWithTimeout", optional: true),
        ]

        if @feature_map.week_day_access_schedules?
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_SET_WEEK_DAY_SCHEDULE), "SetWeekDaySchedule", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_GET_WEEK_DAY_SCHEDULE), "GetWeekDaySchedule", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_CLEAR_WEEK_DAY_SCHEDULE), "ClearWeekDaySchedule", optional: true)
        end

        if @feature_map.year_day_access_schedules?
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_SET_YEAR_DAY_SCHEDULE), "SetYearDaySchedule", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_GET_YEAR_DAY_SCHEDULE), "GetYearDaySchedule", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_CLEAR_YEAR_DAY_SCHEDULE), "ClearYearDaySchedule", optional: true)
        end

        if @feature_map.holiday_schedules?
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_SET_HOLIDAY_SCHEDULE), "SetHolidaySchedule", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_GET_HOLIDAY_SCHEDULE), "GetHolidaySchedule", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_CLEAR_HOLIDAY_SCHEDULE), "ClearHolidaySchedule", optional: true)
        end

        if @feature_map.user?
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_SET_USER), "SetUser", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_GET_USER), "GetUser", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_CLEAR_USER), "ClearUser", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_SET_CREDENTIAL), "SetCredential", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_GET_CREDENTIAL_STATUS), "GetCredentialStatus", optional: true)
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_CLEAR_CREDENTIAL), "ClearCredential", optional: true)
        end

        if @feature_map.unbolting?
          command_list << CommandMetadata.new(DataType::CommandId.new(CMD_UNBOLT_DOOR), "UnboltDoor", optional: true)
        end

        command_list
      end

      def events : Array(EventMetadata)
        event_list = [
          EventMetadata.new(DataType::EventId.new(EVT_DOOR_LOCK_ALARM), "DoorLockAlarm"),
          EventMetadata.new(DataType::EventId.new(EVT_LOCK_OPERATION), "LockOperation"),
          EventMetadata.new(DataType::EventId.new(EVT_LOCK_OPERATION_ERROR), "LockOperationError"),
        ]

        event_list << EventMetadata.new(DataType::EventId.new(EVT_DOOR_STATE_CHANGE), "DoorStateChange") if @feature_map.door_position_sensor?
        event_list << EventMetadata.new(DataType::EventId.new(EVT_LOCK_USER_CHANGE), "LockUserChange") if @feature_map.user?

        event_list
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_LOCK_STATE
          if state = @lock_state
            state.value.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_LOCK_TYPE
          @lock_type.value.to_tlv
        when ATTR_ACTUATOR_ENABLED
          @actuator_enabled.to_tlv
        when ATTR_DOOR_STATE
          return InteractionModel::Status.unsupported_attribute unless @feature_map.door_position_sensor?
          if state = @door_state
            state.value.to_tlv
          else
            nil.to_tlv
          end
        when ATTR_DOOR_OPEN_EVENTS
          return InteractionModel::Status.unsupported_attribute unless @feature_map.door_position_sensor?
          @door_open_events.to_tlv
        when ATTR_DOOR_CLOSED_EVENTS
          return InteractionModel::Status.unsupported_attribute unless @feature_map.door_position_sensor?
          @door_closed_events.to_tlv
        when ATTR_OPEN_PERIOD
          return InteractionModel::Status.unsupported_attribute unless @feature_map.door_position_sensor?
          @open_period.to_tlv
        when ATTR_NUMBER_OF_TOTAL_USERS_SUPPORTED
          return InteractionModel::Status.unsupported_attribute unless @feature_map.user?
          @number_of_total_users_supported.to_tlv
        when ATTR_NUMBER_OF_PIN_USERS_SUPPORTED
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential?
          @number_of_pin_users_supported.to_tlv
        when ATTR_NUMBER_OF_RFID_USERS_SUPPORTED
          return InteractionModel::Status.unsupported_attribute unless @feature_map.rfid_credential?
          @number_of_rfid_users_supported.to_tlv
        when ATTR_NUMBER_OF_WEEK_DAY_SCHEDULES_SUPPORTED_PER_USER
          return InteractionModel::Status.unsupported_attribute unless @feature_map.week_day_access_schedules?
          @number_of_week_day_schedules_supported_per_user.to_tlv
        when ATTR_NUMBER_OF_YEAR_DAY_SCHEDULES_SUPPORTED_PER_USER
          return InteractionModel::Status.unsupported_attribute unless @feature_map.year_day_access_schedules?
          @number_of_year_day_schedules_supported_per_user.to_tlv
        when ATTR_NUMBER_OF_HOLIDAY_SCHEDULES_SUPPORTED
          return InteractionModel::Status.unsupported_attribute unless @feature_map.holiday_schedules?
          @number_of_holiday_schedules_supported.to_tlv
        when ATTR_MAX_PIN_CODE_LENGTH
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential?
          @max_pin_code_length.to_tlv
        when ATTR_MIN_PIN_CODE_LENGTH
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential?
          @min_pin_code_length.to_tlv
        when ATTR_MAX_RFID_CODE_LENGTH
          return InteractionModel::Status.unsupported_attribute unless @feature_map.rfid_credential?
          @max_rfid_code_length.to_tlv
        when ATTR_MIN_RFID_CODE_LENGTH
          return InteractionModel::Status.unsupported_attribute unless @feature_map.rfid_credential?
          @min_rfid_code_length.to_tlv
        when ATTR_CREDENTIAL_RULES_SUPPORT
          return InteractionModel::Status.unsupported_attribute unless @feature_map.user?
          @credential_rules_support.to_tlv
        when ATTR_NUMBER_OF_CREDENTIALS_SUPPORTED_PER_USER
          return InteractionModel::Status.unsupported_attribute unless @feature_map.user?
          @number_of_credentials_supported_per_user.to_tlv
        when ATTR_LANGUAGE
          @language.to_tlv
        when ATTR_LED_SETTINGS
          @led_settings.value.to_tlv
        when ATTR_AUTO_RELOCK_TIME
          @auto_relock_time.to_tlv
        when ATTR_SOUND_VOLUME
          @sound_volume.value.to_tlv
        when ATTR_OPERATING_MODE
          @operating_mode.value.to_tlv
        when ATTR_SUPPORTED_OPERATING_MODES
          @supported_operating_modes.to_tlv
        when ATTR_DEFAULT_CONFIGURATION_REGISTER
          @default_configuration_register.to_tlv
        when ATTR_ENABLE_LOCAL_PROGRAMMING
          @enable_local_programming.to_tlv
        when ATTR_ENABLE_ONE_TOUCH_LOCKING
          @enable_one_touch_locking.to_tlv
        when ATTR_ENABLE_INSIDE_STATUS_LED
          @enable_inside_status_led.to_tlv
        when ATTR_ENABLE_PRIVACY_MODE_BUTTON
          @enable_privacy_mode_button.to_tlv
        when ATTR_LOCAL_PROGRAMMING_FEATURES
          @local_programming_features.to_tlv
        when ATTR_WRONG_CODE_ENTRY_LIMIT
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential? || @feature_map.rfid_credential?
          @wrong_code_entry_limit.to_tlv
        when ATTR_USER_CODE_TEMPORARY_DISABLE_TIME
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential? || @feature_map.rfid_credential?
          @user_code_temporary_disable_time.to_tlv
        when ATTR_SEND_PIN_OVER_THE_AIR
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential?
          return InteractionModel::Status.unsupported_attribute if @feature_map.user?
          @send_pin_over_the_air.to_tlv
        when ATTR_REQUIRE_PIN_FOR_REMOTE_OPERATION
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential? && @feature_map.credential_over_the_air_access?
          @require_pin_for_remote_operation.to_tlv
        when ATTR_EXPIRING_USER_TIMEOUT
          return InteractionModel::Status.unsupported_attribute unless @feature_map.user?
          @expiring_user_timeout.to_tlv
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_LANGUAGE
          text = decode_string(value)
          return InteractionModel::Status.invalid_data_type unless text
          @language = text
          increment_version_and_notify(ATTR_LANGUAGE)
          InteractionModel::Status.success
        when ATTR_LED_SETTINGS
          led = decode_u8(value)
          return InteractionModel::Status.invalid_data_type unless led
          @led_settings = LedSettings.from_value(led)
          increment_version_and_notify(ATTR_LED_SETTINGS)
          InteractionModel::Status.success
        when ATTR_AUTO_RELOCK_TIME
          secs = decode_u32(value)
          return InteractionModel::Status.invalid_data_type unless secs
          @auto_relock_time = secs
          increment_version_and_notify(ATTR_AUTO_RELOCK_TIME)
          InteractionModel::Status.success
        when ATTR_SOUND_VOLUME
          sound = decode_u8(value)
          return InteractionModel::Status.invalid_data_type unless sound
          @sound_volume = SoundVolume.from_value(sound)
          increment_version_and_notify(ATTR_SOUND_VOLUME)
          InteractionModel::Status.success
        when ATTR_OPERATING_MODE
          mode = decode_u8(value)
          return InteractionModel::Status.invalid_data_type unless mode
          @operating_mode = Def::OperatingMode.from_value(mode)
          increment_version_and_notify(ATTR_OPERATING_MODE)
          InteractionModel::Status.success
        when ATTR_ENABLE_LOCAL_PROGRAMMING
          enabled = decode_bool(value)
          return InteractionModel::Status.invalid_data_type if enabled.nil?
          @enable_local_programming = enabled
          increment_version_and_notify(ATTR_ENABLE_LOCAL_PROGRAMMING)
          InteractionModel::Status.success
        when ATTR_ENABLE_ONE_TOUCH_LOCKING
          enabled = decode_bool(value)
          return InteractionModel::Status.invalid_data_type if enabled.nil?
          @enable_one_touch_locking = enabled
          increment_version_and_notify(ATTR_ENABLE_ONE_TOUCH_LOCKING)
          InteractionModel::Status.success
        when ATTR_ENABLE_INSIDE_STATUS_LED
          enabled = decode_bool(value)
          return InteractionModel::Status.invalid_data_type if enabled.nil?
          @enable_inside_status_led = enabled
          increment_version_and_notify(ATTR_ENABLE_INSIDE_STATUS_LED)
          InteractionModel::Status.success
        when ATTR_ENABLE_PRIVACY_MODE_BUTTON
          enabled = decode_bool(value)
          return InteractionModel::Status.invalid_data_type if enabled.nil?
          @enable_privacy_mode_button = enabled
          increment_version_and_notify(ATTR_ENABLE_PRIVACY_MODE_BUTTON)
          InteractionModel::Status.success
        when ATTR_LOCAL_PROGRAMMING_FEATURES
          features = decode_u8(value)
          return InteractionModel::Status.invalid_data_type unless features
          @local_programming_features = features
          increment_version_and_notify(ATTR_LOCAL_PROGRAMMING_FEATURES)
          InteractionModel::Status.success
        when ATTR_DOOR_OPEN_EVENTS
          return InteractionModel::Status.unsupported_attribute unless @feature_map.door_position_sensor?
          counter = decode_u32(value)
          return InteractionModel::Status.invalid_data_type unless counter
          @door_open_events = counter
          increment_version_and_notify(ATTR_DOOR_OPEN_EVENTS)
          InteractionModel::Status.success
        when ATTR_DOOR_CLOSED_EVENTS
          return InteractionModel::Status.unsupported_attribute unless @feature_map.door_position_sensor?
          counter = decode_u32(value)
          return InteractionModel::Status.invalid_data_type unless counter
          @door_closed_events = counter
          increment_version_and_notify(ATTR_DOOR_CLOSED_EVENTS)
          InteractionModel::Status.success
        when ATTR_OPEN_PERIOD
          return InteractionModel::Status.unsupported_attribute unless @feature_map.door_position_sensor?
          period = decode_u16(value)
          return InteractionModel::Status.invalid_data_type unless period
          @open_period = period
          increment_version_and_notify(ATTR_OPEN_PERIOD)
          InteractionModel::Status.success
        when ATTR_WRONG_CODE_ENTRY_LIMIT
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential? || @feature_map.rfid_credential?
          limit = decode_u8(value)
          return InteractionModel::Status.invalid_data_type unless limit
          return InteractionModel::Status.constraint_error if limit < 1_u8
          @wrong_code_entry_limit = limit
          increment_version_and_notify(ATTR_WRONG_CODE_ENTRY_LIMIT)
          InteractionModel::Status.success
        when ATTR_USER_CODE_TEMPORARY_DISABLE_TIME
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential? || @feature_map.rfid_credential?
          secs = decode_u8(value)
          return InteractionModel::Status.invalid_data_type unless secs
          return InteractionModel::Status.constraint_error if secs < 1_u8
          @user_code_temporary_disable_time = secs
          increment_version_and_notify(ATTR_USER_CODE_TEMPORARY_DISABLE_TIME)
          InteractionModel::Status.success
        when ATTR_SEND_PIN_OVER_THE_AIR
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential?
          return InteractionModel::Status.unsupported_attribute if @feature_map.user?
          enabled = decode_bool(value)
          return InteractionModel::Status.invalid_data_type if enabled.nil?
          @send_pin_over_the_air = enabled
          increment_version_and_notify(ATTR_SEND_PIN_OVER_THE_AIR)
          InteractionModel::Status.success
        when ATTR_REQUIRE_PIN_FOR_REMOTE_OPERATION
          return InteractionModel::Status.unsupported_attribute unless @feature_map.pin_credential? && @feature_map.credential_over_the_air_access?
          enabled = decode_bool(value)
          return InteractionModel::Status.invalid_data_type if enabled.nil?
          @require_pin_for_remote_operation = enabled
          increment_version_and_notify(ATTR_REQUIRE_PIN_FOR_REMOTE_OPERATION)
          InteractionModel::Status.success
        when ATTR_EXPIRING_USER_TIMEOUT
          return InteractionModel::Status.unsupported_attribute unless @feature_map.user?
          timeout = decode_u16(value)
          return InteractionModel::Status.invalid_data_type unless timeout
          return InteractionModel::Status.constraint_error if timeout < 1_u16
          @expiring_user_timeout = timeout
          increment_version_and_notify(ATTR_EXPIRING_USER_TIMEOUT)
          InteractionModel::Status.success
        else
          super
        end
      rescue ArgumentError
        InteractionModel::Status.invalid_data_type
      end

      protected def encode_feature_map_global : Bytes
        @feature_map.value.to_tlv
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_LOCK_DOOR
          request = Def::LockDoorRequest.from_slice(fields)
          lock(pin: pin_from_slice(request.pin_code))
        when CMD_UNLOCK_DOOR
          request = Def::UnlockDoorRequest.from_slice(fields)
          unlock(pin: pin_from_slice(request.pin_code))
        when CMD_UNLOCK_WITH_TIMEOUT
          request = Def::UnlockWithTimeoutRequest.from_slice(fields)
          unlock_with_timeout(request.timeout, pin: pin_from_slice(request.pin_code))
        when CMD_UNBOLT_DOOR
          return InteractionModel::Status.unsupported_command unless @feature_map.unbolting?
          request = Def::UnboltDoorRequest.from_slice(fields)
          unbolt(pin: pin_from_slice(request.pin_code))
        when CMD_SET_WEEK_DAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.week_day_access_schedules?
          handle_set_week_day_schedule(fields)
        when CMD_GET_WEEK_DAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.week_day_access_schedules?
          handle_get_week_day_schedule(fields)
        when CMD_CLEAR_WEEK_DAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.week_day_access_schedules?
          handle_clear_week_day_schedule(fields)
        when CMD_SET_YEAR_DAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.year_day_access_schedules?
          handle_set_year_day_schedule(fields)
        when CMD_GET_YEAR_DAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.year_day_access_schedules?
          handle_get_year_day_schedule(fields)
        when CMD_CLEAR_YEAR_DAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.year_day_access_schedules?
          handle_clear_year_day_schedule(fields)
        when CMD_SET_HOLIDAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.holiday_schedules?
          handle_set_holiday_schedule(fields)
        when CMD_GET_HOLIDAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.holiday_schedules?
          handle_get_holiday_schedule(fields)
        when CMD_CLEAR_HOLIDAY_SCHEDULE
          return InteractionModel::Status.unsupported_command unless @feature_map.holiday_schedules?
          handle_clear_holiday_schedule(fields)
        when CMD_SET_USER
          return InteractionModel::Status.unsupported_command unless @feature_map.user?
          handle_set_user(fields)
        when CMD_GET_USER
          return InteractionModel::Status.unsupported_command unless @feature_map.user?
          handle_get_user(fields)
        when CMD_CLEAR_USER
          return InteractionModel::Status.unsupported_command unless @feature_map.user?
          handle_clear_user(fields)
        when CMD_SET_CREDENTIAL
          return InteractionModel::Status.unsupported_command unless @feature_map.user?
          handle_set_credential(fields)
        when CMD_GET_CREDENTIAL_STATUS
          return InteractionModel::Status.unsupported_command unless @feature_map.user?
          handle_get_credential_status(fields)
        when CMD_CLEAR_CREDENTIAL
          return InteractionModel::Status.unsupported_command unless @feature_map.user?
          handle_clear_credential(fields)
        else
          super
        end
      rescue
        InteractionModel::Status.invalid_command
      end

      # Public API for local application logic
      def lock(pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        cancel_pending_relock
        set_lock_state(Def::LockState::Locked)
        InteractionModel::Status.success
      end

      def unlock(pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        set_lock_state(Def::LockState::Unlocked)
        schedule_relock(@auto_relock_time) if @auto_relock_time > 0_u32
        InteractionModel::Status.success
      end

      def unlock_with_timeout(timeout_seconds : UInt16, pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        set_lock_state(Def::LockState::Unlocked)
        schedule_relock(timeout_seconds.to_u32)
        InteractionModel::Status.success
      end

      def unbolt(pin : String? = nil, source : Def::OperationSource = Def::OperationSource::Remote) : InteractionModel::Status
        return InteractionModel::Status.unsupported_command unless @feature_map.unbolting?
        return InteractionModel::Status.cluster_failure(Def::StatusCode::Failure) unless remote_control_allowed?
        if auth = authorize_remote_operation(pin)
          return auth
        end

        set_lock_state(Def::LockState::Unlatched)
        schedule_relock(@auto_relock_time) if @auto_relock_time > 0_u32
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

      def update_door_state(new_state : Def::DoorState?) : Nil
        return unless @feature_map.door_position_sensor?

        old = @door_state
        @door_state = new_state

        if old != new_state
          changed_attributes = [ATTR_DOOR_STATE] of UInt32

          if new_state == Def::DoorState::DoorOpen
            @door_open_events += 1_u32
            changed_attributes << ATTR_DOOR_OPEN_EVENTS
          elsif new_state == Def::DoorState::DoorClosed
            @door_closed_events += 1_u32
            changed_attributes << ATTR_DOOR_CLOSED_EVENTS
          end

          increment_version
          changed_attributes.each { |attribute_id| notify_changed(attribute_id) }
          @on_door_state_changed.try &.call(old, new_state)
        end
      end

      def on_lock_state_changed(&block : Def::LockState?, Def::LockState? -> Nil)
        @on_lock_state_changed = block
      end

      def on_door_state_changed(&block : Def::DoorState?, Def::DoorState? -> Nil)
        @on_door_state_changed = block
      end

      def default_pin_code : String
        @default_pin_code
      end

      private def handle_set_week_day_schedule(fields : Bytes) : InteractionModel::Status
        request = Def::SetWeekDayScheduleRequest.from_slice(fields)
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

      private def handle_get_week_day_schedule(fields : Bytes) : Cluster::CommandResponse
        request = Def::GetWeekDayScheduleRequest.from_slice(fields)

        if !valid_user_index?(request.user_index) || !valid_week_day_schedule_index?(request.week_day_index)
          response = Def::GetWeekDayScheduleResponse.new(
            week_day_index: request.week_day_index,
            user_index: request.user_index,
            status_code: Def::StatusCode::InvalidField,
            week_day: 0_u8,
            start_hour: 0_u8,
            start_minute: 0_u8,
            end_hour: 0_u8,
            end_minute: 0_u8
          )
          return Cluster::CommandResponse.new(CMD_GET_WEEK_DAY_SCHEDULE, response.to_slice)
        end

        if schedule = @week_day_schedules[{request.user_index, request.week_day_index}]?
          response = Def::GetWeekDayScheduleResponse.new(
            week_day_index: request.week_day_index,
            user_index: request.user_index,
            status_code: Def::StatusCode::Success,
            week_day: schedule.week_day,
            start_hour: schedule.start_hour,
            start_minute: schedule.start_minute,
            end_hour: schedule.end_hour,
            end_minute: schedule.end_minute
          )
        else
          response = Def::GetWeekDayScheduleResponse.new(
            week_day_index: request.week_day_index,
            user_index: request.user_index,
            status_code: Def::StatusCode::NotFound,
            week_day: 0_u8,
            start_hour: 0_u8,
            start_minute: 0_u8,
            end_hour: 0_u8,
            end_minute: 0_u8
          )
        end

        Cluster::CommandResponse.new(CMD_GET_WEEK_DAY_SCHEDULE, response.to_slice)
      end

      private def handle_clear_week_day_schedule(fields : Bytes) : InteractionModel::Status
        request = Def::ClearWeekDayScheduleRequest.from_slice(fields)
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

      private def handle_set_year_day_schedule(fields : Bytes) : InteractionModel::Status
        request = Def::SetYearDayScheduleRequest.from_slice(fields)
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

      private def handle_get_year_day_schedule(fields : Bytes) : Cluster::CommandResponse
        request = Def::GetYearDayScheduleRequest.from_slice(fields)

        if !valid_user_index?(request.user_index) || !valid_year_day_schedule_index?(request.year_day_index)
          response = Def::GetYearDayScheduleResponse.new(
            year_day_index: request.year_day_index,
            user_index: request.user_index,
            status_code: Def::StatusCode::InvalidField,
            local_start_time: 0_u32,
            local_end_time: 0_u32
          )
          return Cluster::CommandResponse.new(CMD_GET_YEAR_DAY_SCHEDULE, response.to_slice)
        end

        if schedule = @year_day_schedules[{request.user_index, request.year_day_index}]?
          response = Def::GetYearDayScheduleResponse.new(
            year_day_index: request.year_day_index,
            user_index: request.user_index,
            status_code: Def::StatusCode::Success,
            local_start_time: schedule.local_start_time,
            local_end_time: schedule.local_end_time
          )
        else
          response = Def::GetYearDayScheduleResponse.new(
            year_day_index: request.year_day_index,
            user_index: request.user_index,
            status_code: Def::StatusCode::NotFound,
            local_start_time: 0_u32,
            local_end_time: 0_u32
          )
        end

        Cluster::CommandResponse.new(CMD_GET_YEAR_DAY_SCHEDULE, response.to_slice)
      end

      private def handle_clear_year_day_schedule(fields : Bytes) : InteractionModel::Status
        request = Def::ClearYearDayScheduleRequest.from_slice(fields)
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

      private def handle_set_holiday_schedule(fields : Bytes) : InteractionModel::Status
        request = Def::SetHolidayScheduleRequest.from_slice(fields)
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

      private def handle_get_holiday_schedule(fields : Bytes) : Cluster::CommandResponse
        request = Def::GetHolidayScheduleRequest.from_slice(fields)

        unless valid_holiday_schedule_index?(request.holiday_index)
          response = Def::GetHolidayScheduleResponse.new(
            holiday_index: request.holiday_index,
            status_code: Def::StatusCode::InvalidField,
            local_start_time: 0_u32,
            local_end_time: 0_u32,
            operating_mode: Def::OperatingMode::Normal
          )
          return Cluster::CommandResponse.new(CMD_GET_HOLIDAY_SCHEDULE, response.to_slice)
        end

        if schedule = @holiday_schedules[request.holiday_index]?
          response = Def::GetHolidayScheduleResponse.new(
            holiday_index: request.holiday_index,
            status_code: Def::StatusCode::Success,
            local_start_time: schedule.local_start_time,
            local_end_time: schedule.local_end_time,
            operating_mode: schedule.operating_mode
          )
        else
          response = Def::GetHolidayScheduleResponse.new(
            holiday_index: request.holiday_index,
            status_code: Def::StatusCode::NotFound,
            local_start_time: 0_u32,
            local_end_time: 0_u32,
            operating_mode: Def::OperatingMode::Normal
          )
        end

        Cluster::CommandResponse.new(CMD_GET_HOLIDAY_SCHEDULE, response.to_slice)
      end

      private def handle_clear_holiday_schedule(fields : Bytes) : InteractionModel::Status
        request = Def::ClearHolidayScheduleRequest.from_slice(fields)
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

      private def handle_set_user(fields : Bytes) : InteractionModel::Status
        request = Def::SetUserRequest.from_slice(fields)
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

      private def handle_get_user(fields : Bytes) : Cluster::CommandResponse
        request = Def::GetUserRequest.from_slice(fields)
        unless valid_user_index?(request.user_index)
          response = Def::GetUserResponse.new(
            user_index: request.user_index,
            user_name: nil,
            user_unique_id: nil,
            user_status: Def::UserStatus::Available,
            user_type: nil,
            credential_rule: nil,
            credentials: nil,
            creator_fabric_index: nil,
            last_modified_fabric_index: nil,
            next_user_index: nil
          )
          return Cluster::CommandResponse.new(CMD_GET_USER_RESPONSE, response.to_slice)
        end

        next_user = @users.keys.select { |index| index > request.user_index }.sort!.first?

        response = if user = @users[request.user_index]?
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
                     Def::GetUserResponse.new(
                       user_index: request.user_index,
                       user_name: nil,
                       user_unique_id: nil,
                       user_status: Def::UserStatus::Available,
                       user_type: nil,
                       credential_rule: nil,
                       credentials: nil,
                       creator_fabric_index: nil,
                       last_modified_fabric_index: nil,
                       next_user_index: next_user
                     )
                   end

        Cluster::CommandResponse.new(CMD_GET_USER_RESPONSE, response.to_slice)
      end

      private def handle_clear_user(fields : Bytes) : InteractionModel::Status
        request = Def::ClearUserRequest.from_slice(fields)

        if request.user_index == ALL_USERS
          @users.keys.each { |user_index| clear_user_record(user_index) }
        else
          return InteractionModel::Status.cluster_failure(Def::StatusCode::InvalidField) unless valid_user_index?(request.user_index)
          clear_user_record(request.user_index)
        end

        increment_version
        InteractionModel::Status.success
      end

      private def handle_set_credential(fields : Bytes) : Cluster::CommandResponse
        request = Def::SetCredentialRequest.from_slice(fields)
        if user_index = request.user_index
          unless valid_user_index?(user_index)
            return Cluster::CommandResponse.new(
              CMD_SET_CREDENTIAL_RESPONSE,
              Def::SetCredentialResponse.new(
                status_code: Def::StatusCode::InvalidField,
                user_index: nil,
                next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
              ).to_slice
            )
          end
        end

        credential_key = credential_key(request.credential)

        if error = validate_credential_input(request.credential, request.credential_data)
          return Cluster::CommandResponse.new(
            CMD_SET_CREDENTIAL_RESPONSE,
            Def::SetCredentialResponse.new(
              status_code: error,
              user_index: nil,
              next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
            ).to_slice
          )
        end

        created_user_index : UInt16? = nil

        case request.operation_type
        when Def::DataOperationType::Add
          if @credentials.has_key?(credential_key)
            status = Def::StatusCode::Occupied
          else
            if user_index = request.user_index
              if @users.size >= @number_of_total_users_supported && !@users.has_key?(user_index)
                return Cluster::CommandResponse.new(
                  CMD_SET_CREDENTIAL_RESPONSE,
                  Def::SetCredentialResponse.new(
                    status_code: Def::StatusCode::ResourceExhausted,
                    user_index: nil,
                    next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
                  ).to_slice
                )
              end

              ensure_user_exists(user_index, request.user_status, request.user_type)
              unless @users.has_key?(user_index)
                return Cluster::CommandResponse.new(
                  CMD_SET_CREDENTIAL_RESPONSE,
                  Def::SetCredentialResponse.new(
                    status_code: Def::StatusCode::ResourceExhausted,
                    user_index: nil,
                    next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
                  ).to_slice
                )
              end

              if user = @users[user_index]?
                if !credential_belongs_to_user?(user, request.credential) && user.credentials.size >= @number_of_credentials_supported_per_user
                  return Cluster::CommandResponse.new(
                    CMD_SET_CREDENTIAL_RESPONSE,
                    Def::SetCredentialResponse.new(
                      status_code: Def::StatusCode::ResourceExhausted,
                      user_index: nil,
                      next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
                    ).to_slice
                  )
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
                return Cluster::CommandResponse.new(
                  CMD_SET_CREDENTIAL_RESPONSE,
                  Def::SetCredentialResponse.new(
                    status_code: Def::StatusCode::ResourceExhausted,
                    user_index: nil,
                    next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
                  ).to_slice
                )
              end

              if user = @users[new_user_index]?
                if !credential_belongs_to_user?(user, request.credential) && user.credentials.size >= @number_of_credentials_supported_per_user
                  add_credential_to_user(existing)
                  return Cluster::CommandResponse.new(
                    CMD_SET_CREDENTIAL_RESPONSE,
                    Def::SetCredentialResponse.new(
                      status_code: Def::StatusCode::ResourceExhausted,
                      user_index: nil,
                      next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
                    ).to_slice
                  )
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

        response = Def::SetCredentialResponse.new(
          status_code: status,
          user_index: created_user_index,
          next_credential_index: next_available_credential_index(request.credential.credential_type, request.credential.credential_index)
        )

        Cluster::CommandResponse.new(CMD_SET_CREDENTIAL_RESPONSE, response.to_slice)
      end

      private def handle_get_credential_status(fields : Bytes) : Cluster::CommandResponse
        request = Def::GetCredentialStatusRequest.from_slice(fields)
        unless credential_index_supported?(request.credential)
          return Cluster::CommandResponse.new(
            CMD_GET_CREDENTIAL_STATUS_RESPONSE,
            Def::GetCredentialStatusResponse.new(
              credential_exists: false,
              user_index: nil,
              creator_fabric_index: nil,
              last_modified_fabric_index: nil,
              next_credential_index: nil
            ).to_slice
          )
        end

        key = credential_key(request.credential)

        response = if credential = @credentials[key]?
                     Def::GetCredentialStatusResponse.new(
                       credential_exists: true,
                       user_index: credential.user_index,
                       creator_fabric_index: fabric_index_from_u8(credential.creator_fabric_index),
                       last_modified_fabric_index: fabric_index_from_u8(credential.last_modified_fabric_index),
                       next_credential_index: next_occupied_credential_index(request.credential.credential_type, request.credential.credential_index)
                     )
                   else
                     Def::GetCredentialStatusResponse.new(
                       credential_exists: false,
                       user_index: nil,
                       creator_fabric_index: nil,
                       last_modified_fabric_index: nil,
                       next_credential_index: next_occupied_credential_index(request.credential.credential_type, request.credential.credential_index)
                     )
                   end

        Cluster::CommandResponse.new(CMD_GET_CREDENTIAL_STATUS_RESPONSE, response.to_slice)
      end

      private def handle_clear_credential(fields : Bytes) : InteractionModel::Status
        request = Def::ClearCredentialRequest.from_slice(fields)

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

      private def remote_control_allowed? : Bool
        return false unless @actuator_enabled

        if @operating_mode == Def::OperatingMode::NoRemoteLockUnlock
          return false
        end

        if @operating_mode == Def::OperatingMode::Privacy
          return false
        end

        if lockout_active
          return false
        end

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

      private def set_lock_state(new_state : Def::LockState?) : Nil
        old_state = @lock_state
        @lock_state = new_state

        if old_state != new_state
          increment_version_and_notify(ATTR_LOCK_STATE)
          @on_lock_state_changed.try &.call(old_state, new_state)
        end
      end

      private def schedule_relock(after_seconds : UInt32) : Nil
        return if after_seconds == 0_u32

        @relock_generation = @relock_generation &+ 1_u64
        generation = @relock_generation

        spawn do
          sleep after_seconds.seconds
          next unless generation == @relock_generation

          set_lock_state(Def::LockState::Locked)
        end
      end

      private def cancel_pending_relock : Nil
        @relock_generation = @relock_generation &+ 1_u64
      end

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

        unless user.credentials.any? do |credential|
                 credential.credential_type == record.credential.credential_type && credential.credential_index == record.credential.credential_index
               end
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
          return Def::StatusCode::InvalidField unless credential.credential_index == 0_u16
          return Def::StatusCode::InvalidField if credential_data.empty?
        when Def::CredentialType::Pin
          return Def::StatusCode::InvalidField unless @feature_map.pin_credential?
          len = credential_data.size
          return Def::StatusCode::InvalidField if len < @min_pin_code_length || len > @max_pin_code_length
        when Def::CredentialType::Rfid
          return Def::StatusCode::InvalidField unless @feature_map.rfid_credential?
          len = credential_data.size
          return Def::StatusCode::InvalidField if len < @min_rfid_code_length || len > @max_rfid_code_length
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
        return credential.credential_index == 0_u16 if credential.credential_type.programming_pin?

        max = max_credential_index(credential.credential_type)
        credential.credential_index >= 1_u16 && credential.credential_index <= max
      end

      private def credential_type_supported?(credential_type : Def::CredentialType) : Bool
        case credential_type
        when Def::CredentialType::ProgrammingPin
          @feature_map.pin_credential?
        when Def::CredentialType::Pin
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
