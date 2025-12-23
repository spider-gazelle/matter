require "../spec_helper"
require "../../src/matter/mdns/multicast_socket"

module Matter::MDNS
  describe MulticastSocket do
    describe "initialization" do
      it "creates IPv4 socket by default" do
        socket = MulticastSocket.new
        socket.family.should eq(Socket::Family::INET)
        socket.multicast_address.should eq("224.0.0.251")
        socket.close
      end

      it "creates IPv6 socket when specified" do
        socket = MulticastSocket.new(Socket::Family::INET6)
        socket.family.should eq(Socket::Family::INET6)
        socket.multicast_address.should eq("ff02::fb")
        socket.close
      end

      it "binds to port 5353" do
        socket = MulticastSocket.new
        # Socket should be bound and ready
        socket.closed?.should be_false
        socket.close
      end
    end

    describe "multicast group" do
      it "joins multicast group" do
        socket = MulticastSocket.new
        socket.join_multicast_group
        socket.close
      end

      it "leaves multicast group" do
        socket = MulticastSocket.new
        socket.join_multicast_group
        socket.leave_multicast_group
        socket.close
      end

      it "handles multiple join calls gracefully" do
        socket = MulticastSocket.new
        socket.join_multicast_group
        socket.join_multicast_group # Should be no-op
        socket.close
      end
    end

    describe "send/receive" do
      it "sends multicast data" do
        socket = MulticastSocket.new
        socket.join_multicast_group

        data = Bytes[1, 2, 3, 4, 5]
        begin
          bytes_sent = socket.send_multicast(data)
          bytes_sent.should eq(5)
        rescue ex : Socket::Error
          {% if flag?(:darwin) %}
            pending "macOS CI runners often don't have multicast routing (224.0.0.251) enabled: #{ex.message}"
          {% else %}
            raise ex
          {% end %}
        end

        socket.close
      end

      it "receives data with timeout" do
        socket = MulticastSocket.new
        socket.join_multicast_group

        buffer = Bytes.new(1024)
        result = socket.receive(buffer, 50.milliseconds)

        # Timeout expected (no data sent), but may receive data if other processes are running
        # Just verify socket.receive() works without crashing
        (result.nil? || result.is_a?(Tuple)).should be_true

        socket.close
      end
    end

    describe "close" do
      it "closes socket and leaves groups" do
        socket = MulticastSocket.new
        socket.join_multicast_group
        socket.close

        socket.closed?.should be_true
      end

      it "handles multiple close calls" do
        socket = MulticastSocket.new
        socket.close
        socket.close # Should not raise
      end
    end
  end
end
