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
        # Each request is a PathContainer with tags: 2=endpoint, 3=cluster, 4=attribute
        # Missing tags indicate wildcards
        attribute_requests = [] of InteractionModel::AttributePath
        if attr_req_array = request_data[0_u8]?.as?(Array)
          Log.debug { "Found #{attr_req_array.size} attribute request(s)" }

          attr_req_array.each_with_index do |attr_req, idx|
            # Extract from PathContainer - values are stored as Int32
            # PathContainer is a wrapper with []? method
            endpoint_raw = case attr_req
                           when TLV::PathContainer
                             attr_req[2_u8]?
                           when Hash
                             attr_req.as(Hash(TLV::Tag, TLV::Value))[2_u8]?
                           else
                             nil
                           end

            cluster_raw = case attr_req
                          when TLV::PathContainer
                            attr_req[3_u8]?
                          when Hash
                            attr_req.as(Hash(TLV::Tag, TLV::Value))[3_u8]?
                          else
                            nil
                          end

            attribute_raw = case attr_req
                            when TLV::PathContainer
                              attr_req[4_u8]?
                            when Hash
                              attr_req.as(Hash(TLV::Tag, TLV::Value))[4_u8]?
                            else
                              nil
                            end

            # Convert to proper types - TLV may store as Int32
            endpoint = if endpoint_raw
                         case endpoint_raw
                         when Int
                           endpoint_raw.to_u16
                         when UInt8, UInt16, UInt32
                           endpoint_raw.to_u16
                         else
                           nil
                         end
                       end

            cluster = if cluster_raw
                        case cluster_raw
                        when Int
                          cluster_raw.to_u32
                        when UInt8, UInt16, UInt32
                          cluster_raw.to_u32
                        else
                          nil
                        end
                      end

            attribute = if attribute_raw
                          case attribute_raw
                          when Int
                            attribute_raw.to_u32
                          when UInt8, UInt16, UInt32
                            attribute_raw.to_u32
                          else
                            nil
                          end
                        end

            path = InteractionModel::AttributePath.new(
              endpoint: endpoint,
              cluster: cluster,
              attribute: attribute
            )

            Log.debug { "  Request #{idx}: endpoint=#{path.endpoint || "nil"}, cluster=0x#{path.cluster.try(&.to_s(16)) || "nil"}, attribute=0x#{path.attribute.try(&.to_s(16)) || "nil"}" }

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

        # Tag 1: subscriptionId (optional) - not implemented yet

        # Tag 1: attributeReports (array) - matches matter.js structure
        writer.start_array(1_u8)

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

        # Add AttributeStatus entries to the same array
        response.attribute_status.each_with_index do |status, idx|
          begin
            # Start AttributeReportIB
            writer.start_structure(nil)

            # Tag 0: AttributeStatusIB (for errors)
            writer.start_structure(0_u8)

            # Tag 0: path (using PATH container!)
            writer.start_path(0_u8)
            writer.put(2_u8, status.path.endpoint.not_nil!) if status.path.endpoint
            writer.put(3_u8, status.path.cluster.not_nil!) if status.path.cluster
            writer.put(4_u8, status.path.attribute.not_nil!) if status.path.attribute
            writer.end_container # End path

            # Tag 1: status (StatusIB structure)
            writer.start_structure(1_u8)
            writer.put(0_u8, status.status.status.value) # Tag 0: status code
            # Tag 1: cluster-status (optional) - not implemented
            writer.end_container # End StatusIB

            writer.end_container # End AttributeStatusIB
            writer.end_container # End AttributeReportIB

            Log.debug { "Encoded attribute status #{idx}: endpoint=#{status.path.endpoint}, cluster=0x#{status.path.cluster.try(&.to_s(16))}, attr=#{status.path.attribute}, status=#{status.status.status}" }
          rescue ex
            Log.error { "Failed to encode status #{idx}: #{ex.message}" }
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
    end
  end
end
