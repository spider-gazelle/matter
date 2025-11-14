require "../interaction_model/messages"
require "../interaction_model/paths"
require "../interaction_model/status_code"
require "../cluster/cluster"
require "tlv"

module Matter
  module Protocol
    # Helper module for Interaction Model message handling
    module IMHandler
      Log = ::Log.for("matter.im")

      # IM message types
      MSG_STATUS_RESPONSE    = 0x01_u8
      MSG_READ_REQUEST       = 0x02_u8
      MSG_SUBSCRIBE_REQUEST  = 0x03_u8
      MSG_SUBSCRIBE_RESPONSE = 0x04_u8
      MSG_REPORT_DATA        = 0x05_u8
      MSG_WRITE_REQUEST      = 0x06_u8
      MSG_WRITE_RESPONSE     = 0x07_u8
      MSG_INVOKE_REQUEST     = 0x08_u8
      MSG_INVOKE_RESPONSE    = 0x09_u8
      MSG_TIMED_REQUEST      = 0x0A_u8

      # Parse ReadRequest from decrypted TLV payload
      def self.parse_read_request(payload : Bytes) : InteractionModel::ReadRequest?
        reader = TLV::Reader.new(payload)
        data = reader.get.as(Hash(TLV::Tag, TLV::Value))

        # ReadRequest structure (TLV anonymous)
        request_data = data["Any"].as(Hash(TLV::Tag, TLV::Value))

        Log.debug { "ReadRequest TLV structure: #{request_data.keys.inspect}" }

        # Extract attribute requests (tag 0, array)
        attribute_requests = [] of InteractionModel::AttributePath
        if attr_req_array = request_data[0_u8]?.as?(Array)
          Log.debug { "Found #{attr_req_array.size} attribute request(s)" }
          attr_req_array.each_with_index do |attr_req, idx|
            Log.debug { "  Attribute request #{idx}: type=#{attr_req.class}, value=#{attr_req.inspect[0, 100]}" }

            # attr_req can be either:
            # 1. Array (list-form path): [endpoint, cluster, attribute] - compact encoding used by iPhone
            # 2. Hash (structure-form path): {2 => endpoint, 3 => cluster, 4 => attribute}

            endpoint : UInt16? = nil
            cluster : UInt32? = nil
            attribute : UInt32? = nil

            if attr_req.is_a?(Array)
              # List-form: [endpoint, cluster, attribute, ...]
              arr = attr_req.as(Array)
              Log.debug { "    List-form path: #{arr.inspect}" }

              # Extract by position, handling different integer types
              if ep = arr[0]?
                endpoint = ep.is_a?(Int32) ? ep.to_u16 : ep.as?(UInt16)
              end

              if cl = arr[1]?
                cluster = cl.is_a?(Int32) ? cl.to_u32 : cl.as?(UInt32)
              end

              if at = arr[2]?
                attribute = at.is_a?(Int32) ? at.to_u32 : at.as?(UInt32)
              end
            elsif attr_req.is_a?(Hash)
              # Structure-form with tags
              path_data = attr_req.as(Hash(TLV::Tag, TLV::Value))
              Log.debug { "    Structure-form path with tags: #{path_data.keys.inspect}" }

              endpoint = path_data[2_u8]?.as?(UInt16)
              cluster = path_data[3_u8]?.as?(UInt32)
              attribute = path_data[4_u8]?.as?(UInt32)
            else
              Log.warn { "    Unknown attribute request type: #{attr_req.class}" }
              next
            end

            Log.debug { "    Parsed path: endpoint=#{endpoint}, cluster=#{cluster}, attribute=#{attribute}" }

            attribute_requests << InteractionModel::AttributePath.new(
              endpoint: endpoint,
              cluster: cluster,
              attribute: attribute
            )
          end
        end

        # Extract fabric_filtered flag (tag 3, optional, defaults to true)
        fabric_filtered = request_data[3_u8]?.as?(Bool) || true

        InteractionModel::ReadRequest.new(
          attribute_requests: attribute_requests,
          fabric_filtered: fabric_filtered
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse ReadRequest: #{ex.message}" }
        nil
      end

      # Read attributes from clusters
      def self.read_attributes(
        attribute_requests : Array(InteractionModel::AttributePath),
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
      ) : InteractionModel::ReadResponse
        attribute_reports = [] of InteractionModel::AttributeData
        attribute_status = [] of InteractionModel::AttributeStatus

        attribute_requests.each do |path|
          Log.debug { "Reading attribute: endpoint=#{path.endpoint}, cluster=0x#{path.cluster.try(&.to_s(16)) || "nil"}, attribute=0x#{path.attribute.try(&.to_s(16)) || "nil"}" }

          # Handle wildcard reads (endpoint/cluster/attribute can be nil)
          if path.wildcard?
            # TODO: Implement wildcard reads
            Log.warn { "Wildcard reads not yet implemented" }
            next
          end

          # Concrete path - read specific attribute
          endpoint_id = path.endpoint.not_nil!
          cluster_id = path.cluster.not_nil!
          attribute_id = path.attribute.not_nil!

          # Find cluster
          cluster = clusters[{endpoint_id, cluster_id}]?
          unless cluster
            # Cluster not found - return NotFound status
            attribute_status << InteractionModel::AttributeStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
            )
            next
          end

          # Read attribute from cluster
          result = cluster.read_attribute(attribute_id)

          if result.is_a?(InteractionModel::Status)
            # Error status
            attribute_status << InteractionModel::AttributeStatus.new(
              path: path,
              status: result
            )
          else
            # Success - attribute data
            attribute_reports << InteractionModel::AttributeData.new(
              path: path,
              data_version: cluster.data_version,
              value: result.as(Bytes)
            )
          end
        end

        InteractionModel::ReadResponse.new(
          attribute_reports: attribute_reports,
          attribute_status: attribute_status
        )
      end

      # Encode ReadResponse as TLV
      def self.encode_read_response(response : InteractionModel::ReadResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # ReadResponse structure (anonymous)
        writer.start_structure(nil)

        # Tag 1: AttributeReports (array)
        if response.attribute_reports.size > 0
          writer.start_array(1_u8)
          response.attribute_reports.each do |report|
            writer.start_structure(nil)

            # Tag 0: AttributeDataIB
            writer.start_structure(0_u8)

            # Tag 0: DataVersion
            writer.put(0_u8, report.data_version)

            # Tag 1: Path (AttributePathIB)
            writer.start_structure(1_u8)
            if endpoint = report.path.endpoint
              writer.put(2_u8, endpoint)
            end
            if cluster = report.path.cluster
              writer.put(3_u8, cluster)
            end
            if attribute = report.path.attribute
              writer.put(4_u8, attribute)
            end
            writer.end_container # End Path

            # Tag 2: Data (TLV value - already encoded)
            # We need to write the raw TLV bytes directly
            # For now, write as byte string tag
            io2 = IO::Memory.new(report.value)
            reader = TLV::Reader.new(report.value)
            value_data = reader.get
            writer.put(2_u8, value_data)

            writer.end_container # End AttributeDataIB
            writer.end_container # End array element
          end
          writer.end_container # End array
        end

        # Tag 2: AttributeStatusIB (array, optional)
        if response.attribute_status.size > 0
          writer.start_array(2_u8)
          response.attribute_status.each do |status_report|
            writer.start_structure(nil)

            # Tag 0: Path
            writer.start_structure(0_u8)
            if endpoint = status_report.path.endpoint
              writer.put(2_u8, endpoint)
            end
            if cluster = status_report.path.cluster
              writer.put(3_u8, cluster)
            end
            if attribute = status_report.path.attribute
              writer.put(4_u8, attribute)
            end
            writer.end_container # End Path

            # Tag 1: StatusIB
            writer.start_structure(1_u8)
            writer.put(0_u8, status_report.status.status.value.to_u8) # Status code
            writer.end_container                                      # End StatusIB

            writer.end_container # End array element
          end
          writer.end_container # End array
        end

        # Tag 3: MoreChunkedMessages (optional, defaults to false)
        if response.more_chunks
          writer.put(3_u8, true)
        end

        # Tag 4: SuppressResponse (optional, defaults to false)
        if response.suppress_response
          writer.put(4_u8, true)
        end

        writer.end_container # End ReadResponse
        io.rewind.to_slice
      end
    end
  end
end
