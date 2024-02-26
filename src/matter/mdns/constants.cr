module Matter
  module MDNS
    module Constants
      SERVICE_DISCOVERY_QNAME           = "_services._dns-sd._udp.local"
      MATTER_COMMISSION_SERVICE_QNAME   = "_matterc._udp.local"
      MATTER_COMMISSIONER_SERVICE_QNAME = "_matterd._udp.local"
      MATTER_SERVICE_QNAME              = "_matter._tcp.local"

      def get_fabric_qname(operational_id_string : String) : String
        "_I#{operational_id_string}._sub.#{MATTER_SERVICE_QNAME}"
      end

      def get_device_matter_qname(operational_id_string : String, node_id_string : String) : String
        "#{operationalIdString}-#{nodeIdString}.#{MATTER_SERVICE_QNAME}"
      end

      def get_vendor_qname(vendor_id : DataType::VendorId) : String
        "_V#{vendor_id.id}._sub.#{MATTER_COMMISSION_SERVICE_QNAME}"
      end

      def get_device_type_qname(device_type : Int) : String
        "_T#{device_type}._sub.#{MATTER_COMMISSION_SERVICE_QNAME}"
      end

      def get_short_discriminator_qname(short_discriminator : Int) : String
        "_S#{short_discriminator}._sub.#{MATTER_COMMISSION_SERVICE_QNAME}"
      end

      def get_long_discriminator_qname(long_discriminator : Int) : String
        "_L#{long_discriminator}._sub.#{MATTER_COMMISSION_SERVICE_QNAME}"
      end

      def get_commissioning_mode_qname : String
        "_CM._sub.#{MATTER_COMMISSION_SERVICE_QNAME}"
      end

      def get_device_instance_qname(instance_id : String) : String
        "#{instance_id}.#{MATTER_COMMISSION_SERVICE_QNAME}"
      end
    end
  end
end
