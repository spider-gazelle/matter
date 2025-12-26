require "../spec_helper"
require "../../src/matter/mdns/commissionable_advertisement"

module Matter::MDNS
  describe CommissionableAdvertisement do
    describe "initialization" do
      it "creates advertisement with service description" do
        description = CommissionableServiceDescription.new(
          name: "Test Light",
          device_type: 256_u32, # Light
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 1234_u16,
          mode: CommissioningMode::Enhanced
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])

        ad.instance_id.size.should eq(16) # 8 bytes hex = 16 characters
        ad.hostname.should end_with(".local")
        ad.instance_name.should end_with("._matterc._udp.local")
      end

      it "generates unique instance IDs" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 0_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad1 = CommissionableAdvertisement.new(description, ["192.168.1.1"])
        ad2 = CommissionableAdvertisement.new(description, ["192.168.1.2"])

        ad1.instance_id.should_not eq(ad2.instance_id)
      end
    end

    describe "DNS records" do
      it "generates PTR records for service browsing" do
        description = CommissionableServiceDescription.new(
          name: "Test Device",
          device_type: 15_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 2048_u16, # 0x800, short discriminator = 8
          mode: CommissioningMode::Enhanced
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])
        records = ad.records

        ptr_records = records.select { |record| record.type == DNS::RecordType::PTR.value }

        # Should have 6 PTR records:
        # - Main service type
        # - Device type subtype
        # - Short discriminator subtype
        # - Long discriminator subtype
        # - Commissioning mode subtype
        # - Vendor subtype
        ptr_records.size.should eq(6)

        # Check for main service type
        main_ptr = ptr_records.find { |record| record.name == "_matterc._udp.local" }
        main_ptr.should_not be_nil

        # Check for device type subtype
        device_type_ptr = ptr_records.find { |record| record.name == "_T15._sub._matterc._udp.local" }
        device_type_ptr.should_not be_nil

        # Check for short discriminator subtype
        short_disc_ptr = ptr_records.find { |record| record.name == "_S8._sub._matterc._udp.local" }
        short_disc_ptr.should_not be_nil

        # Check for long discriminator subtype
        long_disc_ptr = ptr_records.find { |record| record.name == "_L2048._sub._matterc._udp.local" }
        long_disc_ptr.should_not be_nil
      end

      it "generates SRV record with hostname and port" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 0_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])
        records = ad.records

        srv_records = records.select { |record| record.type == DNS::RecordType::SRV.value }
        srv_records.size.should eq(1)

        srv = srv_records.first
        srv.name.should eq(ad.instance_name)
        srv.resource_data.size.should be > 0
      end

      it "generates TXT record with device properties" do
        description = CommissionableServiceDescription.new(
          name: "My Light",
          device_type: 256_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 3840_u16,
          mode: CommissioningMode::Enhanced,
          pairing_hint: PairingHint::PowerCycle | PairingHint::DeviceManual
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])
        records = ad.records

        txt_records = records.select { |record| record.type == DNS::RecordType::TXT.value }
        txt_records.size.should eq(1)

        txt = txt_records.first
        txt.name.should eq(ad.instance_name)
        txt.resource_data.size.should be > 0
      end

      it "generates A records for IPv4 addresses" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 0_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100", "10.0.0.50"])
        records = ad.records

        a_records = records.select { |record| record.type == DNS::RecordType::A.value }
        a_records.size.should eq(2)

        a_records.each do |record|
          record.name.should eq(ad.hostname)
          record.resource_data.size.should eq(4) # IPv4 = 4 bytes
        end
      end

      it "generates AAAA records for IPv6 addresses" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 0_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad = CommissionableAdvertisement.new(description, ["fe80::1", "2001:db8::1"])
        records = ad.records

        aaaa_records = records.select { |record| record.type == DNS::RecordType::AAAA.value }
        aaaa_records.size.should eq(2)

        aaaa_records.each do |record|
          record.name.should eq(ad.hostname)
          record.resource_data.size.should eq(16) # IPv6 = 16 bytes
        end
      end

      it "sets appropriate TTL for all records" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 0_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])
        records = ad.records

        records.each do |record|
          record.ttl.should eq(120.seconds) # DEFAULT_TTL = 120 seconds
        end
      end
    end

    describe "query handling" do
      it "responds to main service type query" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 0_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])
        ad.handles?("_matterc._udp.local").should be_true
      end

      it "responds to subtype queries" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 15_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 1234_u16,
          mode: CommissioningMode::Basic
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])

        ad.handles?("_T15._sub._matterc._udp.local").should be_true
        ad.handles?("_L1234._sub._matterc._udp.local").should be_true
        ad.handles?("_V65521._sub._matterc._udp.local").should be_true
      end

      it "responds to instance name query" do
        description = CommissionableServiceDescription.new(
          name: "Device",
          device_type: 0_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad = CommissionableAdvertisement.new(description, ["192.168.1.100"])
        ad.handles?(ad.instance_name).should be_true
      end
    end
  end
end
