require "./fields"

module Matter
  module Storage
    module Legacy
      # Converts one entry of the legacy `fabrics/fabric_table` JSON string
      # into a `fabrics/<fabric_index>` document.
      module FabricImport
        # Legacy field names.
        FABRIC_ID              = "fabric_id"
        FABRIC_INDEX           = "fabric_index"
        NODE_ID                = "node_id"
        VENDOR_ID              = "vendor_id"
        LABEL                  = "label"
        ROOT_PUBLIC_KEY        = "root_public_key"
        OPERATIONAL_CERT       = "operational_cert"
        OPERATIONAL_KEY        = "operational_key"
        OPERATIONAL_PUBLIC_KEY = "operational_public_key"
        IPK                    = "ipk"
        INTERMEDIATE_CERT      = "intermediate_cert"
        ROOT_CERT              = "root_cert"
        CREATED_AT             = "created_at"
        LAST_USED_AT           = "last_used_at"
        CATS                   = "cats"

        # Target field names that differ from the legacy ones.
        OPERATIONAL_PRIVATE_KEY = "operational_private_key"

        def self.convert(legacy : Document) : Document
          fabric = Document{
            FABRIC_INDEX            => Fields.int64(legacy, FABRIC_INDEX),
            FABRIC_ID               => Fields.integer(legacy, FABRIC_ID),
            NODE_ID                 => Fields.integer(legacy, NODE_ID),
            VENDOR_ID               => Fields.int64(legacy, VENDOR_ID),
            LABEL                   => Fields.string(legacy, LABEL),
            ROOT_PUBLIC_KEY         => Fields.base64(legacy, ROOT_PUBLIC_KEY),
            OPERATIONAL_CERT        => Fields.base64(legacy, OPERATIONAL_CERT),
            OPERATIONAL_PRIVATE_KEY => Fields.base64(legacy, OPERATIONAL_KEY),
            OPERATIONAL_PUBLIC_KEY  => Fields.base64(legacy, OPERATIONAL_PUBLIC_KEY),
            IPK                     => Fields.base64(legacy, IPK),
          }
          if root_cert = Fields.base64?(legacy, ROOT_CERT)
            fabric[ROOT_CERT] = root_cert
          end
          if intermediate_cert = Fields.base64?(legacy, INTERMEDIATE_CERT)
            fabric[INTERMEDIATE_CERT] = intermediate_cert
          end
          fabric[CATS] = cats(Fields.string?(legacy, CATS))
          fabric[CREATED_AT] = Fields.unix_time(legacy, CREATED_AT)
          fabric[LAST_USED_AT] = Fields.unix_time(legacy, LAST_USED_AT)
          fabric
        end

        # `"1234abcd,00000001"` -> `[0x1234abcd, 1]`; `""` or absent -> `[]`.
        private def self.cats(text : String?) : Array(Type)
          return [] of Type if text.nil? || text.empty?

          text.split(Format::LIST_SEPARATOR).map do |hex|
            (hex.to_i64?(Format::HEX_BASE) || raise ImportError.new("Field #{CATS.inspect} is not a comma-separated hex list")).as(Type)
          end
        end
      end
    end
  end
end
