require "./cluster"

module Matter
  module Cluster
    # Occupancy Sensing Cluster (0x0406)
    #
    # Provides an interface to occupancy sensing functionality based on various sensing
    # modalities (PIR, Ultrasonic, Physical Contact, etc.), including configuration and
    # provision of notifications of occupancy status.
    #
    # This implementation supports PIR (Passive Infrared) sensing.
    #
    # Specification: Matter 1.4 § 2.7
    class OccupancySensingCluster < Base
      CLUSTER_ID = 0x0406_u32

      # Attributes
      ATTR_OCCUPANCY                         = 0x0000_u32
      ATTR_OCCUPANCY_SENSOR_TYPE             = 0x0001_u32
      ATTR_OCCUPANCY_SENSOR_TYPE_BITMAP      = 0x0002_u32
      ATTR_HOLD_TIME                         = 0x0003_u32
      ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY  = 0x0010_u32
      ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_DELAY  = 0x0011_u32
      ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_THRESH = 0x0012_u32

      # Occupancy sensor types (legacy enum)
      enum OccupancySensorType
        PIR              = 0
        Ultrasonic       = 1
        PIRAndUltrasonic = 2
        PhysicalContact  = 3
      end

      # Occupancy bitmap (bit 0 = occupied)
      OCCUPANCY_OCCUPIED = 0x01_u8

      # Current occupancy state (bitmap, bit 0 = occupied)
      property occupancy : UInt8

      # Sensor type (fixed)
      property occupancy_sensor_type : OccupancySensorType

      # Sensor type bitmap (bit 0 = PIR)
      property occupancy_sensor_type_bitmap : UInt8

      # Hold time in seconds (optional, writable)
      property hold_time : UInt16?

      # PIR-specific attributes (optional, writable)
      property pir_occupied_to_unoccupied_delay : UInt16?
      property pir_unoccupied_to_occupied_delay : UInt16?
      property pir_unoccupied_to_occupied_threshold : UInt8?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @occupancy : UInt8 = 0_u8,
                     @occupancy_sensor_type : OccupancySensorType = OccupancySensorType::PIR,
                     @occupancy_sensor_type_bitmap : UInt8 = 0x01_u8, # Bit 0 = PIR
                     @hold_time : UInt16? = nil,
                     @pir_occupied_to_unoccupied_delay : UInt16? = nil,
                     @pir_unoccupied_to_occupied_delay : UInt16? = nil,
                     @pir_unoccupied_to_occupied_threshold : UInt8? = nil)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        # Validate occupancy is a bitmap (should be 0 or 1 for bit 0)
        raise ArgumentError.new("occupancy must be <= 1") if @occupancy > 1_u8

        # Validate threshold if provided (1-254 per spec)
        if threshold = @pir_unoccupied_to_occupied_threshold
          raise ArgumentError.new("pir_unoccupied_to_occupied_threshold must be between 1 and 254") if threshold < 1_u8 || threshold > 254_u8
        end
      end

      def name : String
        "OccupancySensing"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OCCUPANCY),
            "Occupancy",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OCCUPANCY_SENSOR_TYPE),
            "OccupancySensorType",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_OCCUPANCY_SENSOR_TYPE_BITMAP),
            "OccupancySensorTypeBitmap",
            :uint8,
            writable: false
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_HOLD_TIME),
            "HoldTime",
            :uint16,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY),
            "PIROccupiedToUnoccupiedDelay",
            :uint16,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_DELAY),
            "PIRUnoccupiedToOccupiedDelay",
            :uint16,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_THRESH),
            "PIRUnoccupiedToOccupiedThreshold",
            :uint8,
            writable: true
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [] of CommandMetadata # No commands for sensing clusters
      end

      def read_attribute(attribute_id : UInt32) : Bytes | InteractionModel::Status
        case attribute_id
        when ATTR_OCCUPANCY
          Bytes[@occupancy]
        when ATTR_OCCUPANCY_SENSOR_TYPE
          Bytes[@occupancy_sensor_type.value.to_u8]
        when ATTR_OCCUPANCY_SENSOR_TYPE_BITMAP
          Bytes[@occupancy_sensor_type_bitmap]
        when ATTR_HOLD_TIME
          if hold_time = @hold_time
            encode_uint16(hold_time)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PIR_OCCUPIED_TO_UNOCCUPIED_DELAY
          if delay = @pir_occupied_to_unoccupied_delay
            encode_uint16(delay)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_DELAY
          if delay = @pir_unoccupied_to_occupied_delay
            encode_uint16(delay)
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
        when ATTR_PIR_UNOCCUPIED_TO_OCCUPIED_THRESH
          if threshold = @pir_unoccupied_to_occupied_threshold
            Bytes[threshold]
          else
            return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute)
          end
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

      private def encode_uint16(value : UInt16) : Bytes
        bytes = Bytes.new(2)
        IO::ByteFormat::LittleEndian.encode(value, bytes)
        bytes
      end
    end
  end
end
