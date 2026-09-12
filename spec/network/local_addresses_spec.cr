require "../spec_helper"

describe Matter::Network do
  describe ".local_ip_addresses" do
    it "returns the addresses of the routable interface with an unspecified port" do
      require_udp_sockets!

      addresses = Matter::Network.local_ip_addresses
      addresses.should_not be_empty

      # Sandboxes without a route to the internet only get the loopback fallback.
      pending! "no non-loopback interface in this environment" if addresses.all?(&.loopback?)

      addresses.each do |address|
        address.loopback?.should be_false
        address.port.should eq(Matter::Network::UNSPECIFIED_PORT)
      end
    end

    it "never returns duplicate addresses" do
      require_udp_sockets!

      addresses = Matter::Network.local_ip_addresses
      addresses.uniq.size.should eq(addresses.size)
    end
  end
end
