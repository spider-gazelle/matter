require "../registry"

module ChipTool
  module Commands
    module Pairing
      extend self

      def register : Nil
        Registry.register("pairing", "code", "Commission over IP using manual pairing code") do |_ctx, _args|
          ctx = _ctx
          args = _args.dup

          node_id_str = args.shift?
          manual_code = args.shift?

          unless node_id_str && manual_code
            STDERR.puts "Usage: pairing code <node-id> <manual-code> [--address <ip[:port]>]"
            next 2
          end

          peer = nil.as(Socket::IPAddress?)
          if idx = args.index("--address")
            addr = args[idx + 1]?
            raise ArgumentError.new("missing value for --address") unless addr
            args.delete_at(idx)
            args.delete_at(idx)

            host, port = addr.includes?(':') ? addr.split(':', 2) : {addr, "5540"}
            peer = Socket::IPAddress.new(host, port.to_i)
          end

          node_id = parse_u64(node_id_str) || raise ArgumentError.new("invalid node-id: #{node_id_str}")

          store = Matter::Controller::StateStore.new(ctx.storage_directory)
          commissioner = Matter::Controller::Commissioning::Commissioner.new(store, timeout: ctx.timeout)
          begin
            commissioner.pairing_code(node_id, manual_code, peer: peer)
          ensure
            commissioner.close
          end

          puts "Commissioned node 0x#{node_id.to_s(16)}"
          0
        end
      end

      private def parse_u64(s : String) : UInt64?
        v = s.strip
        return nil if v.empty?
        if v.starts_with?("0x") || v.starts_with?("0X")
          v[2..].to_u64?(16)
        else
          v.to_u64?
        end
      end
    end
  end
end
