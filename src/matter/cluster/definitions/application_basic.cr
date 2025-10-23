module Matter
  module Cluster
    module Definitions
      module ApplicationBasic
        enum ApplicationStatus : UInt8
          # Application is not running.
          Stopped = 0

          # Application is running, is visible to the user, and is the active target for input.
          ActiveVisibleFocus = 1

          # Application is running but not visible to the user.
          ActiveHidden = 2

          # Application is running and visible, but is not the active target for input.
          ActiveVisibleNotFocus = 3
        end

        # This indicates a global identifier for an Application given a catalog.
        struct Application
          include TLV::Serializable

          # This shall indicate the Connectivity Standards Alliance issued vendor ID for the catalog. The DIAL registry
          # shall use value 0x0000.
          #
          # It is assumed that Content App Platform providers (see Video Player Architecture section in [MatterDevLib] )
          # will have their own catalog vendor ID (set to their own Vendor ID) and will assign an ApplicationID to each
          # Content App.
          @[TLV::Field(tag: 0)]
          property catalog_vendor_id : UInt16

          # This shall indicate the application identifier, expressed as a string, such as "123456-5433", "PruneVideo"
          # or "Company X". This field shall be unique within a catalog.
          #
          # For the DIAL registry catalog, this value shall be the DIAL prefix.
          @[TLV::Field(tag: 1)]
          property application_id : String
        end
      end
    end
  end
end
