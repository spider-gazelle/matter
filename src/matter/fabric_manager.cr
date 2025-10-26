require "./fabric_table"
require "./crypto/key"
require "log"

module Matter
  # FabricManager provides high-level fabric management operations
  #
  # This class wraps FabricTable and adds additional functionality needed
  # for commissioning operations, including:
  # - Fabric removal for failsafe rollback
  # - NOC restoration for UpdateNOC rollback
  # - Fabric lifecycle management
  #
  # Matter Core Spec §11.17 - Operational Credentials Cluster
  class FabricManager
    Log = ::Log.for("matter.fabric_manager")

    # Underlying fabric table
    property fabric_table : FabricTable

    def initialize(@fabric_table : FabricTable)
      Log.info { "FabricManager initialized with #{@fabric_table.size} fabric(s)" }
    end

    # Remove a fabric by fabric index
    #
    # This is used during failsafe rollback to remove fabrics added during
    # the commissioning session.
    #
    # @param fabric_index Fabric index to remove (1-254)
    # @return True if fabric was removed, false if not found
    def remove_fabric(fabric_index : UInt8) : Bool
      if fabric = @fabric_table.get_fabric(fabric_index)
        Log.info { "Removing fabric: #{fabric}" }
        @fabric_table.remove_fabric(fabric_index)
        Log.info { "Fabric #{fabric_index} removed successfully" }
        true
      else
        Log.warn { "Cannot remove fabric #{fabric_index}: not found" }
        false
      end
    end

    # Restore NOC (operational certificate and key) for a fabric
    #
    # This is used during failsafe rollback to revert UpdateNOC changes.
    # The method restores the previous operational certificate and private key
    # for a fabric that was updated during commissioning.
    #
    # @param fabric_index Fabric index to restore
    # @param operational_cert Previous operational certificate (TLV-encoded)
    # @param operational_key_bytes Previous operational private key bytes
    # @return True if NOC was restored, false if fabric not found
    def restore_noc(fabric_index : UInt8, operational_cert : Bytes, operational_key_bytes : Bytes) : Bool
      fabric = @fabric_table.get_fabric(fabric_index)
      unless fabric
        Log.warn { "Cannot restore NOC for fabric #{fabric_index}: fabric not found" }
        return false
      end

      Log.info { "Restoring NOC for fabric #{fabric_index}" }

      # Reconstruct operational key from bytes
      operational_key = Crypto::Key.new(Crypto::KeyType::EC, Crypto::CurveType::P256)
      operational_key.private_bits = operational_key_bytes

      # Update fabric with restored values
      fabric.operational_cert = operational_cert
      fabric.operational_key = operational_key

      # Persist changes
      @fabric_table.update_fabric(fabric)

      Log.info { "NOC restored successfully for fabric #{fabric_index}" }
      true
    rescue ex
      Log.error(exception: ex) { "Failed to restore NOC for fabric #{fabric_index}" }
      false
    end

    # Get a fabric by index
    def get_fabric(fabric_index : UInt8) : Fabric?
      @fabric_table.get_fabric(fabric_index)
    end

    # Get all fabrics
    def all_fabrics : Array(Fabric)
      @fabric_table.all_fabrics
    end

    # Add a new fabric
    def add_fabric(fabric : Fabric) : Bool
      @fabric_table.add_fabric(fabric)
    end

    # Update an existing fabric
    def update_fabric(fabric : Fabric) : Bool
      @fabric_table.update_fabric(fabric)
    end

    # Get fabric count
    def size : Int32
      @fabric_table.size
    end

    # Check if table is empty
    def empty? : Bool
      @fabric_table.empty?
    end

    # Check if table is full
    def full? : Bool
      @fabric_table.full?
    end

    # Get fabric descriptors for Operational Credentials cluster
    def fabric_descriptors : Array(FabricDescriptor)
      @fabric_table.fabric_descriptors
    end

    # Mark a fabric as recently used
    def mark_fabric_used(fabric_index : UInt8) : Bool
      @fabric_table.mark_fabric_used(fabric_index)
    end
  end
end
