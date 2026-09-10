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
          @phy_rate.try(&.value).to_tlv
        when ATTR_FULL_DUPLEX
          @full_duplex.to_tlv
        when ATTR_PACKET_RX_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.packet_counts?
          @packet_rx_count.to_tlv
        when ATTR_PACKET_TX_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.packet_counts?
          @packet_tx_count.to_tlv
        when ATTR_TX_ERR_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.error_counts?
          @tx_err_count.to_tlv
        when ATTR_COLLISION_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.error_counts?
          @collision_count.to_tlv
        when ATTR_OVERRUN_COUNT
          return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless @feature_map.error_counts?
          @overrun_count.to_tlv
        when ATTR_CARRIER_DETECT
          @carrier_detect.to_tlv
        when ATTR_TIME_SINCE_RESET
          time_since_reset.to_tlv
        when GLOBAL_FEATURE_MAP
          @feature_map.value.to_tlv
        when GLOBAL_ATTRIBUTE_LIST
          encode_attribute_list
        when GLOBAL_ACCEPTED_COMMAND_LIST
          encode_accepted_command_list
        when GLOBAL_GENERATED_COMMAND_LIST
          ([] of UInt32).to_tlv
        else
          super
        end
      end

      private def time_since_reset : UInt64
        # TimeSinceReset is in minutes per Matter spec
        (Time.utc - @reset_time).total_minutes.to_u64
      end

      private def encode_attribute_list : Bytes
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
        attr_ids << GLOBAL_GENERATED_COMMAND_LIST
        attr_ids << GLOBAL_ACCEPTED_COMMAND_LIST
        attr_ids << GLOBAL_ATTRIBUTE_LIST
        attr_ids << GLOBAL_FEATURE_MAP
        attr_ids << GLOBAL_CLUSTER_REVISION

        attr_ids.to_tlv
      end

      private def encode_accepted_command_list : Bytes
        cmd_ids = [] of UInt32
        if @feature_map.packet_counts? || @feature_map.error_counts?
          cmd_ids << CMD_RESET_COUNTS
        end
        cmd_ids.to_tlv
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
