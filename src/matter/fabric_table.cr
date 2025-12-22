require "./fabric"
require "./storage/base"
require "json"
require "log"

module Matter
  # FabricTable manages the collection of fabrics on a device
  #
  # Matter devices can be members of multiple fabrics simultaneously (multi-admin).
  # Each fabric represents a separate administrative domain with its own trust root,
  # operational certificates, and access control.
  #
  # The FabricTable:
  # - Stores up to a device-specific maximum number of fabrics (typically 16)
  # - Assigns unique local fabric indices (1-254)
  # - Persists fabrics to storage
  # - Provides lookup by fabric_index or fabric_id
  # - Handles fabric lifecycle (add, update, remove)
  #
  # Specification: Matter 1.4 § 4.13.3 (Fabric Table)
  class FabricTable
    Log = ::Log.for("matter.fabric_table")

    # Storage context for fabric persistence
    STORAGE_CONTEXT = ["fabrics"]

    # Maximum number of fabrics a device can support
    # Matter spec requires minimum 5, but devices may support more
    DEFAULT_MAX_FABRICS = 16_u8

    # Fabrics indexed by fabric_index (1-254)
    @fabrics : Hash(UInt8, Fabric)

    # Storage backend for persistence
    @storage : Storage::Base

    # Maximum number of fabrics this device supports
    property max_fabrics : UInt8

    def initialize(
      @storage : Storage::Base,
      @max_fabrics : UInt8 = DEFAULT_MAX_FABRICS,
    )
      @fabrics = Hash(UInt8, Fabric).new

      # Validate max_fabrics
      raise ArgumentError.new("max_fabrics must be >= 5 (Matter requirement)") if @max_fabrics < 5
      raise ArgumentError.new("max_fabrics must be <= 254") if @max_fabrics > 254

      # Load existing fabrics from storage
      load_from_storage
    end

    # Add a new fabric to the table
    def add_fabric(fabric : Fabric) : Bool
      # Check if we're at capacity
      if @fabrics.size >= @max_fabrics
        return false
      end

      # Check if fabric_index is already in use
      if @fabrics.has_key?(fabric.fabric_index)
        return false
      end

      # Check if fabric_id already exists (can't have duplicate fabric IDs)
      if find_by_fabric_id(fabric.fabric_id)
        return false
      end

      # Add fabric and persist
      @fabrics[fabric.fabric_index] = fabric
      persist_to_storage
      true
    end

    # Add a fabric with automatic index assignment
    def add_fabric_auto_index(
      fabric_id : UInt64,
      node_id : UInt64,
      root_public_key : Bytes,
      operational_cert : Bytes,
      operational_key : Crypto::Key,
      ipk : Bytes,
      vendor_id : UInt16 = 0xFFF1_u16,
      label : String = "",
      intermediate_cert : Bytes? = nil,
      root_cert : Bytes? = nil,
    ) : Fabric?
      # Find next available fabric index
      fabric_index = next_available_index
      return nil unless fabric_index

      # Create fabric
      fabric = Fabric.new(
        fabric_id: fabric_id,
        fabric_index: fabric_index,
        node_id: node_id,
        root_public_key: root_public_key,
        operational_cert: operational_cert,
        operational_key: operational_key,
        ipk: ipk,
        vendor_id: vendor_id,
        label: label,
        intermediate_cert: intermediate_cert,
        root_cert: root_cert
      )

      # Add fabric
      add_fabric(fabric) ? fabric : nil
    end

    # Update an existing fabric
    def update_fabric(fabric : Fabric) : Bool
      # Fabric must already exist
      return false unless @fabrics.has_key?(fabric.fabric_index)

      @fabrics[fabric.fabric_index] = fabric
      persist_to_storage
      true
    end

    # Remove a fabric by fabric_index
    def remove_fabric(fabric_index : UInt8) : Bool
      if @fabrics.delete(fabric_index)
        persist_to_storage
        true
      else
        false
      end
    end

    # Remove a fabric by fabric_id
    def remove_fabric_by_id(fabric_id : UInt64) : Bool
      fabric = find_by_fabric_id(fabric_id)
      return false unless fabric

      remove_fabric(fabric.fabric_index)
    end

    # Get a fabric by fabric_index
    def get_fabric(fabric_index : UInt8) : Fabric?
      @fabrics[fabric_index]?
    end

    # Find a fabric by fabric_id
    def find_by_fabric_id(fabric_id : UInt64) : Fabric?
      @fabrics.values.find { |f| f.fabric_id == fabric_id }
    end

    # Get all fabrics
    def all_fabrics : Array(Fabric)
      @fabrics.values.to_a
    end

    # Get fabric count
    def size : Int32
      @fabrics.size
    end

    # Check if table is empty
    def empty? : Bool
      @fabrics.empty?
    end

    # Check if table is full
    def full? : Bool
      @fabrics.size >= @max_fabrics
    end

    # Get number of available slots
    def available_slots : Int32
      @max_fabrics - @fabrics.size
    end

    # Find next available fabric index (1-254)
    def next_available_index : UInt8?
      (1_u8..254_u8).each do |index|
        return index unless @fabrics.has_key?(index)
      end
      nil
    end

    # Get all fabric indices currently in use
    def used_indices : Array(UInt8)
      @fabrics.keys.sort
    end

    # Get all fabric descriptors (for Fabrics attribute)
    def fabric_descriptors : Array(FabricDescriptor)
      @fabrics.values.map { |f| FabricDescriptor.from_fabric(f) }.to_a
    end

    # Clear all fabrics (used for factory reset)
    def clear_all
      @fabrics.clear
      persist_to_storage
    end

    # Mark a fabric as recently used (updates last_used_at)
    def mark_fabric_used(fabric_index : UInt8) : Bool
      fabric = @fabrics[fabric_index]?
      return false unless fabric

      fabric.mark_used
      persist_to_storage
      true
    end

    # Persist fabrics to storage
    def persist_to_storage
      # Convert UInt8 keys to String keys for JSON serialization
      data = {} of String => Hash(String, String | UInt64 | UInt16 | UInt8 | Int64)
      @fabrics.each do |index, fabric|
        data[index.to_s] = fabric.to_h
      end
      json = data.to_json
      @storage.set(STORAGE_CONTEXT, "fabric_table", json)
    end

    # Load fabrics from storage
    def load_from_storage
      stored_value = @storage.get(STORAGE_CONTEXT, "fabric_table")
      return if stored_value.nil?

      # We store JSON strings, so expect a String back
      unless stored_value.is_a?(String)
        Log.warn { "Expected String from storage, got #{stored_value.class}" }
        return
      end

      json = stored_value

      # Parse JSON and reconstruct fabrics
      begin
        data = Hash(String, Hash(String, JSON::Any)).from_json(json)
      rescue ex
        Log.error(exception: ex) { "Failed to parse fabric table JSON (json=#{json})" }
        return
      end

      @fabrics.clear

      data.each do |index_str, fabric_data|
        # Convert JSON::Any values to proper types
        fabric_hash = {} of String => (String | UInt64 | UInt16 | UInt8 | Int64)

        fabric_data.each do |key, value|
          fabric_hash[key] = case value.raw
                             when String
                               value.as_s
                             when Int64
                               value.as_i64
                             when Float64
                               value.as_i64 # Convert float to int
                             when Bool
                               value.as_bool ? 1_i64 : 0_i64
                             else
                               value.as_s
                             end
        end

        begin
          fabric = Fabric.from_h(fabric_hash)
          @fabrics[fabric.fabric_index] = fabric
        rescue ex
          # Skip invalid fabric entries
          Log.warn(exception: ex) { "Failed to load fabric at index #{index_str}" }
        end
      end

      Log.info { "Loaded #{@fabrics.size} fabric(s) from storage" }
    end

    # Export all fabrics for backup
    def export : String
      data = @fabrics.transform_values { |fabric| fabric.to_h }
      data.to_json
    end

    # Import fabrics from backup (replaces existing)
    def import(json : String) : Bool
      begin
        data = Hash(String, Hash(String, JSON::Any)).from_json(json)

        # Validate before clearing existing fabrics
        new_fabrics = Hash(UInt8, Fabric).new
        data.each do |index_str, fabric_data|
          fabric_hash = fabric_data.transform_values do |value|
            case value.raw
            when String
              value.as_s
            when Int64
              value.as_i64
            when Float64
              value.as_f
            when Bool
              value.as_bool
            else
              value.raw
            end
          end

          fabric = Fabric.from_h(fabric_hash)
          new_fabrics[fabric.fabric_index] = fabric
        end

        # All valid, replace existing
        @fabrics = new_fabrics
        persist_to_storage
        true
      rescue ex
        Log.error(exception: ex) { "Failed to import fabrics (json=#{json})" }
        false
      end
    end

    # Validate fabric table consistency
    def validate : Array(String)
      errors = [] of String

      # Check for duplicate fabric IDs
      fabric_ids = @fabrics.values.map(&.fabric_id)
      if fabric_ids.size != fabric_ids.uniq.size
        errors << "Duplicate fabric IDs detected"
      end

      # Check fabric index range
      @fabrics.each do |index, fabric|
        if index != fabric.fabric_index
          errors << "Fabric index mismatch: key=#{index}, fabric.fabric_index=#{fabric.fabric_index}"
        end

        if index == 0 || index == 255
          errors << "Invalid fabric index: #{index}"
        end
      end

      # Check capacity
      if @fabrics.size > @max_fabrics
        errors << "Fabric count (#{@fabrics.size}) exceeds max (#{@max_fabrics})"
      end

      errors
    end

    # Get statistics about fabric usage
    def statistics : Hash(String, Int32 | Float64)
      now = Time.utc.to_unix
      fabrics_array = @fabrics.values

      active_count = fabrics_array.count { |f| !f.expired? }
      expired_count = fabrics_array.size - active_count

      ages = fabrics_array.map { |f| now - f.created_at }
      avg_age = ages.empty? ? 0.0 : ages.sum.to_f / ages.size

      last_used_ages = fabrics_array.map { |f| now - f.last_used_at }
      avg_last_used = last_used_ages.empty? ? 0.0 : last_used_ages.sum.to_f / last_used_ages.size

      {
        "total_fabrics"         => @fabrics.size,
        "active_fabrics"        => active_count,
        "expired_fabrics"       => expired_count,
        "available_slots"       => available_slots,
        "max_fabrics"           => @max_fabrics.to_i,
        "avg_age_seconds"       => avg_age,
        "avg_last_used_seconds" => avg_last_used,
      }
    end
  end
end
