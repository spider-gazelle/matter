require "../fabric_table"
require "../transport/udp_transport"
require "../protocol/message_handler"
require "../storage/manager"
require "./lifecycle_manager"

require "../mdns/responder"
require "../mdns/service_type"
require "../datatype/endpoint_number"

require "../cluster/descriptor_cluster"
require "../cluster/basic_information_cluster"
require "../cluster/access_control_cluster"
require "../cluster/general_commissioning_cluster"
require "../cluster/operational_credentials_cluster"
require "../cluster/administrator_commissioning_cluster"
require "../cluster/general_diagnostics_cluster"
require "../cluster/network_commissioning_cluster"
require "../cluster/group_key_management_cluster"
require "../cluster/ota_requestor_cluster"
require "../cluster/diagnostic_logs_cluster"
require "../cluster/ethernet_network_diagnostics_cluster"

module Matter
  module Device
    # Base class for Matter device applications.
    #
    # Provides:
    # - Persistent storage + FabricTable
    # - UDP transport + Protocol MessageHandler
    # - Default Root Node clusters (including OperationalCredentials)
    # - DescriptorCluster injection and auto-population
    # - mDNS responder + lifecycle management (commissioning <-> operational)
    #
    # Subclasses typically implement:
    # - `build_storage_manager`
    # - `device_clusters` (endpoint-specific clusters)
    # - device identity getters (name/vendor/product/pin/discriminator)
    # - optional hooks like `started_commissioning_mode`
    abstract class Base
      getter hostname : String
      getter ip_addresses : Array(Socket::IPAddress)

      getter storage_manager : Storage::Manager
      getter fabric_table : FabricTable
      getter transport : Transport::UDPTransport
      getter message_handler : Protocol::MessageHandler
      getter responder : MDNS::Responder
      getter lifecycle : LifecycleManager

      @shutdown_channel : Channel(Nil) = Channel(Nil).new
      @basic_info : Cluster::BasicInformationCluster? = nil
      @general_commissioning : Cluster::GeneralCommissioningCluster? = nil
      @access_control : Cluster::AccessControlCluster? = nil
      @operational_credentials : Cluster::OperationalCredentialsCluster? = nil
      @administrator_commissioning : Cluster::AdministratorCommissioningCluster? = nil

      def basic_info : Cluster::BasicInformationCluster
        @basic_info.as(Cluster::BasicInformationCluster)
      end

      def general_commissioning : Cluster::GeneralCommissioningCluster
        @general_commissioning.as(Cluster::GeneralCommissioningCluster)
      end

      def access_control : Cluster::AccessControlCluster
        @access_control.as(Cluster::AccessControlCluster)
      end

      def operational_credentials : Cluster::OperationalCredentialsCluster
        @operational_credentials.as(Cluster::OperationalCredentialsCluster)
      end

      def administrator_commissioning : Cluster::AdministratorCommissioningCluster
        @administrator_commissioning.as(Cluster::AdministratorCommissioningCluster)
      end

      def port : Int32
        @transport.port
      end

      def initialize(
        ip_addresses : Array(Socket::IPAddress)? = nil,
        port : Int32 = 5540,
        hostname : String? = nil,
      )
        @ip_addresses = ip_addresses || default_ip_addresses

        @storage_manager = build_storage_manager
        @fabric_table = @storage_manager.fabric_table
        @hostname = hostname || load_or_create_commissioning_hostname

        @transport = Transport::UDPTransport.new(port: port)
        @message_handler = Protocol::MessageHandler.new(
          transport: @transport,
          setup_pin: setup_pin,
          discriminator: discriminator,
          fabric_table: @fabric_table,
          vendor_id: vendor_id,
          product_id: product_id,
          persistence: @storage_manager.protocol_persistence
        )

        @responder = MDNS::Responder.new(hostname: @hostname, ip_addresses: @ip_addresses)

        build_and_wire_clusters
        @message_handler.setup_cluster_notifications

        # Restore cluster state (scenes, groups, etc.) from storage
        restore_cluster_states

        @lifecycle = LifecycleManager.new(
          fabric_table: @fabric_table,
          message_handler: @message_handler,
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

        # Save cluster state (scenes, groups, etc.)
        save_cluster_states

        @storage_manager.stop
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

      def product_appearance : Cluster::BasicInformationCluster::ProductAppearanceStruct?
        nil
      end

      # ------------------------------------------------------------------------
      # Storage
      # ------------------------------------------------------------------------
      protected abstract def build_storage_manager : Storage::Manager

      # ------------------------------------------------------------------------
      # Device clusters / endpoints
      # ------------------------------------------------------------------------
      # Return the device-specific clusters (typically for endpoint(s) > 0).
      protected abstract def device_clusters : Array(Cluster::Base)

      # Map endpoint -> device type ID for DescriptorCluster population.
      protected def endpoint_device_types : Hash(UInt16, UInt32)
        {1_u16 => primary_device_type_id} of UInt16 => UInt32
      end

      protected def endpoint_device_type_revision(endpoint_id : UInt16) : UInt16
        1_u16
      end

      # ------------------------------------------------------------------------
      # Networking / diagnostics defaults
      # ------------------------------------------------------------------------
      protected def commissioning_network_type : Cluster::NetworkCommissioningCluster::NetworkType
        Cluster::NetworkCommissioningCluster::NetworkType::Ethernet
      end

      protected def commissioning_network_feature_map : Cluster::NetworkCommissioningCluster::Feature
        Cluster::NetworkCommissioningCluster::Feature::EthernetNetworkInterface
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
        basic_info = Cluster::BasicInformationCluster.new(
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
          serial_number: serial_number || load_or_create_serial_number,
          unique_id: unique_id || load_or_create_unique_id,
          product_appearance: product_appearance
        )
        @basic_info = basic_info

        general_commissioning = Cluster::GeneralCommissioningCluster.new(endpoint_0)
        access_control = Cluster::AccessControlCluster.new(endpoint_0)
        @general_commissioning = general_commissioning
        @access_control = access_control
        operational_credentials = Cluster::OperationalCredentialsCluster.new(
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

        administrator_commissioning = Cluster::AdministratorCommissioningCluster.new(endpoint_0)
        @administrator_commissioning = administrator_commissioning

        general_diagnostics = Cluster::GeneralDiagnosticsCluster.new(endpoint_0)
        icd_management = Cluster::IcdManagementCluster.new(endpoint_0)
        network_commissioning = Cluster::NetworkCommissioningCluster.new(
          endpoint_0,
          network_type: commissioning_network_type,
          feature_map: commissioning_network_feature_map
        )
        group_key_management = Cluster::GroupKeyManagementCluster.new(endpoint_0)
        ota_requestor = Cluster::OtaRequestorCluster.new(endpoint_0)
        diagnostic_logs = Cluster::DiagnosticLogsCluster.new(endpoint_0)
        ethernet_diagnostics = include_ethernet_diagnostics? ? Cluster::EthernetNetworkDiagnosticsCluster.new(endpoint_0) : nil

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

        # Wire root clusters (overwrites MessageHandler defaults)
        @message_handler.clusters[{0_u16, Cluster::BasicInformationCluster::CLUSTER_ID}] = basic_info
        @message_handler.clusters[{0_u16, Cluster::GeneralCommissioningCluster::CLUSTER_ID}] = general_commissioning
        @message_handler.clusters[{0_u16, Cluster::AccessControlCluster::CLUSTER_ID}] = access_control
        @message_handler.clusters[{0_u16, Cluster::OperationalCredentialsCluster::CLUSTER_ID}] = operational_credentials
        @message_handler.clusters[{0_u16, Cluster::AdministratorCommissioningCluster::CLUSTER_ID}] = administrator_commissioning
        @message_handler.clusters[{0_u16, Cluster::GeneralDiagnosticsCluster::CLUSTER_ID}] = general_diagnostics
        @message_handler.clusters[{0_u16, Cluster::IcdManagementCluster::CLUSTER_ID}] = icd_management
        @message_handler.clusters[{0_u16, Cluster::NetworkCommissioningCluster::CLUSTER_ID}] = network_commissioning
        @message_handler.clusters[{0_u16, Cluster::GroupKeyManagementCluster::CLUSTER_ID}] = group_key_management
        @message_handler.clusters[{0_u16, Cluster::OtaRequestorCluster::CLUSTER_ID}] = ota_requestor
        @message_handler.clusters[{0_u16, Cluster::DiagnosticLogsCluster::CLUSTER_ID}] = diagnostic_logs
        if ethernet = ethernet_diagnostics
          @message_handler.clusters[{0_u16, Cluster::EthernetNetworkDiagnosticsCluster::CLUSTER_ID}] = ethernet
        end

        # Wire device clusters (subclass-provided)
        device_clusters.each do |cluster|
          endpoint_id = cluster.endpoint_id.number
          @message_handler.clusters[{endpoint_id, cluster.cluster_id.id}] = cluster
        end

        inject_and_populate_descriptors
        wire_scenes_management_extensions
      end

      private def wire_scenes_management_extensions : Nil
        scenes_clusters = @message_handler.clusters.values.select(Cluster::ScenesManagementCluster)
        return if scenes_clusters.empty?

        scenes_clusters.each do |scenes|
          endpoint_id = scenes.endpoint_id.number
          existing_get = scenes.get_extension_field_sets
          existing_apply = scenes.apply_extension_field_sets

          scenes.get_extension_field_sets = -> do
            sets = [] of Cluster::ScenesManagementCluster::ExtensionFieldSet
            if cb = existing_get
              sets.concat(cb.call)
            end

            sets.concat(
              @message_handler.clusters.values
                .select { |cluster| cluster.endpoint_id.number == endpoint_id }
                .compact_map(&.store_scene_extension_field_set)
            )

            sets
          end

          scenes.apply_extension_field_sets = ->(field_sets : Array(Cluster::ScenesManagementCluster::ExtensionFieldSet)) do
            if cb = existing_apply
              cb.call(field_sets)
            end

            field_sets.each do |field_set|
              if target = @message_handler.clusters[{endpoint_id, field_set.cluster_id}]?
                target.apply_scene_extension_field_set(field_set)
              end
            end
          end
        end
      end

      # Default to ephemeral test credentials unless the device overrides.
      protected def configure_attestation(operational_credentials : Cluster::OperationalCredentialsCluster) : Nil
        operational_credentials.set_attestation_from_manager(vendor_id: vendor_id, product_id: product_id)
      end

      private def inject_and_populate_descriptors : Nil
        endpoints = @message_handler.clusters.keys.map(&.[0]).uniq!.sort!
        endpoints << 0_u16 unless endpoints.includes?(0_u16)

        endpoints.each do |endpoint_id|
          next if @message_handler.clusters.has_key?({endpoint_id, Cluster::DescriptorCluster::CLUSTER_ID})
          descriptor = Cluster::DescriptorCluster.new(DataType::EndpointNumber.new(endpoint_id))
          @message_handler.clusters[{endpoint_id, Cluster::DescriptorCluster::CLUSTER_ID}] = descriptor
        end

        endpoints.each do |endpoint_id|
          descriptor = @message_handler.clusters[{endpoint_id, Cluster::DescriptorCluster::CLUSTER_ID}]
            .as(Cluster::DescriptorCluster)

          # ServerList: all clusters present on endpoint
          cluster_ids = @message_handler.clusters
            .select { |k, _| k[0] == endpoint_id }
            .keys
            .map(&.[1])
            .uniq!
            .sort!

          cluster_ids.each { |id| descriptor.server_list << id unless descriptor.server_list.includes?(id) }

          # DeviceTypeList: Root Node on endpoint 0, otherwise use endpoint_device_types
          descriptor.device_type_list.clear
          if endpoint_id == 0_u16
            descriptor.device_type_list << Cluster::DescriptorCluster::DeviceTypeStruct.new(
              device_type: DeviceType::ROOT_NODE,
              revision: 1_u16
            )
          end

          if device_type = endpoint_device_types[endpoint_id]?
            descriptor.device_type_list << Cluster::DescriptorCluster::DeviceTypeStruct.new(
              device_type: device_type,
              revision: endpoint_device_type_revision(endpoint_id)
            )
          end
        end

        # PartsList: endpoint 0 references all other endpoints
        if root_desc = @message_handler.clusters[{0_u16, Cluster::DescriptorCluster::CLUSTER_ID}]?.as?(Cluster::DescriptorCluster)
          root_desc.parts_list.clear
          endpoints.each do |endpoint_id|
            next if endpoint_id == 0_u16
            root_desc.add_part(endpoint_id)
          end
        end
      end

      protected def default_ip_addresses : Array(Socket::IPAddress)
        ips = [] of Socket::IPAddress

        # Prefer localhost as a safe default
        ips << Socket::IPAddress.new("127.0.0.1", 0)
        ips
      end

      private IDENTITY_CONTEXT  = ["device_identity"] of String
      private HOSTNAME_KEY      = "commissioning_hostname"
      private SERIAL_NUMBER_KEY = "serial_number"
      private UNIQUE_ID_KEY     = "unique_id"
      private HOSTNAME_RE       = /^[0-9A-F]{16}\\.local$/

      private def load_or_create_commissioning_hostname : String
        stored = @storage_manager.storage.get(IDENTITY_CONTEXT, HOSTNAME_KEY)
        if stored.is_a?(String)
          hostname = stored.strip
          return hostname if hostname.matches?(HOSTNAME_RE)
          return hostname if hostname.ends_with?(".local") && !hostname.empty?
        end

        token = Hex.node_id(Random::Secure.rand(UInt64))
        hostname = "#{token}.local"
        @storage_manager.storage.set(IDENTITY_CONTEXT, HOSTNAME_KEY, hostname)
        hostname
      rescue
        "#{Hex.node_id(Random::Secure.rand(UInt64))}.local"
      end

      private def load_or_create_serial_number : String
        stored = @storage_manager.storage.get(IDENTITY_CONTEXT, SERIAL_NUMBER_KEY)
        if stored.is_a?(String) && !stored.empty?
          return stored
        end

        serial = Random::Secure.hex(8).upcase
        @storage_manager.storage.set(IDENTITY_CONTEXT, SERIAL_NUMBER_KEY, serial)
        serial
      rescue
        Random::Secure.hex(8).upcase
      end

      private def load_or_create_unique_id : String
        stored = @storage_manager.storage.get(IDENTITY_CONTEXT, UNIQUE_ID_KEY)
        if stored.is_a?(String) && !stored.empty?
          return stored
        end

        unique_id = Random::Secure.hex(16)
        @storage_manager.storage.set(IDENTITY_CONTEXT, UNIQUE_ID_KEY, unique_id)
        unique_id
      rescue
        Random::Secure.hex(16)
      end

      # Updates the default commissioning target hostname used for mDNS advertisements.
      # This is useful for platforms that rotate link-layer identifiers or for hosting
      # multiple virtual devices in one executable.
      def update_hostname(hostname : String) : Nil
        normalized = hostname.strip
        raise ArgumentError.new("hostname must be non-empty") if normalized.empty?

        @hostname = normalized
        @storage_manager.storage.set(IDENTITY_CONTEXT, HOSTNAME_KEY, normalized)
        @responder.update_commissioning_hostname(normalized)
      end

      # ------------------------------------------------------------------------
      # Dynamic Endpoint Management (for bridges)
      # ------------------------------------------------------------------------

      # Adds a new endpoint with the given clusters at runtime.
      # This is primarily used by bridge devices to add bridged endpoints dynamically.
      #
      # The clusters should already be configured with the correct endpoint_id.
      # A DescriptorCluster will be automatically injected if not provided.
      #
      # Set `notify_subscribers` to false when restoring endpoints from storage
      # to avoid sending spurious subscription updates on startup.
      #
      # Returns true if the endpoint was added successfully, false if it already exists.
      def add_endpoint(
        endpoint_id : UInt16,
        device_type : UInt32,
        clusters : Array(Cluster::Base),
        device_type_revision : UInt16 = 1_u16,
        notify_subscribers : Bool = true,
      ) : Bool
        # Don't allow adding endpoint 0 (root node)
        return false if endpoint_id == 0_u16

        # Check if endpoint already exists
        existing = @message_handler.clusters.keys.any? { |k| k[0] == endpoint_id }
        return false if existing

        # Register all provided clusters
        clusters.each do |cluster|
          if cluster.endpoint_id.number != endpoint_id
            raise ArgumentError.new("Cluster endpoint_id (#{cluster.endpoint_id.number}) doesn't match endpoint_id (#{endpoint_id})")
          end
          @message_handler.clusters[{endpoint_id, cluster.cluster_id.id}] = cluster
        end

        # Inject DescriptorCluster if not provided
        unless @message_handler.clusters.has_key?({endpoint_id, Cluster::DescriptorCluster::CLUSTER_ID})
          descriptor = Cluster::DescriptorCluster.new(DataType::EndpointNumber.new(endpoint_id))
          @message_handler.clusters[{endpoint_id, Cluster::DescriptorCluster::CLUSTER_ID}] = descriptor
        end

        # Populate the descriptor
        descriptor = @message_handler.clusters[{endpoint_id, Cluster::DescriptorCluster::CLUSTER_ID}]
          .as(Cluster::DescriptorCluster)

        # Set device type
        descriptor.device_type_list.clear
        descriptor.device_type_list << Cluster::DescriptorCluster::DeviceTypeStruct.new(
          device_type: device_type,
          revision: device_type_revision
        )

        # Populate server list
        cluster_ids = @message_handler.clusters
          .select { |k, _| k[0] == endpoint_id }
          .keys
          .map(&.[1])
          .uniq!
          .sort!
        descriptor.server_list.clear
        cluster_ids.each { |id| descriptor.server_list << id }

        # Track if we need to notify about root PartsList change
        root_parts_list_changed = false

        # Add to root node's PartsList
        if root_desc = @message_handler.clusters[{0_u16, Cluster::DescriptorCluster::CLUSTER_ID}]?.as?(Cluster::DescriptorCluster)
          unless root_desc.has_part?(endpoint_id)
            root_desc.add_part(endpoint_id)
            root_parts_list_changed = true
          end
        end

        # Setup attribute change notifications for the new clusters
        @message_handler.setup_cluster_notifications

        # Notify subscribers of PartsList change on root node (endpoint 0).
        # This tells controllers a new endpoint exists - they will read the
        # new endpoint's attributes on their own (same pattern as remove_endpoint).
        if notify_subscribers && root_parts_list_changed
          @message_handler.notify_subscriptions(
            0_u16,
            Cluster::DescriptorCluster::CLUSTER_ID,
            Cluster::DescriptorCluster::ATTR_PARTS_LIST
          )
        end

        true
      end

      # Removes an endpoint and all its clusters at runtime.
      # This is primarily used by bridge devices to remove bridged endpoints dynamically.
      #
      # Returns true if the endpoint was removed, false if it didn't exist.
      def remove_endpoint(endpoint_id : UInt16) : Bool
        # Don't allow removing endpoint 0 (root node)
        return false if endpoint_id == 0_u16

        # Find all clusters on this endpoint
        cluster_keys = @message_handler.clusters.keys.select { |k| k[0] == endpoint_id }
        return false if cluster_keys.empty?

        # Remove all clusters from the registry
        cluster_keys.each do |key|
          @message_handler.clusters.delete(key)
        end

        # Remove from root node's PartsList
        if root_desc = @message_handler.clusters[{0_u16, Cluster::DescriptorCluster::CLUSTER_ID}]?.as?(Cluster::DescriptorCluster)
          if root_desc.has_part?(endpoint_id)
            root_desc.parts_list.reject! { |part| part == endpoint_id }

            # Notify subscribers of PartsList change (important for controllers to discover removed devices)
            @message_handler.notify_subscriptions(
              0_u16,
              Cluster::DescriptorCluster::CLUSTER_ID,
              Cluster::DescriptorCluster::ATTR_PARTS_LIST
            )
          end
        end

        true
      end

      # Returns all endpoint IDs currently registered (excluding endpoint 0)
      def endpoint_ids : Array(UInt16)
        @message_handler.clusters.keys
          .map(&.[0])
          .uniq!
          .reject { |id| id == 0_u16 }
          .sort!
      end

      # Returns the next available endpoint ID for dynamic endpoints
      # Starts from 1 and finds the first unused ID
      def next_endpoint_id : UInt16
        existing = endpoint_ids
        id = 1_u16
        while existing.includes?(id)
          id += 1
        end
        id
      end

      # Save state for all clusters that need persistence
      protected def save_cluster_states : Nil
        @storage_manager.save_all_cluster_states(@message_handler.clusters.values)
      end

      # Restore state for all clusters from storage
      protected def restore_cluster_states : Nil
        @storage_manager.restore_all_cluster_states(@message_handler.clusters.values)
      end
    end
  end
end
