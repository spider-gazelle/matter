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
      Log = ::Log.for("matter.protocol.im_handler")

      private def self.access_control_cluster(clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base)) : Cluster::AccessControlCluster?
        clusters[{0_u16, Cluster::AccessControlCluster::CLUSTER_ID}]?.as?(Cluster::AccessControlCluster)
      end

      private def self.authorized?(
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        required : InteractionModel::EntryPrivilege,
        endpoint_id : UInt16,
        cluster_id : UInt32,
        is_case_session : Bool,
        fabric_index : UInt8?,
        peer_subject_ids : Array(UInt64)?,
      ) : Bool
        return true unless is_case_session
        return false unless fabric_index && peer_subject_ids && peer_subject_ids.size > 0

        acl = access_control_cluster(clusters)
        return true unless acl

        # Recovery path: if a fabric has no ACL entries (e.g., legacy devices that
        # didn't persist ACLs), allow AccessControl reads/writes so the fabric can
        # re-establish its ACL and regain access.
        if acl.get_acl_for_fabric(fabric_index).empty?
          return true if cluster_id == Cluster::AccessControlCluster::CLUSTER_ID
        end

        peer_subject_ids.any? do |subject_id|
          acl.check_access(
            subject: subject_id,
            fabric_index: fabric_index,
            privilege: required,
            cluster: cluster_id,
            endpoint: endpoint_id,
            auth_mode: InteractionModel::EntryAuthMode::Case
          )
        end
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
      def self.parse_read_request(payload : Bytes) : InteractionModel::ReadRequestMessage?
        msg = InteractionModel::ReadRequestMessage.from_slice(payload)

        attribute_requests = msg.attribute_requests || [] of InteractionModel::AttributePath
        Log.debug { "ReadRequest parsed: #{attribute_requests.size} attribute request(s)" }

        attribute_requests.each_with_index do |path, idx|
          Log.debug { "  Request #{idx}: #{path}" }
        end

        msg
      rescue ex
        Log.error(exception: ex) { "Failed to parse ReadRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Read attributes from clusters
      # The fabric_index parameter is used for fabric-scoped attributes like CurrentFabricIndex
      # Returns an array of AttributeReportIB, each containing either data or status
      def self.read_attributes(
        attribute_requests : Array(InteractionModel::AttributePath)?,
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        fabric_index : UInt8? = nil,
        is_case_session : Bool = false,
        peer_subject_ids : Array(UInt64)? = nil,
      ) : Array(InteractionModel::AttributeReportIB)
        attribute_reports = [] of InteractionModel::AttributeReportIB
        requests = attribute_requests || [] of InteractionModel::AttributePath

        requests.each do |path|
          Log.debug { "Reading attribute: #{path}" }

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

              concrete_path = InteractionModel::AttributePath.new(
                endpoint: endpoint_id,
                cluster: cluster_id,
                attribute: attribute_id
              )

              required = cluster.attributes.find { |attr| attr.id.id == attribute_id }.try(&.access) || InteractionModel::EntryPrivilege::View
              unless authorized?(clusters, required, endpoint_id, cluster_id, is_case_session, fabric_index, peer_subject_ids)
                status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::UnsupportedAccess.value)
                attr_status = InteractionModel::AttributeStatusIB.new(path: concrete_path, status: status_ib)
                attribute_reports << InteractionModel::AttributeReportIB.new(attribute_status: attr_status)
                next
              end

              cluster.request_fabric_index = fabric_index
              cluster.request_is_case_session = !fabric_index.nil?
              result = safe_read_attribute(cluster, attribute_id, fabric_index, concrete_path, endpoint_id, cluster_id)
              attribute_reports << build_attribute_report(concrete_path, result, cluster_id, endpoint_id, cluster.data_version)
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
            status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::UnsupportedCluster.value)
            attr_status = InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
            attribute_reports << InteractionModel::AttributeReportIB.new(attribute_status: attr_status)
            next
          end

          required = cluster.attributes.find { |attr| attr.id.id == attribute_id }.try(&.access) || InteractionModel::EntryPrivilege::View
          unless authorized?(clusters, required, endpoint_id, cluster_id, is_case_session, fabric_index, peer_subject_ids)
            status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::UnsupportedAccess.value)
            attr_status = InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
            attribute_reports << InteractionModel::AttributeReportIB.new(attribute_status: attr_status)
            next
          end

          # Read attribute from cluster
          cluster.request_fabric_index = fabric_index
          cluster.request_is_case_session = !fabric_index.nil?
          result = safe_read_attribute(cluster, attribute_id, fabric_index, path, endpoint_id, cluster_id)
          attribute_reports << build_attribute_report(path, result, cluster_id, endpoint_id, cluster.data_version)
        end

        attribute_reports
      end

      private def self.safe_read_attribute(
        cluster : Cluster::Base,
        attribute_id : UInt32,
        fabric_index : UInt8?,
        path : InteractionModel::AttributePath,
        endpoint_id : UInt16,
        cluster_id : UInt32,
      ) : InteractionModel::Status | TLV::Any
        cluster.read_attribute(attribute_id, fabric_index)
      rescue ex
        Log.error(exception: ex) do
          "Failed reading attribute from cluster: #{path}"
        end
        InteractionModel::Status.failure
      end

      # `Cluster::Base#invoke_command` already maps handler exceptions to a
      # status; this guards the protocol layer against a cluster that overrides
      # `invoke_command` itself and lets an exception escape.
      private def self.safe_invoke_command(
        cluster : Cluster::Base,
        path : InteractionModel::CommandPath,
        fields : TLV::Any?,
        session_id : UInt64?,
        is_case_session : Bool,
        fabric_index : UInt8?,
      ) : InteractionModel::Status | Cluster::CommandResponse
        cluster.invoke_command(path.command, fields, session_id, is_case_session, fabric_index)
      rescue ex
        Log.error(exception: ex) do
          "Failed invoking command on cluster: #{path}"
        end
        InteractionModel::Status.failure
      end

      private def self.build_attribute_report(
        path : InteractionModel::AttributePath,
        result : InteractionModel::Status | TLV::Any,
        cluster_id : UInt32,
        endpoint_id : UInt16,
        data_version : UInt32,
      ) : InteractionModel::AttributeReportIB
        if result.is_a?(InteractionModel::Status)
          status_ib = InteractionModel::StatusIB.new(status: result.status.value, cluster_status: result.cluster_status)
          attr_status = InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
          return InteractionModel::AttributeReportIB.new(attribute_status: attr_status)
        end

        attr_data = InteractionModel::AttributeDataIB.new(
          path: path,
          data: result,
          data_version: data_version
        )
        InteractionModel::AttributeReportIB.new(attribute_data: attr_data)
      end

      # Parse WriteRequest from decrypted TLV payload
      def self.parse_write_request(payload : Bytes) : InteractionModel::WriteRequestMessage?
        msg = InteractionModel::WriteRequestMessage.from_slice(payload)

        write_requests = msg.write_requests || [] of InteractionModel::AttributeDataIB
        Log.debug { "WriteRequest parsed: #{write_requests.size} write request(s)" }

        write_requests.each_with_index do |req, idx|
          Log.debug { "  Write #{idx}: #{req.path}" }
        end

        msg
      rescue ex
        Log.error(exception: ex) { "Failed to parse WriteRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Write attributes to clusters
      # Returns array of AttributeStatusIB for each write operation
      def self.write_attributes(
        write_requests : Array(InteractionModel::AttributeDataIB)?,
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        session_id : UInt16? = nil,
        is_case_session : Bool = false,
        fabric_index : UInt8? = nil,
        peer_subject_ids : Array(UInt64)? = nil,
      ) : Array(InteractionModel::AttributeStatusIB)
        write_responses = [] of InteractionModel::AttributeStatusIB
        requests = write_requests || [] of InteractionModel::AttributeDataIB

        requests.each do |request|
          path = request.path
          Log.debug { "Writing attribute: #{path}" }

          # Get endpoint and cluster IDs
          endpoint_id = path.endpoint || 0_u16 # Default to endpoint 0 if not specified
          cluster_id = path.cluster

          unless cluster_id
            status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::InvalidAction.value)
            write_responses << InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
            next
          end

          attribute_id = path.attribute
          unless attribute_id
            status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::InvalidAction.value)
            write_responses << InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
            next
          end

          # Find cluster
          cluster = clusters[{endpoint_id, cluster_id}]?
          unless cluster
            # Cluster not found on this endpoint - return UnsupportedCluster status
            status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::UnsupportedCluster.value)
            write_responses << InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
            next
          end

          if metadata = cluster.get_attribute_metadata(attribute_id)
            unless authorized?(clusters, metadata.write_access, endpoint_id, cluster_id, is_case_session, fabric_index, peer_subject_ids)
              status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::UnsupportedAccess.value)
              write_responses << InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
              next
            end
          end

          cluster.request_session_id = session_id.try(&.to_u64)
          cluster.request_is_case_session = is_case_session
          cluster.request_fabric_index = fabric_index
          cluster.request_peer_node_id = peer_subject_ids.try(&.first?)

          # Preserve the TLV type when passing the attribute to its cluster.
          value = request.data
          status = cluster.write_attribute(attribute_id, value)

          status_ib = InteractionModel::StatusIB.new(status: status.status.value, cluster_status: status.cluster_status)
          write_responses << InteractionModel::AttributeStatusIB.new(path: path, status: status_ib)
        end

        write_responses
      end

      # Parse SubscribeRequest from decrypted TLV payload
      def self.parse_subscribe_request(payload : Bytes) : InteractionModel::SubscribeRequestMessage?
        msg = InteractionModel::SubscribeRequestMessage.from_slice(payload)

        attribute_requests = msg.attribute_requests || [] of InteractionModel::AttributePath
        Log.debug { "SubscribeRequest parsed: #{attribute_requests.size} attribute request(s), min=#{msg.min_interval_floor}s, max=#{msg.max_interval_ceiling}s" }

        attribute_requests.each_with_index do |path, idx|
          Log.debug { "  Request #{idx}: #{path}" }
        end

        msg
      rescue ex
        Log.error(exception: ex) { "Failed to parse SubscribeRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Encode ReportData from array of AttributeReportIB
      # Used for both ReadResponse and initial subscription data
      def self.encode_report_data(
        attribute_reports : Array(InteractionModel::AttributeReportIB),
        subscription_id : UInt32? = nil,
        more_chunked_messages : Bool = false,
        suppress_response : Bool = false,
      ) : Bytes
        report_msg = InteractionModel::ReportDataMessage.new(
          subscription_id: subscription_id,
          attribute_reports: attribute_reports.empty? ? nil : attribute_reports,
          more_chunked_messages: more_chunked_messages ? true : nil,
          suppress_response: suppress_response,
          interaction_model_revision: InteractionModel::INTERACTION_MODEL_REVISION
        )

        report_msg.to_slice
      end

      # Maximum TLV payload size per message (conservative value to stay under IPv6 MTU of 1280)
      # Overhead: UDP header (8) + IPv6 header (40) + Matter packet header (~12) +
      # Matter payload header (~13) + MAC tag (16) = ~89 bytes overhead
      # 1280 - 89 = ~1191 bytes available for TLV payload, use 1100 for safety margin
      MAX_REPORT_PAYLOAD_SIZE = 1100

      # Chunk attributes into multiple ReportData messages that fit within MTU
      # Returns an array of (encoded_bytes, is_last_chunk) tuples
      def self.encode_chunked_report_data(
        attribute_reports : Array(InteractionModel::AttributeReportIB),
        subscription_id : UInt32? = nil,
      ) : Array(Tuple(Bytes, Bool))
        chunks = [] of Tuple(Bytes, Bool)

        # Pre-encode all attribute reports with their sizes
        encoded_reports = [] of Tuple(InteractionModel::AttributeReportIB, Bytes)
        attribute_reports.each do |report|
          encoded_reports << {report, report.to_slice}
        end

        # Calculate base overhead for ReportData structure
        # Structure start (~1) + subscriptionId (~6 if present) + array start (~2) +
        # moreChunkedMessages (~2) + interactionModelRevision (~3) + structure end (~1) = ~15 bytes
        base_overhead = subscription_id ? 20 : 15

        # Current chunk state
        current_reports = [] of InteractionModel::AttributeReportIB
        current_size = base_overhead
        report_index = 0

        # Process all reports
        while report_index < encoded_reports.size
          report, encoded = encoded_reports[report_index]

          if current_size + encoded.size <= MAX_REPORT_PAYLOAD_SIZE
            current_reports << report
            current_size += encoded.size
            report_index += 1
          elsif current_reports.empty?
            # Single report too large - include it anyway (will exceed MTU but necessary)
            Log.warn { "Single attribute report exceeds max payload size (#{encoded.size} bytes)" }
            current_reports << report
            current_size += encoded.size
            report_index += 1
          else
            # Chunk is full, output what we have
            is_last = (report_index >= encoded_reports.size)
            chunk_bytes = encode_report_data(current_reports, subscription_id, more_chunked_messages: !is_last)
            chunks << {chunk_bytes, is_last}

            Log.debug { "Created chunk #{chunks.size}: #{current_reports.size} reports, #{chunk_bytes.size} bytes, more=#{!is_last}" }

            # Reset for next chunk
            current_reports = [] of InteractionModel::AttributeReportIB
            current_size = base_overhead
          end
        end

        # Output final chunk if there's anything left
        if !current_reports.empty?
          chunk_bytes = encode_report_data(current_reports, subscription_id, more_chunked_messages: false)
          chunks << {chunk_bytes, true}

          Log.debug { "Created final chunk #{chunks.size}: #{current_reports.size} reports, #{chunk_bytes.size} bytes" }
        end

        # Edge case: empty response
        if chunks.empty?
          chunk_bytes = encode_report_data([] of InteractionModel::AttributeReportIB, subscription_id)
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
          interaction_model_revision: InteractionModel::INTERACTION_MODEL_REVISION
        )
        msg.to_slice
      end

      # Encode WriteResponse from array of AttributeStatusIB
      def self.encode_write_response(write_responses : Array(InteractionModel::AttributeStatusIB)) : Bytes
        msg = InteractionModel::WriteResponseMessage.new(
          write_responses: write_responses,
          interaction_model_revision: InteractionModel::INTERACTION_MODEL_REVISION
        )
        msg.to_slice
      end

      # Parse InvokeRequest from decrypted TLV payload
      def self.parse_invoke_request(payload : Bytes) : InteractionModel::InvokeRequestMessage?
        msg = InteractionModel::InvokeRequestMessage.from_slice(payload)
        Log.debug { "InvokeRequest parsed: #{msg.invoke_requests.size} invoke request(s)" }

        msg.invoke_requests.each_with_index do |cmd_data, idx|
          path = cmd_data.command_path
          Log.debug { "  Invoke #{idx}: endpoint=#{path.endpoint}, cluster=0x#{path.cluster.to_s(16)}, command=0x#{path.command.to_s(16)}" }
        end

        msg
      rescue ex
        Log.error(exception: ex) { "Failed to parse InvokeRequest (bytes=#{payload.hexstring})" }
        nil
      end

      # Execute commands from invoke requests
      # Returns array of InvokeResponseIB for each command
      def self.invoke_commands(
        invoke_requests : Array(InteractionModel::CommandDataIBTlv),
        clusters : Hash(Tuple(UInt16, UInt32), Cluster::Base),
        session_id : UInt64? = nil,
        is_case_session : Bool = false,
        fabric_index : UInt8? = nil,
        peer_subject_ids : Array(UInt64)? = nil,
      ) : Array(InteractionModel::InvokeResponseIB)
        invoke_responses = [] of InteractionModel::InvokeResponseIB

        invoke_requests.each do |cmd_data|
          path = cmd_data.command_path
          Log.debug { "Invoking command: endpoint=#{path.endpoint}, cluster=0x#{path.cluster.to_s(16)}, command=0x#{path.command.to_s(16)}" }

          # Find cluster
          endpoint_id = path.endpoint || 0_u16 # Default to endpoint 0 if not specified
          cluster = clusters[{endpoint_id, path.cluster}]?

          unless cluster
            # Cluster not found on this endpoint - return UnsupportedCluster status
            Log.warn { "Cluster not found: endpoint=#{endpoint_id}, cluster=0x#{path.cluster.to_s(16)}" }
            status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::UnsupportedCluster.value)
            cmd_status = InteractionModel::CommandStatusIB.new(command_path: path, status: status_ib)
            invoke_responses << InteractionModel::InvokeResponseIB.new(command_status: cmd_status)
            next
          end

          if metadata = cluster.commands.find { |cmd| cmd.id.id == path.command }
            unless authorized?(clusters, metadata.access, endpoint_id, path.cluster, is_case_session, fabric_index, peer_subject_ids)
              status_ib = InteractionModel::StatusIB.new(status: InteractionModel::StatusCode::UnsupportedAccess.value)
              cmd_status = InteractionModel::CommandStatusIB.new(command_path: path, status: status_ib)
              invoke_responses << InteractionModel::InvokeResponseIB.new(command_status: cmd_status)
              next
            end
          end

          result = safe_invoke_command(cluster, path, cmd_data.command_fields, session_id, is_case_session, fabric_index)

          if result.is_a?(InteractionModel::Status)
            # Error status
            status_ib = InteractionModel::StatusIB.new(status: result.status.value, cluster_status: result.cluster_status)
            cmd_status = InteractionModel::CommandStatusIB.new(command_path: path, status: status_ib)
            invoke_responses << InteractionModel::InvokeResponseIB.new(command_status: cmd_status)
          elsif result.is_a?(Cluster::CommandResponse)
            # Success - command response data with response command ID
            response_path = InteractionModel::CommandPath.new(
              endpoint: path.endpoint,
              cluster: path.cluster,
              command: result.command_id # Use response command ID from cluster
            )

            cmd_response = InteractionModel::CommandDataIBTlv.new(
              command_path: response_path,
              command_fields: result.response
            )
            invoke_responses << InteractionModel::InvokeResponseIB.new(command_data: cmd_response)
          end
        end

        invoke_responses
      end

      # Encode InvokeResponse using TLV::Serializable
      # Encode InvokeResponse from array of InvokeResponseIB
      def self.encode_invoke_response(
        invoke_responses : Array(InteractionModel::InvokeResponseIB),
        suppress_response : Bool = false,
      ) : Bytes
        msg = InteractionModel::InvokeResponseMessage.new(
          suppress_response: suppress_response,
          invoke_responses: invoke_responses,
          more_chunked_messages: nil,
          interaction_model_revision: InteractionModel::INTERACTION_MODEL_REVISION
        )
        msg.to_slice
      end
    end
  end
end
