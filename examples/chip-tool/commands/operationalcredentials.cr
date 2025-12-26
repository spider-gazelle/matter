require "../registry"

module ChipTool
  module Commands
    module OperationalCredentials
      extend self

      alias FabricDescriptor = Matter::Cluster::Definitions::OperationalCredentials::FabricDescriptor

      def register : Nil
        Registry.register("operationalcredentials", "read", "Read OperationalCredentials cluster attributes") do |_ctx, _args|
          ctx = _ctx
          args = _args.dup

          attribute = args.shift?
          node_id_str = args.shift?
          endpoint_str = args.shift?

          unless attribute && node_id_str && endpoint_str
            STDERR.puts "Usage: operationalcredentials read fabrics <node-id> <endpoint-id>"
            next 2
          end

          cluster_id = Matter::Cluster::OperationalCredentialsCluster::CLUSTER_ID
          attribute_id = case attribute
                         when "fabrics" then Matter::Cluster::OperationalCredentialsCluster::ATTR_FABRICS
                         else
                           STDERR.puts "Unsupported attribute: #{attribute} (supported: fabrics)"
                           next 2
                         end

          node_id = parse_u64(node_id_str) || raise ArgumentError.new("invalid node-id: #{node_id_str}")
          endpoint_id = endpoint_str.to_u16

          store = Matter::Controller::StateStore.new(ctx.storage_directory)
          state = store.load
          fabric = state.fabric || raise "No controller fabric found; run `pairing code ...` first"

          peer = resolve_peer(state, fabric, node_id, ctx.timeout)
          state.nodes[node_id] = Matter::Controller::NodeInfo.new(node_id, peer.address, peer.port)
          store.save(state)

          controller = Matter::Controller::Client.new
          begin
            session = Matter::Controller::Pairing::CasePairing.new.pair(controller, peer, fabric, peer_node_id: node_id, timeout: ctx.timeout)
            im = Matter::Controller::ImClient.new(controller, ctx.timeout)
            report = im.read_attribute(
              session: session,
              peer: peer,
              endpoint_id: endpoint_id,
              cluster_id: cluster_id,
              attribute_id: attribute_id
            )

            fabrics = extract_fabrics(report, cluster_id, attribute_id) || raise "ReportData missing fabrics"
            puts "Fabrics: #{fabrics.size} entries"
            fabrics.each_with_index do |f, idx|
              puts "  [#{idx}]:"
              puts "    FabricIndex: #{f.fabric_index}"
              puts "    FabricId: 0x#{f.fabric_id.to_s(16)}"
              puts "    NodeId: 0x#{f.node_id.to_s(16)}"
              puts "    VendorId: #{f.vendor_id}"
            end
            0
          ensure
            controller.close
          end
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

      private def resolve_peer(state : Matter::Controller::State, fabric : Matter::Controller::FabricInfo, node_id : UInt64, timeout : Time::Span) : Socket::IPAddress
        if info = state.nodes[node_id]?
          if addr = info.address
            return Socket::IPAddress.new(addr, info.port)
          end
        end

        scanner = nil.as(Matter::MDNS::Scanner?)
        scanner = Matter::MDNS::Scanner.new
        scanner.start
        scanner.query_operational

        deadline = Time.monotonic + timeout
        loop do
          if dev = scanner.operational_devices.find { |d| d.fabric_id == fabric.fabric_id && d.node_id == node_id }
            address = dev.addresses.find(&.family.inet?) || dev.addresses.first?
            if addr = address
              return Socket::IPAddress.new(addr.address, dev.port)
            end
          end
          break if Time.monotonic >= deadline
          sleep 100.milliseconds
        end

        raise "Failed to resolve operational address via mDNS (fabric_id=0x#{fabric.fabric_id.to_s(16)} node_id=0x#{node_id.to_s(16)})"
      ensure
        scanner.try(&.close)
      end

      private def extract_fabrics(report : Matter::InteractionModel::ReportDataMessage, cluster_id : UInt32, attribute_id : UInt32) : Array(FabricDescriptor)?
        reports = report.attribute_reports
        return nil unless reports

        reports.each do |r|
          data = r.attribute_data
          next unless data
          path = data.path
          next unless path.cluster == cluster_id
          next unless path.attribute == attribute_id

          any = data.data
          case v = any.value
          when Array(TLV::Any)
            fabrics = [] of FabricDescriptor
            v.each do |elem|
              fabrics << FabricDescriptor.from_slice(elem.to_slice)
            end
            return fabrics
          else
            return nil
          end
        end

        nil
      end
    end
  end
end
