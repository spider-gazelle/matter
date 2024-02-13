module Matter
  module Cluster
    module Definitions
      module GeneralDiagnostics
        enum InterfaceType : UInt8
          # Indicates an interface of an unspecified type.
          Unspecified = 0

          # Indicates a Wi-Fi interface.
          WiFi = 1

          # Indicates a Ethernet interface.
          Ethernet = 2

          # Indicates a Cellular interface.
          Cellular = 3

          # Indicates a Thread interface.
          Thread = 4
        end

        enum BootReason : UInt8
          # The Node is unable to identify the Power-On reason as one of the other provided enumeration values.
          Unspecified = 0

          # The Node has booted as the result of physical interaction with the device resulting in a reboot.
          PowerOnReboot = 1

          # The Node has rebooted as the result of a brown-out of the Node’s power supply.
          BrownOutReset = 2

          # The Node has rebooted as the result of a software watchdog timer.
          SoftwareWatchdogReset = 3

          # The Node has rebooted as the result of a hardware watchdog timer.
          HardwareWatchdogReset = 4

          # The Node has rebooted as the result of a completed software update.
          SoftwareUpdateCompleted = 5

          # The Node has rebooted as the result of a software initiated reboot.
          SoftwareReset = 6
        end

        enum HardwareFault : UInt8
          # The Node has encountered an unspecified fault.
          Unspecified = 0

          # The Node has encountered a fault with at least one of its radios.
          Radio = 1

          # The Node has encountered a fault with at least one of its sensors.
          Sensor = 2

          # The Node has encountered an over-temperature fault that is resettable.
          ResettableOverTemp = 3

          # The Node has encountered an over-temperature fault that is not resettable.
          NonResettableOverTemp = 4

          # The Node has encountered a fault with at least one of its power sources.
          PowerSource = 5

          # The Node has encountered a fault with at least one of its visual displays.
          VisualDisplayFault = 6

          # The Node has encountered a fault with at least one of its audio outputs.
          AudioOutputFault = 7

          # The Node has encountered a fault with at least one of its user interfaces.
          UserInterfaceFault = 8

          # The Node has encountered a fault with its non-volatile memory.
          NonVolatileMemoryError = 9

          # The Node has encountered disallowed physical tampering.
          TamperDetected = 10
        end

        enum RadioFault : UInt8
          # The Node has encountered an unspecified radio fault.
          Unspecified = 0

          # The Node has encountered a fault with its Wi-Fi radio.
          WiFiFault = 1

          # The Node has encountered a fault with its cellular radio.
          CellularFault = 2

          # The Node has encountered a fault with its802.15.4 radio.
          ThreadFault = 3

          # The Node has encountered a fault with its NFC radio.
          NfcFault = 4

          # The Node has encountered a fault with its BLE radio.
          BleFault = 5

          # The Node has encountered a fault with its Ethernet controller.
          EthernetFault = 6
        end

        enum NetworkFault : UInt8
          # The Node has encountered an unspecified fault.
          Unspecified = 0

          # The Node has encountered a network fault as a result of a hardware failure.
          HardwareFailure = 1

          # The Node has encountered a network fault as a result of a jammed network.
          NetworkJammed = 2

          # The Node has encountered a network fault as a result of a failure to establish a connection.
          ConnectionFailed = 3
        end

        # This structure describes a network interface supported by the Node, as provided in the NetworkInterfaces
        # attribute.
        struct NetworkInterface
          include TLV::Serializable

          # This field shall indicate a human-readable (displayable) name for the network interface, that is different
          # from all other interfaces.
          @[TLV::Field(tag: 0)]
          property name : String

          # This field shall indicate if the Node is currently advertising itself operationally on this network
          # interface and is capable of successfully receiving incoming traffic from other Nodes.
          @[TLV::Field(tag: 1)]
          property is_operational : Bool

          # This field shall indicate whether the Node is currently able to reach off-premise services it uses by
          # utilizing IPv4. The value shall be null if the Node does not use such services or does not know whether it
          # can reach them.
          @[TLV::Field(tag: 2)]
          property off_premise_services_reachable_ipv4 : Bool?

          # This field shall indicate whether the Node is currently able to reach off-premise services it uses by
          # utilizing IPv6. The value shall be null if the Node does not use such services or does not know whether it
          # can reach them.
          @[TLV::Field(tag: 3)]
          property off_premise_services_reachable_ipv6 : Bool?

          # This field shall contain the current link-layer address for a 802.3 or IEEE 802.11-2020 network interface
          # and contain the current extended MAC address for a 802.15.4 interface. The byte order of the octstr shall be
          # in wire byte order. For addresses values less than 64 bits, the first two bytes shall be zero.
          @[TLV::Field(tag: 4)]
          property hardware_address : Slice(UInt8)

          # This field shall provide a list of the IPv4 addresses that are currently assigned to the network interface.
          @[TLV::Field(tag: 5)]
          property ipv4_addresses : Array(Slice(UInt8))

          # This field shall provide a list of the unicast IPv6 addresses that are currently assigned to the network
          # interface. This list shall include the Node’s link-local address and SHOULD include any assigned GUA and ULA
          # addresses. This list shall NOT include any multicast group addresses to which the Node is subscribed.
          @[TLV::Field(tag: 6)]
          property ipv6_Addresses : Array(Slice(UInt8))

          # This field shall indicate the type of the interface using the InterfaceTypeEnum.
          @[TLV::Field(tag: 7)]
          property type : InterfaceType
        end

        # Input to the GeneralDiagnostics testEventTrigger command
        struct TestEventTriggerRequest
          include TLV::Serializable

          # The EnableKey is a 128 bit value provided by the client in this command, which needs to match a value chosen
          # by the manufacturer and configured on the server using manufacturer-specific means, such as
          # pre-provisioning. The value of all zeroes is reserved to indicate that no EnableKey is set. Therefore, if
          # the EnableKey field is received with all zeroes, this command shall FAIL with a response status of
          # CONSTRAINT_ERROR.
          #
          # The EnableKey SHOULD be unique per exact set of devices going to a certification test.
          #
          # Devices not targeted towards going to a certification test event shall NOT have a non-zero EnableKey value
          # configured, so that only devices in test environments are responsive to this command.
          #
          # In order to prevent unwittingly actuating a particular trigger, this command shall respond with the
          # cluster-specific error status code EnableKeyMismatch if the EnableKey field does not match the a-priori
          # value configured on the device.
          @[TLV::Field(tag: 0)]
          property enable_key : Slice(UInt8)

          # This field shall indicate the test or test mode which the client wants to trigger.
          #
          # The expected side-effects of EventTrigger values are out of scope of this specification and will be
          # described within appropriate certification test literature provided to manufacturers by the Connectivity
          # Standards Alliance, in conjunction with certification test cases documentation.
          #
          # Values of EventTrigger in the range 0xFFFF_FFFF_0000_0000 through 0xFFFF_FFFF_FFFF_FFFF are reserved for
          # testing use by manufacturers and will not appear in CSA certification test literature.
          #
          # If the value of EventTrigger received is not supported by the receiving Node, this command shall fail with a
          # status code of INVALID_COMMAND.
          #
          # Otherwise, if the EnableKey value matches the configured internal value for a particular Node, and the
          # EventTrigger value matches a supported test event trigger value, the command shall succeed and execute the
          # expected trigger action.
          #
          # If no specific test event triggers are required to be supported by certification test requirements for the
          # features that a given product will be certified against, this command may always fail with the
          # INVALID_COMMAND status, equivalent to the situation of receiving an unknown EventTrigger, for all possible
          # EventTrigger values.
          @[TLV::Field(tag: 1)]
          property event_trigger : UInt64
        end

        module Events
          struct HardwareFaultChange
            include TLV::Serializable

            # This field shall represent the set of faults currently detected, as per Section 11.11.4.1,
            # “HardwareFaultEnum”.
            @[TLV::Field(tag: 0)]
            property current : Array(HardwareFault)

            # This field shall represent the set of faults detected prior to this change event, as per Section
            #
            # 11.11.4.1, “HardwareFaultEnum”.
            @[TLV::Field(tag: 1)]
            property previous : Array(HardwareFault)
          end

          # Body of the GeneralDiagnostics radioFaultChange event
          struct RadioFaultChange
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property current : Array(RadioFault)

            @[TLV::Field(tag: 1)]
            property previous : Array(RadioFault)
          end

          # Body of the GeneralDiagnostics networkFaultChange event
          struct NetworkFaultChange
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property current : Array(NetworkFault)

            @[TLV::Field(tag: 1)]
            property previous : Array(NetworkFault)
          end

          # Body of the GeneralDiagnostics bootReason event
          struct BootReasonEvent
            include TLV::Serializable

            @[TLV::Field(tag: 0)]
            property boot_reason : BootReason
          end
        end
      end
    end
  end
end
