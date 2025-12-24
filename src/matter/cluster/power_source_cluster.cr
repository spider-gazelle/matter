require "./cluster"

module Matter
  module Cluster
    # Power Source Cluster (0x002F)
    #
    # Provides attributes and events for determining detailed information about power sources
    # present on a node, such as batteries or wired power.
    #
    # Features:
    # - Wired (WIRED): Wired power source
    # - Battery (BAT): Battery power source
    # - Rechargeable (RECHG): Rechargeable battery
    # - Replaceable (REPLC): Replaceable battery
    #
    # Note: Wired and Battery features are mutually exclusive.
    #
    # Specification: Matter 1.4 § 11.7
    class PowerSourceCluster < Base
      CLUSTER_ID = 0x002F_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        Wired        = 0x01 # WIRED - Wired power source
        Battery      = 0x02 # BAT - Battery power source
        Rechargeable = 0x04 # RECHG - Rechargeable battery
        Replaceable  = 0x08 # REPLC - Replaceable battery
      end

      # Base Attributes
      ATTR_STATUS      = 0x0000_u32
      ATTR_ORDER       = 0x0001_u32
      ATTR_DESCRIPTION = 0x0002_u32

      # Wired Feature Attributes
      ATTR_WIRED_ASSESSED_INPUT_VOLTAGE   = 0x0003_u32
      ATTR_WIRED_ASSESSED_INPUT_FREQUENCY = 0x0004_u32
      ATTR_WIRED_CURRENT_TYPE             = 0x0005_u32
      ATTR_WIRED_ASSESSED_CURRENT         = 0x0006_u32
      ATTR_WIRED_NOMINAL_VOLTAGE          = 0x0007_u32
      ATTR_WIRED_MAXIMUM_CURRENT          = 0x0008_u32
      ATTR_WIRED_PRESENT                  = 0x0009_u32
      ATTR_ACTIVE_WIRED_FAULTS            = 0x000A_u32

      # Battery Feature Attributes
      ATTR_BAT_VOLTAGE            = 0x000B_u32
      ATTR_BAT_PERCENT_REMAINING  = 0x000C_u32
      ATTR_BAT_TIME_REMAINING     = 0x000D_u32
      ATTR_BAT_CHARGE_LEVEL       = 0x000E_u32
      ATTR_BAT_REPLACEMENT_NEEDED = 0x000F_u32
      ATTR_BAT_REPLACEABILITY     = 0x0010_u32
      ATTR_BAT_PRESENT            = 0x0011_u32
      ATTR_ACTIVE_BAT_FAULTS      = 0x0012_u32

      # Replaceable Feature Attributes
      ATTR_BAT_REPLACEMENT_DESCRIPTION = 0x0013_u32
      ATTR_BAT_COMMON_DESIGNATION      = 0x0014_u32
      ATTR_BAT_ANSI_DESIGNATION        = 0x0015_u32
      ATTR_BAT_IEC_DESIGNATION         = 0x0016_u32
      ATTR_BAT_APPROVED_CHEMISTRY      = 0x0017_u32
      ATTR_BAT_CAPACITY                = 0x0018_u32
      ATTR_BAT_QUANTITY                = 0x0019_u32

      # Rechargeable Feature Attributes
      ATTR_BAT_CHARGE_STATE              = 0x001A_u32
      ATTR_BAT_TIME_TO_FULL_CHARGE       = 0x001B_u32
      ATTR_BAT_FUNCTIONAL_WHILE_CHARGING = 0x001C_u32
      ATTR_BAT_CHARGING_CURRENT          = 0x001D_u32
      ATTR_ACTIVE_BAT_CHARGE_FAULTS      = 0x001E_u32

      # Power source status values
      enum PowerSourceStatus
        Unspecified = 0 # Status is not specified
        Active      = 1 # Source is available and currently supplying power
        Standby     = 2 # Source is available but not currently supplying power
        Unavailable = 3 # Source is not currently available to supply power
      end

      # Wired current type values
      enum WiredCurrentType
        AC = 0 # Alternating current
        DC = 1 # Direct current
      end

      # Battery charge level values (coarse ranking)
      enum BatChargeLevel
        Ok       = 0 # Charge level is nominal
        Warning  = 1 # Charge level is low, intervention may soon be required
        Critical = 2 # Charge level is critical, immediate intervention is required
      end

      # Battery replaceability values
      enum BatReplaceability
        Unspecified        = 0 # Replaceability is unspecified or unknown
        NotReplaceable     = 1 # Battery is not replaceable
        UserReplaceable    = 2 # Battery is replaceable by the user or customer
        FactoryReplaceable = 3 # Battery is replaceable by an authorized factory technician
      end

      # Battery charge state values
      enum BatChargeState
        Unknown        = 0 # Charge state is unknown
        IsCharging     = 1 # Battery is charging
        IsAtFullCharge = 2 # Battery is at full charge
        IsNotCharging  = 3 # Battery is not charging
      end

      # Feature map
      property feature_map : Feature

      # Base attributes
      property status : PowerSourceStatus
      property order : UInt8
      property description : String

      # Wired feature attributes
      property wired_assessed_input_voltage : UInt32?
      property wired_assessed_input_frequency : UInt16?
      property wired_current_type : WiredCurrentType?
      property wired_assessed_current : UInt32?
      property wired_nominal_voltage : UInt32?
      property wired_maximum_current : UInt32?
      property wired_present : Bool?

      # Battery feature attributes
      property bat_voltage : UInt32?
      property bat_percent_remaining : UInt8?
      property bat_time_remaining : UInt32?
      property bat_charge_level : BatChargeLevel?
      property bat_replacement_needed : Bool?
      property bat_replaceability : BatReplaceability?
      property bat_present : Bool?

      # Replaceable feature attributes
      property bat_replacement_description : String?
      property bat_quantity : UInt8?

      # Rechargeable feature attributes
      property bat_charge_state : BatChargeState?
      property bat_time_to_full_charge : UInt32?
      property bat_functional_while_charging : Bool?
      property bat_charging_current : UInt32?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @feature_map : Feature = Feature::Battery,
                     @status : PowerSourceStatus = PowerSourceStatus::Active,
                     @order : UInt8 = 0_u8,
                     @description : String = "Battery",
                     # Wired feature
                     @wired_assessed_input_voltage : UInt32? = nil,
                     @wired_assessed_input_frequency : UInt16? = nil,
                     @wired_current_type : WiredCurrentType? = nil,
                     @wired_assessed_current : UInt32? = nil,
                     @wired_nominal_voltage : UInt32? = nil,
                     @wired_maximum_current : UInt32? = nil,
                     @wired_present : Bool? = nil,
                     # Battery feature
                     @bat_voltage : UInt32? = nil,
                     @bat_percent_remaining : UInt8? = nil,
                     @bat_time_remaining : UInt32? = nil,
                     @bat_charge_level : BatChargeLevel? = nil,
                     @bat_replacement_needed : Bool? = nil,
                     @bat_replaceability : BatReplaceability? = nil,
                     @bat_present : Bool? = nil,
                     # Replaceable feature
                     @bat_replacement_description : String? = nil,
                     @bat_quantity : UInt8? = nil,
                     # Rechargeable feature
                     @bat_charge_state : BatChargeState? = nil,
                     @bat_time_to_full_charge : UInt32? = nil,
                     @bat_functional_while_charging : Bool? = nil,
                     @bat_charging_current : UInt32? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate mutually exclusive features
        if @feature_map.wired? && @feature_map.battery?
          raise ArgumentError.new("Wired and Battery features are mutually exclusive")
        end

        # Validate description length
        raise ArgumentError.new("description must be <= 60 characters") if @description.size > 60

        # Validate bat_replacement_description length if provided
        if desc = @bat_replacement_description
          raise ArgumentError.new("bat_replacement_description must be <= 60 characters") if desc.size > 60
        end

        # Validate Battery feature: if feature is enabled, mandatory attributes must be set
        if @feature_map.battery?
          battery_attrs = [@bat_charge_level, @bat_replacement_needed, @bat_replaceability]
          if battery_attrs.any?(Nil) && battery_attrs.any?(&.!=(nil))
            raise ArgumentError.new("Battery feature requires bat_charge_level, bat_replacement_needed, and bat_replaceability")
          end
        end

        # Validate Replaceable feature dependencies
        if @feature_map.replaceable? && !@feature_map.battery?
          raise ArgumentError.new("Replaceable feature requires Battery feature")
        end

        # Validate Replaceable feature: if feature is enabled, mandatory attributes must be set
        if @feature_map.replaceable?
          replaceable_attrs = [@bat_replacement_description, @bat_quantity]
          if replaceable_attrs.any?(Nil) && replaceable_attrs.any?(&.!=(nil))
            raise ArgumentError.new("Replaceable feature requires bat_replacement_description and bat_quantity")
          end
        end

        # Validate Rechargeable feature dependencies
        if @feature_map.rechargeable? && !@feature_map.battery?
          raise ArgumentError.new("Rechargeable feature requires Battery feature")
        end
      end

      def name : String
        "PowerSource"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_STATUS),
            "status",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ORDER),
            "order",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_DESCRIPTION),
            "description",
            :string,
            writable: false
          ),
        ]

        # Wired feature attributes
        if @feature_map.wired?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_WIRED_CURRENT_TYPE),
            "wiredCurrentType",
            :uint8,
            writable: false
          )
          if @wired_assessed_input_voltage
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_WIRED_ASSESSED_INPUT_VOLTAGE),
              "wiredAssessedInputVoltage",
              :uint32,
              writable: false
            )
          end
          if @wired_assessed_input_frequency
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_WIRED_ASSESSED_INPUT_FREQUENCY),
              "wiredAssessedInputFrequency",
              :uint16,
              writable: false
            )
          end
          if @wired_present != nil
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_WIRED_PRESENT),
              "wiredPresent",
              :bool,
              writable: false
            )
          end
        end

        # Battery feature attributes
        if @feature_map.battery?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_CHARGE_LEVEL),
            "batChargeLevel",
            :uint8,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_REPLACEMENT_NEEDED),
            "batReplacementNeeded",
            :bool,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_REPLACEABILITY),
            "batReplaceability",
            :uint8,
            writable: false
          )
          if @bat_voltage
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_BAT_VOLTAGE),
              "batVoltage",
              :uint32,
              writable: false
            )
          end
          if @bat_percent_remaining
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_BAT_PERCENT_REMAINING),
              "batPercentRemaining",
              :uint8,
              writable: false
            )
          end
          if @bat_time_remaining
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_BAT_TIME_REMAINING),
              "batTimeRemaining",
              :uint32,
              writable: false
            )
          end
          if @bat_present != nil
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_BAT_PRESENT),
              "batPresent",
              :bool,
              writable: false
            )
          end
        end

        # Replaceable feature attributes
        if @feature_map.replaceable?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_REPLACEMENT_DESCRIPTION),
            "batReplacementDescription",
            :string,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_QUANTITY),
            "batQuantity",
            :uint8,
            writable: false
          )
        end

        # Rechargeable feature attributes
        if @feature_map.rechargeable?
          if @bat_charge_state
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_BAT_CHARGE_STATE),
              "batChargeState",
              :uint8,
              writable: false
            )
          end
          if @bat_time_to_full_charge
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_BAT_TIME_TO_FULL_CHARGE),
              "batTimeToFullCharge",
              :uint32,
              writable: false
            )
          end
          if @bat_functional_while_charging != nil
            attrs << AttributeMetadata.new(
              DataType::AttributeId.new(ATTR_BAT_FUNCTIONAL_WHILE_CHARGING),
              "batFunctionalWhileCharging",
              :bool,
              writable: false
            )
          end
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands for power source cluster
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_STATUS
          Bytes[@status.value.to_u8]
        when ATTR_ORDER
          Bytes[@order]
        when ATTR_DESCRIPTION
          encode_string(@description)
          # Wired feature attributes
        when ATTR_WIRED_CURRENT_TYPE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.wired?
          if current_type = @wired_current_type
            Bytes[current_type.value.to_u8]
          else
            Bytes[WiredCurrentType::AC.value.to_u8]
          end
        when ATTR_WIRED_ASSESSED_INPUT_VOLTAGE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.wired?
          if voltage = @wired_assessed_input_voltage
            voltage.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_WIRED_ASSESSED_INPUT_FREQUENCY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.wired?
          if freq = @wired_assessed_input_frequency
            freq.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_WIRED_PRESENT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.wired?
          if present = @wired_present
            Bytes[present ? 1_u8 : 0_u8]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
          # Battery feature attributes
        when ATTR_BAT_CHARGE_LEVEL
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.battery?
          if level = @bat_charge_level
            Bytes[level.value.to_u8]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_REPLACEMENT_NEEDED
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.battery?
          if needed = @bat_replacement_needed
            Bytes[needed ? 1_u8 : 0_u8]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_REPLACEABILITY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.battery?
          if replaceability = @bat_replaceability
            Bytes[replaceability.value.to_u8]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_VOLTAGE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.battery?
          if voltage = @bat_voltage
            voltage.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_PERCENT_REMAINING
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.battery?
          if percent = @bat_percent_remaining
            Bytes[percent]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_TIME_REMAINING
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.battery?
          if time = @bat_time_remaining
            time.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_PRESENT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.battery?
          if present = @bat_present
            Bytes[present ? 1_u8 : 0_u8]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
          # Replaceable feature attributes
        when ATTR_BAT_REPLACEMENT_DESCRIPTION
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.replaceable?
          if desc = @bat_replacement_description
            encode_string(desc)
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_QUANTITY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.replaceable?
          if quantity = @bat_quantity
            Bytes[quantity]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
          # Rechargeable feature attributes
        when ATTR_BAT_CHARGE_STATE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.rechargeable?
          if state = @bat_charge_state
            Bytes[state.value.to_u8]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_TIME_TO_FULL_CHARGE
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.rechargeable?
          if time = @bat_time_to_full_charge
            time.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_FUNCTIONAL_WHILE_CHARGING
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.rechargeable?
          if functional = @bat_functional_while_charging
            Bytes[functional ? 1_u8 : 0_u8]
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      # Update battery charge level
      def update_bat_charge_level(level : BatChargeLevel)
        return unless @feature_map.battery?

        old_value = @bat_charge_level
        @bat_charge_level = level

        if old_value != level
          @on_charge_level_changed.try &.call(old_value, level)
          increment_version
        end
      end

      # Update battery replacement needed status
      def update_bat_replacement_needed(needed : Bool)
        return unless @feature_map.battery?

        old_value = @bat_replacement_needed
        @bat_replacement_needed = needed

        if old_value != needed
          @on_replacement_needed_changed.try &.call(old_value, needed)
          increment_version
        end
      end

      # Check if Battery feature is enabled (for backward compatibility)
      def battery_feature_enabled? : Bool
        @feature_map.battery?
      end

      # Check if Replaceable feature is enabled (for backward compatibility)
      def replaceable_feature_enabled? : Bool
        @feature_map.replaceable?
      end

      # Callback when battery charge level changes
      @on_charge_level_changed : Proc(BatChargeLevel?, BatChargeLevel, Nil)?

      def on_charge_level_changed(&block : BatChargeLevel?, BatChargeLevel -> Nil)
        @on_charge_level_changed = block
      end

      # Callback when battery replacement needed status changes
      @on_replacement_needed_changed : Proc(Bool?, Bool, Nil)?

      def on_replacement_needed_changed(&block : Bool?, Bool -> Nil)
        @on_replacement_needed_changed = block
      end

      private def encode_string(value : String) : Bytes
        bytes = Bytes.new(1 + value.bytesize)
        bytes[0] = value.bytesize.to_u8
        value.to_slice.copy_to(bytes + 1)
        bytes
      end

      # NOTE: Attributes are returned as TLV-encoded bytes (use `value.to_tlv`).
    end
  end
end
