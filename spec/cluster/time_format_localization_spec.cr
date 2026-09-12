require "../spec_helper"

describe Matter::Cluster::TimeFormatLocalization do
  describe "initialization" do
    it "creates with default values (24-hour format)" do
      cluster = build(Matter::Cluster::TimeFormatLocalization)
      cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24)
      cluster.active_calendar_type.should be_nil
      cluster.supported_calendar_types.should be_nil
      cluster.calendar_format_enabled?.should be_false
    end

    it "creates with 12-hour format" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12
      )
      cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12)
    end

    it "creates with calendar format feature" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
        ]
      )
      cluster.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian)
      cluster.supported_calendar_types.should eq([
        Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
      ])
      cluster.calendar_format_enabled?.should be_true
    end

    it "validates active calendar type is in supported list" do
      expect_raises(ArgumentError, /active_calendar_type must be in supported_calendar_types/) do
        build(Matter::Cluster::TimeFormatLocalization,
          feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
          active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese,
          ]
        )
      end
    end

    it "validates no duplicates in supported calendar types" do
      expect_raises(ArgumentError, /supported_calendar_types must not contain duplicates/) do
        build(Matter::Cluster::TimeFormatLocalization,
          feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
            Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
          ]
        )
      end
    end
  end

  describe "attributes" do
    it "has required base attributes" do
      cluster = build(Matter::Cluster::TimeFormatLocalization)
      attrs = cluster.attributes
      attrs.size.should eq(1)
      attrs.map(&.name).should contain("hourFormat")
    end

    it "has calendar format attributes when feature enabled" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        ]
      )
      attrs = cluster.attributes
      attrs.size.should eq(3)
      attrs.map(&.name).should contain("hourFormat")
      attrs.map(&.name).should contain("activeCalendarType")
      attrs.map(&.name).should contain("supportedCalendarTypes")
    end

    it "reads HourFormat" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12
      )
      read(cluster, Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT).should eq(0_u8) # Hr12 = 0
    end

    it "reads ActiveCalendarType when set" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
        ]
      )
      read(cluster, Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE).should eq(2_u8) # Coptic = 2
    end

    it "returns unsupported for ActiveCalendarType when not set" do
      cluster = build(Matter::Cluster::TimeFormatLocalization)
      read_status(cluster, Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end

    it "reads SupportedCalendarTypes when set" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
        ]
      )
      values = read_tlv(cluster, Matter::Cluster::TimeFormatLocalization::ATTR_SUPPORTED_CALENDAR_TYPES).as_list.map(&.as_u8)
      values.should eq([0_u8, 1_u8, 2_u8]) # Buddhist, Chinese, Coptic
    end

    it "marks HourFormat as writable" do
      cluster = build(Matter::Cluster::TimeFormatLocalization)
      attr = cluster.attributes.find { |attribute| attribute.name == "hourFormat" }
      attr.should_not be_nil
      attr.as(Matter::Cluster::AttributeMetadata).writable?.should be_true
    end

    it "marks ActiveCalendarType as writable" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        ]
      )
      attr = cluster.attributes.find { |attribute| attribute.name == "activeCalendarType" }
      attr.should_not be_nil
      attr.as(Matter::Cluster::AttributeMetadata).writable?.should be_true
    end
  end

  describe "write_attribute" do
    describe "HourFormat" do
      it "writes valid hour format" do
        cluster = build(Matter::Cluster::TimeFormatLocalization,
          hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24
        )

        status = write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT,
          0_u8 # Hr12
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12)
      end

      it "writes UseActiveLocale hour format" do
        cluster = build(Matter::Cluster::TimeFormatLocalization)

        status = write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT,
          255_u8 # UseActiveLocale
        )
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::UseActiveLocale)
      end

      it "rejects invalid hour format value" do
        cluster = build(Matter::Cluster::TimeFormatLocalization)

        status = write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT,
          2_u8 # Invalid value
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end

      it "calls callback when hour format changes" do
        cluster = build(Matter::Cluster::TimeFormatLocalization,
          hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24
        )

        old_format = nil.as(Matter::Cluster::TimeFormatLocalization::HourFormat?)
        new_format = nil.as(Matter::Cluster::TimeFormatLocalization::HourFormat?)
        cluster.on_hour_format_changed do |old, new|
          old_format = old
          new_format = new
        end

        write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT,
          0_u8 # Hr12
        )
        old_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24)
        new_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12)
      end
    end

    describe "ActiveCalendarType" do
      it "writes valid calendar type (from matter.js test)" do
        cluster = build(Matter::Cluster::TimeFormatLocalization,
          feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
          hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24,
          active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese,
            Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
          ]
        )

        status = write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE,
          1_u8 # Chinese
        )
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese)
      end

      it "rejects invalid calendar type (from matter.js test)" do
        cluster = build(Matter::Cluster::TimeFormatLocalization,
          feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
          hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24,
          active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese,
            Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
          ]
        )

        # Try to set Gregorian (4) which is not in supported list
        status = write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE,
          4_u8 # Gregorian - not supported
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
        # Calendar type should remain unchanged
        cluster.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic)
      end

      it "rejects calendar type when feature not enabled" do
        cluster = build(Matter::Cluster::TimeFormatLocalization)

        status = write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE,
          4_u8 # Gregorian
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
      end

      it "calls callback when calendar type changes" do
        cluster = build(Matter::Cluster::TimeFormatLocalization,
          feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
          active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese,
          ]
        )

        old_calendar = nil.as(Matter::Cluster::TimeFormatLocalization::CalendarType??)
        new_calendar = nil.as(Matter::Cluster::TimeFormatLocalization::CalendarType?)
        cluster.on_calendar_changed do |old, new|
          old_calendar = old
          new_calendar = new
        end

        write(cluster,
          Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE,
          1_u8 # Chinese
        )
        old_calendar.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist)
        new_calendar.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese)
      end
    end

    it "returns error for read-only attributes" do
      cluster = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        ]
      )
      status = write(cluster,
        Matter::Cluster::TimeFormatLocalization::ATTR_SUPPORTED_CALENDAR_TYPES,
        Bytes[1, 0]
      )
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end

    it "returns error for unsupported attributes" do
      cluster = build(Matter::Cluster::TimeFormatLocalization)
      status = write(cluster, 0x9999_u32, 1_u8)
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "practical scenarios" do
    it "models a US device with 12-hour format and Gregorian calendar" do
      device = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        ]
      )

      device.hour_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12)
      device.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian)
    end

    it "models a European device with 24-hour format" do
      device = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        ]
      )

      device.hour_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24)
    end

    it "models a multi-cultural device supporting multiple calendars" do
      device = build(Matter::Cluster::TimeFormatLocalization,
        feature_map: Matter::Cluster::TimeFormatLocalization::Feature::CalendarFormat,
        hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24,
        active_calendar_type: Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalization::CalendarType::Buddhist,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Chinese,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Coptic,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Ethiopian,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Gregorian,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Hebrew,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Islamic,
          Matter::Cluster::TimeFormatLocalization::CalendarType::Japanese,
        ]
      )

      device.supported_calendar_types.as(Array).size.should eq(8)

      # Switch between calendars
      write(device,
        Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE,
        7_u8 # Islamic
      )
      device.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Islamic)

      write(device,
        Matter::Cluster::TimeFormatLocalization::ATTR_ACTIVE_CALENDAR_TYPE,
        5_u8 # Hebrew
      )
      device.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalization::CalendarType::Hebrew)
    end

    it "models user changing hour format preference" do
      device = build(Matter::Cluster::TimeFormatLocalization,
        hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12
      )

      changes = [] of String
      device.on_hour_format_changed do |old, new|
        changes << "#{old} -> #{new}"
      end

      # User switches to 24-hour format
      write(device,
        Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT,
        1_u8 # Hr24
      )

      # User switches back to 12-hour format
      write(device,
        Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT,
        0_u8 # Hr12
      )

      changes.should eq([
        "Hr12 -> Hr24",
        "Hr24 -> Hr12",
      ])
    end

    it "models a simple device without calendar format feature" do
      device = build(Matter::Cluster::TimeFormatLocalization,
        hour_format: Matter::Cluster::TimeFormatLocalization::HourFormat::Hr24
      )

      device.calendar_format_enabled?.should be_false
      device.attributes.size.should eq(1)

      # Can change hour format
      write(device,
        Matter::Cluster::TimeFormatLocalization::ATTR_HOUR_FORMAT,
        0_u8 # Hr12
      )
      device.hour_format.should eq(Matter::Cluster::TimeFormatLocalization::HourFormat::Hr12)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute reads" do
      cluster = build(Matter::Cluster::TimeFormatLocalization)
      read_status(cluster, 0x9999_u32).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end
end
