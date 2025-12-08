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

      # Parse WriteRequest from decrypted TLV payload
      def self.parse_write_request(payload : Bytes) : InteractionModel::WriteRequest?
        reader = TLV::Reader.new(payload)
        data = reader.get.as(Hash(TLV::Tag, TLV::Value))

        # WriteRequest structure (TLV anonymous)
        request_data = data["Any"].as(Hash(TLV::Tag, TLV::Value))

        Log.debug { "WriteRequest TLV structure: #{request_data.keys.inspect}" }

        # Extract suppressResponse (tag 0, optional, defaults to false)
        suppress_response = request_data[0_u8]?.as?(Bool) || false

        # Extract timedRequest (tag 1, required)
        timed_request = request_data[1_u8]?.as?(Bool) || false

        # Extract writeRequests (tag 2, array of AttributeDataIB)
        write_requests = [] of InteractionModel::AttributeWriteRequest
        if write_req_array = request_data[2_u8]?.as?(Array)
          Log.debug { "Found #{write_req_array.size} write request(s)" }

          write_req_array.each_with_index do |write_req, idx|
            # Extract AttributeDataIB structure
            attr_data = case write_req
                        when Hash
                          write_req.as(Hash(TLV::Tag, TLV::Value))
                        else
                          next
                        end

            # Extract dataVersion (tag 0, optional)
            data_version = if dv = attr_data[0_u8]?
                             case dv
                             when Int
                               dv.to_u32
                             when UInt32
                               dv
                             else
                               nil
                             end
                           end

            # Extract path (tag 1, PATH container with endpoint/cluster/attribute)
            path_raw = attr_data[1_u8]?
            unless path_raw
              Log.warn { "Write request #{idx} missing path" }
              next
            end

            path_data = case path_raw
                        when TLV::PathContainer
                          {
                            endpoint:  path_raw[2_u8]?,
                            cluster:   path_raw[3_u8]?,
                            attribute: path_raw[4_u8]?,
                          }
                        when Hash
                          hash = path_raw.as(Hash(TLV::Tag, TLV::Value))
                          {
                            endpoint:  hash[2_u8]?,
                            cluster:   hash[3_u8]?,
                            attribute: hash[4_u8]?,
                          }
                        else
                          Log.warn { "Write request #{idx} has unexpected path type: #{path_raw.class}" }
                          next
                        end

            # Convert to proper types
            endpoint = if ep = path_data[:endpoint]
                         case ep
                         when Int
                           ep.to_u16
                         when UInt16
                           ep
                         else
                           nil
                         end
                       end

            cluster = if cl = path_data[:cluster]
                        case cl
                        when Int
                          cl.to_u32
                        when UInt32
                          cl
                        else
                          nil
                        end
                      end

            attribute = if at = path_data[:attribute]
                          case at
                          when Int
                            at.to_u32
                          when UInt32
                            at
                          else
                            nil
                          end
                        end

            unless cluster && attribute
              Log.warn { "Write request #{idx} missing cluster or attribute" }
              next
            end

            path = InteractionModel::AttributePath.new(
              endpoint: endpoint,
              cluster: cluster,
              attribute: attribute
            )

            # Extract data (tag 2)
            value_data = attr_data[2_u8]?
            value = if value_data
                      # Encode the TLV value back to bytes for cluster processing
                      io = IO::Memory.new
                      writer = TLV::Writer.new(io)
                      writer.put(nil, value_data)
                      io.rewind.to_slice
                    else
                      Bytes.empty
                    end

            Log.debug { "  Write #{idx}: endpoint=#{endpoint || "nil"}, cluster=0x#{cluster.to_s(16)}, attribute=0x#{attribute.to_s(16)}, value=#{value.size} bytes" }

            write_requests << InteractionModel::AttributeWriteRequest.new(
              path: path,
              value: value,
              data_version: data_version
            )
          end
        end

        # Extract moreChunkedMessages (tag 3, optional, defaults to false)
        more_chunked_messages = request_data[3_u8]?.as?(Bool) || false

        InteractionModel::WriteRequest.new(
          write_requests: write_requests,
          timed_request: timed_request,
          suppress_response: suppress_response,
          more_chunked_messages: more_chunked_messages
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse WriteRequest: #{ex.message}" }
        nil
      end

      # Write attributes to clusters
      def self.write_attributes(
        write_requests : Array(InteractionModel::AttributeWriteRequest),
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
      ) : InteractionModel::WriteResponse
        write_responses = [] of InteractionModel::AttributeStatus

        write_requests.each do |request|
          path = request.path
          Log.debug { "Writing attribute: endpoint=#{path.endpoint}, cluster=0x#{path.cluster.try(&.to_s(16)) || "nil"}, attribute=0x#{path.attribute.try(&.to_s(16)) || "nil"}" }

          # Get endpoint and cluster IDs
          endpoint_id = path.endpoint || 0_u16 # Default to endpoint 0 if not specified
          cluster_id = path.cluster

          unless cluster_id
            write_responses << InteractionModel::AttributeStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::InvalidAction)
            )
            next
          end

          attribute_id = path.attribute
          unless attribute_id
            write_responses << InteractionModel::AttributeStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::InvalidAction)
            )
            next
          end

          # Find cluster
          cluster = clusters[{endpoint_id, cluster_id}]?
          unless cluster
            # Cluster not found on this endpoint
            write_responses << InteractionModel::AttributeStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
            )
            next
          end

          # Write attribute to cluster
          status = cluster.write_attribute(attribute_id, request.value)

          write_responses << InteractionModel::AttributeStatus.new(
            path: path,
            status: status
          )
        end

        InteractionModel::WriteResponse.new(write_responses: write_responses)
      end

      # Parse SubscribeRequest from decrypted TLV payload
      def self.parse_subscribe_request(payload : Bytes) : InteractionModel::SubscribeRequest?
        reader = TLV::Reader.new(payload)
        data = reader.get.as(Hash(TLV::Tag, TLV::Value))

        # SubscribeRequest structure (TLV anonymous)
        request_data = data["Any"].as(Hash(TLV::Tag, TLV::Value))

        Log.debug { "SubscribeRequest TLV structure: #{request_data.keys.inspect}" }

        # Extract keepSubscriptions (tag 0, required)
        keep_subscriptions = request_data[0_u8]?.as?(Bool) || false

        # Extract minIntervalFloorSeconds (tag 1, required)
        min_interval_floor = if mi = request_data[1_u8]?
                               case mi
                               when Int
                                 mi.to_u16
                               when UInt16
                                 mi
                               else
                                 0_u16
                               end
                             else
                               0_u16
                             end

        # Extract maxIntervalCeilingSeconds (tag 2, required)
        max_interval_ceiling = if mx = request_data[2_u8]?
                                 case mx
                                 when Int
                                   mx.to_u16
                                 when UInt16
                                   mx
                                 else
                                   3600_u16
                                 end
                               else
                                 3600_u16
                               end

        # Extract attributeRequests (tag 3, optional array)
        attribute_requests = [] of InteractionModel::AttributePath
        if attr_req_array = request_data[3_u8]?.as?(Array)
          Log.debug { "Found #{attr_req_array.size} attribute request(s)" }

          attr_req_array.each_with_index do |attr_req, idx|
            # Extract from PathContainer
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

            # Convert to proper types
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

        # Extract isFabricFiltered (tag 7, required)
        fabric_filtered = request_data[7_u8]?.as?(Bool) || true

        InteractionModel::SubscribeRequest.new(
          attribute_requests: attribute_requests,
          fabric_filtered: fabric_filtered,
          min_interval_floor: min_interval_floor,
          max_interval_ceiling: max_interval_ceiling,
          keep_subscriptions: keep_subscriptions
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse SubscribeRequest: #{ex.message}" }
        nil
      end

      # Encode ReportData (used for both ReadResponse and initial subscription data)
      def self.encode_report_data(
        response : InteractionModel::ReadResponse,
        subscription_id : UInt32? = nil,
      ) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Start root structure (anonymous) - ReportData
        writer.start_structure(nil)

        # Tag 0: subscriptionId (optional, only for subscriptions)
        if sub_id = subscription_id
          writer.put(0_u8, sub_id)
        end

        # Tag 1: attributeReports (array)
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
            writer.end_container                         # End StatusIB

            writer.end_container # End AttributeStatusIB
            writer.end_container # End AttributeReportIB

            Log.debug { "Encoded attribute status #{idx}: endpoint=#{status.path.endpoint}, cluster=0x#{status.path.cluster.try(&.to_s(16))}, attr=#{status.path.attribute}, status=#{status.status.status}" }
          rescue ex
            Log.error { "Failed to encode status #{idx}: #{ex.message}" }
          end
        end

        writer.end_container # End attributeReports array

        # Tag 3: suppressResponse (optional, for subscriptions - set to false to get ACK)
        # Note: We don't suppress to ensure we get the ACK before sending SubscribeResponse

        # Tag 4: moreChunkedMessages (optional, defaults to false)
        if response.more_chunks
          writer.put(4_u8, true)
        end

        # Tag 0xFF: interactionModelRevision (REQUIRED, Matter 1.3 = revision 12)
        writer.put(0xFF_u8, 12_u8)

        writer.end_container # End root structure

        io.rewind.to_slice
      end

      # Encode SubscribeResponse
      def self.encode_subscribe_response(
        subscription_id : UInt32,
        max_interval : UInt16,
      ) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Start root structure (anonymous) - SubscribeResponse
        writer.start_structure(nil)

        # Tag 0: subscriptionId (required)
        writer.put(0_u8, subscription_id)

        # Tag 2: maxInterval (required) - Note: tag 1 is not used
        writer.put(2_u8, max_interval)

        # Tag 0xFF: interactionModelRevision (REQUIRED, Matter 1.3 = revision 12)
        writer.put(0xFF_u8, 12_u8)

        writer.end_container # End root structure

        io.rewind.to_slice
      end

      # Encode WriteResponse manually to preserve PATH container types
      def self.encode_write_response(response : InteractionModel::WriteResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Start root structure (anonymous) - WriteResponseMessage
        writer.start_structure(nil)

        # Tag 0: writeResponses (array of AttributeStatusIB)
        writer.start_array(0_u8)

        response.write_responses.each_with_index do |status, idx|
          begin
            # Start AttributeStatusIB
            writer.start_structure(nil)

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

            Log.debug { "Encoded write status #{idx}: endpoint=#{status.path.endpoint}, cluster=0x#{status.path.cluster.try(&.to_s(16))}, attr=#{status.path.attribute}, status=#{status.status.status}" }
          rescue ex
            Log.error { "Failed to encode write status #{idx}: #{ex.message}" }
          end
        end

        writer.end_container # End writeResponses array

        # Tag 0xFF: interactionModelRevision (REQUIRED, Matter 1.3 = revision 12)
        writer.put(0xFF_u8, 12_u8)

        writer.end_container # End root structure

        io.rewind.to_slice
      end

      # Parse InvokeRequest from decrypted TLV payload
      def self.parse_invoke_request(payload : Bytes) : InteractionModel::InvokeRequest?
        reader = TLV::Reader.new(payload)
        data = reader.get.as(Hash(TLV::Tag, TLV::Value))

        # InvokeRequest structure (TLV anonymous)
        request_data = data["Any"].as(Hash(TLV::Tag, TLV::Value))

        Log.debug { "InvokeRequest TLV structure: #{request_data.keys.inspect}" }

        # Extract suppressResponse (tag 0, optional, defaults to false)
        suppress_response = request_data[0_u8]?.as?(Bool) || false

        # Extract timedRequest (tag 1, optional, defaults to false)
        timed_request = request_data[1_u8]?.as?(Bool) || false

        # Extract invokeRequests (tag 2, array)
        invoke_requests = [] of InteractionModel::CommandDataIB
        if invoke_req_array = request_data[2_u8]?.as?(Array)
          Log.debug { "Found #{invoke_req_array.size} invoke request(s)" }

          invoke_req_array.each_with_index do |invoke_req, idx|
            # Extract CommandDataIB structure
            cmd_data = case invoke_req
                       when Hash
                         invoke_req.as(Hash(TLV::Tag, TLV::Value))
                       else
                         next
                       end

            # Extract commandPath (tag 0, LIST container with endpoint/cluster/command)
            cmd_path_raw = cmd_data[0_u8]?
            unless cmd_path_raw
              Log.warn { "Invoke request #{idx} missing commandPath" }
              next
            end

            cmd_path_data = case cmd_path_raw
                            when TLV::PathContainer
                              # PathContainer wrapper
                              {
                                endpoint: cmd_path_raw[0_u8]?,
                                cluster:  cmd_path_raw[1_u8]?,
                                command:  cmd_path_raw[2_u8]?,
                              }
                            when Hash
                              # Direct hash
                              hash = cmd_path_raw.as(Hash(TLV::Tag, TLV::Value))
                              {
                                endpoint: hash[0_u8]?,
                                cluster:  hash[1_u8]?,
                                command:  hash[2_u8]?,
                              }
                            else
                              Log.warn { "Invoke request #{idx} has unexpected commandPath type: #{cmd_path_raw.class}" }
                              next
                            end

            # Convert to proper types
            endpoint = if ep = cmd_path_data[:endpoint]
                         case ep
                         when Int
                           ep.to_u16
                         when UInt16
                           ep
                         else
                           nil
                         end
                       end

            cluster = if cl = cmd_path_data[:cluster]
                        case cl
                        when Int
                          cl.to_u32
                        when UInt32
                          cl
                        else
                          nil
                        end
                      end

            command = if cm = cmd_path_data[:command]
                        case cm
                        when Int
                          cm.to_u32
                        when UInt32
                          cm
                        else
                          nil
                        end
                      end

            unless cluster && command
              Log.warn { "Invoke request #{idx} missing cluster or command" }
              next
            end

            command_path = InteractionModel::CommandPath.new(
              endpoint: endpoint || 0_u16, # Default to endpoint 0 if not specified
              cluster: cluster,
              command: command
            )

            # Extract commandFields (tag 1, optional)
            command_fields = if fields = cmd_data[1_u8]?
                               # Encode the TLV value back to bytes for cluster processing
                               io = IO::Memory.new
                               writer = TLV::Writer.new(io)
                               writer.put(nil, fields)
                               io.rewind.to_slice
                             else
                               Bytes.empty
                             end

            Log.debug { "  Invoke #{idx}: endpoint=#{endpoint || "nil"}, cluster=0x#{cluster.to_s(16)}, command=0x#{command.to_s(16)}, fields=#{command_fields.size} bytes" }

            invoke_requests << InteractionModel::CommandDataIB.new(
              path: command_path,
              fields: command_fields
            )
          end
        end

        InteractionModel::InvokeRequest.new(
          invoke_requests: invoke_requests,
          timed_request: timed_request,
          suppress_response: suppress_response
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse InvokeRequest: #{ex.message}" }
        nil
      end

      # Execute commands from invoke requests
      def self.invoke_commands(
        invoke_requests : Array(InteractionModel::CommandDataIB),
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        session_id : UInt64? = nil,
        is_case_session : Bool = false,
        fabric_index : UInt8? = nil,
      ) : InteractionModel::InvokeResponse
        invoke_responses = [] of InteractionModel::CommandResponse
        invoke_status = [] of InteractionModel::CommandStatus

        invoke_requests.each do |cmd_data|
          path = cmd_data.path
          Log.debug { "Invoking command: endpoint=#{path.endpoint}, cluster=0x#{path.cluster.to_s(16)}, command=0x#{path.command.to_s(16)}" }

          # Find cluster
          endpoint_id = path.endpoint || 0_u16 # Default to endpoint 0 if not specified
          cluster = clusters[{endpoint_id, path.cluster}]?

          unless cluster
            # Cluster not found
            Log.warn { "Cluster not found: endpoint=#{endpoint_id}, cluster=0x#{path.cluster.to_s(16)}" }
            invoke_status << InteractionModel::CommandStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::NotFound)
            )
            next
          end

          # Invoke command on cluster (pass session info for authentication)
          result = cluster.invoke_command(path.command, cmd_data.fields, session_id, is_case_session, fabric_index)

          if result.is_a?(InteractionModel::Status)
            # Error status
            invoke_status << InteractionModel::CommandStatus.new(
              path: path,
              status: result
            )
          elsif result.is_a?(Cluster::CommandResponse)
            # Success - command response data with response command ID
            response_path = InteractionModel::CommandPath.new(
              endpoint: path.endpoint,
              cluster: path.cluster,
              command: result.command_id # Use response command ID from cluster
            )
            invoke_responses << InteractionModel::CommandResponse.new(
              path: response_path,
              fields: result.data
            )
          end
        end

        InteractionModel::InvokeResponse.new(
          invoke_responses: invoke_responses,
          invoke_status: invoke_status,
          suppress_response: false,
          more_chunked_messages: false
        )
      end

      # Encode InvokeResponse manually to preserve PATH container types
      def self.encode_invoke_response(response : InteractionModel::InvokeResponse) : Bytes
        io = IO::Memory.new
        writer = TLV::Writer.new(io)

        # Start root structure (anonymous) - InvokeResponseMessage
        writer.start_structure(nil)

        # Tag 0: suppressResponse (required, even though deprecated)
        writer.put(0_u8, response.suppress_response)

        # Tag 1: invokeResponses (array)
        writer.start_array(1_u8)

        # Add command response data
        response.invoke_responses.each_with_index do |cmd_response, idx|
          begin
            # Parse command response fields
            reader = TLV::Reader.new(cmd_response.fields)
            fields_data = reader.get
            actual_fields = fields_data.is_a?(Hash) && fields_data.has_key?("Any") ? fields_data["Any"] : fields_data

            # Start InvokeResponseIB
            writer.start_structure(nil)

            # Tag 0: CommandDataIB
            writer.start_structure(0_u8)

            # Tag 0: commandPath (using PATH container!)
            writer.start_path(0_u8)
            writer.put(0_u8, cmd_response.path.endpoint) if cmd_response.path.endpoint
            writer.put(1_u8, cmd_response.path.cluster)
            writer.put(2_u8, cmd_response.path.command)
            writer.end_container # End commandPath

            # Tag 1: commandFields (optional)
            unless cmd_response.fields.empty?
              writer.put(1_u8, actual_fields)
            end

            writer.end_container # End CommandDataIB
            writer.end_container # End InvokeResponseIB

            Log.debug { "Encoded command response #{idx}: endpoint=#{cmd_response.path.endpoint}, cluster=0x#{cmd_response.path.cluster.to_s(16)}, command=0x#{cmd_response.path.command.to_s(16)}" }
          rescue ex
            Log.error { "Failed to encode response #{idx}: #{ex.message}" }
          end
        end

        # Add command status entries
        response.invoke_status.each_with_index do |cmd_status, idx|
          begin
            # Start InvokeResponseIB
            writer.start_structure(nil)

            # Tag 1: CommandStatusIB (for errors)
            writer.start_structure(1_u8)

            # Tag 0: commandPath (using PATH container!)
            writer.start_path(0_u8)
            writer.put(0_u8, cmd_status.path.endpoint) if cmd_status.path.endpoint
            writer.put(1_u8, cmd_status.path.cluster)
            writer.put(2_u8, cmd_status.path.command)
            writer.end_container # End commandPath

            # Tag 1: status (StatusIB structure)
            writer.start_structure(1_u8)
            writer.put(0_u8, cmd_status.status.status.value) # Tag 0: status code
            # Tag 1: cluster-status (optional) - not implemented
            writer.end_container # End StatusIB

            writer.end_container # End CommandStatusIB
            writer.end_container # End InvokeResponseIB

            Log.debug { "Encoded command status #{idx}: endpoint=#{cmd_status.path.endpoint}, cluster=0x#{cmd_status.path.cluster.to_s(16)}, command=0x#{cmd_status.path.command.to_s(16)}, status=#{cmd_status.status.status}" }
          rescue ex
            Log.error { "Failed to encode status #{idx}: #{ex.message}" }
          end
        end

        writer.end_container # End invokeResponses array

        # Tag 2: moreChunkedMessages (optional)
        if response.more_chunked_messages
          writer.put(2_u8, true)
        end

        # Tag 0xFF: interactionModelRevision (REQUIRED, Matter 1.3 = revision 12)
        writer.put(0xFF_u8, 12_u8)

        writer.end_container # End root structure

        io.rewind.to_slice
      end
    end
  end
end
