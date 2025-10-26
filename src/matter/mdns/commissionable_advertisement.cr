require "dns"
require "random"
require "./server"
require "./service_description"

module Matter
  module MDNS
    # Advertisement for a commissionable Matter device
    #
    # Generates DNS-SD records for _matterc._udp.local service type
    # Matter Core Spec §4.3.1: Commissionable Node Discovery
    class CommissionableAdvertisement < RecordGenerator
      Log = ::Log.for("matter.mdns.advertisement.commissionable")

      # Service constants
      SERVICE_TYPE    = "_matterc._udp.local"
      MATTER_PORT     = 5540_u16
      DEFAULT_TTL     = 120.seconds # 2 minutes (RFC 6762 recommends 75 minutes, but Matter uses shorter)
      HOSTNAME_SUFFIX = ".local"

      property description : CommissionableServiceDescription
      property instance_id : String
      property hostname : String
      property addresses : Array(String) # IPv4/IPv6 addresses

      def initialize(@description : CommissionableServiceDescription, @addresses : Array(String))
        # Generate random 8-byte instance ID (16 hex characters)
        @instance_id = Random::Secure.hex(8).upcase

        # Generate hostname from instance ID
        @hostname = "#{@instance_id}#{HOSTNAME_SUFFIX}"

        Log.info { "Created advertisement: instance=#{@instance_id}, name=#{@description.name}" }
      end

      # Get the service instance name
      def instance_name : String
        "#{@instance_id}.#{SERVICE_TYPE}"
      end

      # Generate all DNS records for this service
      def records : Array(DNS::Packet::ResourceRecord)
        records = [] of DNS::Packet::ResourceRecord

        # PTR records (service enumeration)
        records.concat(ptr_records)

        # SRV record (hostname + port)
        records << srv_record

        # TXT record (device properties)
        records << txt_record

        # A/AAAA records (IP addresses)
        records.concat(address_records)

        records
      end

      # Query names this generator responds to
      def queries_handled : Array(String)
        [
          SERVICE_TYPE,
          device_type_subtype,
          short_discriminator_subtype,
          long_discriminator_subtype,
          commissioning_mode_subtype,
          vendor_subtype,
        ]
      end

      # Generate PTR records for service browsing
      private def ptr_records : Array(DNS::Packet::ResourceRecord)
        records = [] of DNS::Packet::ResourceRecord

        # Main service type: _matterc._udp.local
        records << create_ptr_record(SERVICE_TYPE, instance_name)

        # Device type sub-type: _T<deviceType>._sub._matterc._udp.local
        records << create_ptr_record(device_type_subtype, instance_name)

        # Short discriminator sub-type: _S<shortDiscriminator>._sub._matterc._udp.local
        records << create_ptr_record(short_discriminator_subtype, instance_name)

        # Long discriminator sub-type: _L<longDiscriminator>._sub._matterc._udp.local
        records << create_ptr_record(long_discriminator_subtype, instance_name)

        # Commissioning mode sub-type: _CM._sub._matterc._udp.local
        records << create_ptr_record(commissioning_mode_subtype, instance_name)

        # Vendor sub-type: _V<vendorId>._sub._matterc._udp.local
        records << create_ptr_record(vendor_subtype, instance_name)

        records
      end

      # Create a PTR record
      private def create_ptr_record(name : String, target : String) : DNS::Packet::ResourceRecord
        # Build PTR resource data (domain name)
        resource_data = encode_domain_name(target)

        DNS::Packet::ResourceRecord.new(
          name: name,
          type: DNS::RecordType::PTR.value,
          class_code: DNS::ClassCode::Internet.value,
          ttl: DEFAULT_TTL,
          resource_data: resource_data
        )
      end

      # Encode a domain name in DNS format (length-prefixed labels)
      private def encode_domain_name(domain : String) : Bytes
        io = IO::Memory.new
        domain.split('.').each do |label|
          io.write_byte(label.size.to_u8)
          io.write(label.to_slice)
        end
        io.write_byte(0_u8) # Null terminator
        io.to_slice
      end

      # Generate SRV record (hostname + port)
      private def srv_record : DNS::Packet::ResourceRecord
        # Build SRV resource data: priority (2) + weight (2) + port (2) + target (variable)
        io = IO::Memory.new
        io.write_bytes(0_u16, IO::ByteFormat::BigEndian)       # priority
        io.write_bytes(0_u16, IO::ByteFormat::BigEndian)       # weight
        io.write_bytes(MATTER_PORT, IO::ByteFormat::BigEndian) # port
        io.write(encode_domain_name(@hostname))                # target

        DNS::Packet::ResourceRecord.new(
          name: instance_name,
          type: DNS::RecordType::SRV.value,
          class_code: DNS::ClassCode::Internet.value,
          ttl: DEFAULT_TTL,
          resource_data: io.to_slice
        )
      end

      # Generate TXT record (device properties)
      private def txt_record : DNS::Packet::ResourceRecord
        # Build TXT record fields
        txt_fields = build_txt_fields

        # Build TXT resource data: each string is length-prefixed
        io = IO::Memory.new
        txt_fields.each do |field|
          io.write_byte(field.size.to_u8)
          io.write(field.to_slice)
        end

        DNS::Packet::ResourceRecord.new(
          name: instance_name,
          type: DNS::RecordType::TXT.value,
          class_code: DNS::ClassCode::Internet.value,
          ttl: DEFAULT_TTL,
          resource_data: io.to_slice
        )
      end

      # Build TXT record key-value pairs
      private def build_txt_fields : Array(String)
        fields = [] of String

        # Mandatory fields
        fields << "D=#{@description.long_discriminator}" # Discriminator
        fields << "CM=#{@description.mode.value}"        # Commissioning Mode
        fields << "DT=#{@description.device_type}"       # Device Type
        fields << "DN=#{@description.name}"              # Device Name
        fields << "VP=#{@description.vendor_product}"    # Vendor+Product ID

        # Optional fields
        if hint = @description.pairing_hint
          fields << "PH=#{hint.value}" unless hint.value == 0
        end

        if instructions = @description.pairing_instructions
          fields << "PI=#{instructions}" unless instructions.empty?
        end

        if interval = @description.session_idle_interval_ms
          fields << "SII=#{interval}"
        end

        if interval = @description.session_active_interval_ms
          fields << "SAI=#{interval}"
        end

        if threshold = @description.session_active_threshold_ms
          fields << "SAT=#{threshold}"
        end

        if @description.tcp_supported
          fields << "T=1"
        end

        if mode = @description.icd_operating_mode
          fields << "ICD=#{mode}"
        end

        fields
      end

      # Generate A/AAAA records for IP addresses
      private def address_records : Array(DNS::Packet::ResourceRecord)
        records = [] of DNS::Packet::ResourceRecord

        @addresses.each do |address|
          begin
            # Detect if IPv4 or IPv6 by checking for colons
            is_ipv6 = address.includes?(':')

            if !is_ipv6
              # IPv4 A record - 4 bytes
              octets = address.split('.').map(&.to_u8)
              resource_data = Bytes.new(4)
              4.times { |i| resource_data[i] = octets[i] }

              record = DNS::Packet::ResourceRecord.new(
                name: @hostname,
                type: DNS::RecordType::A.value,
                class_code: DNS::ClassCode::Internet.value,
                ttl: DEFAULT_TTL,
                resource_data: resource_data
              )
              records << record
            else
              # IPv6 AAAA record - 16 bytes
              # Parse IPv6 address into 16 bytes
              resource_data = encode_ipv6(address)

              record = DNS::Packet::ResourceRecord.new(
                name: @hostname,
                type: DNS::RecordType::AAAA.value,
                class_code: DNS::ClassCode::Internet.value,
                ttl: DEFAULT_TTL,
                resource_data: resource_data
              )
              records << record
            end
          rescue ex
            Log.warn(exception: ex) { "Failed to parse address: #{address}" }
          end
        end

        records
      end

      # Encode IPv6 address to 16 bytes
      private def encode_ipv6(address : String) : Bytes
        # Expand abbreviated IPv6 (:: notation)
        parts = address.split("::")
        if parts.size == 2
          left = parts[0].split(':').reject(&.empty?)
          right = parts[1].split(':').reject(&.empty?)
          missing = 8 - left.size - right.size
          middle = Array.new(missing, "0")
          groups = left + middle + right
        else
          groups = address.split(':')
        end

        # Convert each group to 2 bytes
        bytes = Bytes.new(16)
        groups.each_with_index do |group, i|
          value = group.to_u16(16)
          bytes[i * 2] = (value >> 8).to_u8
          bytes[i * 2 + 1] = (value & 0xFF).to_u8
        end

        bytes
      end

      # Sub-type naming methods

      private def device_type_subtype : String
        "_T#{@description.device_type}._sub.#{SERVICE_TYPE}"
      end

      private def short_discriminator_subtype : String
        "_S#{@description.short_discriminator}._sub.#{SERVICE_TYPE}"
      end

      private def long_discriminator_subtype : String
        "_L#{@description.long_discriminator}._sub.#{SERVICE_TYPE}"
      end

      private def commissioning_mode_subtype : String
        "_CM._sub.#{SERVICE_TYPE}"
      end

      private def vendor_subtype : String
        "_V#{@description.vendor_id}._sub.#{SERVICE_TYPE}"
      end
    end
  end
end
