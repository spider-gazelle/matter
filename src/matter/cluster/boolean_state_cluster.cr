require "./cluster"

module Matter
  module Cluster
    # Boolean State Cluster (0x0045)
    #
    # Exposes a single read-only boolean state value.
    # Commonly used by contact sensors.
    class BooleanStateCluster < Base
      cluster 0x0045, revision: 1

      attribute 0x0000, :state_value, Bool, default: false

      event 0x00, :state_change, priority: :info

      def initialize(endpoint_id : DataType::EndpointNumber, @state_value : Bool = false)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      # Reports a new reading; `state_value=` with a device-facing name.
      def update_state(value : Bool) : Nil
        self.state_value = value
      end

      # Called with the previous and the new value whenever the state changes.
      def on_state_changed(&block : Bool, Bool -> Nil) : Nil
        on_state_value_changed(&block)
      end
    end
  end
end
