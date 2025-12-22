require "./cluster"

module Matter
  module Cluster
    # Occupancy Sensing Cluster (0x0406)
    #
    # Provides an interface to occupancy sensing functionality based on various sensing
    # modalities (PIR, Ultrasonic, Physical Contact, etc.), including configuration and
    # provision of notifications of occupancy status.
    #
    # Features:
    # - Other (OTHER): Other sensing modality
    # - PassiveInfrared (PIR): PIR sensing
    # - Ultrasonic (US): Ultrasonic sensing
    # - PhysicalContact (PHY): Physical contact sensing
    # - ActiveInfrared (AIR): Active IR sensing
    # - Radar (RADAR): Radar/microwave sensing
    # - RfSensing (RFSENS): RF signal analysis
    # - Vision (VIS): Vision-based sensing
    #
    # Specification: Matter 1.4 § 2.7
    class OccupancySensingCluster < Base
      CLUSTER_ID = 0x0406_u32

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        Other           = 0x01 # OTHER - Other sensing modality
        PassiveInfrared = 0x02 # PIR - PIR sensing
        Ultrasonic      = 0x04 # US - Ultrasonic sensing
        PhysicalContact = 0x08 # PHY - Physical contact sensing
        ActiveInfrared  = 0x10 # AIR - Active IR sensing
        Radar           = 0x20 # RADAR - Radar/microwave sensing
        RfSensing       = 0x40 # RFSENS - RF signal analysis
        Vision          = 0x80 # VIS - Vision-based sensing
      end

      # Attributes - Required
      ATTR_OCCUPANCY                    = 0x0000_u32
      ATTR_OCCUPANCY_SENSOR_TYPE        = 0x0001_u32
      ATTR_OCCUPANCY_SENSOR_TYPE_BITMAP = 0x0002_u32

      # Attributes - Optional (all features)
      ATTR_HOLD_TIME = 0x0003_u32

      # Attributes - PIR feature
      ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY  = 0x0010_u32
      ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_DELAY  = 0x0011_u32
      ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_THRESH = 0x0012_u32

      # Attributes - Ultrasonic feature
      ATTR_ULTRASONIC_OCCUPIED_TO_UNOCCUPIED_DELAY  = 0x0020_u32
      ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_DELAY  = 0x0021_u32
      ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_THRESH = 0x0022_u32

      # Attributes - PhysicalContact feature
      ATTR_PHYSICAL_CONTACT_OCCUPIED_TO_UNOCCUPIED_DELAY  = 0x0030_u32
      ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_DELAY  = 0x0031_u32
      ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_THRESH = 0x0032_u32

      # Occupancy sensor types (legacy enum)
      enum OccupancySensorType
        PIR              = 0
        Ultrasonic       = 1
        PIRAndUltrasonic = 2
        PhysicalContact  = 3
      end

      # Occupancy bitmap (bit 0 = occupied)
      OCCUPANCY_OCCUPIED = 0x01_u8

      # Feature map
      property feature_map : Feature

      # Required attributes
      property occupancy : UInt8
      property occupancy_sensor_type : OccupancySensorType
      property occupancy_sensor_type_bitmap : UInt8

      # Optional attribute (all features)
      property hold_time : UInt16?

      # PIR-specific attributes (PassiveInfrared feature)
      property pir_occupied_to_unoccupied_delay : UInt16?
      property pir_unoccupied_to_occupied_delay : UInt16?
      property pir_unoccupied_to_occupied_threshold : UInt8?

      # Ultrasonic-specific attributes (Ultrasonic feature)
      property ultrasonic_occupied_to_unoccupied_delay : UInt16?
      property ultrasonic_unoccupied_to_occupied_delay : UInt16?
      property ultrasonic_unoccupied_to_occupied_threshold : UInt8?

      # PhysicalContact-specific attributes (PhysicalContact feature)
      property physical_contact_occupied_to_unoccupied_delay : UInt16?
      property physical_contact_unoccupied_to_occupied_delay : UInt16?
      property physical_contact_unoccupied_to_occupied_threshold : UInt8?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @feature_map : Feature = Feature::PassiveInfrared,
                     @occupancy : UInt8 = 0_u8,
                     @occupancy_sensor_type : OccupancySensorType = OccupancySensorType::PIR,
                     @occupancy_sensor_type_bitmap : UInt8 = 0x01_u8, # Bit 0 = PIR
                     @hold_time : UInt16? = nil,
                     # PIR feature attributes
                     @pir_occupied_to_unoccupied_delay : UInt16? = nil,
                     @pir_unoccupied_to_occupied_delay : UInt16? = nil,
                     @pir_unoccupied_to_occupied_threshold : UInt8? = nil,
                     # Ultrasonic feature attributes
                     @ultrasonic_occupied_to_unoccupied_delay : UInt16? = nil,
                     @ultrasonic_unoccupied_to_occupied_delay : UInt16? = nil,
                     @ultrasonic_unoccupied_to_occupied_threshold : UInt8? = nil,
                     # PhysicalContact feature attributes
                     @physical_contact_occupied_to_unoccupied_delay : UInt16? = nil,
                     @physical_contact_unoccupied_to_occupied_delay : UInt16? = nil,
                     @physical_contact_unoccupied_to_occupied_threshold : UInt8? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate occupancy is a bitmap (should be 0 or 1 for bit 0)
        raise ArgumentError.new("occupancy must be <= 1") if @occupancy > 1_u8

        # Validate PIR threshold if provided (1-254 per spec)
        if threshold = @pir_unoccupied_to_occupied_threshold
          raise ArgumentError.new("pir_unoccupied_to_occupied_threshold must be between 1 and 254") if threshold < 1_u8 || threshold > 254_u8
        end

        # Validate Ultrasonic threshold if provided (1-254 per spec)
        if threshold = @ultrasonic_unoccupied_to_occupied_threshold
          raise ArgumentError.new("ultrasonic_unoccupied_to_occupied_threshold must be between 1 and 254") if threshold < 1_u8 || threshold > 254_u8
        end

        # Validate PhysicalContact threshold if provided (1-254 per spec)
        if threshold = @physical_contact_unoccupied_to_occupied_threshold
          raise ArgumentError.new("physical_contact_unoccupied_to_occupied_threshold must be between 1 and 254") if threshold < 1_u8 || threshold > 254_u8
        end
      end

      def name : String
        "OccupancySensing"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OCCUPANCY),
            "occupancy",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OCCUPANCY_SENSOR_TYPE),
            "occupancySensorType",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OCCUPANCY_SENSOR_TYPE_BITMAP),
            "occupancySensorTypeBitmap",
            :uint8,
            writable: false
          ),
        ]

        # HoldTime is optional for all features
        if @hold_time
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_HOLD_TIME),
            "holdTime",
            :uint16,
            writable: true
          )
        end

        # PIR feature attributes
        if @feature_map.passive_infrared?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY),
            "pirOccupiedToUnoccupiedDelay",
            :uint16,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_DELAY),
            "pirUnoccupiedToOccupiedDelay",
            :uint16,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_THRESH),
            "pirUnoccupiedToOccupiedThreshold",
            :uint8,
            writable: true
          )
        end

        # Ultrasonic feature attributes
        if @feature_map.ultrasonic?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ULTRASONIC_OCCUPIED_TO_UNOCCUPIED_DELAY),
            "ultrasonicOccupiedToUnoccupiedDelay",
            :uint16,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_DELAY),
            "ultrasonicUnoccupiedToOccupiedDelay",
            :uint16,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_THRESH),
            "ultrasonicUnoccupiedToOccupiedThreshold",
            :uint8,
            writable: true
          )
        end

        # PhysicalContact feature attributes
        if @feature_map.physical_contact?
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PHYSICAL_CONTACT_OCCUPIED_TO_UNOCCUPIED_DELAY),
            "physicalContactOccupiedToUnoccupiedDelay",
            :uint16,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_DELAY),
            "physicalContactUnoccupiedToOccupiedDelay",
            :uint16,
            writable: true
          )
          attrs << AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_THRESH),
            "physicalContactUnoccupiedToOccupiedThreshold",
            :uint8,
            writable: true
          )
        end

        attrs
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands for sensing clusters
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_OCCUPANCY
          Bytes[@occupancy]
        when ATTR_OCCUPANCY_SENSOR_TYPE
          Bytes[@occupancy_sensor_type.value.to_u8]
        when ATTR_OCCUPANCY_SENSOR_TYPE_BITMAP
          Bytes[@occupancy_sensor_type_bitmap]
        when ATTR_HOLD_TIME
          if hold_time = @hold_time
            hold_time.to_tlv
          else
            InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
          # PIR feature attributes
        when ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.passive_infrared?
          if delay = @pir_occupied_to_unoccupied_delay
            delay.to_tlv
          else
            0_u16.to_tlv # Default value
          end
        when ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.passive_infrared?
          if delay = @pir_unoccupied_to_occupied_delay
            delay.to_tlv
          else
            0_u16.to_tlv # Default value
          end
        when ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_THRESH
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.passive_infrared?
          if threshold = @pir_unoccupied_to_occupied_threshold
            Bytes[threshold]
          else
            Bytes[1_u8] # Default value
          end
          # Ultrasonic feature attributes
        when ATTR_ULTRASONIC_OCCUPIED_TO_UNOCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.ultrasonic?
          if delay = @ultrasonic_occupied_to_unoccupied_delay
            delay.to_tlv
          else
            0_u16.to_tlv
          end
        when ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.ultrasonic?
          if delay = @ultrasonic_unoccupied_to_occupied_delay
            delay.to_tlv
          else
            0_u16.to_tlv
          end
        when ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_THRESH
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.ultrasonic?
          if threshold = @ultrasonic_unoccupied_to_occupied_threshold
            Bytes[threshold]
          else
            Bytes[1_u8]
          end
          # PhysicalContact feature attributes
        when ATTR_PHYSICAL_CONTACT_OCCUPIED_TO_UNOCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.physical_contact?
          if delay = @physical_contact_occupied_to_unoccupied_delay
            delay.to_tlv
          else
            0_u16.to_tlv
          end
        when ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.physical_contact?
          if delay = @physical_contact_unoccupied_to_occupied_delay
            delay.to_tlv
          else
            0_u16.to_tlv
          end
        when ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_THRESH
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.physical_contact?
          if threshold = @physical_contact_unoccupied_to_occupied_threshold
            Bytes[threshold]
          else
            Bytes[1_u8]
          end
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_HOLD_TIME
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 2
          @hold_time = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          # PIR feature attributes
        when ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.passive_infrared?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 2
          @pir_occupied_to_unoccupied_delay = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.passive_infrared?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 2
          @pir_unoccupied_to_occupied_delay = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_THRESH
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.passive_infrared?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1
          threshold = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if threshold < 1_u8 || threshold > 254_u8
          @pir_unoccupied_to_occupied_threshold = threshold
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          # Ultrasonic feature attributes
        when ATTR_ULTRASONIC_OCCUPIED_TO_UNOCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.ultrasonic?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 2
          @ultrasonic_occupied_to_unoccupied_delay = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.ultrasonic?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 2
          @ultrasonic_unoccupied_to_occupied_delay = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_ULTRASONIC_UNOCCUPIED_TO_OCCUPIED_THRESH
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.ultrasonic?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1
          threshold = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if threshold < 1_u8 || threshold > 254_u8
          @ultrasonic_unoccupied_to_occupied_threshold = threshold
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          # PhysicalContact feature attributes
        when ATTR_PHYSICAL_CONTACT_OCCUPIED_TO_UNOCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.physical_contact?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 2
          @physical_contact_occupied_to_unoccupied_delay = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_DELAY
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.physical_contact?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 2
          @physical_contact_unoccupied_to_occupied_delay = IO::ByteFormat::LittleEndian.decode(UInt16, value)
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        when ATTR_PHYSICAL_CONTACT_UNOCCUPIED_TO_OCCUPIED_THRESH
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.physical_contact?
          return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType) if value.size != 1
          threshold = value[0]
          return InteractionModel::Status.new(InteractionModel::StatusCode::ConstraintError) if threshold < 1_u8 || threshold > 254_u8
          @physical_contact_unoccupied_to_occupied_threshold = threshold
          increment_version
          InteractionModel::Status.new(InteractionModel::StatusCode::Success)
        else
          super
        end
      end

      # Update the occupancy state
      def update_occupancy(occupied : Bool)
        old_value = @occupancy
        new_value = occupied ? OCCUPANCY_OCCUPIED : 0_u8

        @occupancy = new_value

        # Invoke callback if value changed
        if old_value != new_value
          @on_occupancy_changed.try &.call(old_value, new_value)
          increment_version
        end
      end

      # Check if currently occupied
      def occupied? : Bool
        (@occupancy & OCCUPANCY_OCCUPIED) != 0
      end

      # Callback when occupancy changes
      @on_occupancy_changed : Proc(UInt8, UInt8, Nil)?

      def on_occupancy_changed(&block : UInt8, UInt8 -> Nil)
        @on_occupancy_changed = block
      end

      # NOTE: Attributes are returned as TLV-encoded bytes (use `value.to_tlv`).
    end
  end
end
