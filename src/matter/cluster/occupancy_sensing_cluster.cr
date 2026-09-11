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
      cluster 0x0406, revision: 5

      feature :other, bit: 0            # OTHER - Other sensing modality
      feature :passive_infrared, bit: 1 # PIR - PIR sensing
      feature :ultrasonic, bit: 2       # US - Ultrasonic sensing
      feature :physical_contact, bit: 3 # PHY - Physical contact sensing
      feature :active_infrared, bit: 4  # AIR - Active IR sensing
      feature :radar, bit: 5            # RADAR - Radar/microwave sensing
      feature :rf_sensing, bit: 6       # RFSENS - RF signal analysis
      feature :vision, bit: 7           # VIS - Vision-based sensing

      # Occupancy sensor types (legacy enum)
      enum OccupancySensorType : UInt8
        PIR              = 0
        Ultrasonic       = 1
        PIRAndUltrasonic = 2
        PhysicalContact  = 3
      end

      # Occupancy bitmap (bit 0 = occupied)
      OCCUPANCY_OCCUPIED   = 0x01_u8
      OCCUPANCY_UNOCCUPIED = 0x00_u8

      # OccupancySensorTypeBitmap (bit 0 = PIR)
      SENSOR_TYPE_BITMAP_PIR = 0x01_u8

      # Specification defaults and limits of the per-modality delays and thresholds
      DEFAULT_DELAY     =  0_u16
      DEFAULT_THRESHOLD =   1_u8
      MIN_THRESHOLD     =   1_u8
      MAX_THRESHOLD     = 254_u8

      attribute 0x0000, :occupancy, UInt8, default: OCCUPANCY_UNOCCUPIED, max: OCCUPANCY_OCCUPIED
      attribute 0x0001, :occupancy_sensor_type, OccupancySensorType, default: OccupancySensorType::PIR, fixed: true
      attribute 0x0002, :occupancy_sensor_type_bitmap, UInt8, default: SENSOR_TYPE_BITMAP_PIR, fixed: true
      attribute 0x0003, :hold_time, UInt16, nullable: true, optional: true, writable: true, write_access: :manage, present_if: :hold_time

      attribute 0x0010, :pir_occupied_to_unoccupied_delay, UInt16, default: DEFAULT_DELAY, writable: true, write_access: :manage, optional: true, requires: :passive_infrared
      attribute 0x0011, :pir_unoccupied_to_occupied_delay, UInt16, default: DEFAULT_DELAY, writable: true, write_access: :manage, optional: true, requires: :passive_infrared
      attribute 0x0012, :pir_unoccupied_to_occupied_threshold, UInt8, default: DEFAULT_THRESHOLD, writable: true, write_access: :manage, optional: true, min: MIN_THRESHOLD, max: MAX_THRESHOLD, requires: :passive_infrared

      attribute 0x0020, :ultrasonic_occupied_to_unoccupied_delay, UInt16, default: DEFAULT_DELAY, writable: true, write_access: :manage, optional: true, requires: :ultrasonic
      attribute 0x0021, :ultrasonic_unoccupied_to_occupied_delay, UInt16, default: DEFAULT_DELAY, writable: true, write_access: :manage, optional: true, requires: :ultrasonic
      attribute 0x0022, :ultrasonic_unoccupied_to_occupied_threshold, UInt8, default: DEFAULT_THRESHOLD, writable: true, write_access: :manage, optional: true, min: MIN_THRESHOLD, max: MAX_THRESHOLD, requires: :ultrasonic

      attribute 0x0030, :physical_contact_occupied_to_unoccupied_delay, UInt16, default: DEFAULT_DELAY, writable: true, write_access: :manage, optional: true, requires: :physical_contact
      attribute 0x0031, :physical_contact_unoccupied_to_occupied_delay, UInt16, default: DEFAULT_DELAY, writable: true, write_access: :manage, optional: true, requires: :physical_contact
      attribute 0x0032, :physical_contact_unoccupied_to_occupied_threshold, UInt8, default: DEFAULT_THRESHOLD, writable: true, write_access: :manage, optional: true, min: MIN_THRESHOLD, max: MAX_THRESHOLD, requires: :physical_contact

      event 0x00, :occupancy_changed, priority: :info

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @feature_map : Feature = Feature::PassiveInfrared,
                     @occupancy : UInt8 = OCCUPANCY_UNOCCUPIED,
                     @occupancy_sensor_type : OccupancySensorType = OccupancySensorType::PIR,
                     @occupancy_sensor_type_bitmap : UInt8 = SENSOR_TYPE_BITMAP_PIR,
                     @hold_time : UInt16? = nil,
                     @pir_occupied_to_unoccupied_delay : UInt16 = DEFAULT_DELAY,
                     @pir_unoccupied_to_occupied_delay : UInt16 = DEFAULT_DELAY,
                     @pir_unoccupied_to_occupied_threshold : UInt8 = DEFAULT_THRESHOLD,
                     @ultrasonic_occupied_to_unoccupied_delay : UInt16 = DEFAULT_DELAY,
                     @ultrasonic_unoccupied_to_occupied_delay : UInt16 = DEFAULT_DELAY,
                     @ultrasonic_unoccupied_to_occupied_threshold : UInt8 = DEFAULT_THRESHOLD,
                     @physical_contact_occupied_to_unoccupied_delay : UInt16 = DEFAULT_DELAY,
                     @physical_contact_unoccupied_to_occupied_delay : UInt16 = DEFAULT_DELAY,
                     @physical_contact_unoccupied_to_occupied_threshold : UInt8 = DEFAULT_THRESHOLD)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))

        raise ArgumentError.new("occupancy must be <= #{OCCUPANCY_OCCUPIED}") if @occupancy > OCCUPANCY_OCCUPIED
        validate_threshold("pir_unoccupied_to_occupied_threshold", @pir_unoccupied_to_occupied_threshold)
        validate_threshold("ultrasonic_unoccupied_to_occupied_threshold", @ultrasonic_unoccupied_to_occupied_threshold)
        validate_threshold("physical_contact_unoccupied_to_occupied_threshold", @physical_contact_unoccupied_to_occupied_threshold)
      end

      # HoldTime is optional: unsupported until configured.
      # Reports the occupancy state; `occupancy=` with a device-facing name
      def update_occupancy(occupied : Bool) : Nil
        self.occupancy = occupied ? OCCUPANCY_OCCUPIED : OCCUPANCY_UNOCCUPIED
      end

      def occupied? : Bool
        (@occupancy & OCCUPANCY_OCCUPIED) != 0
      end

      private def validate_threshold(name : String, threshold : UInt8) : Nil
        return if (MIN_THRESHOLD..MAX_THRESHOLD).includes?(threshold)
        raise ArgumentError.new("#{name} must be between #{MIN_THRESHOLD} and #{MAX_THRESHOLD}")
      end
    end
  end
end
