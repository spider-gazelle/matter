require "../storage/record"

module Matter
  module Controller
    struct NodeInfo
      include Storage::Record

      # Default Matter operational UDP port.
      DEFAULT_PORT = 5540

      getter node_id : UInt64
      getter address : String?
      getter port : Int32

      def initialize(@node_id : UInt64, @address : String? = nil, @port : Int32 = DEFAULT_PORT)
      end
    end

    struct FabricInfo
      include Storage::Record

      # Default (test) vendor id used when creating a fabric.
      DEFAULT_ADMIN_VENDOR_ID = 0xFFF1_u16

      getter fabric_id : UInt64
      getter controller_node_id : UInt64

      # Raw epoch key (IPK value) provided during AddNOC (16 bytes).
      getter ipk_value : Bytes

      # TLV root certificate provided via AddTrustedRootCertificate.
      getter root_cert : Bytes

      # Root public key extracted from root cert (65 bytes, uncompressed point).
      getter root_public_key : Bytes

      # Controller operational identity (NOC + private key).
      getter controller_noc : Bytes
      getter controller_private_key : Bytes

      getter admin_vendor_id : UInt16

      def initialize(
        @fabric_id : UInt64,
        @controller_node_id : UInt64,
        @ipk_value : Bytes,
        @root_cert : Bytes,
        @root_public_key : Bytes,
        @controller_noc : Bytes,
        @controller_private_key : Bytes,
        @admin_vendor_id : UInt16 = DEFAULT_ADMIN_VENDOR_ID,
      )
      end
    end

    struct State
      include Storage::Record

      property fabric : FabricInfo?
      property nodes : Hash(UInt64, NodeInfo)

      # Commissioner node id used for unsecured message source_node_id and as the
      # controller node id when creating a new fabric.
      property commissioner_node_id : UInt64 = 0_u64

      # Monotonic counter for unsecured (session_id=0) messages. This must not go
      # backwards across process restarts or peers may treat requests as stale.
      property unsecured_message_counter : UInt32 = 0_u32

      def initialize(
        @fabric : FabricInfo? = nil,
        @nodes : Hash(UInt64, NodeInfo) = {} of UInt64 => NodeInfo,
        @commissioner_node_id : UInt64 = 0_u64,
        @unsecured_message_counter : UInt32 = 0_u32,
      )
      end
    end
  end
end
