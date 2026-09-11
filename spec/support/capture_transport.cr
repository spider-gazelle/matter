require "../../src/matter/transport/udp_transport"

module Matter
  module Spec
    # A `Transport::UDPTransport` that binds no socket and records what would
    # have gone out on the wire.
    #
    # Specs that exercise the protocol layer need a transport, not a network;
    # binding a real UDP socket is both slow and unavailable in some sandboxes.
    class CaptureTransport < Transport::UDPTransport
      getter sent_packets : Array(Tuple(Bytes, Socket::IPAddress)) = [] of Tuple(Bytes, Socket::IPAddress)

      def self.new_for_spec : self
        transport = allocate
        transport.initialize_for_spec
        transport
      end

      protected def initialize_for_spec : Nil
        @port = 0
        @on_message = nil
        @sent_packets = [] of Tuple(Bytes, Socket::IPAddress)
      end

      def start : Nil
      end

      def stop : Nil
      end

      def close : Nil
      end

      def send_raw(data : Bytes | Slice(UInt8), peer_address : Socket::IPAddress) : Nil
        @sent_packets << {data.to_slice.dup, peer_address}
      end
    end
  end
end
