require "../interaction_model/messages"
require "../interaction_model/paths"
require "../interaction_model/status_code"
require "../interaction_model/tlv_messages"
require "../cluster/cluster"
require "../cluster/access_control_cluster"
require "tlv"

module Matter
  module Protocol
    # Helper module for Interaction Model message handling
    module IMHandler
      Log = ::Log.for("matter.im")

      private def self.access_control_cluster(clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base)) : Cluster::AccessControlCluster?
        clusters[{0_u16, Cluster::AccessControlCluster::CLUSTER_ID}]?.as?(Cluster::AccessControlCluster)
      end

      private def self.authorized?(
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        required : Cluster::Definitions::AccessControl::EntryPrivilege,
        endpoint_id : UInt16,
        cluster_id : UInt32,
        is_case_session : Bool,
        fabric_index : UInt8?,
        peer_node_id : UInt64?,
      ) : Bool
        return true unless is_case_session
        return false unless fabric_index && peer_node_id

        acl = access_control_cluster(clusters)
        return true unless acl

        # Recovery path: if a fabric has no ACL entries (e.g., legacy devices that
        # didn't persist ACLs), allow AccessControl reads/writes so the fabric can
        # re-establish its ACL and regain access.
        if acl.get_acl_for_fabric(fabric_index).empty?
          return true if cluster_id == Cluster::AccessControlCluster::CLUSTER_ID
        end

        acl.check_access(
          subject: peer_node_id,
          fabric_index: fabric_index,
          privilege: required,
          cluster: cluster_id,
          endpoint: endpoint_id,
          auth_mode: Cluster::Definitions::AccessControl::EntryAuthMode::Case
        )
      end

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
        msg = InteractionModel::ReadRequestMessage.from_slice(payload)

        attribute_requests = msg.attribute_requests || [] of InteractionModel::AttributePath
        Log.debug { "ReadRequest parsed: #{attribute_requests.size} attribute request(s)" }

        attribute_requests.each_with_index do |path, idx|
          Log.debug { "  Request #{idx}: endpoint=#{path.endpoint || "nil"}, cluster=0x#{path.cluster.try(&.to_s(16)) || "nil"}, attribute=0x#{path.attribute.try(&.to_s(16)) || "nil"}" }
        end

        InteractionModel::ReadRequest.new(
          attribute_requests: attribute_requests,
          fabric_filtered: msg.fabric_filtered || true
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse ReadRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Read attributes from clusters
      # The fabric_index parameter is used for fabric-scoped attributes like CurrentFabricIndex
      def self.read_attributes(
        attribute_requests : Array(InteractionModel::AttributePath),
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        fabric_index : UInt8? = nil,
        is_case_session : Bool = false,
        peer_node_id : UInt64? = nil,
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
                # Track which attributes we've added to avoid duplicates
                added_attrs = Set(UInt32).new

                # Get all attribute IDs from cluster metadata
                cluster.attributes.each do |attr_meta|
                  expanded_paths << {endpoint_id, cluster_id, attr_meta.id.id}
                  added_attrs << attr_meta.id.id
                end

                # Also include global attributes (required on all clusters) if not already added
                [
                  Cluster::Base::GLOBAL_GENERATED_COMMAND_LIST,
                  Cluster::Base::GLOBAL_ACCEPTED_COMMAND_LIST,
                  Cluster::Base::GLOBAL_ATTRIBUTE_LIST,
                  Cluster::Base::GLOBAL_FEATURE_MAP,
                  Cluster::Base::GLOBAL_CLUSTER_REVISION,
                ].each do |global_attr|
                  unless added_attrs.includes?(global_attr)
                    expanded_paths << {endpoint_id, cluster_id, global_attr}
                  end
                end
              else
                # Specific attribute on wildcard endpoint/cluster
                expanded_paths << {endpoint_id, cluster_id, path.attribute.as(UInt32)}
              end
            end

            Log.debug { "Expanded wildcard to #{expanded_paths.size} concrete paths" }

            # Read each expanded path
            expanded_paths.each do |(endpoint_id, cluster_id, attribute_id)|
              cluster = clusters[{endpoint_id, cluster_id}]
              next unless cluster

              required = cluster.attributes.find { |attr| attr.id.id == attribute_id }.try(&.access) || Cluster::Definitions::AccessControl::EntryPrivilege::View
              unless authorized?(clusters, required, endpoint_id, cluster_id, is_case_session, fabric_index, peer_node_id)
                concrete_path = InteractionModel::AttributePath.new(
                  endpoint: endpoint_id,
                  cluster: cluster_id,
                  attribute: attribute_id
                )
                attribute_status << InteractionModel::AttributeStatus.new(
                  path: concrete_path,
                  status: InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAccess)
                )
                next
              end

              cluster.request_fabric_index = fabric_index
              cluster.request_is_case_session = !fabric_index.nil?
              result = cluster.read_attribute(attribute_id, fabric_index)
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
          endpoint_id = path.endpoint.as(UInt16)
          cluster_id = path.cluster.as(UInt32)
          attribute_id = path.attribute.as(UInt32)

          # Find cluster
          cluster = clusters[{endpoint_id, cluster_id}]?
          unless cluster
            # Cluster not found on this endpoint - return UnsupportedCluster status
            # Per Matter spec, NotFound should only be used for missing endpoints,
            # UnsupportedCluster is correct for missing clusters on a valid endpoint
            attribute_status << InteractionModel::AttributeStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCluster)
            )
            next
          end

          required = cluster.attributes.find { |attr| attr.id.id == attribute_id }.try(&.access) || Cluster::Definitions::AccessControl::EntryPrivilege::View
          unless authorized?(clusters, required, endpoint_id, cluster_id, is_case_session, fabric_index, peer_node_id)
            attribute_status << InteractionModel::AttributeStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAccess)
            )
            next
          end

          # Read attribute from cluster
          cluster.request_fabric_index = fabric_index
          cluster.request_is_case_session = !fabric_index.nil?
          result = cluster.read_attribute(attribute_id, fabric_index)

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

      # Encode ReadResponse using TLV::Serializable structs
      def self.encode_read_response(response : InteractionModel::ReadResponse) : Bytes
        attribute_reports = [] of InteractionModel::AttributeReportIB

        # Convert attribute data reports
        response.attribute_reports.each_with_index do |report, idx|
          begin
            # Validate attribute value
            if report.value.empty?
              Log.warn { "Skipping empty report #{idx}" }
              next
            end

            # IMPORTANT: Response paths MUST always have concrete endpoint/cluster/attribute
            ep = report.path.endpoint
            cl = report.path.cluster
            at = report.path.attribute
            unless ep && cl && at
              Log.warn { "Skipping report #{idx} with incomplete path: endpoint=#{ep}, cluster=#{cl}, attribute=#{at}" }
              next
            end

            # Create the path
            path = InteractionModel::AttributePath.new(
              endpoint: ep,
              cluster: cl,
              attribute: at
            )

            # Parse the raw value bytes as TLV::Any to preserve encoding
            data = TLV::Any.from_slice(report.value)

            # Create AttributeDataIB
            attr_data = InteractionModel::AttributeDataIB.new(
              path: path,
              data: data,
              data_version: report.data_version
            )

            # Wrap in AttributeReportIB
            attribute_reports << InteractionModel::AttributeReportIB.new(
              attribute_data: attr_data
            )

            Log.debug { "Encoded attribute report #{idx}: endpoint=#{ep}, cluster=0x#{cl.to_s(16)}, attr=0x#{at.to_s(16)}" }
          rescue ex
            Log.error(exception: ex) { "Failed to encode report #{idx} (path=#{report.path.inspect} value_hex=#{report.value.hexstring})" }
          end
        end

        # Convert attribute status entries (errors)
        response.attribute_status.each_with_index do |status, idx|
          begin
            ep = status.path.endpoint
            cl = status.path.cluster
            at = status.path.attribute
            unless ep && cl && at
              Log.warn { "Skipping status #{idx} with incomplete path: endpoint=#{ep}, cluster=#{cl}, attribute=#{at}" }
              next
            end

            # Create the path
            path = InteractionModel::AttributePath.new(
              endpoint: ep,
              cluster: cl,
              attribute: at
            )

            # Create StatusIB
            status_ib = InteractionModel::StatusIB.new(
              status: status.status.status.value
            )

            # Create AttributeStatusIB
            attr_status = InteractionModel::AttributeStatusIB.new(
              path: path,
              status: status_ib
            )

            # Wrap in AttributeReportIB
            attribute_reports << InteractionModel::AttributeReportIB.new(
              attribute_status: attr_status
            )

            Log.debug { "Encoded attribute status #{idx}: endpoint=#{ep}, cluster=0x#{cl.to_s(16)}, attr=0x#{at.to_s(16)}, status=#{status.status.status}" }
          rescue ex
            Log.error(exception: ex) { "Failed to encode status #{idx} (path=#{status.path.inspect} status=#{status.status.status})" }
          end
        end

        # Build ReportDataMessage
        report_msg = InteractionModel::ReportDataMessage.new(
          attribute_reports: attribute_reports.empty? ? nil : attribute_reports,
          more_chunked_messages: response.more_chunks? ? true : nil,
          suppress_response: response.suppress_response? ? true : nil,
          interaction_model_revision: 12_u8
        )

        report_msg.to_slice
      end

      # Parse WriteRequest from decrypted TLV payload
      def self.parse_write_request(payload : Bytes) : InteractionModel::WriteRequest?
        parsed = TLV::Any.from_slice(payload)
        request_data = parsed.value.as(TLV::Structure)

        Log.debug { "WriteRequest TLV structure: #{request_data.keys.inspect}" }

        # Extract suppressResponse (tag 0, optional, defaults to false)
        suppress_response = if sr_any = request_data[0_u8]?
                              sr_any.value.as?(Bool) || false
                            else
                              false
                            end

        # Extract timedRequest (tag 1, required)
        timed_request = if tr_any = request_data[1_u8]?
                          tr_any.value.as?(Bool) || false
                        else
                          false
                        end

        # Extract writeRequests (tag 2, array of AttributeDataIB)
        write_requests = [] of InteractionModel::AttributeWriteRequest
        if write_req_any = request_data[2_u8]?
          write_req_list = write_req_any.value.as(TLV::List)
          Log.debug { "Found #{write_req_list.size} write request(s)" }

          write_req_list.each_with_index do |write_req_elem, idx|
            # Extract AttributeDataIB structure
            attr_data = write_req_elem.value.as?(TLV::Structure)
            next unless attr_data

            # Extract dataVersion (tag 0, optional)
            data_version = if dv_any = attr_data[0_u8]?
                             case dv = dv_any.value
                             when Int
                               dv.to_u32
                             when UInt32
                               dv
                             else
                               nil
                             end
                           end

            # Extract path (tag 1, PATH/LIST container with endpoint/cluster/attribute)
            path_any = attr_data[1_u8]?
            unless path_any
              Log.warn { "Write request #{idx} missing path" }
              next
            end

            # Parse path using AttributePath TLV::Serializable
            path = InteractionModel::AttributePath.from_slice(path_any.to_slice)

            unless path.cluster && path.attribute
              Log.warn { "Write request #{idx} missing cluster or attribute" }
              next
            end

            # Extract data (tag 2)
            value = if value_any = attr_data[2_u8]?
                      # Use to_slice directly since value_any is already TLV::Any
                      value_any.to_slice
                    else
                      Bytes.empty
                    end

            Log.debug { "  Write #{idx}: endpoint=#{path.endpoint || "nil"}, cluster=0x#{path.cluster.try(&.to_s(16)) || "nil"}, attribute=0x#{path.attribute.try(&.to_s(16)) || "nil"}, value=#{value.size} bytes" }

            write_requests << InteractionModel::AttributeWriteRequest.new(
              path: path,
              value: value,
              data_version: data_version
            )
          end
        end

        # Extract moreChunkedMessages (tag 3, optional, defaults to false)
        more_chunked_messages = if mc_any = request_data[3_u8]?
                                  mc_any.value.as?(Bool) || false
                                else
                                  false
                                end

        InteractionModel::WriteRequest.new(
          write_requests: write_requests,
          timed_request: timed_request,
          suppress_response: suppress_response,
          more_chunked_messages: more_chunked_messages
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse WriteRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Write attributes to clusters
      def self.write_attributes(
        write_requests : Array(InteractionModel::AttributeWriteRequest),
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        session_id : UInt16? = nil,
        is_case_session : Bool = false,
        fabric_index : UInt8? = nil,
        peer_node_id : UInt64? = nil,
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
            # Cluster not found on this endpoint - return UnsupportedCluster status
            # Per Matter spec, NotFound should only be used for missing endpoints
            write_responses << InteractionModel::AttributeStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCluster)
            )
            next
          end

          if metadata = cluster.attributes.find { |attr| attr.id.id == attribute_id }
            unless authorized?(clusters, metadata.access, endpoint_id, cluster_id, is_case_session, fabric_index, peer_node_id)
              write_responses << InteractionModel::AttributeStatus.new(
                path: path,
                status: InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAccess)
              )
              next
            end
          end

          cluster.request_session_id = session_id.try(&.to_u64)
          cluster.request_is_case_session = is_case_session
          cluster.request_fabric_index = fabric_index
          cluster.request_peer_node_id = peer_node_id

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
        parsed = TLV::Any.from_slice(payload)
        request_data = parsed.value.as(TLV::Structure)

        Log.debug { "SubscribeRequest TLV structure: #{request_data.keys.inspect}" }

        # Extract keepSubscriptions (tag 0, required)
        keep_subscriptions = if ks_any = request_data[0_u8]?
                               ks_any.value.as?(Bool) || false
                             else
                               false
                             end

        # Extract minIntervalFloorSeconds (tag 1, required)
        min_interval_floor = if mi_any = request_data[1_u8]?
                               case mi = mi_any.value
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
        max_interval_ceiling = if mx_any = request_data[2_u8]?
                                 case mx = mx_any.value
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
        if attr_req_any = request_data[3_u8]?
          attr_req_list = attr_req_any.value.as(TLV::List)
          Log.debug { "Found #{attr_req_list.size} attribute request(s)" }

          attr_req_list.each_with_index do |attr_req_elem, idx|
            # Parse path using AttributePath TLV::Serializable
            path = InteractionModel::AttributePath.from_slice(attr_req_elem.to_slice)

            Log.debug { "  Request #{idx}: endpoint=#{path.endpoint || "nil"}, cluster=0x#{path.cluster.try(&.to_s(16)) || "nil"}, attribute=0x#{path.attribute.try(&.to_s(16)) || "nil"}" }

            attribute_requests << path
          end
        end

        # Extract isFabricFiltered (tag 7, required)
        fabric_filtered = if ff_any = request_data[7_u8]?
                            ff_any.value.as?(Bool) || true
                          else
                            true
                          end

        InteractionModel::SubscribeRequest.new(
          attribute_requests: attribute_requests,
          fabric_filtered: fabric_filtered,
          min_interval_floor: min_interval_floor,
          max_interval_ceiling: max_interval_ceiling,
          keep_subscriptions: keep_subscriptions
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse SubscribeRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Encode ReportData (used for both ReadResponse and initial subscription data)
      def self.encode_report_data(
        response : InteractionModel::ReadResponse,
        subscription_id : UInt32? = nil,
      ) : Bytes
        attribute_reports = [] of InteractionModel::AttributeReportIB

        # Convert attribute data reports
        response.attribute_reports.each_with_index do |report, idx|
          begin
            if report.value.empty?
              Log.warn { "Skipping empty report #{idx}" }
              next
            end

            ep = report.path.endpoint
            cl = report.path.cluster
            at = report.path.attribute
            unless ep && cl && at
              Log.error { "Skipping report #{idx} with incomplete path: endpoint=#{ep}, cluster=#{cl}, attribute=#{at}" }
              next
            end

            path = InteractionModel::AttributePath.new(endpoint: ep, cluster: cl, attribute: at)
            data = TLV::Any.from_slice(report.value)

            attr_data = InteractionModel::AttributeDataIB.new(
              path: path,
              data: data,
              data_version: report.data_version
            )

            attribute_reports << InteractionModel::AttributeReportIB.new(attribute_data: attr_data)
            Log.debug { "Encoded attribute report #{idx}: endpoint=#{ep}, cluster=0x#{cl.to_s(16)}, attr=0x#{at.to_s(16)}" }
          rescue ex
            Log.error(exception: ex) { "Failed to encode report #{idx} (path=#{report.path.inspect} value_hex=#{report.value.hexstring})" }
          end
        end

        # Convert attribute status entries (errors)
        response.attribute_status.each_with_index do |status, idx|
          begin
            path = InteractionModel::AttributePath.new(
              endpoint: status.path.endpoint,
              cluster: status.path.cluster,
              attribute: status.path.attribute
            )

            status_ib = InteractionModel::StatusIB.new(status: status.status.status.value)
            attr_status = InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)

            attribute_reports << InteractionModel::AttributeReportIB.new(attribute_status: attr_status)
            Log.debug { "Encoded attribute status #{idx}: endpoint=#{status.path.endpoint}, cluster=0x#{status.path.cluster.try(&.to_s(16))}, attr=#{status.path.attribute}, status=#{status.status.status}" }
          rescue ex
            Log.error(exception: ex) { "Failed to encode status #{idx} (path=#{status.path.inspect} status=#{status.status.status})" }
          end
        end

        # Build ReportDataMessage
        # For subscription updates with data, suppress_response should be false
        # to ensure the client sends a StatusResponse
        report_msg = InteractionModel::ReportDataMessage.new(
          subscription_id: subscription_id,
          attribute_reports: attribute_reports.empty? ? nil : attribute_reports,
          more_chunked_messages: response.more_chunks? ? true : nil,
          suppress_response: response.suppress_response?,
          interaction_model_revision: 12_u8
        )

        report_msg.to_slice
      end

      # Maximum TLV payload size per message (conservative value to stay under IPv6 MTU of 1280)
      # Overhead: UDP header (8) + IPv6 header (40) + Matter packet header (~12) +
      # Matter payload header (~13) + MAC tag (16) = ~89 bytes overhead
      # 1280 - 89 = ~1191 bytes available for TLV payload, use 1100 for safety margin
      MAX_REPORT_PAYLOAD_SIZE = 1100

      # Encode a single attribute report to TLV bytes (for size estimation)
      private def self.encode_single_attribute_report(report : InteractionModel::AttributeData) : Bytes?
        return nil if report.value.empty?

        # Response paths MUST have concrete endpoint/cluster/attribute
        ep = report.path.endpoint
        cl = report.path.cluster
        at = report.path.attribute
        return nil unless ep && cl && at

        path = InteractionModel::AttributePath.new(endpoint: ep, cluster: cl, attribute: at)
        data = TLV::Any.from_slice(report.value)

        attr_data = InteractionModel::AttributeDataIB.new(
          path: path,
          data: data,
          data_version: report.data_version
        )

        report_ib = InteractionModel::AttributeReportIB.new(attribute_data: attr_data)
        report_ib.to_slice
      rescue
        nil
      end

      # Encode a single attribute status to TLV bytes (for size estimation)
      private def self.encode_single_attribute_status(status : InteractionModel::AttributeStatus) : Bytes
        path = InteractionModel::AttributePath.new(
          endpoint: status.path.endpoint,
          cluster: status.path.cluster,
          attribute: status.path.attribute
        )

        status_ib = InteractionModel::StatusIB.new(status: status.status.status.value)
        attr_status = InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)

        report_ib = InteractionModel::AttributeReportIB.new(attribute_status: attr_status)
        report_ib.to_slice
      end

      # Chunk attributes into multiple ReportData messages that fit within MTU
      # Returns an array of (encoded_bytes, is_last_chunk) tuples
      def self.encode_chunked_report_data(
        response : InteractionModel::ReadResponse,
        subscription_id : UInt32? = nil,
      ) : Array(Tuple(Bytes, Bool))
        chunks = [] of Tuple(Bytes, Bool)

        # Pre-encode all attribute reports and statuses with their sizes
        encoded_reports = [] of Tuple(InteractionModel::AttributeData, Bytes)
        response.attribute_reports.each do |report|
          if encoded = encode_single_attribute_report(report)
            encoded_reports << {report, encoded}
          end
        end

        encoded_statuses = [] of Tuple(InteractionModel::AttributeStatus, Bytes)
        response.attribute_status.each do |status|
          encoded_statuses << {status, encode_single_attribute_status(status)}
        end

        # Calculate base overhead for ReportData structure
        # Structure start (~1) + subscriptionId (~6 if present) + array start (~2) +
        # moreChunkedMessages (~2) + interactionModelRevision (~3) + structure end (~1) = ~15 bytes
        base_overhead = subscription_id ? 20 : 15

        # Current chunk state
        current_reports = [] of InteractionModel::AttributeData
        current_statuses = [] of InteractionModel::AttributeStatus
        current_size = base_overhead

        report_index = 0
        status_index = 0

        # Process all reports and statuses
        while report_index < encoded_reports.size || status_index < encoded_statuses.size
          # Try to add the next report
          if report_index < encoded_reports.size
            report, encoded = encoded_reports[report_index]

            if current_size + encoded.size <= MAX_REPORT_PAYLOAD_SIZE
              current_reports << report
              current_size += encoded.size
              report_index += 1
              next
            elsif current_reports.empty? && current_statuses.empty?
              # Single report too large - include it anyway (will exceed MTU but necessary)
              Log.warn { "Single attribute report exceeds max payload size (#{encoded.size} bytes)" }
              current_reports << report
              current_size += encoded.size
              report_index += 1
            end
          end

          # Try to add the next status
          if status_index < encoded_statuses.size && report_index >= encoded_reports.size
            status, encoded = encoded_statuses[status_index]

            if current_size + encoded.size <= MAX_REPORT_PAYLOAD_SIZE
              current_statuses << status
              current_size += encoded.size
              status_index += 1
              next
            elsif current_reports.empty? && current_statuses.empty?
              # Single status too large - include it anyway
              Log.warn { "Single attribute status exceeds max payload size (#{encoded.size} bytes)" }
              current_statuses << status
              current_size += encoded.size
              status_index += 1
            end
          end

          # Chunk is full or we need to output what we have
          if !current_reports.empty? || !current_statuses.empty?
            is_last = (report_index >= encoded_reports.size && status_index >= encoded_statuses.size)

            chunk_response = InteractionModel::ReadResponse.new(
              attribute_reports: current_reports,
              attribute_status: current_statuses,
              more_chunks: !is_last
            )

            chunk_bytes = encode_report_data(chunk_response, subscription_id)
            chunks << {chunk_bytes, is_last}

            Log.debug { "Created chunk #{chunks.size}: #{current_reports.size} reports, #{current_statuses.size} statuses, #{chunk_bytes.size} bytes, more=#{!is_last}" }

            # Reset for next chunk
            current_reports = [] of InteractionModel::AttributeData
            current_statuses = [] of InteractionModel::AttributeStatus
            current_size = base_overhead
          end
        end

        # Output final chunk if there's anything left
        if !current_reports.empty? || !current_statuses.empty?
          chunk_response = InteractionModel::ReadResponse.new(
            attribute_reports: current_reports,
            attribute_status: current_statuses,
            more_chunks: false
          )

          chunk_bytes = encode_report_data(chunk_response, subscription_id)
          chunks << {chunk_bytes, true}

          Log.debug { "Created final chunk #{chunks.size}: #{current_reports.size} reports, #{current_statuses.size} statuses, #{chunk_bytes.size} bytes" }
        end

        # Edge case: empty response
        if chunks.empty?
          empty_response = InteractionModel::ReadResponse.new(more_chunks: false)
          chunk_bytes = encode_report_data(empty_response, subscription_id)
          chunks << {chunk_bytes, true}
          Log.debug { "Created empty chunk: #{chunk_bytes.size} bytes" }
        end

        Log.debug { "Total chunks: #{chunks.size}" }
        chunks
      end

      # Encode SubscribeResponse
      def self.encode_subscribe_response(
        subscription_id : UInt32,
        max_interval : UInt16,
      ) : Bytes
        msg = InteractionModel::SubscribeResponseMessage.new(
          subscription_id: subscription_id,
          max_interval: max_interval,
          interaction_model_revision: 12_u8
        )
        msg.to_slice
      end

      # Encode WriteResponse using TLV::Serializable
      def self.encode_write_response(response : InteractionModel::WriteResponse) : Bytes
        write_responses = response.write_responses.compact_map do |status|
          # Response paths MUST have concrete endpoint/cluster/attribute
          ep = status.path.endpoint
          cl = status.path.cluster
          at = status.path.attribute
          next unless ep && cl && at

          path = InteractionModel::AttributePath.new(
            endpoint: ep,
            cluster: cl,
            attribute: at
          )
          status_ib = InteractionModel::StatusIB.new(status: status.status.status.value)
          InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
        end

        msg = InteractionModel::WriteResponseMessage.new(
          write_responses: write_responses,
          interaction_model_revision: 12_u8
        )
        msg.to_slice
      end

      # Parse InvokeRequest from decrypted TLV payload
      def self.parse_invoke_request(payload : Bytes) : InteractionModel::InvokeRequest?
        msg = InteractionModel::InvokeRequestMessage.from_slice(payload)
        Log.debug { "InvokeRequest parsed: #{msg.invoke_requests.size} invoke request(s)" }

        invoke_requests = msg.invoke_requests.compact_map do |cmd_data|
          path = cmd_data.command_path
          cluster = path.cluster
          command = path.command

          command_path = InteractionModel::CommandPath.new(
            endpoint: path.endpoint,
            cluster: cluster,
            command: command
          )

          # Convert command fields TLV::Any to bytes for cluster processing
          command_fields = if fields = cmd_data.command_fields
                             fields.to_slice
                           else
                             Bytes.empty
                           end

          Log.debug { "  Invoke: endpoint=#{path.endpoint}, cluster=0x#{cluster.to_s(16)}, command=0x#{command.to_s(16)}, fields=#{command_fields.size} bytes" }

          InteractionModel::CommandDataIB.new(
            path: command_path,
            fields: command_fields
          )
        end

        InteractionModel::InvokeRequest.new(
          invoke_requests: invoke_requests,
          timed_request: msg.timed_request || false,
          suppress_response: msg.suppress_response || false
        )
      rescue ex
        Log.error(exception: ex) { "Failed to parse InvokeRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Execute commands from invoke requests
      def self.invoke_commands(
        invoke_requests : Array(InteractionModel::CommandDataIB),
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        session_id : UInt64? = nil,
        is_case_session : Bool = false,
        fabric_index : UInt8? = nil,
        peer_node_id : UInt64? = nil,
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
            # Cluster not found on this endpoint - return UnsupportedCluster status
            Log.warn { "Cluster not found: endpoint=#{endpoint_id}, cluster=0x#{path.cluster.to_s(16)}" }
            invoke_status << InteractionModel::CommandStatus.new(
              path: path,
              status: InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedCluster)
            )
            next
          end

          if metadata = cluster.commands.find { |cmd| cmd.id.id == path.command }
            unless authorized?(clusters, metadata.access, endpoint_id, path.cluster, is_case_session, fabric_index, peer_node_id)
              invoke_status << InteractionModel::CommandStatus.new(
                path: path,
                status: InteractionModel::Status.new(InteractionModel::StatusCode::UnsupportedAccess)
              )
              next
            end
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

      # Encode InvokeResponse using TLV::Serializable
      def self.encode_invoke_response(response : InteractionModel::InvokeResponse) : Bytes
        invoke_responses = [] of InteractionModel::InvokeResponseIB

        # Add command response data
        response.invoke_responses.each do |cmd_response|
          command_path = InteractionModel::CommandPath.new(
            endpoint: cmd_response.path.endpoint || 0_u16,
            cluster: cmd_response.path.cluster,
            command: cmd_response.path.command
          )

          # Parse command fields if present
          command_fields = unless cmd_response.fields.empty?
            TLV::Any.from_slice(cmd_response.fields)
          end

          command_data = InteractionModel::CommandDataIBTlv.new(
            command_path: command_path,
            command_fields: command_fields
          )

          invoke_responses << InteractionModel::InvokeResponseIB.new(command_data: command_data)
        end

        # Add command status entries
        response.invoke_status.each do |cmd_status|
          command_path = InteractionModel::CommandPath.new(
            endpoint: cmd_status.path.endpoint || 0_u16,
            cluster: cmd_status.path.cluster,
            command: cmd_status.path.command
          )
          status_ib = InteractionModel::StatusIB.new(status: cmd_status.status.status.value)
          command_status = InteractionModel::CommandStatusIB.new(
            command_path: command_path,
            status: status_ib
          )

          invoke_responses << InteractionModel::InvokeResponseIB.new(command_status: command_status)
        end

        msg = InteractionModel::InvokeResponseMessage.new(
          suppress_response: response.suppress_response?,
          invoke_responses: invoke_responses,
          more_chunked_messages: response.more_chunked_messages? ? true : nil,
          interaction_model_revision: 12_u8
        )
        msg.to_slice
      end
    end
  end
end
