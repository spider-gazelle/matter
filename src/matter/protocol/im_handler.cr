require "../interaction_model/messages"
require "../interaction_model/paths"
require "../interaction_model/status_code"
require "../interaction_model/tlv_messages"
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
        # Each request is an AttributePath that automatically handles both:
        # - List-form: [endpoint, cluster, attribute]  (compact, positional)
        # - Structure-form: {2 => endpoint, 3 => cluster, 4 => attribute}  (tagged)
        attribute_requests = [] of InteractionModel::AttributePath
        if attr_req_array = request_data[0_u8]?.as?(Array)
          Log.debug { "Found #{attr_req_array.size} attribute request(s)" }

          attr_req_array.each_with_index do |attr_req, idx|
            # Re-encode this individual request as TLV bytes
            # Then AttributePath.new(bytes) automatically detects and parses both forms!
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            writer.put(nil, attr_req)
            attr_req_bytes = io.rewind.to_slice

            # Parse using @[TLV::ListForm] AttributePath - handles both forms automatically
            path = InteractionModel::AttributePath.new(attr_req_bytes)

            Log.debug { "  Request #{idx}: endpoint=#{path.endpoint}, cluster=0x#{path.cluster.try(&.to_s(16)) || "?"}, attribute=#{path.attribute}" }

            attribute_requests << path
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
            Log.debug { "Handling wildcard read" }

            # Expand wildcards into concrete paths
            expanded_paths = [] of Tuple(UInt16, UInt32, UInt32)

            clusters.each do |(endpoint_id, cluster_id), cluster|
              # Check if this endpoint matches (or is wildcard)
              next if path.endpoint && path.endpoint != endpoint_id

              # Check if this cluster matches (or is wildcard)
              next if path.cluster && path.cluster != cluster_id

              # If attribute is wildcard, read all attributes from this cluster
              if path.attribute.nil?
                # Get all attribute IDs from cluster metadata
                cluster.attributes.each do |attr_meta|
                  expanded_paths << {endpoint_id, cluster_id, attr_meta.id.id}
                end
              else
                # Specific attribute on wildcard endpoint/cluster
                expanded_paths << {endpoint_id, cluster_id, path.attribute.not_nil!}
              end
            end

            Log.debug { "Expanded wildcard to #{expanded_paths.size} concrete paths" }

            # Read each expanded path
            expanded_paths.each do |(endpoint_id, cluster_id, attribute_id)|
              cluster = clusters[{endpoint_id, cluster_id}]
              next unless cluster

              result = cluster.read_attribute(attribute_id)
              concrete_path = InteractionModel::AttributePath.new(
                endpoint: endpoint_id,
                cluster: cluster_id,
                attribute: attribute_id
              )

              if result.is_a?(InteractionModel::Status)
                attribute_status << InteractionModel::AttributeStatus.new(
                  path: concrete_path,
                  status: result
                )
              else
                attribute_reports << InteractionModel::AttributeData.new(
                  path: concrete_path,
                  data_version: cluster.data_version,
                  value: result.as(Bytes)
                )
              end
            end

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

      # Encode ReadResponse manually to preserve PATH container types
      # TLV::Serializable loses container type metadata, so we build manually
      def self.encode_read_response(response : InteractionModel::ReadResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Start root structure (anonymous) - ReportData/ReadResponse
        writer.start_structure(nil)

        # Tag 1: suppressResponse (optional, defaults to false)
        if response.suppress_response
          writer.put(1_u8, true)
        end

        # Tag 2: subscriptionId (optional) - not implemented yet

        # Tag 3: attributeReports (array) - FIXED: was tag 1, should be tag 3!
        writer.start_array(3_u8)

        response.attribute_reports.each_with_index do |report, idx|
          begin
            # Validate attribute value
            if report.value.empty?
              Log.warn { "Skipping empty report #{idx}" }
              next
            end

            # Parse attribute value
            reader = TLV::Reader.new(report.value)
            value_data = reader.get
            actual_value = value_data.is_a?(Hash) && value_data.has_key?("Any") ? value_data["Any"] : value_data

            # Start AttributeReportIB
            writer.start_structure(nil)

            # Tag 1: AttributeDataIB
            writer.start_structure(1_u8)

            # Tag 0: dataVersion
            writer.put(0_u8, report.data_version)

            # Tag 1: path (using PATH container!)
            writer.start_path(1_u8)
            writer.put(2_u8, report.path.endpoint.not_nil!) if report.path.endpoint
            writer.put(3_u8, report.path.cluster.not_nil!) if report.path.cluster
            writer.put(4_u8, report.path.attribute.not_nil!) if report.path.attribute
            writer.end_container # End path

            # Tag 2: data
            writer.put(2_u8, actual_value)

            writer.end_container # End AttributeDataIB
            writer.end_container # End AttributeReportIB

            Log.debug { "Encoded attribute report #{idx}: endpoint=#{report.path.endpoint}, cluster=0x#{report.path.cluster.try(&.to_s(16))}, attr=#{report.path.attribute}" }
          rescue ex
            Log.error { "Failed to encode report #{idx}: #{ex.message}" }
          end
        end

        writer.end_container # End attributeReports array

        # Tag 4: eventReports (array, optional) - not implemented yet

        # Tag 5: moreChunkedMessages (optional, defaults to false)
        if response.more_chunks
          writer.put(5_u8, true)
        end

        # Tag 0xFF: interactionModelRevision (REQUIRED, Matter 1.3 = revision 12)
        writer.put(0xFF_u8, 12_u8)

        writer.end_container # End root structure

        io.rewind.to_slice
      end

      # OLD manual encoding (keeping as reference)
      def self.encode_read_response_manual(response : InteractionModel::ReadResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # ReadResponse/ReportData structure (anonymous)
        writer.start_structure(nil)

        # Tag 1: suppressResponse (optional, defaults to false)
        if response.suppress_response
          writer.put(1_u8, true)
        end

        # Tag 2: subscriptionId (optional) - not implemented yet
        # if subscription_id = response.subscription_id
        #   writer.put(2_u8, subscription_id)
        # end

        # Tag 3: AttributeReports (array)
        if response.attribute_reports.size > 0
          writer.start_array(3_u8)
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
            # Parse and unwrap the "Any" wrapper from reader.get
            reader = TLV::Reader.new(report.value)
            value_data = reader.get

            # Unwrap "Any" key if present (reader.get wraps values in {"Any" => value})
            actual_value = if value_data.is_a?(Hash) && value_data.has_key?("Any")
                             value_data["Any"]
                           else
                             value_data
                           end

            writer.put(2_u8, actual_value)

            writer.end_container # End AttributeDataIB
            writer.end_container # End array element
          end
          writer.end_container # End array
        end

        # Tag 4: EventReports (array, optional) - not implemented, would go here

        # Tag 5: MoreChunkedMessages (optional, defaults to false)
        if response.more_chunks
          writer.put(5_u8, true)
        end

        # Tag 0xFF: InteractionModelRevision (REQUIRED!)
        # Per Matter spec and matter.js - this is a required field
        writer.put(0xFF_u8, 12_u8) # IM revision 12 (Matter 1.3)

        writer.end_container # End ReadResponse
        io.rewind.to_slice
      end
    end
  end
end
