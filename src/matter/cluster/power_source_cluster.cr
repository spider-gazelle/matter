require "./cluster"

module Matter
  module Cluster
    # Power Source Cluster (0x002F)
    #
    # Provides attributes and events for determining detailed information about power sources
    # present on a node, such as batteries or wired power.
    #
    # This implementation focuses on Battery and Replaceable features for battery-powered devices.
    #
    # Specification: Matter 1.4 § 11.7
    class PowerSourceCluster < Base
      CLUSTER_ID = 0x002F_u32

      # Base Attributes
      ATTR_STATUS      = 0x0000_u32
      ATTR_ORDER       = 0x0001_u32
      ATTR_DESCRIPTION = 0x0002_u32

      # Battery Feature Attributes
      ATTR_BAT_CHARGE_LEVEL       = 0x000E_u32
      ATTR_BAT_REPLACEMENT_NEEDED = 0x000F_u32
      ATTR_BAT_REPLACEABILITY     = 0x0010_u32

      # Replaceable Feature Attributes
      ATTR_BAT_REPLACEMENT_DESCRIPTION = 0x0013_u32
      ATTR_BAT_QUANTITY                = 0x0019_u32

      # Power source status values
      enum PowerSourceStatus
        Unspecified = 0 # Status is not specified
        Active      = 1 # Source is available and currently supplying power
        Standby     = 2 # Source is available but not currently supplying power
        Unavailable = 3 # Source is not currently available to supply power
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

      # Current power source status
      property status : PowerSourceStatus

      # Relative preference for power selection (lower is preferred)
      property order : UInt8

      # User-facing description of this source
      property description : String

      # Battery charge level (Battery feature)
      property bat_charge_level : BatChargeLevel?

      # Whether battery needs replacement (Battery feature)
      property bat_replacement_needed : Bool?

      # Battery replaceability (Battery feature)
      property bat_replaceability : BatReplaceability?

      # Battery replacement description (Replaceable feature)
      property bat_replacement_description : String?

      # Number of battery cells/packs (Replaceable feature)
      property bat_quantity : UInt8?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @status : PowerSourceStatus = PowerSourceStatus::Active,
                     @order : UInt8 = 0_u8,
                     @description : String = "Battery",
                     @bat_charge_level : BatChargeLevel? = nil,
                     @bat_replacement_needed : Bool? = nil,
                     @bat_replaceability : BatReplaceability? = nil,
                     @bat_replacement_description : String? = nil,
                     @bat_quantity : UInt8? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate description length
        raise ArgumentError.new("description must be <= 60 characters") if @description.size > 60

        # Validate bat_replacement_description length if provided
        if desc = @bat_replacement_description
          raise ArgumentError.new("bat_replacement_description must be <= 60 characters") if desc.size > 60
        end

        # Validate Battery feature: if any battery attribute is set, all mandatory ones must be set
        battery_attrs = [@bat_charge_level, @bat_replacement_needed, @bat_replaceability]
        if battery_attrs.any?(&.nil?) && battery_attrs.any?(&.!=(nil))
          raise ArgumentError.new("Battery feature requires bat_charge_level, bat_replacement_needed, and bat_replaceability")
        end

        # Validate Replaceable feature: if any replaceable attribute is set, all mandatory ones must be set
        replaceable_attrs = [@bat_replacement_description, @bat_quantity]
        if replaceable_attrs.any?(&.nil?) && replaceable_attrs.any?(&.!=(nil))
          raise ArgumentError.new("Replaceable feature requires bat_replacement_description and bat_quantity")
        end
      end

      def name : String
        "PowerSource"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_STATUS),
            "Status",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ORDER),
            "Order",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_DESCRIPTION),
            "Description",
            :string,
            writable: false
          ),
        ]

        # Add Battery feature attributes if enabled
        if battery_feature_enabled?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_CHARGE_LEVEL),
            "BatChargeLevel",
            :uint8,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_REPLACEMENT_NEEDED),
            "BatReplacementNeeded",
            :bool,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_REPLACEABILITY),
            "BatReplaceability",
            :uint8,
            writable: false
          )
        end

        # Add Replaceable feature attributes if enabled
        if replaceable_feature_enabled?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_REPLACEMENT_DESCRIPTION),
            "BatReplacementDescription",
            :string,
            writable: false
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_BAT_QUANTITY),
            "BatQuantity",
            :uint8,
            writable: false
          )
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands for power source cluster
      end

      def read_attribute(attribute_id : UInt32) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_STATUS
          Bytes[@status.value.to_u8]
        when ATTR_ORDER
          Bytes[@order]
        when ATTR_DESCRIPTION
          encode_string(@description)
        when ATTR_BAT_CHARGE_LEVEL
          if level = @bat_charge_level
            Bytes[level.value.to_u8]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_REPLACEMENT_NEEDED
          if needed = @bat_replacement_needed
            Bytes[needed ? 1_u8 : 0_u8]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_REPLACEABILITY
          if replaceability = @bat_replaceability
            Bytes[replaceability.value.to_u8]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_REPLACEMENT_DESCRIPTION
          if desc = @bat_replacement_description
            encode_string(desc)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_BAT_QUANTITY
          if quantity = @bat_quantity
            Bytes[quantity]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        else
          super
        end
      end

      # Update battery charge level
      def update_bat_charge_level(level : BatChargeLevel)
        return unless battery_feature_enabled?

        old_value = @bat_charge_level
        @bat_charge_level = level

        if old_value != level
          @on_charge_level_changed.try &.call(old_value, level)
          increment_version
        end
      end

      # Update battery replacement needed status
      def update_bat_replacement_needed(needed : Bool)
        return unless battery_feature_enabled?

        old_value = @bat_replacement_needed
        @bat_replacement_needed = needed

        if old_value != needed
          @on_replacement_needed_changed.try &.call(old_value, needed)
          increment_version
        end
      end

      # Check if Battery feature is enabled
      def battery_feature_enabled? : Bool
        !@bat_charge_level.nil?
      end

      # Check if Replaceable feature is enabled
      def replaceable_feature_enabled? : Bool
        !@bat_replacement_description.nil?
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
    end
  end
end
