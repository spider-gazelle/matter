require "../spec_helper"

describe Matter::Cluster::TimeFormatLocalizationCluster do
  endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)

  describe "initialization" do
    it "creates with default values (24-hour format)" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)
      cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24)
      cluster.active_calendar_type.should be_nil
      cluster.supported_calendar_types.should be_nil
      cluster.calendar_format_enabled?.should be_false
    end

    it "creates with 12-hour format" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12
      )
      cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12)
    end

    it "creates with calendar format feature" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
        ]
      )
      cluster.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian)
      cluster.supported_calendar_types.should eq([
        Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
      ])
      cluster.calendar_format_enabled?.should be_true
    end

    it "validates active calendar type is in supported list" do
      expect_raises(ArgumentError, /active_calendar_type must be in supported_calendar_types/) do
        Matter::Cluster::TimeFormatLocalizationCluster.new(
          endpoint_id,
          feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
          active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese,
          ]
        )
      end
    end

    it "validates no duplicates in supported calendar types" do
      expect_raises(ArgumentError, /supported_calendar_types must not contain duplicates/) do
        Matter::Cluster::TimeFormatLocalizationCluster.new(
          endpoint_id,
          feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
          ]
        )
      end
    end
  end

  describe "attributes" do
    it "has required base attributes" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)
      attrs = cluster.attributes
      attrs.size.should eq(1)
      attrs.map(&.name).should contain("hourFormat")
    end

    it "has calendar format attributes when feature enabled" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        ]
      )
      attrs = cluster.attributes
      attrs.size.should eq(3)
      attrs.map(&.name).should contain("hourFormat")
      attrs.map(&.name).should contain("activeCalendarType")
      attrs.map(&.name).should contain("supportedCalendarTypes")
    end

    it "reads HourFormat" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12
      )
      bytes = cluster.read_attribute(Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[0]) # Hr12 = 0
    end

    it "reads ActiveCalendarType when set" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
        ]
      )
      bytes = cluster.read_attribute(Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE)
      bytes.should be_a(Bytes)
      bytes.as(Bytes).should eq(Bytes[2]) # Coptic = 2
    end

    it "returns unsupported for ActiveCalendarType when not set" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)
      result = cluster.read_attribute(Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end

    it "reads SupportedCalendarTypes when set" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
        ]
      )
      bytes = cluster.read_attribute(Matter::Cluster::TimeFormatLocalizationCluster::ATTR_SUPPORTED_CALENDAR_TYPES)
      bytes.should be_a(Bytes)
      # Array format: [count, value1, value2, value3]
      bytes.as(Bytes)[0].should eq(3) # Count
      bytes.as(Bytes)[1].should eq(0) # Buddhist
      bytes.as(Bytes)[2].should eq(1) # Chinese
      bytes.as(Bytes)[3].should eq(2) # Coptic
    end

    it "marks HourFormat as writable" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)
      attr = cluster.attributes.find { |a| a.name == "hourFormat" }
      attr.should_not be_nil
      attr.not_nil!.writable?.should be_true
    end

    it "marks ActiveCalendarType as writable" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        ]
      )
      attr = cluster.attributes.find { |a| a.name == "activeCalendarType" }
      attr.should_not be_nil
      attr.not_nil!.writable?.should be_true
    end
  end

  describe "write_attribute" do
    describe "HourFormat" do
      it "writes valid hour format" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
          endpoint_id,
          hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24
        )

        status = cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT,
          Bytes[0] # Hr12
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12)
      end

      it "writes UseActiveLocale hour format" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)

        status = cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT,
          Bytes[255] # UseActiveLocale
        )
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.hour_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::UseActiveLocale)
      end

      it "rejects invalid hour format value" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)

        status = cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT,
          Bytes[2] # Invalid value
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
      end

      it "calls callback when hour format changes" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
          endpoint_id,
          hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24
        )

        old_format = nil.as(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat?)
        new_format = nil.as(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat?)
        cluster.on_hour_format_changed do |old, new|
          old_format = old
          new_format = new
        end

        cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT,
          Bytes[0] # Hr12
        )
        old_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24)
        new_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12)
      end
    end

    describe "ActiveCalendarType" do
      it "writes valid calendar type (from matter.js test)" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
          endpoint_id,
          feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
          hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24,
          active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese,
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
          ]
        )

        status = cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE,
          Bytes[1] # Chinese
        )
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::Success)
        cluster.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese)
      end

      it "rejects invalid calendar type (from matter.js test)" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
          endpoint_id,
          feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
          hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24,
          active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese,
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
          ]
        )

        # Try to set Gregorian (4) which is not in supported list
        status = cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE,
          Bytes[4] # Gregorian - not supported
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::ConstraintError)
        # Calendar type should remain unchanged
        cluster.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic)
      end

      it "rejects calendar type when feature not enabled" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)

        status = cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE,
          Bytes[4] # Gregorian
        )
        status.should be_a(Matter::InteractionModel::Status)
        status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
      end

      it "calls callback when calendar type changes" do
        cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
          endpoint_id,
          feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
          active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
          supported_calendar_types: [
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
            Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese,
          ]
        )

        old_calendar = nil.as(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType??)
        new_calendar = nil.as(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType?)
        cluster.on_calendar_changed do |old, new|
          old_calendar = old
          new_calendar = new
        end

        cluster.write_attribute(
          Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE,
          Bytes[1] # Chinese
        )
        old_calendar.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist)
        new_calendar.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese)
      end
    end

    it "returns error for read-only attributes" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        ]
      )
      status = cluster.write_attribute(
        Matter::Cluster::TimeFormatLocalizationCluster::ATTR_SUPPORTED_CALENDAR_TYPES,
        Bytes[1, 0]
      )
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end

    it "returns error for unsupported attributes" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)
      status = cluster.write_attribute(0x9999_u32, Bytes[1])
      status.should be_a(Matter::InteractionModel::Status)
      status.as(Matter::InteractionModel::Status).status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end

  describe "practical scenarios" do
    it "models a US device with 12-hour format and Gregorian calendar" do
      device = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        ]
      )

      device.hour_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12)
      device.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian)
    end

    it "models a European device with 24-hour format" do
      device = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        ]
      )

      device.hour_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24)
    end

    it "models a multi-cultural device supporting multiple calendars" do
      device = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        feature_map: Matter::Cluster::TimeFormatLocalizationCluster::Feature::CalendarFormat,
        hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24,
        active_calendar_type: Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
        supported_calendar_types: [
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Buddhist,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Chinese,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Coptic,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Ethiopian,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Gregorian,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Hebrew,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Islamic,
          Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Japanese,
        ]
      )

      device.supported_calendar_types.not_nil!.size.should eq(8)

      # Switch between calendars
      device.write_attribute(
        Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE,
        Bytes[7] # Islamic
      )
      device.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Islamic)

      device.write_attribute(
        Matter::Cluster::TimeFormatLocalizationCluster::ATTR_ACTIVE_CALENDAR_TYPE,
        Bytes[5] # Hebrew
      )
      device.active_calendar_type.should eq(Matter::Cluster::TimeFormatLocalizationCluster::CalendarType::Hebrew)
    end

    it "models user changing hour format preference" do
      device = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12
      )

      changes = [] of String
      device.on_hour_format_changed do |old, new|
        changes << "#{old} -> #{new}"
      end

      # User switches to 24-hour format
      device.write_attribute(
        Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT,
        Bytes[1] # Hr24
      )

      # User switches back to 12-hour format
      device.write_attribute(
        Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT,
        Bytes[0] # Hr12
      )

      changes.should eq([
        "Hr12 -> Hr24",
        "Hr24 -> Hr12",
      ])
    end

    it "models a simple device without calendar format feature" do
      device = Matter::Cluster::TimeFormatLocalizationCluster.new(
        endpoint_id,
        hour_format: Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr24
      )

      device.calendar_format_enabled?.should be_false
      device.attributes.size.should eq(1)

      # Can change hour format
      device.write_attribute(
        Matter::Cluster::TimeFormatLocalizationCluster::ATTR_HOUR_FORMAT,
        Bytes[0] # Hr12
      )
      device.hour_format.should eq(Matter::Cluster::TimeFormatLocalizationCluster::HourFormat::Hr12)
    end
  end

  describe "error handling" do
    it "returns error for unsupported attribute reads" do
      cluster = Matter::Cluster::TimeFormatLocalizationCluster.new(endpoint_id)
      result = cluster.read_attribute(0x9999_u32)
      result.should be_a(Matter::InteractionModel::Status)
      status = result.as(Matter::InteractionModel::Status)
      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedAttribute)
    end
  end
end
