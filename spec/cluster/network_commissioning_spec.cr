require "../spec_helper"
require "../../src/matter/cluster/network_commissioning_cluster"
require "tlv"

describe Matter::Cluster::NetworkCommissioningCluster do
  describe "initialization" do
    it "creates WiFi network commissioning cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi,
        Matter::Cluster::NetworkCommissioningCluster::Feature::WiFiNetworkInterface
      )

      cluster.cluster_id.id.should eq(0x0031_u32)
      cluster.network_type.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi)
      cluster.max_networks.should eq(1_u8)
      cluster.interface_enabled?.should be_true
      cluster.name.should eq("NetworkCommissioning")
    end

    it "creates Thread network commissioning cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::Thread,
        Matter::Cluster::NetworkCommissioningCluster::Feature::ThreadNetworkInterface
      )

      cluster.network_type.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkType::Thread)
    end

    it "creates Ethernet network commissioning cluster" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::Ethernet,
        Matter::Cluster::NetworkCommissioningCluster::Feature::EthernetNetworkInterface
      )

      cluster.network_type.should eq(Matter::Cluster::NetworkCommissioningCluster::NetworkType::Ethernet)
    end
  end

  describe "attributes" do
    it "reads MaxNetworks attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      value = cluster.read_attribute(Matter::Cluster::NetworkCommissioningCluster::ATTR_MAX_NETWORKS)
      value.should be_a(Bytes)
      # Decode TLV to get actual value
      decoded = decode_tlv_value(value.as(Bytes))
      decoded.should eq(1_u8)
    end

    it "reads ScanMaxTimeSeconds attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      value = cluster.read_attribute(Matter::Cluster::NetworkCommissioningCluster::ATTR_SCAN_MAX_TIME_SECONDS)
      value.should be_a(Bytes)
      # Decode TLV to get actual value
      decoded = decode_tlv_value(value.as(Bytes))
      decoded.should eq(30_u8)
    end

    it "reads ConnectMaxTimeSeconds attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      value = cluster.read_attribute(Matter::Cluster::NetworkCommissioningCluster::ATTR_CONNECT_MAX_TIME_SECONDS)
      value.should be_a(Bytes)
      # Decode TLV to get actual value
      decoded = decode_tlv_value(value.as(Bytes))
      decoded.should eq(60_u8)
    end

    it "reads InterfaceEnabled attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      value = cluster.read_attribute(Matter::Cluster::NetworkCommissioningCluster::ATTR_INTERFACE_ENABLED)
      value.should be_a(Bytes)
      # Decode TLV to get actual value (true = boolean)
      decoded = decode_tlv_value(value.as(Bytes))
      decoded.should eq(true)
    end

    it "writes InterfaceEnabled attribute" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      status = cluster.write_attribute(
        Matter::Cluster::NetworkCommissioningCluster::ATTR_INTERFACE_ENABLED,
        Bytes[0]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::Success)
      cluster.interface_enabled?.should be_false
    end

    it "reads LastNetworkingStatus when nil" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      value = cluster.read_attribute(Matter::Cluster::NetworkCommissioningCluster::ATTR_LAST_NETWORKING_STATUS)
      value.should be_a(Bytes)
      # TLV null encoding - parse and check it's a null type
      tlv = TLV::Any.from_slice(value.as(Bytes))
      tlv.as_nil.should be_nil
    end

    it "returns status for unsupported attribute write" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      status = cluster.write_attribute(
        Matter::Cluster::NetworkCommissioningCluster::ATTR_MAX_NETWORKS,
        Bytes[5]
      )

      status.status.should eq(Matter::InteractionModel::StatusCode::UnsupportedWrite)
    end
  end

  describe "metadata" do
    it "provides attribute metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      attributes = cluster.attributes
      attributes.should_not be_empty
      attributes.size.should be >= 4

      max_networks = attributes.find { |attr| attr.id.id == Matter::Cluster::NetworkCommissioningCluster::ATTR_MAX_NETWORKS }
      max_networks.should_not be_nil
      max_networks_attr = max_networks.as(Matter::Cluster::AttributeMetadata)
      max_networks_attr.name.should eq("MaxNetworks")
      max_networks_attr.writable?.should be_false
    end

    it "provides command metadata" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      commands = cluster.commands
      commands.should_not be_empty
      commands.size.should be >= 6

      scan_command = commands.find { |cmd| cmd.id.id == Matter::Cluster::NetworkCommissioningCluster::CMD_SCAN_NETWORKS }
      scan_command.should_not be_nil
      scan_command.as(Matter::Cluster::CommandMetadata).name.should eq("ScanNetworks")
    end
  end

  describe "network info" do
    it "creates network info" do
      ssid = "MyNetwork".to_slice
      info = Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(ssid, false)

      info.network_id.should eq(ssid)
      info.connected?.should be_false
    end

    it "tracks connected status" do
      ssid = "MyNetwork".to_slice
      info = Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(ssid, true)

      info.connected?.should be_true
      info.connected = false
      info.connected?.should be_false
    end
  end

  describe "WiFi scan results" do
    it "creates WiFi scan result" do
      result = Matter::Cluster::NetworkCommissioningCluster::WiFiInterfaceScanResult.new(
        security: Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA2,
        ssid: "TestNetwork".to_slice,
        bssid: Bytes[0x01, 0x02, 0x03, 0x04, 0x05, 0x06],
        channel: 6_u16,
        wifi_band: Matter::Cluster::NetworkCommissioningCluster::WiFiBandEnum::Band3G65,
        rssi: -45_i8
      )

      result.security.should eq(Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA2)
      result.ssid.should eq("TestNetwork".to_slice)
      result.channel.should eq(6_u16)
      result.rssi.should eq(-45_i8)
    end
  end

  describe "Thread scan results" do
    it "creates Thread scan result" do
      result = Matter::Cluster::NetworkCommissioningCluster::ThreadInterfaceScanResult.new(
        pan_id: 0x1234_u16,
        extended_pan_id: 0x0102030405060708_u64,
        network_name: "TestThread",
        channel: 15_u16,
        version: 2_u8,
        extended_address: Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88],
        rssi: -50_i8,
        lqi: 200_u8
      )

      result.pan_id.should eq(0x1234_u16)
      result.network_name.should eq("TestThread")
      result.channel.should eq(15_u16)
      result.rssi.should eq(-50_i8)
    end
  end

  describe "network management" do
    it "tracks networks list" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      cluster.networks.should be_empty

      # Add network
      ssid = "MyNetwork".to_slice
      cluster.networks << Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(ssid, false)

      cluster.networks.size.should eq(1)
      cluster.has_network?(ssid).should be_true
    end

    it "finds connected network" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      ssid1 = "Network1".to_slice
      ssid2 = "Network2".to_slice

      cluster.networks << Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(ssid1, false)
      cluster.networks << Matter::Cluster::NetworkCommissioningCluster::NetworkInfo.new(ssid2, true)

      connected = cluster.connected_network
      connected.should_not be_nil
      connected.as(Matter::Cluster::NetworkCommissioningCluster::NetworkInfo).network_id.should eq(ssid2)
    end

    it "returns nil when no network connected" do
      endpoint_id = Matter::DataType::EndpointNumber.new(1_u16)
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id,
        Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi
      )

      cluster.connected_network.should be_nil
    end
  end

  describe "network types" do
    it "defines WiFi network type" do
      Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi.value.should eq(0_u8)
    end

    it "defines Thread network type" do
      Matter::Cluster::NetworkCommissioningCluster::NetworkType::Thread.value.should eq(1_u8)
    end

    it "defines Ethernet network type" do
      Matter::Cluster::NetworkCommissioningCluster::NetworkType::Ethernet.value.should eq(2_u8)
    end
  end

  describe "WiFi security types" do
    it "defines security types" do
      Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::Unencrypted.value.should eq(0_u8)
      Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WEP.value.should eq(1_u8)
      Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA.value.should eq(2_u8)
      Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA2.value.should eq(3_u8)
      Matter::Cluster::NetworkCommissioningCluster::WiFiSecurityType::WPA3.value.should eq(4_u8)
    end
  end

  describe "status codes" do
    it "defines status codes" do
      Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::Success.value.should eq(0_u8)
      Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::NetworkIDNotFound.value.should eq(3_u8)
      Matter::Cluster::NetworkCommissioningCluster::NetworkCommissioningStatus::AuthFailure.value.should eq(7_u8)
    end
  end

  describe "protocol-level TLV command handling" do
    it "handles ScanNetworks TLV command" do
      backend = Matter::Network::TestBackend.new
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        network_type: Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi,
        backend: backend
      )

      # Use TLV::Serializable struct for request
      request_bytes = Matter::Cluster::Definitions::NetworkCommissioning::ScanAvailableNetworksRequest.new.to_slice

      # Invoke command
      result = cluster.invoke_command(Matter::Cluster::NetworkCommissioningCluster::CMD_SCAN_NETWORKS, request_bytes)
      result.should be_a(Matter::Cluster::CommandResponse)

      # Parse response using TLV::Serializable
      response = Matter::Cluster::Definitions::NetworkCommissioning::ScanNetworksResponse.from_slice(result.as(Matter::Cluster::CommandResponse).data)
      response.status_code.should eq(Matter::Cluster::Definitions::NetworkCommissioning::StatusCode::Success)
      response.wifi_scan_results.should_not be_nil
    end

    it "handles AddOrUpdateWiFiNetwork TLV command" do
      backend = Matter::Network::TestBackend.new
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        network_type: Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi,
        backend: backend
      )

      # Use TLV::Serializable struct for request
      request_bytes = Matter::Cluster::Definitions::NetworkCommissioning::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "TestSSID".to_slice,
        credentials: "password".to_slice
      ).to_slice

      # Invoke command
      result = cluster.invoke_command(Matter::Cluster::NetworkCommissioningCluster::CMD_ADD_OR_UPDATE_WIFI_NETWORK, request_bytes)
      result.should be_a(Matter::Cluster::CommandResponse)

      # Parse response using TLV::Serializable
      response = Matter::Cluster::Definitions::NetworkCommissioning::NetworkConfigurationResponse.from_slice(result.as(Matter::Cluster::CommandResponse).data)
      response.status_code.should eq(Matter::Cluster::Definitions::NetworkCommissioning::StatusCode::Success)
    end

    it "handles ConnectNetwork TLV command" do
      backend = Matter::Network::TestBackend.new
      cluster = Matter::Cluster::NetworkCommissioningCluster.new(
        endpoint_id: Matter::DataType::EndpointNumber.new(1_u16),
        network_type: Matter::Cluster::NetworkCommissioningCluster::NetworkType::WiFi,
        backend: backend
      )

      # First add a network
      add_req = Matter::Cluster::NetworkCommissioningCluster::AddOrUpdateWiFiNetworkRequest.new(
        ssid: "TestNet".to_slice,
        credentials: "password".to_slice
      )
      cluster.handle_add_or_update_wifi_network(add_req, failsafe_armed: true)

      # Use TLV::Serializable struct for request
      request_bytes = Matter::Cluster::Definitions::NetworkCommissioning::ConnectNetworkRequest.new(
        network_id: "TestNet".to_slice
      ).to_slice

      # Invoke command
      result = cluster.invoke_command(Matter::Cluster::NetworkCommissioningCluster::CMD_CONNECT_NETWORK, request_bytes)
      result.should be_a(Matter::Cluster::CommandResponse)

      # Parse response using TLV::Serializable
      response = Matter::Cluster::Definitions::NetworkCommissioning::ConnectNetworkResponse.from_slice(result.as(Matter::Cluster::CommandResponse).data)
      response.status_code.should eq(Matter::Cluster::Definitions::NetworkCommissioning::StatusCode::Success)
    end
  end
end
