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
