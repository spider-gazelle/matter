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
      cluster 0x002F, revision: 3

      feature :wired, bit: 0        # WIRED - Wired power source
      feature :battery, bit: 1      # BAT - Battery power source
      feature :rechargeable, bit: 2 # RECHG - Rechargeable battery
      feature :replaceable, bit: 3  # REPLC - Replaceable battery
      conflicts :wired, :battery

      # Description strings are at most 60 characters; BatPercentRemaining
      # is in half-percent units (0..200).
      DESCRIPTION_MAX_LENGTH    =  60
      BAT_PERCENT_REMAINING_MAX = 200

      # Power source status values
      enum PowerSourceStatus : UInt8
        Unspecified = 0 # Status is not specified
        Active      = 1 # Source is available and currently supplying power
        Standby     = 2 # Source is available but not currently supplying power
        Unavailable = 3 # Source is not currently available to supply power
      end

      # Wired current type values
      enum WiredCurrentType : UInt8
        AC = 0 # Alternating current
        DC = 1 # Direct current
      end

      # Battery charge level values (coarse ranking)
      enum BatChargeLevel : UInt8
        Ok       = 0 # Charge level is nominal
        Warning  = 1 # Charge level is low, intervention may soon be required
        Critical = 2 # Charge level is critical, immediate intervention is required
      end

      # Battery replaceability values
      enum BatReplaceability : UInt8
        Unspecified        = 0 # Replaceability is unspecified or unknown
        NotReplaceable     = 1 # Battery is not replaceable
        UserReplaceable    = 2 # Battery is replaceable by the user or customer
        FactoryReplaceable = 3 # Battery is replaceable by an authorized factory technician
      end

      # Battery charge state values
      enum BatChargeState : UInt8
        Unknown        = 0 # Charge state is unknown
        IsCharging     = 1 # Battery is charging
        IsAtFullCharge = 2 # Battery is at full charge
        IsNotCharging  = 3 # Battery is not charging
      end

      # Base attributes
      attribute 0x0000, :status, PowerSourceStatus, default: PowerSourceStatus::Active
      attribute 0x0001, :order, UInt8, default: 0_u8
      attribute 0x0002, :description, String, default: "Battery", fixed: true

      # Feature attributes. Those without a default are present exactly when
      # the device supplied a value (see `attribute_present?`).
      attribute 0x0003, :wired_assessed_input_voltage, UInt32, nullable: true, optional: true, omit_changes: true, requires: :wired
      attribute 0x0004, :wired_assessed_input_frequency, UInt16, nullable: true, optional: true, omit_changes: true, requires: :wired
      attribute 0x0005, :wired_current_type, WiredCurrentType, default: WiredCurrentType::AC, fixed: true, requires: :wired
      attribute 0x0009, :wired_present, Bool, nullable: true, optional: true, requires: :wired

      attribute 0x000B, :bat_voltage, UInt32, nullable: true, optional: true, omit_changes: true, requires: :battery
      attribute 0x000C, :bat_percent_remaining, UInt8, nullable: true, optional: true, max: BAT_PERCENT_REMAINING_MAX, requires: :battery
      attribute 0x000D, :bat_time_remaining, UInt32, nullable: true, optional: true, requires: :battery
      attribute 0x000E, :bat_charge_level, BatChargeLevel, nullable: true, requires: :battery
      attribute 0x000F, :bat_replacement_needed, Bool, nullable: true, requires: :battery
      attribute 0x0010, :bat_replaceability, BatReplaceability, nullable: true, fixed: true, requires: :battery
      attribute 0x0011, :bat_present, Bool, nullable: true, optional: true, requires: :battery

      attribute 0x0013, :bat_replacement_description, String, nullable: true, fixed: true, requires: :replaceable
      attribute 0x0019, :bat_quantity, UInt8, nullable: true, fixed: true, requires: :replaceable

      attribute 0x001A, :bat_charge_state, BatChargeState, nullable: true, optional: true, requires: :rechargeable
      attribute 0x001B, :bat_time_to_full_charge, UInt32, nullable: true, optional: true, requires: :rechargeable
      attribute 0x001C, :bat_functional_while_charging, Bool, nullable: true, optional: true, requires: :rechargeable

      # The DSL gates attributes on features only; this hook runs after the
      # DSL's own `finished` hook and narrows the generated tables to the
      # attributes that have a value.
      macro finished
        protected def dsl_attribute_supported?(attribute_id : UInt32) : Bool
          previous_def && attribute_present?(attribute_id)
        end

        def attributes : Array(AttributeMetadata)
          ATTRIBUTES.select { |attribute| dsl_attribute_supported?(attribute.id.id) }
        end
      end

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @feature_map : Feature = Feature::Battery,
                     @status : PowerSourceStatus = PowerSourceStatus::Active,
                     @order : UInt8 = 0_u8,
                     @description : String = "Battery",
                     # Wired feature
                     @wired_assessed_input_voltage : UInt32? = nil,
                     @wired_assessed_input_frequency : UInt16? = nil,
                     @wired_current_type : WiredCurrentType = WiredCurrentType::AC,
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
                     @bat_functional_while_charging : Bool? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        raise ArgumentError.new("description must be <= #{DESCRIPTION_MAX_LENGTH} characters") if @description.size > DESCRIPTION_MAX_LENGTH

        if desc = @bat_replacement_description
          raise ArgumentError.new("bat_replacement_description must be <= #{DESCRIPTION_MAX_LENGTH} characters") if desc.size > DESCRIPTION_MAX_LENGTH
        end

        # A feature's mandatory attributes are supplied together or not at all
        if @feature_map.battery?
          battery_attrs = [@bat_charge_level, @bat_replacement_needed, @bat_replaceability]
          if battery_attrs.any?(Nil) && battery_attrs.any?(&.!=(nil))
            raise ArgumentError.new("Battery feature requires bat_charge_level, bat_replacement_needed, and bat_replaceability")
          end
        end

        if @feature_map.replaceable? && !@feature_map.battery?
          raise ArgumentError.new("Replaceable feature requires Battery feature")
        end

        if @feature_map.replaceable?
          replaceable_attrs = [@bat_replacement_description, @bat_quantity]
          if replaceable_attrs.any?(Nil) && replaceable_attrs.any?(&.!=(nil))
            raise ArgumentError.new("Replaceable feature requires bat_replacement_description and bat_quantity")
          end
        end

        if @feature_map.rechargeable? && !@feature_map.battery?
          raise ArgumentError.new("Rechargeable feature requires Battery feature")
        end
      end

      # A feature attribute without a value is absent.
      private def attribute_present?(attribute_id : UInt32) : Bool
        case attribute_id
        when ATTR_WIRED_ASSESSED_INPUT_VOLTAGE   then !@wired_assessed_input_voltage.nil?
        when ATTR_WIRED_ASSESSED_INPUT_FREQUENCY then !@wired_assessed_input_frequency.nil?
        when ATTR_WIRED_PRESENT                  then !@wired_present.nil?
        when ATTR_BAT_VOLTAGE                    then !@bat_voltage.nil?
        when ATTR_BAT_PERCENT_REMAINING          then !@bat_percent_remaining.nil?
        when ATTR_BAT_TIME_REMAINING             then !@bat_time_remaining.nil?
        when ATTR_BAT_CHARGE_LEVEL               then !@bat_charge_level.nil?
        when ATTR_BAT_REPLACEMENT_NEEDED         then !@bat_replacement_needed.nil?
        when ATTR_BAT_REPLACEABILITY             then !@bat_replaceability.nil?
        when ATTR_BAT_PRESENT                    then !@bat_present.nil?
        when ATTR_BAT_REPLACEMENT_DESCRIPTION    then !@bat_replacement_description.nil?
        when ATTR_BAT_QUANTITY                   then !@bat_quantity.nil?
        when ATTR_BAT_CHARGE_STATE               then !@bat_charge_state.nil?
        when ATTR_BAT_TIME_TO_FULL_CHARGE        then !@bat_time_to_full_charge.nil?
        when ATTR_BAT_FUNCTIONAL_WHILE_CHARGING  then !@bat_functional_while_charging.nil?
        else                                          true
        end
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | TLV::Any
        return InteractionModel::Status.unsupported_attribute unless attribute_present?(attribute_id)
        super
      end

      protected def handle_write_attribute(attribute_id : UInt32, value : TLV::Any) : InteractionModel::Status
        return InteractionModel::Status.unsupported_attribute unless attribute_present?(attribute_id)
        super
      end

      # Update the remaining battery percentage (0-200 half-percent units,
      # nil = unknown) and report the change to subscribed controllers.
      def update_bat_percent_remaining(value : UInt8?)
        return unless @feature_map.battery?

        if percent = value
          raise ArgumentError.new("bat_percent_remaining must be <= #{BAT_PERCENT_REMAINING_MAX}") if percent > BAT_PERCENT_REMAINING_MAX
        end

        self.bat_percent_remaining = value
      end

      # Update battery charge level
      def update_bat_charge_level(level : BatChargeLevel)
        return unless @feature_map.battery?

        self.bat_charge_level = level
      end

      # Update battery replacement needed status
      def update_bat_replacement_needed(needed : Bool)
        return unless @feature_map.battery?

        self.bat_replacement_needed = needed
      end

      # Check if Battery feature is enabled (for backward compatibility)
      def battery_feature_enabled? : Bool
        @feature_map.battery?
      end

      # Check if Replaceable feature is enabled (for backward compatibility)
      def replaceable_feature_enabled? : Bool
        @feature_map.replaceable?
      end

      # Called with the previous and the new value when the charge level changes
      def on_charge_level_changed(&block : BatChargeLevel?, BatChargeLevel? -> Nil) : Nil
        on_bat_charge_level_changed(&block)
      end

      # Called with the previous and the new value when replacement-needed changes
      def on_replacement_needed_changed(&block : Bool?, Bool? -> Nil) : Nil
        on_bat_replacement_needed_changed(&block)
      end
    end
  end
end
