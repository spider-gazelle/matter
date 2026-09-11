require "../fabric_table"
require "../node"
require "../transport/udp_transport"
require "../protocol/message_handler"
require "./persistence"
require "./lifecycle_manager"

require "../mdns/responder"
require "../mdns/service_type"
require "../datatype/endpoint_number"

require "../cluster/descriptor"
require "../cluster/basic_information"
require "../cluster/access_control"
require "../cluster/general_commissioning"
require "../cluster/operational_credentials"
require "../cluster/administrator_commissioning"
require "../cluster/general_diagnostics"
require "../cluster/network_commissioning"
require "../cluster/group_key_management"
require "../cluster/ota_requestor"
require "../cluster/diagnostic_logs"
require "../cluster/ethernet_network_diagnostics"

module Matter
  module Device
    # Base class for Matter device applications.
    #
    # Provides:
    # - Persistence (fabrics, sessions, cluster state, identity) on a `Storage::Backend`
    # - UDP transport + Protocol MessageHandler
    # - Default Root Node clusters (including OperationalCredentials)
    # - Descriptor injection and auto-population
    # - mDNS responder + lifecycle management (commissioning <-> operational)
    #
    # Subclasses typically implement:
    # - `device_clusters` (endpoint-specific clusters)
    # - device identity getters (name/vendor/product/pin/discriminator)
    # - optional hooks like `started_commissioning_mode`
    abstract class Base
      Log = ::Log.for("matter.device.base")

      getter hostname : String
      getter ip_addresses : Array(Socket::IPAddress)

      # Default Matter operational UDP port.
      DEFAULT_PORT = 5540

      getter persistence : Persistence
      getter fabric_table : FabricTable

      # The device's data model: its endpoints and their clusters.
      getter node : Node

      getter transport : Transport::UDPTransport
      getter message_handler : Protocol::MessageHandler
      getter responder : MDNS::Responder
      getter lifecycle : LifecycleManager

      @shutdown_channel : Channel(Nil) = Channel(Nil).new
      @basic_info : Cluster::BasicInformation? = nil
      @general_commissioning : Cluster::GeneralCommissioning? = nil
      @access_control : Cluster::AccessControl? = nil
      @operational_credentials : Cluster::OperationalCredentials? = nil
      @administrator_commissioning : Cluster::AdministratorCommissioning? = nil

      def basic_info : Cluster::BasicInformation
        @basic_info.as(Cluster::BasicInformation)
      end

      def general_commissioning : Cluster::GeneralCommissioning
        @general_commissioning.as(Cluster::GeneralCommissioning)
      end

      def access_control : Cluster::AccessControl
        @access_control.as(Cluster::AccessControl)
      end

      def operational_credentials : Cluster::OperationalCredentials
        @operational_credentials.as(Cluster::OperationalCredentials)
      end

      def administrator_commissioning : Cluster::AdministratorCommissioning
        @administrator_commissioning.as(Cluster::AdministratorCommissioning)
      end

      def port : Int32
        @transport.port
      end

      def initialize(
        storage : Storage::Backend,
        ip_addresses : Array(Socket::IPAddress)? = nil,
        port : Int32 = DEFAULT_PORT,
        hostname : String? = nil,
        max_fabrics : UInt8 = FabricTable::DEFAULT_MAX_FABRICS,
      )
        @ip_addresses = ip_addresses || default_ip_addresses

        @persistence = Persistence.new(storage, max_fabrics: max_fabrics)
        @fabric_table = @persistence.fabric_table
        @hostname = hostname || @persistence.commissioning_hostname

        @transport = Transport::UDPTransport.new(port: port)
        @message_handler = Protocol::MessageHandler.new(
          transport: @transport,
          setup_pin: setup_pin,
          discriminator: discriminator,
          fabric_table: @fabric_table,
          vendor_id: vendor_id,
          product_id: product_id,
          persistence: @persistence.protocol_persistence
        )

        @responder = MDNS::Responder.new(hostname: @hostname, ip_addresses: @ip_addresses)

        # One place where every cluster, however late it joins the node, gets
        # its state written on change.
        @node = @message_handler.node
        @node.on_version_changed = ->(cluster : Cluster::Base) { @persistence.mark_dirty(cluster) }

        build_and_wire_clusters
        @message_handler.setup_cluster_notifications

        # Restore cluster state (scenes, groups, etc.) and track changes
        @persistence.restore_clusters(@message_handler.clusters.values)

        @lifecycle = LifecycleManager.new(
          fabric_table: @fabric_table,
          registry: @message_handler.registry,
          operational_credentials: operational_credentials,
          responder: @responder,
          port: @transport.port,
          commissioning_info: -> { commissioning_info },
          operational_info_factory: ->(fabric : Fabric) { operational_info_for(fabric) }
        )

        @lifecycle.on_fabric_added = ->(fabric : Fabric) { fabric_added(fabric) }
        @lifecycle.on_fabric_removed = ->(fabric_index : UInt8) { fabric_removed(fabric_index) }
        @lifecycle.on_commissioned = ->(fabric : Fabric) do
          started_operational_mode
          commissioned(fabric)
        end
        @lifecycle.on_decommissioned = -> do
          started_commissioning_mode
          decommissioned
        end
      end

      # Starts mDNS and UDP transport and syncs advertisements for the current fabric set.
      # Returns immediately after starting - use `await_shutdown` to block until shutdown.
      def start : Nil
        before_start
        @lifecycle.sync_advertisements
        @fabric_table.empty? ? started_commissioning_mode : started_operational_mode
        @responder.start
        @transport.start
        on_started
      rescue error
        Log.error(exception: error) { "error during startup" }
        shutdown!
      end

      # Blocks until `shutdown!` is called. Optional - use when you need the main
      # fiber to wait for shutdown (e.g., in a daemon or CLI application).
      # Multiple fibers can safely wait on this.
      def await_shutdown : Nil
        @shutdown_channel.receive?
      end

      # Signals shutdown, stops all services, and unblocks all `await_shutdown` waiters.
      # Safe to call from signal handlers or other fibers.
      def shutdown! : Nil
        # Persist all session state before shutdown to ensure message counters
        # and other session data are saved for clean reconnection after restart
        @message_handler.persist_all_sessions

        @persistence.flush
        @persistence.close
        @transport.close
        @responder.stop
        on_shutdown
      rescue error
        Log.error(exception: error) { "error performing shutdown" }
      ensure
        @shutdown_channel.close
      end

      # ------------------------------------------------------------------------
      # Required device identity
      # ------------------------------------------------------------------------
      abstract def device_name : String
      abstract def vendor_id : UInt16
      abstract def product_id : UInt16
      abstract def discriminator : UInt16
      abstract def setup_pin : UInt32
      abstract def primary_device_type_id : UInt32

      # ------------------------------------------------------------------------
      # Optional identity / BasicInformation fields
      # ------------------------------------------------------------------------
      def vendor_name : String
        "Crystal Matter"
      end

      def product_name : String
        device_name
      end

      def hardware_version : UInt16
        1_u16
      end

      def hardware_version_string : String
        "1.0"
      end

      def software_version : UInt32
        1_u32
      end

      def software_version_string : String
        "1.0.0"
      end

      def serial_number : String?
        nil
      end

      def unique_id : String?
        nil
      end

      def product_appearance : Cluster::BasicInformation::ProductAppearanceStruct?
        nil
      end

      # ------------------------------------------------------------------------
      # Device clusters / endpoints
      # ------------------------------------------------------------------------
      # Return the device-specific clusters (typically for endpoint(s) > 0).
      protected abstract def device_clusters : Array(Cluster::Base)

      # Map endpoint -> device type ID for Descriptor population.
      protected def endpoint_device_types : Hash(UInt16, UInt32)
        {1_u16 => primary_device_type_id} of UInt16 => UInt32
      end

      # ------------------------------------------------------------------------
      # Networking / diagnostics defaults
      # ------------------------------------------------------------------------
      protected def commissioning_network_type : Cluster::NetworkCommissioning::NetworkType
        Cluster::NetworkCommissioning::NetworkType::Ethernet
      end

      protected def commissioning_network_feature_map : Cluster::NetworkCommissioning::Feature
        Cluster::NetworkCommissioning::Feature::EthernetNetworkInterface
      end

      protected def include_ethernet_diagnostics? : Bool
        commissioning_network_type.ethernet?
      end

      # ------------------------------------------------------------------------
      # Hooks (override as needed)
      # ------------------------------------------------------------------------
      protected def before_start : Nil
      end

      # Called after the device is fully started. Use this to spawn background
      # fibers (e.g., interactive CLI loop). Non-blocking - returns immediately.
      protected def on_started : Nil
      end

      # Called after `stop` completes during `shutdown!`. Use for final cleanup.
      protected def on_shutdown : Nil
      end

      protected def started_commissioning_mode : Nil
      end

      protected def started_operational_mode : Nil
      end

      protected def fabric_added(fabric : Fabric) : Nil
      end

      protected def fabric_removed(fabric_index : UInt8) : Nil
      end

      protected def commissioned(fabric : Fabric) : Nil
      end

      protected def decommissioned : Nil
      end

      # ------------------------------------------------------------------------
      # mDNS info factories (override for ICD, TCP, etc)
      # ------------------------------------------------------------------------
      protected def commissioning_info_for(mode : MDNS::CommissioningMode) : MDNS::CommissioningInfo
        MDNS::CommissioningInfo.new(
          device_name: device_name,
          vendor_id: vendor_id,
          product_id: product_id,
          discriminator: discriminator,
          device_type: primary_device_type_id,
          commissioning_mode: mode
        )
      end

      protected def commissioning_info : MDNS::CommissioningInfo
        commissioning_info_for(MDNS::CommissioningMode::Basic)
      end

      protected def operational_info_for(fabric : Fabric) : MDNS::OperationalInfo
        MDNS::OperationalInfo.new(
          compressed_fabric_id: fabric.compressed_fabric_id,
          node_id: fabric.node_id,
          tcp_supported: false
        )
      end

      # ------------------------------------------------------------------------
      # Internal wiring
      # ------------------------------------------------------------------------
      private def build_and_wire_clusters : Nil
        endpoint_0 = DataType::EndpointNumber.new(0_u16)

        # Root Node clusters
        basic_info = Cluster::BasicInformation.new(
          endpoint_0,
          data_model_revision: 1_u16,
          vendor_name: vendor_name,
          vendor_id: vendor_id,
          product_name: product_name,
          product_id: product_id,
          hardware_version: hardware_version,
          hardware_version_string: hardware_version_string,
          software_version: software_version,
          software_version_string: software_version_string,
          serial_number: serial_number || @persistence.serial_number,
          unique_id: unique_id || @persistence.unique_id,
          product_appearance: product_appearance
        )
        @basic_info = basic_info

        general_commissioning = Cluster::GeneralCommissioning.new(endpoint_0)
        access_control = Cluster::AccessControl.new(endpoint_0)
        @general_commissioning = general_commissioning
        @access_control = access_control
        operational_credentials = Cluster::OperationalCredentials.new(
          @fabric_table,
          endpoint_0,
          access_control_cluster: access_control,
          general_commissioning_cluster: general_commissioning
        )
        @operational_credentials = operational_credentials
        configure_attestation(operational_credentials)

        # Ensure OperationalCredentials resets its internal per-failsafe state when a
        # new failsafe context is armed (required for follow-up CSR/UpdateNOC flows).
        general_commissioning.on_failsafe_armed = -> { operational_credentials.on_failsafe_armed }

        # Ensure attestation signatures can access the PASE session's attestation_challenge.
        sessions = @message_handler.sessions
        operational_credentials.session_lookup = ->(session_id : UInt64) : Bytes? do
          sessions[session_id.to_u16]?.try(&.attestation_challenge)
        end

        administrator_commissioning = Cluster::AdministratorCommissioning.new(endpoint_0)
        @administrator_commissioning = administrator_commissioning

        general_diagnostics = Cluster::GeneralDiagnostics.new(endpoint_0)
        icd_management = Cluster::IcdManagement.new(endpoint_0)
        network_commissioning = Cluster::NetworkCommissioning.new(
          endpoint_0,
          network_type: commissioning_network_type,
          feature_map: commissioning_network_feature_map
        )
        group_key_management = Cluster::GroupKeyManagement.new(endpoint_0)
        ota_requestor = Cluster::OtaRequestor.new(endpoint_0)
        diagnostic_logs = Cluster::DiagnosticLogs.new(endpoint_0)
        ethernet_diagnostics = include_ethernet_diagnostics? ? Cluster::EthernetNetworkDiagnostics.new(endpoint_0) : nil

        # Wire commissioning-window mDNS advertisement via the Responder.
        # This enables multi-admin flows (chip-tool/iOS) that require _matterc advertising
        # while the commissioning window is open, even when already operational.
        # A basic window (nil discriminator) advertises the device's own discriminator.
        administrator_commissioning.on_start_commissioning_advertising = ->(disc : UInt16?, mode : MDNS::CommissioningMode) do
          @responder.stop_commissioning
          info = commissioning_info_for(mode)
          info.discriminator = disc if disc
          @responder.advertise_commissioning(info, port: port)
        end
        administrator_commissioning.on_stop_commissioning_advertising = -> do
          @responder.stop_commissioning
        end

        # Wire commissioning-window PASE configuration into the protocol layer.
        # Enhanced windows provide a pre-computed SPAKE2+ verifier (w0||L).
        administrator_commissioning.on_configure_pase_server = ->(verifier : Bytes, iterations : UInt32, salt : Bytes) do
          @message_handler.configure_pase_server(verifier, iterations, salt)
        end
        administrator_commissioning.on_configure_pase_pin = ->(_pin : UInt32, iterations : UInt32, salt : Bytes) do
          # OpenBasicCommissioningWindow uses the device's default passcode; ignore any
          # test pin passed by the cluster implementation.
          @message_handler.configure_pase_pin(setup_pin, iterations, salt)
        end
        administrator_commissioning.on_stop_pase_server = -> do
          @message_handler.reset_pase_server
        end

        # The subclass's clusters, split by the endpoint each was built for.
        declared_types = endpoint_device_types
        device_endpoints = device_clusters.group_by(&.endpoint_id.number)

        # Root endpoint: replaces the MessageHandler defaults wholesale.
        root = Endpoint.new(endpoint_0, device_types_for(Node::ROOT_ENDPOINT_ID, declared_types))
        [
          basic_info,
          general_commissioning,
          access_control,
          operational_credentials,
          administrator_commissioning,
          general_diagnostics,
          icd_management,
          network_commissioning,
          group_key_management,
          ota_requestor,
          diagnostic_logs,
        ].each { |cluster| root.add_cluster(cluster) }
        root.add_cluster(ethernet_diagnostics.as(Cluster::EthernetNetworkDiagnostics)) if ethernet_diagnostics
        device_endpoints.delete(Node::ROOT_ENDPOINT_ID).try(&.each { |cluster| root.add_cluster(cluster) })
        @node.add_endpoint(root)

        device_endpoints.each do |endpoint_id, clusters|
          endpoint = Endpoint.new(
            DataType::EndpointNumber.new(endpoint_id),
            device_types_for(endpoint_id, declared_types)
          )
          clusters.each { |cluster| endpoint.add_cluster(cluster) }
          @node.add_endpoint(endpoint)
        end

        refresh_root_parts_list
      end

      # The device types of *endpoint_id*: every endpoint 0 is a Root Node, on
      # top of whatever the subclass declared for it.
      private def device_types_for(endpoint_id : UInt16, declared_types : Hash(UInt16, UInt32)) : Array(DeviceType)
        device_types = [] of DeviceType
        device_types << DeviceType.root_node if endpoint_id == Node::ROOT_ENDPOINT_ID
        if declared = declared_types[endpoint_id]?
          device_types << DeviceType.for(declared)
        end
        device_types
      end

      # The root endpoint's PartsList is the list of every other endpoint.
      private def refresh_root_parts_list : Nil
        descriptor = root_descriptor
        descriptor.parts_list.clear
        @node.endpoint_ids.each do |endpoint_id|
          next if endpoint_id == Node::ROOT_ENDPOINT_ID
          descriptor.add_part(endpoint_id)
        end
      end

      private def root_descriptor : Cluster::Descriptor
        @node.endpoint!(Node::ROOT_ENDPOINT_ID).descriptor
      end

      private def notify_root_parts_list : Nil
        @message_handler.notify_subscriptions(
          Node::ROOT_ENDPOINT_ID,
          Cluster::Descriptor::CLUSTER_ID,
          Cluster::Descriptor::ATTR_PARTS_LIST
        )
      end

      # Default to ephemeral test credentials unless the device overrides.
      protected def configure_attestation(operational_credentials : Cluster::OperationalCredentials) : Nil
        operational_credentials.set_attestation_from_manager(vendor_id: vendor_id, product_id: product_id)
      end

      protected def default_ip_addresses : Array(Socket::IPAddress)
        ips = [] of Socket::IPAddress

        # Prefer localhost as a safe default
        ips << Socket::IPAddress.new("127.0.0.1", 0)
        ips
      end

      # Updates the default commissioning target hostname used for mDNS advertisements.
      # This is useful for platforms that rotate link-layer identifiers or for hosting
      # multiple virtual devices in one executable.
      def update_hostname(hostname : String) : Nil
        normalized = hostname.strip
        raise ArgumentError.new("hostname must be non-empty") if normalized.empty?

        @hostname = normalized
        @persistence.update_hostname(normalized)
        @responder.update_commissioning_hostname(normalized)
      end

      # ------------------------------------------------------------------------
      # Dynamic Endpoint Management (for bridges)
      # ------------------------------------------------------------------------

      # Adds a new endpoint with the given clusters at runtime.
      # This is primarily used by bridge devices to add bridged endpoints dynamically.
      #
      # The clusters should already be configured with the correct endpoint_id.
      # A Descriptor is injected and populated by the node, and the endpoint is
      # held to its device type: a missing mandatory cluster raises
      # `ConfigurationError`.
      #
      # *device_type_revision* defaults to the revision of the device type
      # definition. Set `notify_subscribers` to false when restoring endpoints
      # from storage to avoid sending spurious subscription updates on startup.
      #
      # Returns true if the endpoint was added successfully, false if it already exists.
      def add_endpoint(
        endpoint_id : UInt16,
        device_type : UInt32,
        clusters : Array(Cluster::Base),
        device_type_revision : UInt16? = nil,
        notify_subscribers : Bool = true,
      ) : Bool
        # Don't allow adding endpoint 0 (root node)
        return false if endpoint_id == Node::ROOT_ENDPOINT_ID
        return false if @node.has_endpoint?(endpoint_id)

        endpoint = Endpoint.new(
          DataType::EndpointNumber.new(endpoint_id),
          dynamic_device_type(device_type, device_type_revision)
        )
        clusters.each { |cluster| endpoint.add_cluster(cluster) }
        @node.add_endpoint(endpoint)

        # Tell controllers a new endpoint exists - they read its attributes on
        # their own (same pattern as remove_endpoint).
        descriptor = root_descriptor
        return true if descriptor.has_part?(endpoint_id)

        descriptor.add_part(endpoint_id)
        notify_root_parts_list if notify_subscribers
        true
      end

      # Removes an endpoint, its clusters and their persisted state at runtime.
      # This is primarily used by bridge devices to remove bridged endpoints dynamically.
      #
      # Returns true if the endpoint was removed, false if it didn't exist.
      def remove_endpoint(endpoint_id : UInt16, notify_subscribers : Bool = true) : Bool
        # Don't allow removing endpoint 0 (root node)
        return false if endpoint_id == Node::ROOT_ENDPOINT_ID

        endpoint = @node.remove_endpoint(endpoint_id)
        return false unless endpoint

        endpoint.clusters.each_value { |cluster| @persistence.forget_cluster(cluster) }

        descriptor = root_descriptor
        return true unless descriptor.has_part?(endpoint_id)

        descriptor.parts_list.reject! { |part| part == endpoint_id }
        notify_root_parts_list if notify_subscribers
        true
      end

      # Returns all endpoint IDs currently registered (excluding endpoint 0)
      def endpoint_ids : Array(UInt16)
        @node.endpoint_ids.reject { |endpoint_id| endpoint_id == Node::ROOT_ENDPOINT_ID }
      end

      # Returns the next available endpoint ID for dynamic endpoints
      # Starts from 1 and finds the first unused ID
      def next_endpoint_id : UInt16
        @node.next_endpoint_id
      end

      # The definition for *device_type*, at *revision* when the caller pinned one.
      private def dynamic_device_type(device_type : UInt32, revision : UInt16?) : DeviceType
        definition = DeviceType.for(device_type)
        return definition unless revision

        DeviceType.new(
          definition.device_type_id,
          definition.name,
          revision,
          definition.required_server_clusters,
          definition.optional_server_clusters
        )
      end
    end
  end
end
