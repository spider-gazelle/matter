require "json"

module Matter
  module Controller
    struct NodeInfo
      include JSON::Serializable

      getter node_id : UInt64
      getter address : String?
      getter port : Int32

      def initialize(@node_id : UInt64, @address : String? = nil, @port : Int32 = 5540)
      end
    end

    struct FabricInfo
      include JSON::Serializable

      getter fabric_id : UInt64
      getter controller_node_id : UInt64

      # Raw epoch key (IPK value) provided during AddNOC (16 bytes).
      getter ipk_value_hex : String

      # TLV root certificate provided via AddTrustedRootCertificate.
      getter root_cert_hex : String

      # Root public key extracted from root cert (65 bytes, uncompressed point).
      getter root_public_key_hex : String

      # Controller operational identity (NOC + private key).
      getter controller_noc_hex : String
      getter controller_private_key_hex : String

      getter admin_vendor_id : UInt16

      def initialize(
        @fabric_id : UInt64,
        @controller_node_id : UInt64,
        @ipk_value_hex : String,
        @root_cert_hex : String,
        @root_public_key_hex : String,
        @controller_noc_hex : String,
        @controller_private_key_hex : String,
        @admin_vendor_id : UInt16 = 0xFFF1_u16,
      )
      end

      def ipk_value : Bytes
        @ipk_value_hex.hexbytes
      end

      def root_cert : Bytes
        @root_cert_hex.hexbytes
      end

      def root_public_key : Bytes
        @root_public_key_hex.hexbytes
      end

      def controller_noc : Bytes
        @controller_noc_hex.hexbytes
      end

      def controller_private_key : Bytes
        @controller_private_key_hex.hexbytes
      end
    end

    struct State
      include JSON::Serializable

      property fabric : FabricInfo?
      property nodes : Hash(UInt64, NodeInfo)

      # Commissioner node id used for unsecured message source_node_id and as the
      # controller node id when creating a new fabric.
      @[JSON::Field(default: 0_u64)]
      property commissioner_node_id : UInt64

      # Monotonic counter for unsecured (session_id=0) messages. This must not go
      # backwards across process restarts or peers may treat requests as stale.
      @[JSON::Field(default: 0_u32)]
      property unsecured_message_counter : UInt32

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
