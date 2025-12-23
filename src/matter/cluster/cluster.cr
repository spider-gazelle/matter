require "tlv"
require "json"
require "../interaction_model/status_code"
require "../interaction_model/paths"
require "../datatype/*"
require "./definitions/access_control"

module Matter
  module Cluster
    # Attribute metadata
    struct AttributeMetadata
      property id : DataType::AttributeId
      property name : String
      property type : Symbol # :bool, :uint8, :uint16, :uint32, :int8, :string, :array, etc.
      property writable : Bool
      property optional : Bool
      property fixed : Bool
      property default : Bytes?
      property min : Int64?
      property max : Int64?
      property access : Definitions::AccessControl::EntryPrivilege

      def initialize(
        @id : DataType::AttributeId,
        @name : String,
        @type : Symbol,
        @writable : Bool = false,
        @optional : Bool = false,
        @fixed : Bool = false,
        @default : Bytes? = nil,
        @min : Int64? = nil,
        @max : Int64? = nil,
        @access : Definitions::AccessControl::EntryPrivilege = Definitions::AccessControl::EntryPrivilege::View,
      )
      end
    end

    # Command metadata
    struct CommandMetadata
      property id : DataType::CommandId
      property name : String
      property optional : Bool
      property access : Definitions::AccessControl::EntryPrivilege

      def initialize(
        @id : DataType::CommandId,
        @name : String,
        @optional : Bool = false,
        @access : Definitions::AccessControl::EntryPrivilege = Definitions::AccessControl::EntryPrivilege::Operate,
      )
      end
    end

    # Command response - returned by invoke_command
    struct CommandResponse
      property command_id : UInt32
      property data : Bytes

      def initialize(@command_id : UInt32, @data : Bytes)
      end
    end

    # Event metadata
    struct EventMetadata
      property id : DataType::EventId
      property name : String
      property priority : InteractionModel::EventPriority

      def initialize(
        @id : DataType::EventId,
        @name : String,
        @priority : InteractionModel::EventPriority = InteractionModel::EventPriority::Info,
      )
      end
    end

    # Base class for all cluster implementations
    abstract class Base
      property endpoint_id : DataType::EndpointNumber
      property cluster_id : DataType::ClusterId
      property data_version : UInt32

      # Request context (populated by the protocol layer for the current operation).
      # These are intentionally prefixed to avoid colliding with cluster-specific state.
      property request_session_id : UInt64? = nil
      property request_peer_node_id : UInt64? = nil
      property request_is_case_session : Bool = false
      property request_fabric_index : UInt8? = nil

      # Callback for attribute change notifications (used by subscription system)
      # Parameters: endpoint_id, cluster_id, attribute_id
      property on_attribute_changed : Proc(UInt16, UInt32, UInt32, Nil)?

      # Macro to add class method for accessing CLUSTER_ID constant
      macro inherited
        def self.cluster_id
          CLUSTER_ID
        end
      end

      def initialize(@endpoint_id : DataType::EndpointNumber, @cluster_id : DataType::ClusterId)
        @data_version = 0_u32
        @attribute_values = {} of UInt32 => Bytes
      end

      # Get cluster name
      abstract def name : String

      # Get all attribute metadata
      abstract def attributes : Array(AttributeMetadata)

      # Get all command metadata
      def commands : Array(CommandMetadata)
        [] of CommandMetadata
      end

      # Get all event metadata
      def events : Array(EventMetadata)
        [] of EventMetadata
      end

      # Global attribute IDs (mandatory on all clusters)
      GLOBAL_ATTRIBUTE_LIST         = 0xFFFB_u32
      GLOBAL_ACCEPTED_COMMAND_LIST  = 0xFFF9_u32
      GLOBAL_GENERATED_COMMAND_LIST = 0xFFF8_u32
      GLOBAL_FEATURE_MAP            = 0xFFFC_u32
      GLOBAL_CLUSTER_REVISION       = 0xFFFD_u32

      # Read an attribute value
      # The fabric_index parameter is optional and used for fabric-scoped attributes
      # like CurrentFabricIndex in OperationalCredentialsCluster
      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        # Handle global attributes that all clusters must support
        # These MUST be handled before checking cluster-specific attributes
        case attribute_id
        when GLOBAL_ATTRIBUTE_LIST
          return encode_attribute_list_global
        when GLOBAL_ACCEPTED_COMMAND_LIST
          return encode_accepted_command_list_global
        when GLOBAL_GENERATED_COMMAND_LIST
          return encode_generated_command_list_global
        when GLOBAL_FEATURE_MAP
          return encode_feature_map_global
        when GLOBAL_CLUSTER_REVISION
          return encode_cluster_revision_global
        end

        metadata = attributes.find { |a| a.id.id == attribute_id }
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless metadata

        # Return stored value or default
        @attribute_values.fetch(attribute_id) do
          metadata.default || InteractionModel::Status.new(InteractionModel::StatusCode::Failure)
        end
      end

      # Encode FeatureMap - override in subclass if cluster has features
      protected def encode_feature_map_global : Bytes
        0_u32.to_tlv # Default: no features
      end

      # Encode ClusterRevision - override in subclass for specific revision
      protected def encode_cluster_revision_global : Bytes
        1_u16.to_tlv # Default: revision 1
      end

      # Encode AttributeList - override in subclass for custom handling
      protected def encode_attribute_list_global : Bytes
        # Collect all attribute IDs (cluster-specific + global)
        attr_ids = attributes.map(&.id.id)
        attr_ids << GLOBAL_GENERATED_COMMAND_LIST
        attr_ids << GLOBAL_ACCEPTED_COMMAND_LIST
        attr_ids << GLOBAL_ATTRIBUTE_LIST
        attr_ids << GLOBAL_FEATURE_MAP
        attr_ids << GLOBAL_CLUSTER_REVISION
        attr_ids.to_tlv
      end

      # Encode AcceptedCommandList - override in subclass for custom handling
      protected def encode_accepted_command_list_global : Bytes
        commands.map(&.id.id).to_tlv
      end

      # Encode GeneratedCommandList - override in subclass to add generated commands
      protected def encode_generated_command_list_global : Bytes
        # Default: empty array (no generated commands)
        ([] of UInt32).to_tlv
      end

      # Write an attribute value
      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        metadata = attributes.find { |a| a.id.id == attribute_id }
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAttribute) unless metadata
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedWrite) unless metadata.writable

        # Validate value (simplified - real implementation would decode and validate)
        @attribute_values[attribute_id] = value
        @data_version += 1

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      end

      # Invoke a command
      def invoke_command(command_id : UInt32, fields : Bytes = Bytes.new(0), session_id : UInt64? = nil, is_case_session : Bool = false, fabric_index : UInt8? = nil) : InteractionModel::Status | CommandResponse
        metadata = commands.find { |c| c.id.id == command_id }
        return InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand) unless metadata

        # Store session_id for clusters that need it (like OperationalCredentials)
        if responds_to?(:session_id=)
          self.session_id = session_id
        end

        # Store is_case_session for clusters that need it (like GeneralCommissioning)
        if responds_to?(:is_case_session=)
          self.is_case_session = is_case_session
        end

        # Store fabric_index for clusters that need it (like GeneralCommissioning)
        if responds_to?(:fabric_index=)
          self.fabric_index = fabric_index
        end

        # Command implementations override this
        handle_command(command_id, fields)
      end

      # Handle command implementation (to be overridden)
      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | CommandResponse
        InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCommand)
      end

      # Increment data version (call when attribute changes)
      protected def increment_version
        @data_version += 1
      end

      # Notify that a specific attribute has changed (triggers subscription updates)
      # This should be called after changing an attribute value
      protected def notify_changed(attribute_id : UInt32)
        if callback = @on_attribute_changed
          callback.call(@endpoint_id.number, @cluster_id.id, attribute_id)
        end
      end

      # Increment version AND notify about a specific attribute change
      # This is the preferred method when an attribute value changes
      protected def increment_version_and_notify(attribute_id : UInt32)
        increment_version
        notify_changed(attribute_id)
      end

      # Get attribute metadata by ID
      def get_attribute_metadata(attribute_id : UInt32) : AttributeMetadata?
        attributes.find { |a| a.id.id == attribute_id }
      end

      # Get command metadata by ID
      def get_command_metadata(command_id : UInt32) : CommandMetadata?
        commands.find { |c| c.id.id == command_id }
      end

      # Returns a unique key for this cluster instance for persistence
      # Format: "endpoint_<id>_cluster_<id>"
      def persistence_key : String
        "endpoint_#{@endpoint_id.number}_cluster_#{@cluster_id.id}"
      end

      # Save cluster state to JSON for persistence.
      # Override in subclasses that need to persist state (e.g., scenes, groups).
      # Returns nil if no state needs to be persisted.
      def save_state : String?
        nil
      end

      # Restore cluster state from JSON.
      # Override in subclasses that need to restore state.
      # The json parameter is the string returned by save_state.
      def restore_state(json : String) : Nil
        # Default: no-op
      end

      # ------------------------------------------------------------------------
      # Scenes Management hooks
      # ------------------------------------------------------------------------
      #
      # ScenesManagementCluster (0x0062) stores "extension field sets" that capture
      # cluster-specific state for scene recall. Clusters can override these hooks
      # to participate; default implementations are no-ops.
      #
      # The Device base class wires ScenesManagementCluster callbacks by calling
      # these methods on clusters present on the same endpoint.
      def store_scene_extension_field_set : ScenesManagementCluster::ExtensionFieldSet?
        nil
      end

      def apply_scene_extension_field_set(field_set : ScenesManagementCluster::ExtensionFieldSet) : Bool
        false
      end
    end
  end
end
