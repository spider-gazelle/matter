module Matter
  module MDNS
    # Matter mDNS service types
    enum ServiceType
      # Commissioning service (_matterc._udp.local)
      # Used when device is in commissioning mode
      Commissioning

      # Operational service (_matter._tcp.local)
      # Used after device has been commissioned
      Operational
    end

    # Helper methods for Matter service names
    module ServiceNames
      extend self

      # Commissioning service name
      COMMISSIONING = "_matterc._udp.local"

      # Operational service name
      OPERATIONAL = "_matter._tcp.local"

      # Service discovery service
      SERVICE_DISCOVERY = "_services._dns-sd._udp.local"

      # Get service name for type
      def service_name(type : ServiceType) : String
        case type
        when .commissioning?
          COMMISSIONING
        when .operational?
          OPERATIONAL
        else
          raise ArgumentError.new("Unknown service type: #{type}")
        end
      end

      # Build instance name for commissioning
      # Format: <device-name>._matterc._udp.local
      def commissioning_instance(device_name : String) : String
        "#{device_name}.#{COMMISSIONING}"
      end

      # Build instance name for operational
      # Format: <compressed-fabric-id>-<node-id>._matter._tcp.local
      def operational_instance(fabric_id : UInt64, node_id : UInt64) : String
        fabric_hex = fabric_id.to_s(16).upcase
        node_hex = node_id.to_s(16).upcase
        "#{fabric_hex}-#{node_hex}.#{OPERATIONAL}"
      end

      # Build hostname
      # Format: <mac-address-hex>.local
      def hostname(mac_address : String) : String
        # Remove colons and make uppercase
        mac_hex = mac_address.gsub(":", "").upcase
        "#{mac_hex}.local"
      end

      # Build vendor subtype
      # Format: _V<vendor-id>._sub._matterc._udp.local
      def vendor_subtype(vendor_id : UInt16) : String
        "_V#{vendor_id}._sub.#{COMMISSIONING}"
      end

      # Build device type subtype
      # Format: _T<device-type>._sub._matterc._udp.local
      def device_type_subtype(device_type : UInt16) : String
        "_T#{device_type}._sub.#{COMMISSIONING}"
      end

      # Build short discriminator subtype (4 bits)
      # Format: _S<short-discriminator>._sub._matterc._udp.local
      def short_discriminator_subtype(discriminator : UInt16) : String
        short = (discriminator >> 8) & 0x0F
        "_S#{short}._sub.#{COMMISSIONING}"
      end

      # Build long discriminator subtype (12 bits)
      # Format: _L<long-discriminator>._sub._matterc._udp.local
      def long_discriminator_subtype(discriminator : UInt16) : String
        long = discriminator & 0x0FFF
        "_L#{long}._sub.#{COMMISSIONING}"
      end

      # Build commissioning mode subtype
      # Format: _CM._sub._matterc._udp.local
      def commissioning_mode_subtype : String
        "_CM._sub.#{COMMISSIONING}"
      end
    end

    # Commissioning information for mDNS advertisement
    struct CommissioningInfo
      property device_name : String
      property vendor_id : UInt16
      property product_id : UInt16
      property discriminator : UInt16
      property device_type : UInt16
      property commissioning_mode : UInt8 # 0=basic, 1=enhanced
      property pairing_hint : UInt16?
      property pairing_instruction : String?

      def initialize(
        @device_name : String,
        @vendor_id : UInt16,
        @product_id : UInt16,
        @discriminator : UInt16,
        @device_type : UInt16,
        @commissioning_mode : UInt8 = 0_u8,
        @pairing_hint : UInt16? = nil,
        @pairing_instruction : String? = nil,
      )
      end

      # Convert to TXT record hash
      def to_txt_records : Hash(String, String)
        records = {
          "VP" => "#{@vendor_id}+#{@product_id}",
          "D"  => @discriminator.to_s,
          "CM" => @commissioning_mode.to_s,
          "DT" => @device_type.to_s,
          "DN" => @device_name,
        }

        if hint = @pairing_hint
          records["PH"] = hint.to_s
        end

        if instruction = @pairing_instruction
          records["PI"] = instruction
        end

        records
      end
    end

    # Operational information for mDNS advertisement
    struct OperationalInfo
      property fabric_id : UInt64
      property node_id : UInt64
      property session_idle_interval : UInt32   # milliseconds
      property session_active_interval : UInt32 # milliseconds
      property tcp_supported : Bool

      def initialize(
        @fabric_id : UInt64,
        @node_id : UInt64,
        @session_idle_interval : UInt32 = 500_u32,
        @session_active_interval : UInt32 = 300_u32,
        @tcp_supported : Bool = false,
      )
      end

      # Convert to TXT record hash
      def to_txt_records : Hash(String, String)
        records = {
          "SII" => @session_idle_interval.to_s,
          "SAI" => @session_active_interval.to_s,
        }

        if @tcp_supported
          records["T"] = "1"
        end

        records
      end
    end
  end
end
