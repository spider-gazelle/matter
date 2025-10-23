module Matter
  module Cluster
    module Definitions
      module ContentLauncher
        enum MetricType : UInt8
          # This value is used for dimensions defined in a number of Pixels.
          Pixels = 0

          # This value is for dimensions defined as a percentage of the overall display dimensions. For example, if
          # using a Percentage Metric type for a Width measurement of 50.0, against a display width of 1920 pixels, then
          # the resulting value used would be 960 pixels (50.0% of 1920) for that dimension. Whenever a measurement uses
          # this Metric type, the resulting values shall be rounded ("floored") towards 0 if the measurement requires an
          # integer final value.
          Percentage = 1
        end

        enum Status : UInt8
          # Command succeeded
          Success = 0

          # Requested URL could not be reached by device.
          UrlNotAvailable = 1

          # Requested URL returned 401 error code.
          AuthFailed = 2
        end

        enum ParameterType : UInt8
          # Actor represents an actor credited in video media content; for example, “Gaby sHoffman”
          Actor = 0

          # Channel represents the identifying data for a television channel; for example, "PBS"
          Channel = 1

          # A character represented in video media content; for example, “Snow White”
          Character = 2

          # A director of the video media content; for example, “Spike Lee”
          Director = 3

          # An event is a reference to a type of event; examples would include sports, music, or other types of events.
          # For example, searching for "Football games" would search for a 'game' event entity and a 'football' sport
          # entity.
          Event = 4

          # A franchise is a video entity which can represent a number of video entities, like movies or TV shows. For
          # example, take the fictional franchise "Intergalactic Wars" which represents a collection of movie trilogies,
          # as well as animated and live action TV shows. This entity type was introduced to account for requests by
          # customers such as "Find Intergalactic Wars movies", which would search for all 'Intergalactic Wars' programs
          # of the MOVIE MediaType, rather than attempting to match to a single title.
          Franchise = 5

          # Genre represents the genre of video media content such as action, drama or comedy.
          Genre = 6

          # League represents the categorical information for a sporting league; for example, "NCAA"
          League = 7

          # Popularity indicates whether the user asks for popular content.
          Popularity = 8

          # The provider (MSP) the user wants this media to be played on; for example, "Netflix".
          Provider = 9

          # Sport represents the categorical information of a sport; for example, football
          Sport = 10

          # SportsTeam represents the categorical information of a professional sports team; for example, "University of
          # Washington Huskies"
          SportsTeam = 11

          # The type of content requested. Supported types are "Movie", "MovieSeries", "TVSeries", "TVSeason",
          # "TVEpisode", "SportsEvent", and "Video"
          Type = 12

          # Video represents the identifying data for a specific piece of video content; for example, "Manchester by the
          # Sea".
          Video = 13
        end

        # This object defines dimension which can be used for defining Size of background images.
        struct Dimension
          include TLV::Serializable

          # This indicates the width using the metric defined in Metric
          @[TLV::Field(tag: 0)]
          property width : Float64

          # This indicates the height using the metric defined in Metric
          @[TLV::Field(tag: 1)]
          property height : Float64

          # This shall indicate metric used for defining Height/Width.
          @[TLV::Field(tag: 2)]
          property metric : MetricType
        end

        # This object defines style information which can be used by content providers to change the Media Player’s style
        # related properties.
        struct StyleInformation
          include TLV::Serializable

          # This shall indicate the URL of image used for Styling different Video Player sections like Logo, Watermark etc.
          @[TLV::Field(tag: 0)]
          property image_url : String?

          # This shall indicate the color, in RGB or RGBA, used for styling different Video Player sections like Logo,
          # Watermark, etc. The value shall conform to the 6-digit or 8-digit format defined for CSS sRGB hexadecimal
          # color notation [https://www.w3.org/TR/css-color-4/#hex-notation]. Examples:
          #
          #   • #76DE19 for R=0x76, G=0xDE, B=0x19, A absent
          #
          #   • #76DE1980 for R=0x76, G=0xDE, B=0x19, A=0x80
          @[TLV::Field(tag: 1)]
          property color : String?

          # This shall indicate the size of the image used for Styling different Video Player sections like Logo, Watermark etc.
          @[TLV::Field(tag: 2)]
          property size : Dimension?
        end

        # This object defines Branding Information which can be provided by the client in order to customize the skin of
        # the Video Player during playback.
        struct BrandingInformation
          include TLV::Serializable

          # This shall indicate name of of the provider for the given content.
          @[TLV::Field(tag: 0)]
          property provider_name : String

          # This shall indicate background of the Video Player while content launch request is being processed by it.
          # This background information may also be used by the Video Player when it is in idle state.
          @[TLV::Field(tag: 1)]
          property background : StyleInformation?

          # This shall indicate the logo shown when the Video Player is launching. This is also used when the Video
          # Player is in the idle state and Splash field is not available.
          @[TLV::Field(tag: 2)]
          property logo : StyleInformation?

          # This shall indicate the style of progress bar for media playback.
          @[TLV::Field(tag: 3)]
          property progress_bar : StyleInformation?

          # This shall indicate the screen shown when the Video Player is in an idle state. If this property is not
          # populated, the Video Player shall default to logo or the provider name.
          @[TLV::Field(tag: 4)]
          property splash : StyleInformation?

          # This shall indicate watermark shown when the media is playing.
          @[TLV::Field(tag: 5)]
          property water_mark : StyleInformation?
        end

        # Input to the ContentLauncher launchUrl command
        struct LaunchUrlRequest
          include TLV::Serializable

          # This shall indicate the URL of content to launch.
          @[TLV::Field(tag: 0)]
          property content_url : String

          # This field, if present, shall provide a string that may be used to describe the content being accessed at
          # the given URL.
          @[TLV::Field(tag: 1)]
          property display_string : String?

          # This field, if present, shall indicate the branding information that may be displayed when playing back the
          # given content.
          @[TLV::Field(tag: 2)]
          property branding_information : BrandingInformation?
        end

        # This command shall be generated in response to LaunchContent and LaunchURL commands.
        struct LauncherResponse
          include TLV::Serializable

          # This shall indicate the status of the command which resulted in this response.
          property status : Status

          # This shall indicate Optional app-specific data.
          property data : Slice(UInt8)?
        end

        # This object defines additional name=value pairs that can be used for identifying content.
        struct AdditionalInformation
          include TLV::Serializable

          # This shall indicate the name of external id, ex. "musicbrainz".
          @[TLV::Field(tag: 0)]
          property name : String

          # This shall indicate the value for external id, ex. "ST0000000666661".
          @[TLV::Field(tag: 1)]
          property value : String
        end

        # This object defines inputs to a search for content for display or playback.
        struct Parameter
          include TLV::Serializable

          # This shall indicate the entity type.
          @[TLV::Field(tag: 0)]
          property type : ParameterType

          # This shall indicate the entity value, which is a search string, ex. “Manchester by the Sea”.
          @[TLV::Field(tag: 1)]
          property value : String

          # This shall indicate the list of additional external content identifiers.
          @[TLV::Field(tag: 2)]
          property external_ids : Array(AdditionalInformation)?
        end

        # This object defines inputs to a search for content for display or playback.
        struct ContentSearch
          include TLV::Serializable

          # This shall indicate the list of parameters comprising the search. If multiple parameters are provided, the
          # search parameters shall be joined with 'AND' logic. e.g. action movies with Tom Cruise will be represented
          # as [{Actor: 'Tom Cruise'}, {Type: 'Movie'}, {Genre: 'Action'}]
          @[TLV::Field(tag: 0)]
          property parameters : Array(Parameter)?
        end

        # Input to the ContentLauncher launchContent command
        struct LaunchContentRequest
          include TLV::Serializable

          # This shall indicate the content to launch.
          @[TLV::Field(tag: 0)]
          property search : ContentSearch

          # This shall indicate whether to automatically start playing content, where: * TRUE means best match should
          # start playing automatically. * FALSE means matches should be displayed on screen for user selection.
          @[TLV::Field(tag: 1)]
          property auto_play : Bool

          # This shall indicate Optional app-specific data.
          @[TLV::Field(tag: 2)]
          property data : Slice(UInt8)
        end
      end
    end
  end
end
