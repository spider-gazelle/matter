require "../fabric_table"
require "../transport/udp_transport"
require "../protocol/message_handler"
require "../persistence/storage_manager"
require "../persistence/json_storage"
require "./lifecycle_manager"

require "../mdns/responder"
require "../mdns/service_type"
require "../constants/device_types"
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
      getter port : Int32

      getter storage_manager : Persistence::StorageManager
      getter fabric_table : FabricTable
      getter transport : Transport::UDPTransport
      getter message_handler : Protocol::MessageHandler
      getter responder : MDNS::Responder
      getter lifecycle : LifecycleManager
      @basic_info : Cluster::BasicInformationCluster? = nil
      @general_commissioning : Cluster::GeneralCommissioningCluster? = nil
      @access_control : Cluster::AccessControlCluster? = nil
      @operational_credentials : Cluster::OperationalCredentialsCluster? = nil

      def basic_info : Cluster::BasicInformationCluster
        @basic_info.not_nil!
      end

      def general_commissioning : Cluster::GeneralCommissioningCluster
        @general_commissioning.not_nil!
      end

      def access_control : Cluster::AccessControlCluster
        @access_control.not_nil!
      end

      def operational_credentials : Cluster::OperationalCredentialsCluster
        @operational_credentials.not_nil!
      end

      def initialize(
        @hostname : String = "matter-device.local",
        @port : Int32 = 5540,
        ip_addresses : Array(Socket::IPAddress)? = nil,
      )
        @ip_addresses = ip_addresses || default_ip_addresses

        @storage_manager = build_storage_manager
        @fabric_table = @storage_manager.fabric_table

        @transport = Transport::UDPTransport.new(port: @port)
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
          port: @port,
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
      def start : Nil
        before_start
        @lifecycle.sync_advertisements
        @fabric_table.empty? ? started_commissioning_mode : started_operational_mode
        @responder.start
        @transport.start
        after_start
        main_loop
      end

      def stop : Nil
        # Persist all session state before shutdown to ensure message counters
        # and other session data are saved for clean reconnection after restart
        @message_handler.persist_all_sessions

        # Save cluster state (scenes, groups, etc.)
        save_cluster_states

        @storage_manager.stop
        @transport.close
        @responder.stop
      end

      # ------------------------------------------------------------------------
      # Required device identity
      # ------------------------------------------------------------------------
      abstract def device_name : String
      abstract def vendor_id : UInt16
      abstract def product_id : UInt16
      abstract def discriminator : UInt16
      abstract def setup_pin : UInt32
      abstract def primary_device_type_id : UInt16

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
      protected abstract def build_storage_manager : Persistence::StorageManager

      # ------------------------------------------------------------------------
      # Device clusters / endpoints
      # ------------------------------------------------------------------------
      # Return the device-specific clusters (typically for endpoint(s) > 0).
      protected abstract def device_clusters : Array(Cluster::Base)

      # Map endpoint -> device type ID for DescriptorCluster population.
      protected def endpoint_device_types : Hash(UInt16, UInt32)
        {1_u16 => primary_device_type_id.to_u32} of UInt16 => UInt32
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

      protected def after_start : Nil
      end

      # Optional main loop hook. Override to block (e.g., interactive UI loop).
      protected def main_loop : Nil
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
      protected def commissioning_info : MDNS::CommissioningInfo
        MDNS::CommissioningInfo.new(
          device_name: device_name,
          vendor_id: vendor_id,
          product_id: product_id,
          discriminator: discriminator,
          device_type: primary_device_type_id,
          commissioning_mode: MDNS::CommissioningMode::Basic
        )
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
          serial_number: serial_number,
          unique_id: unique_id,
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
        endpoints = @message_handler.clusters.keys.map(&.[0]).uniq.sort
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
            .uniq
            .sort

          cluster_ids.each { |id| descriptor.server_list << id unless descriptor.server_list.includes?(id) }

          # DeviceTypeList: Root Node on endpoint 0, otherwise use endpoint_device_types
          descriptor.device_type_list.clear
          if endpoint_id == 0_u16
            descriptor.device_type_list << Cluster::DescriptorCluster::DeviceTypeStruct.new(
              device_type: DeviceTypes::ROOT_NODE.to_u32,
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
