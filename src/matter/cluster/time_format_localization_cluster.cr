require "./cluster"

module Matter
  module Cluster
    # Time Format Localization Cluster (0x002C)
    #
    # Provides attributes for determining and configuring time and date formatting
    # information that a node uses when conveying values to a user. This cluster
    # supports both hour format (12hr/24hr) and calendar format preferences.
    #
    # Features:
    # - CalendarFormat (CALFMT): Calendar format support
    #
    # Specification: Matter 1.4 § 11.4
    class TimeFormatLocalizationCluster < Base
      CLUSTER_ID = 0x002C_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        CalendarFormat = 0x01 # CALFMT - Calendar format support
      end

      # Attributes
      ATTR_HOUR_FORMAT              = 0x0000_u32
      ATTR_ACTIVE_CALENDAR_TYPE     = 0x0001_u32
      ATTR_SUPPORTED_CALENDAR_TYPES = 0x0002_u32

      # Hour format values
      enum HourFormat
        Hr12            =   0 # 12-hour clock
        Hr24            =   1 # 24-hour clock
        UseActiveLocale = 255 # Use active locale clock
      end

      # Calendar type values
      enum CalendarType
        Buddhist        =   0
        Chinese         =   1
        Coptic          =   2
        Ethiopian       =   3
        Gregorian       =   4
        Hebrew          =   5
        Indian          =   6
        Islamic         =   7
        Japanese        =   8
        Korean          =   9
        Persian         =  10
        Taiwanese       =  11
        UseActiveLocale = 255
      end

      # Feature map
      property feature_map : Feature

      # Hour format preference (writable)
      property hour_format : HourFormat

      # Active calendar type (writable, optional - requires CalendarFormat feature)
      property active_calendar_type : CalendarType?

      # Supported calendar types (fixed, optional - requires CalendarFormat feature)
      property supported_calendar_types : Array(CalendarType)?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @feature_map : Feature = Feature::None,
                     @hour_format : HourFormat = HourFormat::Hr24,
                     @active_calendar_type : CalendarType? = nil,
                     @supported_calendar_types : Array(CalendarType)? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # If CalendarFormat feature is enabled, validate calendar attributes
        if @feature_map.calendar_format?
          # Validate active calendar type is in supported list if both are provided
          if active = @active_calendar_type
            if supported = @supported_calendar_types
              unless supported.includes?(active)
                raise ArgumentError.new("active_calendar_type must be in supported_calendar_types")
              end
            end
          end

          # Validate no duplicates in supported calendar types
          if supported = @supported_calendar_types
            if supported.size != supported.uniq.size
              raise ArgumentError.new("supported_calendar_types must not contain duplicates")
            end
          end
        end
      end

      def name : String
        "TimeFormatLocalization"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_HOUR_FORMAT),
            "hourFormat",
            :uint8,
            writable: true
          ),
        ]

        # Add calendar format attributes if CalendarFormat feature is enabled
        if @feature_map.calendar_format?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ACTIVE_CALENDAR_TYPE),
            "activeCalendarType",
            :uint8,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_SUPPORTED_CALENDAR_TYPES),
            "supportedCalendarTypes",
            :array,
            writable: false
          )
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands for localization cluster
      end

      # Report the cluster's features to controllers.
      protected def encode_feature_map_global : Bytes
        @feature_map.value.to_tlv
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_HOUR_FORMAT
          @hour_format.value.to_u8.to_tlv
        when ATTR_ACTIVE_CALENDAR_TYPE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.calendar_format?
          if active = @active_calendar_type
            active.value.to_u8.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_SUPPORTED_CALENDAR_TYPES
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.calendar_format?
          if supported = @supported_calendar_types
            encode_array(supported.map(&.value.to_u8))
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_HOUR_FORMAT
          hour_value = decode_u8(value)
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) unless hour_value

          # Validate hour format value
          unless hour_value.in?(0_u8, 1_u8, 255_u8)
            return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end

          old_format = @hour_format
          @hour_format = HourFormat.from_value(hour_value)

          # Call callback if registered
          @on_hour_format_changed.try &.call(old_format, @hour_format)
          increment_version

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_ACTIVE_CALENDAR_TYPE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.calendar_format?
          calendar_value = decode_u8(value)
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) unless calendar_value

          # Validate calendar type value
          valid_values = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 255]
          unless valid_values.includes?(calendar_value)
            return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
          end

          new_calendar = CalendarType.from_value(calendar_value)

          # Validate new calendar type is in supported list
          if supported = @supported_calendar_types
            unless supported.includes?(new_calendar)
              return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError)
            end
          end

          old_calendar = @active_calendar_type
          @active_calendar_type = new_calendar

          # Call callback if registered
          @on_calendar_changed.try &.call(old_calendar, new_calendar)
          increment_version

          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # Check if CalendarFormat feature is enabled
      def calendar_format_enabled? : Bool
        @feature_map.calendar_format?
      end

      # Callback when hour format changes
      @on_hour_format_changed : Proc(HourFormat, HourFormat, Nil)?

      def on_hour_format_changed(&block : HourFormat, HourFormat -> Nil)
        @on_hour_format_changed = block
      end

      # Callback when calendar type changes
      @on_calendar_changed : Proc(CalendarType?, CalendarType, Nil)?

      def on_calendar_changed(&block : CalendarType?, CalendarType -> Nil)
        @on_calendar_changed = block
      end

      private def encode_array(values : Array(UInt8)) : Bytes
        values.to_tlv
      end
    end
  end
end
