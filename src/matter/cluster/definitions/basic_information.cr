module Matter
  module Cluster
    module Definitions
      module BasicInformation
        enum ProductFinish
          Other    = 0
          Matte    = 1
          Satin    = 2
          Polished = 3
          Rugged   = 4
          Fabric   = 5
        end

        enum Color
          Black   =  0
          Navy    =  1
          Green   =  2
          Teal    =  3
          Maroon  =  4
          Purple  =  5
          Olive   =  6
          Gray    =  7
          Blue    =  8
          Lime    =  9
          Aqua    = 10
          Red     = 11
          Fuchsia = 12
          Yellow  = 13
          White   = 14
          Nickel  = 15
          Chrome  = 16
          Brass   = 17
          Copper  = 18
          Silver  = 19
          Gold    = 20
        end

        # This structure provides constant values related to overall global capabilities of this Node, that are not
        # cluster-specific.
        struct CapabilityMinima
          include TLV::Serializable

          # This field shall indicate the actual minimum number of concurrent CASE sessions that are supported per
          # fabric.
          #
          # This value shall NOT be smaller than the required minimum indicated in Section 4.13.2.8, “Minimal Number of
          # CASE Sessions”.
          @[TLV::Field(tag: 0)]
          property case_sessions_per_fabric : UInt16

          # This field shall indicate the actual minimum number of concurrent subscriptions supported per fabric.
          #
          # This value shall NOT be smaller than the required minimum indicated in Section 8.5.1, “Subscribe
          # Transaction”.
          @[TLV::Field(tag: 1)]
          property subscriptions_per_fabric : UInt16
        end

        struct ProductAppearance
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property finish : ProductFinish

          @[TLV::Field(tag: 1)]
          property primary_color : Color?
        end

        struct Configuration
          include TLV::Serializable

          # This attribute shall be set to the revision number of the Data Model against which the Node is certified.
          @[TLV::Field(tag: 0x0)]
          property data_model_revision : UInt16

          # This attribute shall specify a human readable (displayable) name of the vendor for the Node.
          @[TLV::Field(tag: 0x1)]
          property vendor_name : String

          # This attribute shall specify the Vendor ID.
          @[TLV::Field(tag: 0x2)]
          property vendor_id : DataType::VendorId

          # This attribute shall specify a human readable (displayable) name of the model for the Node such as the
          # model number (or other identifier) assigned by the vendor.
          @[TLV::Field(tag: 0x3)]
          property product_name : String

          # This attribute shall specify the Product ID assigned by the vendor that is unique to the specific
          # product of the Node.
          @[TLV::Field(tag: 0x4)]
          property product_id : UInt16

          # This attribute shall represent a user defined name for the Node. This attribute SHOULD be set during
          # initial commissioning and may be updated by further reconfigurations.
          @[TLV::Field(tag: 0x5)]
          property node_label : String = ""

          # This attribute shall be an ISO 3166-1 alpha-2 code to represent the country, dependent territory, or
          # special area of geographic interest in which the Node is located at the time of the attribute being set.
          # This attribute shall be set during initial commissioning (unless already set) and may be updated by
          # further reconfigurations. This attribute may affect some regulatory aspects of the Node’s operation,
          # such as radio transmission power levels in given spectrum allocation bands if technologies where this is
          # applicable are used. The Location’s region code shall be interpreted in a case-insensitive manner. If
          # the Node cannot understand the location code with which it was configured, or the location code has not
          # yet been configured, it shall configure itself in a region- agnostic manner as determined by the vendor,
          # avoiding region-specific assumptions as much as is practical. The special value XX shall indicate that
          # region-agnostic mode is used.
          @[TLV::Field(tag: 0x6)]
          property location : String = "XX"

          # This attribute shall specify the version number of the hardware of the Node. The meaning of its value,
          # and the versioning scheme, are vendor defined.
          @[TLV::Field(tag: 0x7)]
          property hardware_version : UInt16

          # This attribute shall specify the version number of the hardware of the Node. The meaning of its value,
          # and the versioning scheme, are vendor defined. The HardwareVersionString attribute shall be used to
          # provide a more user-friendly value than that represented by the HardwareVersion attribute.
          @[TLV::Field(tag: 0x8)]
          property hardware_version_string : String

          # This attribute shall contain the current version number for the software running on this Node. The
          # version number can be compared using a total ordering to determine if a version is logically newer than
          # another one. A larger value of SoftwareVersion is newer than a lower value, from the perspective of
          # software updates (see Section 11.19.3.3, “Availability of Software Images”). Nodes may query this field
          # to determine the currently running version of software on another given Node.
          @[TLV::Field(tag: 0x9)]
          property software_version : UInt32 = UInt32.new(0)

          # This attribute shall contain a current human-readable representation for the software running on the
          # Node. This version information may be conveyed to users. The maximum length of the SoftwareVersionString
          # attribute is 64 bytes of UTF-8 characters. The contents SHOULD only use simple 7-bit ASCII alphanumeric
          # and punctuation characters, so as to simplify the conveyance of the value to a variety of cultures.
          #
          # Examples of version strings include "1.0", "1.2.3456", "1.2-2", "1.0b123", "1.2_3".
          @[TLV::Field(tag: 0xa)]
          property software_version_string : String

          # This attribute shall specify the date that the Node was manufactured. The first 8 characters shall
          # specify the date of manufacture of the Node in international date notation according to ISO 8601, i.e.,
          # YYYYMMDD, e.g., 20060814. The final 8 characters may include country, factory, line, shift or other
          # related information at the option of the vendor. The format of this information is vendor
          #
          # defined.

          @[TLV::Field(tag: 0xb)]
          property manufacturing_date : String?

          # This attribute shall specify a human-readable (displayable) vendor assigned part number for the Node
          # whose meaning and numbering scheme is vendor defined.
          #
          # Multiple products (and hence PartNumbers) can share a ProductID. For instance, there may be different
          # packaging (with different PartNumbers) for different regions; also different colors of a product might
          # share the ProductID but may have a different PartNumber.
          @[TLV::Field(tag: 0xc)]
          property part_number : String?

          # This attribute shall specify a link to a product specific web page. The syntax of the ProductURL
          # attribute shall follow the syntax as specified in RFC 3986 [https://tools.ietf.org/html/rfc3986]. The
          # specified URL SHOULD resolve to a maintained web page available for the lifetime of the product. The
          # maximum length of the ProductUrl attribute is 256 ASCII characters.

          @[TLV::Field(tag: 0xd)]
          property product_url : String?

          # This attribute shall specify a vendor specific human readable (displayable) product label. The
          # ProductLabel attribute may be used to provide a more user-friendly value than that represented by the
          # ProductName attribute. The ProductLabel attribute SHOULD NOT include the name of the vendor as defined
          # within the VendorName attribute.

          @[TLV::Field(tag: 0xe)]
          property product_label : String?

          # This attributes shall specify a human readable (displayable) serial number.
          @[TLV::Field(tag: 0xf)]
          property serial_number : String?

          # This attribute shall allow a local Node configuration to be disabled. When this attribute is set to True
          # the Node shall disable the ability to configure the Node through an on-Node user interface. The value of
          # the LocalConfigDisabled attribute shall NOT in any way modify, disable, or otherwise affect the user’s
          # ability to trigger a factory reset on the Node.
          @[TLV::Field(tag: 0x10)]
          property local_config_disabled : Bool? = true

          # This attribute (when used) shall indicate whether the Node can be reached. For a native Node this is
          # implicitly True (and its use is optional).
          #
          # Its main use case is in the derived Bridged Device Basic Information cluster where it is used to
          # indicate whether the bridged device is reachable by the bridge over the non-native network.

          @[TLV::Field(tag: 0x11)]
          property reachable : Bool? = true

          # This attribute (when used) shall indicate a unique identifier for the device, which is constructed in a
          # manufacturer specific manner.
          #
          # It may be constructed using a permanent device identifier (such as device MAC address) as basis. In
          # order to prevent tracking,
          #
          #   • it SHOULD NOT be identical to (or easily derived from) such permanent device identifier
          #
          #   • it SHOULD be updated when the device is factory reset
          #
          #   • it shall not be identical to the SerialNumber attribute
          #
          #   • it shall not be printed on the product or delivered with the product The value does not need to be
          #     human readable.

          @[TLV::Field(tag: 0x12)]
          property unique_id : String?

          # This attribute shall provide the minimum guaranteed value for some system-wide resource capabilities
          # that are not otherwise cluster-specific and do not appear elsewhere. This attribute may be used by
          # clients to optimize communication with Nodes by allowing them to use more than the strict minimum values
          # required by this specification, wherever available.
          #
          # The values supported by the server in reality may be larger than the values provided in this attribute,
          # such as if a server is not resource-constrained at all. However, clients SHOULD only rely on the amounts
          # provided in this attribute.
          #
          # Note that since the fixed values within this attribute may change over time, both increasing and
          # decreasing, as software versions change for a given Node, clients SHOULD take care not to assume forever
          # unchanging values and SHOULD NOT cache this value permanently at Commissioning time.
          @[TLV::Field(tag: 0x13)]
          property capability_minima : CapabilityMinima

          @[TLV::Field(tag: 0x14)]
          property product_appearance : ProductAppearance?
        end

        module Events
          # Body of the BasicInformation startUp event
          struct StartUp
            include TLV::Serializable

            # This field shall be set to the same value as the one available in the Software Version attribute of the
            # Basic Information Cluster.
            @[TLV::Field(tag: 0)]
            property software_version : UInt32
          end

          # Body of the BasicInformation leave event
          struct Leave
            include TLV::Serializable

            # This field shall contain the local Fabric Index of the fabric which the node is about to leave.
            @[TLV::Field(tag: 0)]
            property fabric_index : DataType::FabricIndex
          end

          # Body of the BasicInformation reachableChanged event
          struct ReachableChanged
            include TLV::Serializable

            # This field shall indicate the value of the Reachable attribute after it was changed.
            @[TLV::Field(tag: 0)]
            property? reachable : Bool
          end
        end
      end
    end
  end
end
