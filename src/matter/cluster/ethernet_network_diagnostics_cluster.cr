require "./cluster"

module Matter
  module Cluster
    # Ethernet Network Diagnostics Cluster (0x0037)
    #
    # Provides Ethernet network diagnostic information.
    # Required by Apple Home for Ethernet-connected accessories.
    #
    # Matter Spec: Core 11.15
    class EthernetNetworkDiagnosticsCluster < Base
      CLUSTER_ID = 0x0037_u32

      # PHY Rate enum
      enum PHYRateEnum : UInt8
        Rate10M  = 0 # 10 Mbps
        Rate100M = 1 # 100 Mbps
        Rate1G   = 2 # 1 Gbps
        Rate25G  = 3 # 2.5 Gbps
        Rate5G   = 4 # 5 Gbps
        Rate10G  = 5 # 10 Gbps
        Rate40G  = 6 # 40 Gbps
        Rate100G = 7 # 100 Gbps
        Rate200G = 8 # 200 Gbps
        Rate400G = 9 # 400 Gbps
      end

      # Feature flags
      @[Flags]
      enum Feature : UInt32
        PacketCounts = 0x01 # PKTCNT
        ErrorCounts  = 0x02 # ERRCNT
      end

      # Attribute IDs
      ATTR_PHY_RATE         = 0x0000_u32
      ATTR_FULL_DUPLEX      = 0x0001_u32
      ATTR_PACKET_RX_COUNT  = 0x0002_u32
      ATTR_PACKET_TX_COUNT  = 0x0003_u32
      ATTR_TX_ERR_COUNT     = 0x0004_u32
      ATTR_COLLISION_COUNT  = 0x0005_u32
      ATTR_OVERRUN_COUNT    = 0x0006_u32
      ATTR_CARRIER_DETECT   = 0x0007_u32
      ATTR_TIME_SINCE_RESET = 0x0008_u32

      # Command IDs
      CMD_RESET_COUNTS = 0x00_u32

      # Global attributes
      CLUSTER_REVISION       = 0xFFFD_u32
      FEATURE_MAP            = 0xFFFC_u32
      ATTRIBUTE_LIST         = 0xFFFB_u32
      ACCEPTED_COMMAND_LIST  = 0xFFF9_u32
      GENERATED_COMMAND_LIST = 0xFFF8_u32

      # Attribute values
      property phy_rate : PHYRateEnum?
      property full_duplex : Bool?
      property packet_rx_count : UInt64
      property packet_tx_count : UInt64
      property tx_err_count : UInt64
      property collision_count : UInt64
      property overrun_count : UInt64
      property carrier_detect : Bool?
      property feature_map : Feature

      # Track when counters were last reset
      @reset_time : Time

      def initialize(
        endpoint_id : DataType::EndpointNumber,
        @phy_rate : PHYRateEnum? = PHYRateEnum::Rate1G,
        @full_duplex : Bool? = true,
        @feature_map : Feature = Feature::PacketCounts | Feature::ErrorCounts,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @packet_rx_count = 0_u64
        @packet_tx_count = 0_u64
        @tx_err_count = 0_u64
        @collision_count = 0_u64
        @overrun_count = 0_u64
        @carrier_detect = true
        @reset_time = Time.utc
      end

      def self.cluster_id : UInt32
        CLUSTER_ID
      end

      def name : String
        "EthernetNetworkDiagnostics"
      end

      def attributes : Array(AttributeMetadata)
        attrs = [] of AttributeMetadata

        # PHYRate - nullable
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_PHY_RATE),
          name: "PHYRate",
          type: :enum8,
          writable: false,
          optional: true
        )

        # FullDuplex - nullable
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_FULL_DUPLEX),
          name: "FullDuplex",
          type: :bool,
          writable: false,
          optional: true
        )

        # PacketRxCount - conditional on PKTCNT feature
        if @feature_map.packet_counts?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_PACKET_RX_COUNT),
            name: "PacketRxCount",
            type: :uint64,
            writable: false
          )

          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_PACKET_TX_COUNT),
            name: "PacketTxCount",
            type: :uint64,
            writable: false
          )
        end

        # Error counts - conditional on ERRCNT feature
        if @feature_map.error_counts?
          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_TX_ERR_COUNT),
            name: "TxErrCount",
            type: :uint64,
            writable: false
          )

          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_COLLISION_COUNT),
            name: "CollisionCount",
            type: :uint64,
            writable: false
          )

          attrs << AttributeMetadata.new(
            id: DataType::AttributeId.new(ATTR_OVERRUN_COUNT),
            name: "OverrunCount",
            type: :uint64,
            writable: false
          )
        end

        # CarrierDetect - nullable
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_CARRIER_DETECT),
          name: "CarrierDetect",
          type: :bool,
          writable: false,
          optional: true
        )

        # TimeSinceReset
        attrs << AttributeMetadata.new(
          id: DataType::AttributeId.new(ATTR_TIME_SINCE_RESET),
          name: "TimeSinceReset",
          type: :uint64,
          writable: false
        )

        attrs
      end

      def commands : Array(CommandMetadata)
        cmds = [] of CommandMetadata

        # ResetCounts - conditional on PKTCNT or ERRCNT feature
        if @feature_map.packet_counts? || @feature_map.error_counts?
          cmds << CommandMetadata.new(
            id: DataType::CommandId.new(CMD_RESET_COUNTS),
            name: "ResetCounts"
          )
        end

        cmds
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_PHY_RATE
          if rate = @phy_rate
            encode_uint8(rate.value)
          else
            encode_null
          end
        when ATTR_FULL_DUPLEX
          if fd = @full_duplex
            encode_bool(fd)
          else
            encode_null
          end
        when ATTR_PACKET_RX_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.packet_counts?
          encode_uint64(@packet_rx_count)
        when ATTR_PACKET_TX_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.packet_counts?
          encode_uint64(@packet_tx_count)
        when ATTR_TX_ERR_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.error_counts?
          encode_uint64(@tx_err_count)
        when ATTR_COLLISION_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.error_counts?
          encode_uint64(@collision_count)
        when ATTR_OVERRUN_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.error_counts?
          encode_uint64(@overrun_count)
        when ATTR_CARRIER_DETECT
          if cd = @carrier_detect
            encode_bool(cd)
          else
            encode_null
          end
        when ATTR_TIME_SINCE_RESET
          encode_uint64(time_since_reset)
        when CLUSTER_REVISION
          encode_uint16(1_u16) # EthernetNetworkDiagnostics cluster revision 1
        when FEATURE_MAP
          encode_uint32(@feature_map.value)
        when ATTRIBUTE_LIST
          encode_attribute_list
        when ACCEPTED_COMMAND_LIST
          encode_accepted_command_list
        when GENERATED_COMMAND_LIST
          encode_generated_command_list
        else
          super
        end
      end

      private def encode_null : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put_null(nil)
        io.to_slice
      end

      private def encode_uint64(value : UInt64) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)
        writer.put_unsigned_int(nil, value)
        io.to_slice
      end

      private def time_since_reset : UInt64
        # TimeSinceReset is in minutes per Matter spec
        (Time.utc - @reset_time).total_minutes.to_u64
      end

      private def encode_attribute_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        attr_ids = [ATTR_PHY_RATE, ATTR_FULL_DUPLEX]

        if @feature_map.packet_counts?
          attr_ids << ATTR_PACKET_RX_COUNT
          attr_ids << ATTR_PACKET_TX_COUNT
        end

        if @feature_map.error_counts?
          attr_ids << ATTR_TX_ERR_COUNT
          attr_ids << ATTR_COLLISION_COUNT
          attr_ids << ATTR_OVERRUN_COUNT
        end

        attr_ids << ATTR_CARRIER_DETECT
        attr_ids << ATTR_TIME_SINCE_RESET

        # Global attributes
        attr_ids << GENERATED_COMMAND_LIST
        attr_ids << ACCEPTED_COMMAND_LIST
        attr_ids << ATTRIBUTE_LIST
        attr_ids << FEATURE_MAP
        attr_ids << CLUSTER_REVISION

        writer.start_array(nil)
        attr_ids.each do |id|
          writer.put_unsigned_int(nil, id, force_size: 4)
        end
        writer.end_container

        io.to_slice
      end

      private def encode_accepted_command_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        writer.start_array(nil)
        if @feature_map.packet_counts? || @feature_map.error_counts?
          writer.put_unsigned_int(nil, CMD_RESET_COUNTS, force_size: 4)
        end
        writer.end_container

        io.to_slice
      end

      private def encode_generated_command_list : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # No generated commands
        writer.start_array(nil)
        writer.end_container

        io.to_slice
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_RESET_COUNTS
          handle_reset_counts
        else
          InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
        end
      end

      private def handle_reset_counts : InteractionModel::Status
        @packet_rx_count = 0_u64
        @packet_tx_count = 0_u64
        @tx_err_count = 0_u64
        @collision_count = 0_u64
        @overrun_count = 0_u64
        @reset_time = Time.utc
        increment_version
        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Public API: Increment packet counts
      def record_rx_packet
        @packet_rx_count += 1
      end

      def record_tx_packet
        @packet_tx_count += 1
      end

      def record_tx_error
        @tx_err_count += 1
      end

      def record_collision
        @collision_count += 1
      end

      def record_overrun
        @overrun_count += 1
      end
    end
  end
end
