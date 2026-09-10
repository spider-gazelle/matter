require "./crypto/key"
require "./datatype/case_authenticated_tag"
require "./datatype/node_id"
require "base64"

module Matter
  # Fabric represents a unique administrative domain in Matter
  #
  # A fabric is a logical grouping of Matter nodes that share a common trust root
  # and can communicate securely. Each fabric has:
  # - A unique 64-bit Fabric ID
  # - A trusted Root CA certificate
  # - Node Operational Certificates (NOCs) for each member
  # - An Identity Protection Key (IPK) for privacy
  #
  # Matter devices can be members of multiple fabrics simultaneously (multi-admin).
  # Each fabric gets a local Fabric Index (1-254) on the device.
  #
  # Specification: Matter 1.4 § 4.13 (Fabrics)
  class Fabric
    # Unique 64-bit identifier for this fabric (globally unique)
    property fabric_id : UInt64

    # Local index on the device (1-254, 0 is reserved)
    # This is device-specific and may differ across devices
    property fabric_index : UInt8

    # Our Node ID within this fabric (64-bit)
    # Combined with fabric_id forms a globally unique identifier
    property node_id : UInt64

    # Trusted Root Certificate Authority public key
    # This is the trust anchor for certificate validation
    property root_public_key : Bytes

    # Node Operational Certificate (NOC) - our identity certificate
    # TLV-encoded Matter certificate
    property operational_cert : Bytes

    # Private key corresponding to the public key in our NOC
    property operational_key : Crypto::Key

    # Identity Protection Key (IPK) - 16 bytes
    # Used to encrypt node IDs in operational discovery for privacy
    property ipk : Bytes

    # Vendor ID for this fabric (identifies the admin/commissioner)
    property vendor_id : UInt16

    # User-friendly label for this fabric (max 32 UTF-8 characters)
    property label : String

    # Intermediate CA certificate (optional)
    # If present, forms a chain: Root CA -> ICA -> NOC
    property intermediate_cert : Bytes?

    # Root CA certificate (RCAC) - the trust anchor certificate
    # This is the full TLV-encoded certificate, not just the public key
    property root_cert : Bytes?

    # Timestamp when this fabric was created (Unix epoch seconds)
    property created_at : Int64

    # Timestamp when this fabric was last used (Unix epoch seconds)
    property last_used_at : Int64

    # Case Authenticated Tags (CATs) extracted from NOC certificate
    # CATs provide additional identity attributes for access control.
    # Up to 3 CATs can be specified in the NOC subject field.
    # Specification: Matter 1.4 § 6.6.2.1.1 (Case Authenticated Tag Subject)
    property cats : Array(DataType::CaseAuthenticatedTag)

    def initialize(
      @fabric_id : UInt64,
      @fabric_index : UInt8,
      @node_id : UInt64,
      @root_public_key : Bytes,
      @operational_cert : Bytes,
      @operational_key : Crypto::Key,
      @ipk : Bytes,
      @vendor_id : UInt16 = 0xFFF1_u16, # Default test vendor ID
      @label : String = "",
      @intermediate_cert : Bytes? = nil,
      @root_cert : Bytes? = nil,
      @created_at : Int64 = Time.utc.to_unix,
      @last_used_at : Int64 = Time.utc.to_unix,
      @cats : Array(DataType::CaseAuthenticatedTag) = [] of DataType::CaseAuthenticatedTag,
    )
      validate!
    end

    # Validate fabric constraints
    private def validate!
      # Fabric index must be 1-254 (0 is reserved, 255 is invalid)
      raise ArgumentError.new("fabric_index must be 1-254") if @fabric_index == 0 || @fabric_index == 255

      # IPK must be exactly 16 bytes
      raise ArgumentError.new("ipk must be 16 bytes") if @ipk.size != 16

      # Label must be max 32 UTF-8 characters
      raise ArgumentError.new("label must be <= 32 characters") if @label.size > 32

      # Fabric ID must not be 0
      raise ArgumentError.new("fabric_id must not be 0") if @fabric_id == 0

      # Node ID must not be 0
      raise ArgumentError.new("node_id must not be 0") if @node_id == 0

      # Max 3 CATs per fabric (per Matter spec)
      raise ArgumentError.new("cats must have <= 3 entries") if @cats.size > 3
    end

    # Update the last used timestamp
    def mark_used
      @last_used_at = Time.utc.to_unix
    end

    # Check if this fabric is expired (unused for more than 1 year)
    def expired?(threshold_seconds : Int64 = 31_536_000) : Bool
      Time.utc.to_unix - @last_used_at > threshold_seconds
    end

    # Serialize fabric to hash for storage
    def to_h : Hash(String, String | UInt64 | UInt16 | UInt8 | Int64)
      # Serialize operational key - store BOTH private and public bits
      # This ensures we preserve the exact public key from commissioning
      private_key_bytes = @operational_key.private_bits
      raise "Operational key has no private bits" unless private_key_bytes

      public_key_bytes = @operational_key.public_bits
      raise "Operational key has no public bits" unless public_key_bytes

      # Serialize CATs as comma-separated hex values
      cats_str = @cats.map(&.value.to_s(16)).join(",")

      {
        "fabric_id"              => @fabric_id,
        "fabric_index"           => @fabric_index,
        "node_id"                => @node_id,
        "root_public_key"        => Base64.strict_encode(@root_public_key),
        "operational_cert"       => Base64.strict_encode(@operational_cert),
        "operational_key"        => Base64.strict_encode(private_key_bytes),
        "operational_public_key" => Base64.strict_encode(public_key_bytes),
        "ipk"                    => Base64.strict_encode(@ipk),
        "vendor_id"              => @vendor_id,
        "label"                  => @label,
        "intermediate_cert"      => @intermediate_cert.try { |cert| Base64.strict_encode(cert) } || "",
        "root_cert"              => @root_cert.try { |cert| Base64.strict_encode(cert) } || "",
        "created_at"             => @created_at,
        "last_used_at"           => @last_used_at,
        "cats"                   => cats_str,
      }
    end

    # Deserialize fabric from hash
    def self.from_h(data : Hash(String, String | UInt64 | UInt16 | UInt8 | Int64)) : Fabric
      intermediate_cert = if ic = data["intermediate_cert"]?.as?(String)
                            ic.empty? ? nil : Base64.decode(ic)
                          end

      root_cert = if rc = data["root_cert"]?.as?(String)
                    rc.empty? ? nil : Base64.decode(rc)
                  end

      # Reconstruct operational key from private AND public bits
      # We store both to ensure the exact public key from commissioning is preserved
      operational_key_bytes = Base64.decode(data["operational_key"].as(String))
      operational_key = Crypto::Key.new(Crypto::KeyType::EC, Crypto::CurveType::P256)

      # Set public bits FIRST if available (before private_bits triggers derivation)
      if pub_key_str = data["operational_public_key"]?.as?(String)
        operational_key.public_bits = Base64.decode(pub_key_str)
      end

      # Then set private bits (won't derive public since x_bits is already set)
      operational_key.private_bits = operational_key_bytes

      # Deserialize CATs from comma-separated hex values
      cats = if cats_str = data["cats"]?.as?(String)
               if cats_str.empty?
                 [] of DataType::CaseAuthenticatedTag
               else
                 cats_str.split(",").map do |hex|
                   DataType::CaseAuthenticatedTag.new(hex.to_u32(16))
                 end
               end
             else
               [] of DataType::CaseAuthenticatedTag
             end

      Fabric.new(
        fabric_id: data["fabric_id"].as(UInt64 | Int64).to_u64,
        fabric_index: data["fabric_index"].as(UInt8 | Int32 | Int64).to_u8,
        node_id: data["node_id"].as(UInt64 | Int64).to_u64,
        root_public_key: Base64.decode(data["root_public_key"].as(String)),
        operational_cert: Base64.decode(data["operational_cert"].as(String)),
        operational_key: operational_key,
        ipk: Base64.decode(data["ipk"].as(String)),
        vendor_id: data["vendor_id"].as(UInt16 | Int32 | Int64).to_u16,
        label: data["label"].as(String),
        intermediate_cert: intermediate_cert,
        root_cert: root_cert,
        created_at: data["created_at"].as(Int64),
        last_used_at: data["last_used_at"].as(Int64),
        cats: cats
      )
    end

    # Get the compressed fabric identifier using HKDF
    # This is used in various Matter protocols, especially mDNS service discovery
    #
    # The compressed fabric ID is an 8-byte value derived from:
    # - Key: root public key (excluding first byte which is 0x04 format indicator)
    # - Salt: fabric_id (8 bytes, little-endian)
    # - Info: "CompressedFabric"
    # - Length: 8 bytes
    #
    # Specification: Matter 1.4 § 4.13.2.4.2 (Compressed Fabric Identifier)
    def compressed_fabric_id : Bytes
      # Prepare salt: fabric_id as 8 bytes (big-endian per Matter spec 4.3.2.2)
      salt = Bytes.new(8)
      IO::ByteFormat::BigEndian.encode(@fabric_id, salt)

      # Key: root public key without first byte (skip 0x04 uncompressed point indicator)
      # Root public key format is: 0x04 || x (32 bytes) || y (32 bytes) = 65 bytes total
      key = @root_public_key[1..-1]

      # Info: "CompressedFabric"
      info = "CompressedFabric".to_slice

      # Derive 8-byte compressed fabric ID using HKDF-SHA256
      Crypto.create_hkdf_key(key, salt, info, 8)
    end

    # Derive the Identity Protection Key (IPK) for CASE authentication
    #
    # The IPK is derived from the epoch key (ipk_value from AddNOC) using HKDF.
    # This derived key is what's actually used in the CASE Sigma2 salt.
    #
    # Formula: IPK = HKDF-SHA-256(InputKey=epoch_key, Salt=CompressedFabricId, Info="GroupKey v1.0", Length=16)
    #
    # Note: The info string "GroupKey v1.0" matches matter.js implementation.
    # Specification: Matter 1.4 § 4.16.2.5.2 (Group Key Derivation)
    def derived_ipk : Bytes
      # Salt is the compressed fabric ID (8 bytes)
      salt = compressed_fabric_id

      # Input key is the raw epoch key stored as @ipk
      input_key = @ipk

      # Info string is "GroupKey v1.0" (matches matter.js GROUP_SECURITY_INFO)
      info = "GroupKey v1.0".to_slice

      # Derive 16-byte IPK using HKDF-SHA256
      Crypto.create_hkdf_key(input_key, salt, info, 16)
    end

    # Get scoped node ID (used in CASE for peer identification)
    def scoped_node_id : UInt64
      # Scoped node ID is just the node_id within fabric context
      @node_id
    end

    # Helper to check if a given fabric_index matches
    def matches_index?(index : UInt8) : Bool
      @fabric_index == index
    end

    # Compute the expected destination_id for CASE Sigma1 matching
    #
    # The destination_id helps identify which fabric is being targeted in a CASE session.
    # It's computed as:
    #   destination_id = HMAC-SHA256(key=IPK, data=initiatorRandom || rootPublicKey || fabricId || nodeId)
    #
    # This method computes what the destination_id should be for this fabric given an initiator_random.
    #
    # @param initiator_random The 32-byte random value from CASE Sigma1
    # @return 32-byte destination_id that should match the one in Sigma1 if this fabric is the target
    #
    # Note: fabricId and nodeId are encoded in Little Endian format per matter.js implementation.
    # This differs from some other Matter protocol encodings that use Big Endian.
    def compute_destination_id(initiator_random : Bytes) : Bytes
      # Use derived IPK as the HMAC key
      ipk = derived_ipk

      # Build the data to HMAC: initiatorRandom || rootPublicKey || fabricId || nodeId
      data = IO::Memory.new
      data.write(initiator_random)
      data.write(@root_public_key)

      # fabricId and nodeId are 8 bytes each, Little Endian (matches matter.js DataWriter)
      fabric_id_bytes = Bytes.new(8)
      IO::ByteFormat::LittleEndian.encode(@fabric_id, fabric_id_bytes)
      data.write(fabric_id_bytes)

      node_id_bytes = Bytes.new(8)
      IO::ByteFormat::LittleEndian.encode(@node_id, node_id_bytes)
      data.write(node_id_bytes)

      # Compute HMAC-SHA256
      Crypto.sign_hmac(ipk, data.to_slice)
    end

    # Check if this fabric matches the given destination_id from CASE Sigma1
    #
    # @param destination_id The 32-byte destination_id from Sigma1
    # @param initiator_random The 32-byte initiator_random from Sigma1
    # @return true if this fabric matches the destination_id
    def matches_destination_id?(destination_id : Bytes, initiator_random : Bytes) : Bool
      expected = compute_destination_id(initiator_random)
      destination_id == expected
    end

    # Helper to check if a given fabric_id matches
    def matches_id?(id : UInt64) : Bool
      @fabric_id == id
    end

    # Get CATs as NodeId-encoded values for access control matching
    # Each CAT is encoded as a NodeId with prefix 0xFFFFFFFD
    #
    # This is used during CASE session establishment to provide the
    # subjects that should be checked against access control entries.
    def cat_node_ids : Array(UInt64)
      @cats.map { |cat| DataType::NodeId.from_case_authenticated_tag(cat).id }
    end

    # Check if this fabric has any CATs
    def has_cats? : Bool
      !@cats.empty?
    end

    # String representation for debugging
    def to_s(io : IO)
      io << "Fabric(id=0x#{@fabric_id.to_s(16)}, "
      io << "index=#{@fabric_index}, "
      io << "node_id=0x#{@node_id.to_s(16)}, "
      io << "vendor=0x#{@vendor_id.to_s(16)}, "
      io << "label=\"#{@label}\")"
    end
  end

  # FabricDescriptor is the structure returned by the Fabrics attribute
  # in the Operational Credentials cluster
  #
  # Specification: Matter 1.4 § 11.17.4.5
  struct FabricDescriptor
    property root_public_key : Bytes
    property vendor_id : UInt16
    property fabric_id : UInt64
    property node_id : UInt64
    property label : String
    property fabric_index : UInt8

    def initialize(
      @root_public_key : Bytes,
      @vendor_id : UInt16,
      @fabric_id : UInt64,
      @node_id : UInt64,
      @label : String,
      @fabric_index : UInt8,
    )
    end

    # Create from a Fabric
    def self.from_fabric(fabric : Fabric) : FabricDescriptor
      FabricDescriptor.new(
        root_public_key: fabric.root_public_key,
        vendor_id: fabric.vendor_id,
        fabric_id: fabric.fabric_id,
        node_id: fabric.node_id,
        label: fabric.label,
        fabric_index: fabric.fabric_index
      )
    end
  end
end
