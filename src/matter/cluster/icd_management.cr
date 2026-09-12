require "./cluster"

module Matter
  module Cluster
    # ICD Management Cluster (0x0046)
    #
    # Minimal implementation for always-connected devices.
    # This enables configuration of the ICD's behavior and ensures that listed
    # clients can be notified when an intermittently connected device (ICD)
    # is available for communication.
    #
    # For always-on devices, this cluster returns sane defaults indicating
    # the device is always available (not actually an ICD). No feature is
    # enabled, so the check-in, user-active-mode-trigger and long-idle
    # attributes and commands are not present.
    #
    # Matter Specification: Core 1.4 § 9.16 - ICD Management Cluster
    class IcdManagement < Base
      cluster 0x0046, revision: 3

      # For always-on devices these are "not really an ICD" defaults:
      # an idle interval of 1 second and 300 ms active durations.
      attribute 0x0000, :idle_mode_duration, UInt32, default: 1_u32, fixed: true
      attribute 0x0001, :active_mode_duration, UInt32, default: 300_u32, fixed: true
      attribute 0x0002, :active_mode_threshold, UInt16, default: 300_u16, fixed: true

      def initialize(
        endpoint_id : DataType::EndpointNumber = DataType::EndpointNumber.new(0_u16),
        @idle_mode_duration : UInt32 = 1_u32,
        @active_mode_duration : UInt32 = 300_u32,
        @active_mode_threshold : UInt16 = 300_u16,
      )
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end
    end
  end
end
