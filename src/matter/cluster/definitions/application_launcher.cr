module Matter
  module Cluster
    module Definitions
      module ApplicationLauncher
        enum Status : UInt8
          # Command succeeded
          Success = 0

          # Requested app is not available.
          AppNotAvailable = 1

          # Video platform unable to honor command.
          SystemBusy = 2
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

        # This specifies an app along with its corresponding endpoint.
        struct ApplicationEndpoint
          include TLV::Serializable

          @[TLV::Field(tag: 0)]
          property application : Application

          @[TLV::Field(tag: 1)]
          property endpoint : DataType::EndpointNumber?
        end

        # Input to the ApplicationLauncher launchApp command
        struct LaunchAppRequest
          include TLV::Serializable

          # This field shall specify the Application to launch.
          @[TLV::Field(tag: 0)]
          property application : Application?

          # This field shall specify optional app-specific data to be sent to the app.
          #
          # Note: This format and meaning of this value is proprietary and outside the specification. It provides a
          # transition path for device makers that use other protocols (like DIAL) which allow for proprietary data.
          # Apps that are not yet Matter aware can be launched via Matter, while retaining the existing ability to
          # launch with proprietary data.
          @[TLV::Field(tag: 1)]
          property data : Slice(UInt8)?
        end

        # This command shall be generated in response to LaunchApp/StopApp/HideApp commands.
        struct LauncherResponse
          include TLV::Serializable

          # This shall indicate the status of the command which resulted in this response.
          @[TLV::Field(tag: 0)]
          property status : Status

          # This shall specify Optional app-specific data.
          @[TLV::Field(tag: 1)]
          property data : Slice(UInt8)?
        end

        # Input to the ApplicationLauncher stopApp command
        struct StopAppRequest
          include TLV::Serializable

          # This field shall specify the Application to stop.
          @[TLV::Field(tag: 0)]
          property application : Application?
        end

        # Input to the ApplicationLauncher hideApp command
        struct HideAppRequest
          include TLV::Serializable

          # This field shall specify the Application to hide.
          @[TLV::Field(tag: 0)]
          property application : Application?
        end
      end
    end
  end
end
