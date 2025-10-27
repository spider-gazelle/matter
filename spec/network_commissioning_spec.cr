require "./spec_helper"
require "../src/matter/cluster/network_commissioning_cluster"

describe Matter::Cluster::NetworkCommissioningCluster do
  describe "initialization" do
    it "creates cluster with default settings" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(Matter::DataType::EndpointNumber.new(0_u16), Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi)

      cluster.max_networks.should eq(1_u8)
      cluster.networks.should be_empty
      cluster.interface_enabled.should be_true
      cluster.last_networking_status.should be_nil
      cluster.last_network_id.should be_nil
      cluster.last_connect_error_value.should be_nil
    end

    it "creates cluster with custom max networks" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(max_networks: 8_u8)
      cluster.max_networks.should eq(8_u8)
    end

    it "validates max_networks >= 1" do
      expect_raises(ArgumentError, "max_networks must be >= 1") do
        Matter::Cluster::NetworkCommissioningCluster.new(max_networks: 0_u8)
      end
    end

    it "initializes WiFi-specific attributes when WiFi feature enabled" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )

      cluster.supported_wifi_bands.should_not be_nil
      cluster.supported_wifi_bands.not_nil!.should contain(Matter::Cluster::NetworkCommissioningCluster::WiFiBandEnum::Band2G4)
    end

    it "initializes Thread-specific attributes when Thread feature enabled" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::ThreadNetworkInterface
      )

      cluster.supported_thread_features.should_not be_nil
      cluster.thread_version.should eq(4_u16)
    end
  end

  describe "attributes" do
    it "returns scan and connect max time seconds" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        scan_max_time_seconds: 45_u8,
        connect_max_time_seconds: 90_u8
      )

      cluster.scan_max_time_seconds.should eq(45_u8)
      cluster.connect_max_time_seconds.should eq(90_u8)
    end

    it "allows setting interface_enabled" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new

      cluster.interface_enabled = false
      cluster.interface_enabled.should be_false

      cluster.interface_enabled = true
      cluster.interface_enabled.should be_true
    end
  end

  describe "ScanNetworks command" do
    it "validates request parameters" do
      expect_raises(ArgumentError, "ssid must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new(ssid: Bytes.new(0))
      end

      expect_raises(ArgumentError, "ssid must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new(ssid: Bytes.new(33))
      end
    end

    it "requires armed failsafe" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new
      cmd = Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new

      response = cluster.handle_scan_networks(cmd, failsafe_armed: false)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "performs WiFi scan when WiFi feature enabled" do
      backend = Matter::Network::TestBackend.new
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface,
        backend: backend
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new

      response = cluster.handle_scan_networks(cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.wifi_scan_results.should_not be_nil
      response.wifi_scan_results.not_nil!.size.should be > 0
    end

    it "performs Thread scan when Thread feature enabled" do
      backend = Matter::Network::TestBackend.new
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::ThreadNetworkInterface,
        backend: backend
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new

      response = cluster.handle_scan_networks(cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.thread_scan_results.should_not be_nil
      response.thread_scan_results.not_nil!.size.should be > 0
    end

    it "performs directed WiFi scan with SSID filter" do
      backend = Matter::Network::TestBackend.new
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface,
        backend: backend
      )
      ssid = "TestSSID".to_slice
      cmd = Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new(ssid: ssid)

      response = cluster.handle_scan_networks(cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.wifi_scan_results.not_nil!.size.should eq(1)
      response.wifi_scan_results.not_nil![0].ssid.should eq(ssid)
    end

    it "sorts WiFi results by RSSI (strongest first)" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new

      response = cluster.handle_scan_networks(cmd, failsafe_armed: true)

      results = response.wifi_scan_results.not_nil!
      # Verify sorted by RSSI descending
      results.each_cons(2) do |pair|
        (pair[0].rssi || -100).should be >= (pair[1].rssi || -100)
      end
    end

    it "sorts Thread results by LQI (highest first)" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::ThreadNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new

      response = cluster.handle_scan_networks(cmd, failsafe_armed: true)

      results = response.thread_scan_results.not_nil!
      # Verify sorted by LQI descending
      results.each_cons(2) do |pair|
        (pair[0].lqi || 0).should be >= (pair[1].lqi || 0)
      end
    end

    it "updates state attributes after scan" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new
      cmd = Matter::Cluster::NetworkCommissioningCluster::ScanNetworksRequest.new

      cluster.handle_scan_networks(cmd, failsafe_armed: true)

      cluster.last_networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
    end
  end

  describe "AddOrUpdateWiFiNetwork command" do
    it "validates request parameters" do
      expect_raises(ArgumentError, "ssid must be max 32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: Bytes.new(33),
          credentials: Bytes.new(0)
        )
      end

      expect_raises(ArgumentError, "credentials must be max 64 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: "test".to_slice,
          credentials: Bytes.new(65)
        )
      end
    end

    it "requires armed failsafe" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "TestSSID".to_slice,
        credentials: "password123".to_slice
      )

      response = cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: false)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "requires WiFi feature" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::ThreadNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "TestSSID".to_slice,
        credentials: "password123".to_slice
      )

      response = cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "rejects empty SSID" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: Bytes.new(0),
        credentials: "password123".to_slice
      )

      response = cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::OutOfRange)
    end

    it "adds new WiFi network successfully" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      ssid = "TestSSID".to_slice
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: ssid,
        credentials: "password123".to_slice
      )

      response = cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.network_index.should eq(0_u8)
      cluster.networks.size.should eq(1)
      cluster.networks[0].network_id.should eq(ssid)
      cluster.networks[0].connected.should be_false
    end

    it "updates existing WiFi network" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      ssid = "TestSSID".to_slice

      # Add network first
      cmd1 = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: ssid,
        credentials: "oldpassword".to_slice
      )
      cluster.handle_add_or_update_wifi_network(cmd1, failsafe_armed: true)

      # Update with new credentials
      cmd2 = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: ssid,
        credentials: "newpassword".to_slice
      )
      response = cluster.handle_add_or_update_wifi_network(cmd2, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.network_index.should eq(0_u8)
      cluster.networks.size.should eq(1) # Still only one network
    end

    it "rejects when max networks limit reached" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        max_networks: 2_u8,
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )

      # Add two networks
      (1..2).each do |i|
        cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: "Network#{i}".to_slice,
          credentials: "password".to_slice
        )
        cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      end

      # Try to add third network
      cmd3 = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "Network3".to_slice,
        credentials: "password".to_slice
      )
      response = cluster.handle_add_or_update_wifi_network(cmd3, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::BoundsExceeded)
    end

    it "updates state attributes after add" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      ssid = "TestSSID".to_slice
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: ssid,
        credentials: "password".to_slice
      )

      cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)

      cluster.last_networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      cluster.last_network_id.should eq(ssid)
    end
  end

  describe "AddOrUpdateThreadNetwork command" do
    it "validates request parameters" do
      expect_raises(ArgumentError, "operational_dataset must be max 254 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateThreadNetworkRequest.new(
          operational_dataset: Bytes.new(255)
        )
      end
    end

    it "requires armed failsafe" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateThreadNetworkRequest.new(
        operational_dataset: Bytes.new(10)
      )

      response = cluster.handle_add_or_update_thread_network(cmd, failsafe_armed: false)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "requires Thread feature" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateThreadNetworkRequest.new(
        operational_dataset: Bytes.new(10)
      )

      response = cluster.handle_add_or_update_thread_network(cmd, failsafe_armed: true)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "adds new Thread network successfully" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::ThreadNetworkInterface
      )
      dataset = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA]
      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateThreadNetworkRequest.new(
        operational_dataset: dataset
      )

      response = cluster.handle_add_or_update_thread_network(cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.network_index.should eq(0_u8)
      cluster.networks.size.should eq(1)
    end

    it "updates existing Thread network" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::ThreadNetworkInterface
      )
      dataset = Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA]

      # Add network first
      cmd1 = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateThreadNetworkRequest.new(
        operational_dataset: dataset
      )
      cluster.handle_add_or_update_thread_network(cmd1, failsafe_armed: true)

      # Update with same XPAN ID (first 8 bytes)
      cmd2 = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateThreadNetworkRequest.new(
        operational_dataset: dataset
      )
      response = cluster.handle_add_or_update_thread_network(cmd2, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      cluster.networks.size.should eq(1) # Still only one network
    end
  end

  describe "RemoveNetwork command" do
    it "validates request parameters" do
      expect_raises(ArgumentError, "network_id must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::RemoveNetworkRequest.new(
          network_id: Bytes.new(0)
        )
      end

      expect_raises(ArgumentError, "network_id must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::RemoveNetworkRequest.new(
          network_id: Bytes.new(33)
        )
      end
    end

    it "requires armed failsafe" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new
      cmd = Matter::Cluster::NetworkCommissioningCluster::RemoveNetworkRequest.new(
        network_id: "test".to_slice
      )

      response = cluster.handle_remove_network(cmd, failsafe_armed: false)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "returns NetworkIdNotFound for non-existent network" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::RemoveNetworkRequest.new(
        network_id: "NonExistent".to_slice
      )

      response = cluster.handle_remove_network(cmd, failsafe_armed: true)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::NetworkIdNotFound)
    end

    it "removes network successfully" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      ssid = "TestSSID".to_slice

      # Add network first
      add_cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: ssid,
        credentials: "password".to_slice
      )
      cluster.handle_add_or_update_wifi_network(add_cmd, failsafe_armed: true)

      # Remove network
      remove_cmd = Matter::Cluster::NetworkCommissioningCluster::RemoveNetworkRequest.new(
        network_id: ssid
      )
      response = cluster.handle_remove_network(remove_cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.network_index.should eq(0_u8)
      cluster.networks.should be_empty
    end

    it "maintains relative order of remaining networks after removal" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface,
        max_networks: 4_u8
      )

      # Add three networks
      ["Net1", "Net2", "Net3"].each do |name|
        cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: name.to_slice,
          credentials: "password".to_slice
        )
        cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      end

      # Remove middle network
      remove_cmd = Matter::Cluster::NetworkCommissioningCluster::RemoveNetworkRequest.new(
        network_id: "Net2".to_slice
      )
      cluster.handle_remove_network(remove_cmd, failsafe_armed: true)

      cluster.networks.size.should eq(2)
      cluster.networks[0].network_id.should eq("Net1".to_slice)
      cluster.networks[1].network_id.should eq("Net3".to_slice)
    end
  end

  describe "ConnectNetwork command" do
    it "validates request parameters" do
      expect_raises(ArgumentError, "network_id must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::ConnectNetworkRequest.new(
          network_id: Bytes.new(0)
        )
      end
    end

    it "requires armed failsafe" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new
      cmd = Matter::Cluster::NetworkCommissioningCluster::ConnectNetworkRequest.new(
        network_id: "test".to_slice
      )

      response = cluster.handle_connect_network(cmd, failsafe_armed: false)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "returns NetworkIdNotFound for non-existent network" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::ConnectNetworkRequest.new(
        network_id: "NonExistent".to_slice
      )

      response = cluster.handle_connect_network(cmd, failsafe_armed: true)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::NetworkIdNotFound)
    end

    it "connects to network successfully" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      ssid = "TestSSID".to_slice

      # Add network first
      add_cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: ssid,
        credentials: "password".to_slice
      )
      cluster.handle_add_or_update_wifi_network(add_cmd, failsafe_armed: true)

      # Connect to network
      connect_cmd = Matter::Cluster::NetworkCommissioningCluster::ConnectNetworkRequest.new(
        network_id: ssid
      )
      response = cluster.handle_connect_network(connect_cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.error_value.should be_nil
      cluster.networks[0].connected.should be_true
    end

    it "disconnects other networks when connecting to target" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface,
        max_networks: 4_u8
      )

      # Add two networks
      ["Net1", "Net2"].each do |name|
        cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: name.to_slice,
          credentials: "password".to_slice
        )
        cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      end

      # Connect to second network
      connect_cmd = Matter::Cluster::NetworkCommissioningCluster::ConnectNetworkRequest.new(
        network_id: "Net2".to_slice
      )
      cluster.handle_connect_network(connect_cmd, failsafe_armed: true)

      cluster.networks[0].connected.should be_false
      cluster.networks[1].connected.should be_true
    end

    it "updates state attributes after connect" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      ssid = "TestSSID".to_slice

      # Add and connect
      add_cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: ssid,
        credentials: "password".to_slice
      )
      cluster.handle_add_or_update_wifi_network(add_cmd, failsafe_armed: true)

      connect_cmd = Matter::Cluster::NetworkCommissioningCluster::ConnectNetworkRequest.new(
        network_id: ssid
      )
      cluster.handle_connect_network(connect_cmd, failsafe_armed: true)

      cluster.last_networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      cluster.last_network_id.should eq(ssid)
      cluster.last_connect_error_value.should be_nil
    end
  end

  describe "ReorderNetwork command" do
    it "validates request parameters" do
      expect_raises(ArgumentError, "network_id must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::ReorderNetworkRequest.new(
          network_id: Bytes.new(0),
          network_index: 0_u8
        )
      end
    end

    it "requires armed failsafe" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new
      cmd = Matter::Cluster::NetworkCommissioningCluster::ReorderNetworkRequest.new(
        network_id: "test".to_slice,
        network_index: 0_u8
      )

      response = cluster.handle_reorder_network(cmd, failsafe_armed: false)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::UnknownError)
    end

    it "returns NetworkIdNotFound for non-existent network" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )
      cmd = Matter::Cluster::NetworkCommissioningCluster::ReorderNetworkRequest.new(
        network_id: "NonExistent".to_slice,
        network_index: 0_u8
      )

      response = cluster.handle_reorder_network(cmd, failsafe_armed: true)
      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::NetworkIdNotFound)
    end

    it "returns OutOfRange for invalid network_index" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )

      # Add one network
      add_cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "Net1".to_slice,
        credentials: "password".to_slice
      )
      cluster.handle_add_or_update_wifi_network(add_cmd, failsafe_armed: true)

      # Try to reorder to index 5 (out of range)
      reorder_cmd = Matter::Cluster::NetworkCommissioningCluster::ReorderNetworkRequest.new(
        network_id: "Net1".to_slice,
        network_index: 5_u8
      )
      response = cluster.handle_reorder_network(reorder_cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::OutOfRange)
    end

    it "reorders network successfully" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface,
        max_networks: 4_u8
      )

      # Add three networks
      ["Net1", "Net2", "Net3"].each do |name|
        cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: name.to_slice,
          credentials: "password".to_slice
        )
        cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      end

      # Move Net3 to position 0
      reorder_cmd = Matter::Cluster::NetworkCommissioningCluster::ReorderNetworkRequest.new(
        network_id: "Net3".to_slice,
        network_index: 0_u8
      )
      response = cluster.handle_reorder_network(reorder_cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      response.network_index.should eq(0_u8)

      # Verify new order
      cluster.networks[0].network_id.should eq("Net3".to_slice)
      cluster.networks[1].network_id.should eq("Net1".to_slice)
      cluster.networks[2].network_id.should eq("Net2".to_slice)
    end

    it "maintains relative order of other networks during reorder" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface,
        max_networks: 4_u8
      )

      # Add three networks
      ["Net1", "Net2", "Net3"].each do |name|
        cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: name.to_slice,
          credentials: "password".to_slice
        )
        cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      end

      # Move Net1 to position 2
      reorder_cmd = Matter::Cluster::NetworkCommissioningCluster::ReorderNetworkRequest.new(
        network_id: "Net1".to_slice,
        network_index: 2_u8
      )
      cluster.handle_reorder_network(reorder_cmd, failsafe_armed: true)

      # Verify order: Net2, Net3, Net1
      cluster.networks[0].network_id.should eq("Net2".to_slice)
      cluster.networks[1].network_id.should eq("Net3".to_slice)
      cluster.networks[2].network_id.should eq("Net1".to_slice)
    end

    it "allows reordering to same position (no-op)" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )

      # Add two networks
      ["Net1", "Net2"].each do |name|
        cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
          ssid: name.to_slice,
          credentials: "password".to_slice
        )
        cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)
      end

      # Reorder Net1 to position 0 (same position)
      reorder_cmd = Matter::Cluster::NetworkCommissioningCluster::ReorderNetworkRequest.new(
        network_id: "Net1".to_slice,
        network_index: 0_u8
      )
      response = cluster.handle_reorder_network(reorder_cmd, failsafe_armed: true)

      response.networking_status.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success)
      cluster.networks[0].network_id.should eq("Net1".to_slice)
    end
  end

  describe "breadcrumb callback" do
    it "updates breadcrumb when callback set" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )

      breadcrumb_value = nil
      cluster.breadcrumb_callback = ->(value : UInt64) { breadcrumb_value = value }

      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "Test".to_slice,
        credentials: "password".to_slice,
        breadcrumb: 12345_u64
      )

      cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)

      breadcrumb_value.should eq(12345_u64)
    end

    it "does not call callback when breadcrumb not provided" do
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        features: Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )

      callback_called = false
      cluster.breadcrumb_callback = ->(value : UInt64) { callback_called = true }

      cmd = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "Test".to_slice,
        credentials: "password".to_slice
      )

      cluster.handle_add_or_update_wifi_network(cmd, failsafe_armed: true)

      callback_called.should be_false
    end
  end

  describe "data structure validations" do
    it "validates NetworkInfo network_id length" do
      expect_raises(ArgumentError, "network_id must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(
          network_id: Bytes.new(0),
          connected: false
        )
      end

      expect_raises(ArgumentError, "network_id must be 1-32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(
          network_id: Bytes.new(33),
          connected: false
        )
      end
    end

    it "validates WiFiInterfaceScanResult ssid and bssid lengths" do
      expect_raises(ArgumentError, "ssid must be max 32 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult.new(
          ssid: Bytes.new(33)
        )
      end

      expect_raises(ArgumentError, "bssid must be exactly 6 bytes") do
        Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult.new(
          bssid: Bytes.new(5)
        )
      end
    end

    it "validates ThreadInterfaceScanResult network_name and pan_id" do
      expect_raises(ArgumentError, "network_name must be 1-16 chars") do
        Matter::Cluster::NetworkCommissioningCluster::ThreadInterfaceScanResult.new(
          network_name: ""
        )
      end

      expect_raises(ArgumentError, "network_name must be 1-16 chars") do
        Matter::Cluster::NetworkCommissioningCluster::ThreadInterfaceScanResult.new(
          network_name: "A" * 17
        )
      end

      expect_raises(ArgumentError, "pan_id must be max 65534") do
        Matter::Cluster::NetworkCommissioningCluster::ThreadInterfaceScanResult.new(
          pan_id: 65535_u16
        )
      end
    end

    it "validates response debug_text length" do
      expect_raises(ArgumentError, "debug_text must be max 512 chars") do
        Matter::Cluster::NetworkCommissioningCluster::ScanNetworksResponse.new(
          networking_status: Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success,
          debug_text: "A" * 513
        )
      end
    end
  end
end
