require "./device_type"
require "./cluster/cluster"
require "./datatype/endpoint_number"

module Matter
  # Endpoint represents a single functional unit on a Matter node
  # Each endpoint has a device type and a set of clusters
  class Endpoint
    getter endpoint_id : DataType::EndpointNumber
    getter device_types : Array(DeviceType)
    getter clusters : Hash(UInt32, Cluster::Base)

    def initialize(
      @endpoint_id : DataType::EndpointNumber,
      @device_types : Array(DeviceType) = [] of DeviceType,
    )
      @clusters = {} of UInt32 => Cluster::Base
    end

    # Convenience constructor for single device type
    def initialize(@endpoint_id : DataType::EndpointNumber, device_type : DeviceType)
      @device_types = [device_type]
      @clusters = {} of UInt32 => Cluster::Base
    end

    # Add a cluster to this endpoint
    def add_cluster(cluster : Cluster::Base)
      # Validate that the cluster's endpoint_id matches this endpoint
      unless cluster.endpoint_id.number == @endpoint_id.number
        raise ArgumentError.new("Cluster endpoint_id (#{cluster.endpoint_id.number}) does not match endpoint (#{@endpoint_id.number})")
      end

      @clusters[cluster.cluster_id.id] = cluster
    end

    # Get a cluster by ID
    def get_cluster(cluster_id : UInt32) : Cluster::Base?
      @clusters[cluster_id]?
    end

    # Get a cluster by ID (raises if not found)
    def get_cluster!(cluster_id : UInt32) : Cluster::Base
      @clusters[cluster_id]? || raise KeyError.new("Cluster #{cluster_id} not found on endpoint #{@endpoint_id.number}")
    end

    # Check if endpoint has a cluster
    def has_cluster?(cluster_id : UInt32) : Bool
      @clusters.has_key?(cluster_id)
    end

    # Get all cluster IDs
    def cluster_ids : Array(UInt32)
      @clusters.keys
    end

    # Get primary device type
    def primary_device_type : DeviceType?
      @device_types.first?
    end

    # Validate that this endpoint satisfies its device type requirements
    def validate : Array(String)
      errors = [] of String

      @device_types.each do |device_type|
        # Check all required clusters are present
        device_type.required_server_clusters.each do |cluster_id|
          unless has_cluster?(cluster_id)
            errors << "Missing required cluster #{Hex.u16(cluster_id)} for device type #{device_type.name}"
          end
        end

        # Check that no unexpected clusters are present (optional validation)
        @clusters.each_key do |cluster_id|
          # Descriptor (0x001D) is always allowed
          next if cluster_id == 0x001D_u32

          unless device_type.allows_cluster?(cluster_id)
            # This is a warning rather than an error in Matter spec
            # but we track it for completeness
          end
        end
      end

      errors
    end

    # Check if this endpoint is valid (has all required clusters)
    def valid? : Bool
      validate.empty?
    end

    # Get a human-readable description of this endpoint
    def description : String
      device_type_names = @device_types.map(&.name).join(", ")
      "Endpoint #{@endpoint_id.number}: #{device_type_names} (#{@clusters.size} clusters)"
    end

    # Get the number of clusters
    def cluster_count : Int32
      @clusters.size
    end

    # Read an attribute from a cluster on this endpoint
    def read_attribute(cluster_id : UInt32, attribute_id : UInt32) : InteractionModel::Status | TLV::Any
      cluster = get_cluster(cluster_id)
      return InteractionModel::Status.failure unless cluster

      cluster.read_attribute(attribute_id)
    end

    # Write an attribute to a cluster on this endpoint
    def write_attribute(cluster_id : UInt32, attribute_id : UInt32, value : TLV::Any) : InteractionModel::Status
      cluster = get_cluster(cluster_id)
      return InteractionModel::Status.failure unless cluster

      cluster.write_attribute(attribute_id, value)
    end

    # Invoke a command on a cluster on this endpoint
    def invoke_command(cluster_id : UInt32, command_id : UInt32, fields : TLV::Any? = nil) : InteractionModel::Status | Cluster::CommandResponse
      cluster = get_cluster(cluster_id)
      return InteractionModel::Status.failure unless cluster

      cluster.invoke_command(command_id, fields)
    end

    # Get a typed cluster by class
    # Usage: endpoint.get_cluster(OnOff)
    def get_cluster(cluster_type : T.class) : T? forall T
      found_cluster = @clusters.values.find { |clust| clust.is_a?(T) }
      found_cluster.as(T) if found_cluster
    end

    # Get a typed cluster by class (raises if not found)
    def get_cluster!(cluster_type : T.class) : T forall T
      get_cluster(cluster_type) || raise KeyError.new("Cluster #{cluster_type} not found on endpoint #{@endpoint_id.number}")
    end
  end

  # MatterNode represents a complete Matter device with multiple endpoints
  class MatterNode
    getter endpoints : Hash(UInt16, Endpoint)

    def initialize
      @endpoints = {} of UInt16 => Endpoint
    end

    # Add an endpoint to this node
    def add_endpoint(endpoint : Endpoint)
      @endpoints[endpoint.endpoint_id.number] = endpoint
    end

    # Get an endpoint by ID
    def get_endpoint(endpoint_id : UInt16) : Endpoint?
      @endpoints[endpoint_id]?
    end

    # Get an endpoint by ID (raises if not found)
    def get_endpoint!(endpoint_id : UInt16) : Endpoint
      @endpoints[endpoint_id]? || raise KeyError.new("Endpoint #{endpoint_id} not found")
    end

    # Check if node has an endpoint
    def has_endpoint?(endpoint_id : UInt16) : Bool
      @endpoints.has_key?(endpoint_id)
    end

    # Get all endpoint IDs
    def endpoint_ids : Array(UInt16)
      @endpoints.keys
    end

    # Validate all endpoints
    def validate : Hash(UInt16, Array(String))
      errors = {} of UInt16 => Array(String)

      @endpoints.each do |endpoint_id, endpoint|
        endpoint_errors = endpoint.validate
        errors[endpoint_id] = endpoint_errors unless endpoint_errors.empty?
      end

      errors
    end

    # Check if all endpoints are valid
    def valid? : Bool
      validate.empty?
    end

    # Get the number of endpoints
    def endpoint_count : Int32
      @endpoints.size
    end

    # Read an attribute from a cluster on an endpoint
    def read_attribute(endpoint_id : UInt16, cluster_id : UInt32, attribute_id : UInt32) : InteractionModel::Status | TLV::Any
      endpoint = get_endpoint(endpoint_id)
      return InteractionModel::Status.unsupported_endpoint unless endpoint

      endpoint.read_attribute(cluster_id, attribute_id)
    end

    # Write an attribute to a cluster on an endpoint
    def write_attribute(endpoint_id : UInt16, cluster_id : UInt32, attribute_id : UInt32, value : TLV::Any) : InteractionModel::Status
      endpoint = get_endpoint(endpoint_id)
      return InteractionModel::Status.unsupported_endpoint unless endpoint

      endpoint.write_attribute(cluster_id, attribute_id, value)
    end

    # Invoke a command on a cluster on an endpoint
    def invoke_command(endpoint_id : UInt16, cluster_id : UInt32, command_id : UInt32, fields : TLV::Any? = nil) : InteractionModel::Status | Cluster::CommandResponse
      endpoint = get_endpoint(endpoint_id)
      return InteractionModel::Status.unsupported_endpoint unless endpoint

      endpoint.invoke_command(cluster_id, command_id, fields)
    end

    # Get a typed cluster from an endpoint
    # Usage: node.get_cluster(1_u16, OnOff)
    def get_cluster(endpoint_id : UInt16, cluster_type : T.class) : T? forall T
      endpoint = get_endpoint(endpoint_id)
      return unless endpoint

      endpoint.get_cluster(cluster_type)
    end

    # Get a typed cluster from an endpoint (raises if not found)
    def get_cluster!(endpoint_id : UInt16, cluster_type : T.class) : T forall T
      get_cluster(endpoint_id, cluster_type) || raise KeyError.new("Cluster #{cluster_type} not found on endpoint #{endpoint_id}")
    end

    # Get a human-readable description of this matter node
    def description : String
      lines = ["MatterNode with #{endpoint_count} endpoint(s):"]
      @endpoints.values.each do |endpoint|
        lines << "  #{endpoint.description}"
      end
      lines.join("\n")
    end
  end
end
