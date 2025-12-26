require "json"

require "../../cluster/access_control_cluster"

module Matter
  module Controller
    module Clusters
      module AccessControl
        alias Entry = Matter::Cluster::AccessControlCluster::AccessControlEntry
        alias Target = Matter::Cluster::AccessControlCluster::Target
        alias Privilege = Matter::Cluster::AccessControlCluster::AccessControlEntryPrivilege
        alias AuthMode = Matter::Cluster::AccessControlCluster::AccessControlEntryAuthMode

        # Parses the JSON format used by CHIP's `chip-tool accesscontrol write acl ...`
        # and returns entries suitable for encoding into a TLV list for WriteRequest.
        #
        # Supported keys:
        # - privilege (UInt8)
        # - authMode (UInt8)
        # - subjects (array of UInt64)
        # - targets (null or array of {endpoint, cluster, deviceType})
        # - fabricIndex (ignored; server derives from session)
        def self.parse_acl_json(json : String) : Array(Entry)
          root = JSON.parse(json)
          arr = root.as_a

          mapped = arr.each_with_index.map do |obj, idx|
            begin
              h = obj.as_h
              privilege = Privilege.from_value(h["privilege"].as_i64.to_i)
              auth_mode = AuthMode.from_value(h["authMode"].as_i64.to_i)

              subjects = h["subjects"].as_a.map do |v|
                v.as_i64.to_u64
              end

              targets = begin
                t = h["targets"]?
                if t.nil? || t.raw.nil?
                  nil
                else
                  t.as_a.map do |tg|
                    th = tg.as_h
                    Target.new(
                      cluster: th["cluster"]?.try { |x| x.raw.nil? ? nil : x.as_i64.to_u32 },
                      endpoint: th["endpoint"]?.try { |x| x.raw.nil? ? nil : x.as_i64.to_u16 },
                      device_type: th["deviceType"]?.try { |x| x.raw.nil? ? nil : x.as_i64.to_u32 }
                    )
                  end
                end
              end

              Entry.new(
                privilege: privilege,
                auth_mode: auth_mode,
                subjects: subjects,
                targets: targets,
                fabric_index: nil
              )
            rescue ex
              raise ArgumentError.new("Invalid ACL JSON entry at index #{idx}: #{ex.message}")
            end
          end

          mapped.to_a
        end

        def self.encode_acl_tlv(entries : Array(Entry)) : Bytes
          entries.to_tlv
        end
      end
    end
  end
end
