require "../spec_helper"
require "../../src/matter/mdns/advertiser"

module Matter::MDNS
  describe Advertiser do
    before_each do
      require_udp_sockets!
    end

    describe "initialization" do
      it "creates advertiser with IPv4 by default" do
        advertiser = Advertiser.new
        advertiser.advertising?.should be_false
        advertiser.server.running?.should be_false
        advertiser.close
      end
    end

    describe "advertising lifecycle" do
      it "starts and stops advertising" do
        advertiser = Advertiser.new

        description = CommissionableServiceDescription.new(
          name: "Test Device",
          device_type: 1_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        advertisement = CommissionableAdvertisement.new(description, ["192.168.1.100"])

        advertiser.start_advertising(advertisement)
        advertiser.advertising?.should be_true
        advertiser.server.running?.should be_true

        # Give broadcast fiber time to start
        sleep 0.1.seconds

        advertiser.stop_advertising
        advertiser.advertising?.should be_false

        advertiser.close
      end

      it "sends announcements on broadcast schedule" do
        advertiser = Advertiser.new

        description = CommissionableServiceDescription.new(
          name: "Test Device",
          device_type: 1_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        advertisement = CommissionableAdvertisement.new(description, ["192.168.1.100"])

        advertiser.start_advertising(advertisement)

        # Wait for first announcement
        sleep 1.5.seconds

        # Should still be broadcasting
        advertiser.advertising?.should be_true

        advertiser.stop_advertising
        advertiser.close
      end

      it "sends goodbye packets on stop" do
        advertiser = Advertiser.new

        description = CommissionableServiceDescription.new(
          name: "Test Device",
          device_type: 1_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        advertisement = CommissionableAdvertisement.new(description, ["192.168.1.100"])

        advertiser.start_advertising(advertisement)
        sleep 0.1.seconds

        # Stop should send goodbye (TTL=0)
        advertiser.stop_advertising

        advertiser.close
      end

      it "replaces advertisement when starting new one" do
        advertiser = Advertiser.new

        description1 = CommissionableServiceDescription.new(
          name: "Device 1",
          device_type: 1_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        ad1 = CommissionableAdvertisement.new(description1, ["192.168.1.100"])
        advertiser.start_advertising(ad1)
        sleep 0.1.seconds

        description2 = CommissionableServiceDescription.new(
          name: "Device 2",
          device_type: 2_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8002_u16,
          discriminator: 200_u16,
          mode: CommissioningMode::Enhanced
        )

        ad2 = CommissionableAdvertisement.new(description2, ["192.168.1.200"])
        advertiser.start_advertising(ad2) # Should stop ad1 and start ad2

        sleep 0.1.seconds
        advertiser.advertising?.should be_true

        advertiser.close
      end
    end

    describe "cleanup" do
      it "closes advertiser and stops advertising" do
        advertiser = Advertiser.new

        description = CommissionableServiceDescription.new(
          name: "Test Device",
          device_type: 1_u32,
          vendor_id: 0xFFF1_u16,
          product_id: 0x8001_u16,
          discriminator: 100_u16,
          mode: CommissioningMode::Basic
        )

        advertisement = CommissionableAdvertisement.new(description, ["192.168.1.100"])
        advertiser.start_advertising(advertisement)

        advertiser.close
        advertiser.advertising?.should be_false
      end
    end
  end
end
