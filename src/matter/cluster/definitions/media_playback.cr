module Matter
  module Cluster
    module Definitions
      module MediaPlayback
        enum PlaybackState : UInt8
          # Media is currently playing (includes FF and REW)
          Playing = 0

          # Media is currently paused
          Paused = 1

          # Media is not currently playing
          NotPlaying = 2

          # Media is not currently buffering and playback will start when buffer has been filled
          Buffering = 3
        end

        enum StatusCode : UInt8
          # Command succeeded
          Success = 0

          # Command failed: Requested playback command is invalid in the current playback state.
          InvalidStateForCommand = 1

          # Command failed: Requested playback command is not allowed in the current playback state. For example,
          # attempting to fast-forward during a commercial might return NotAllowed.
          NotAllowed = 2

          # Command failed: This endpoint is not active for playback.
          NotActive = 3

          # Command failed: The FastForward or Rewind Command was issued but the media is already playing back at the
          # fastest speed supported by the server in the respective direction.
          SpeedOutOfRange = 4

          # Command failed: The Seek Command was issued with a value of position outside of the allowed seek range of
          # the media.
          SeekOutOfRange = 5
        end

        # This command shall be generated in response to various Playback Commands.
        struct PlaybackResponse
          include TLV::Serializable

          # This shall indicate the status of the command which resulted in this response.
          @[TLV::Field(tag: 0)]
          property status_code : StatusCode

          # This shall indicate Optional app-specific data.
          @[TLV::Field(tag: 1)]
          property data : Slice(UInt8)?
        end

        # Input to the MediaPlayback skipForward command
        struct SkipForwardRequest
          include TLV::Serializable

          # This shall indicate the duration of the time span to skip forward in the media, in milliseconds. In case the
          # resulting position falls in the middle of a frame, the server shall set the position to the beginning of
          # that frame and set the SampledPosition attribute on the cluster accordingly. If the resultant position falls
          # beyond the furthest valid position in the media the client may seek forward to, the position should be set
          # to that furthest valid position. If the SampledPosition attribute is supported it shall be updated on the
          # cluster accordingly.
          @[TLV::Field(tag: 0)]
          property deltaPositionMilliseconds : UInt64
        end

        # Input to the MediaPlayback skipBackward command
        struct SkipBackwardRequest
          include TLV::Serializable

          # This shall indicate the duration of the time span to skip backward in the media, in milliseconds. In case
          # the resulting position falls in the middle of a frame, the server shall set the position to the beginning of
          # that frame and set the SampledPosition attribute on the cluster accordingly. If the resultant position falls
          # before the earliest valid position to which a client may seek back to, the position should be set to that
          # earliest valid position. If the SampledPosition attribute is supported it shall be updated on the cluster
          # accordingly.
          @[TLV::Field(tag: 0)]
          property deltaPositionMilliseconds : UInt64
        end

        # This structure defines a playback position within a media stream being played.
        struct PlaybackPosition
          include TLV::Serializable

          # This shall indicate the time when the position was last updated.
          @[TLV::Field(tag: 0)]
          property updated_at : UInt64

          # This shall indicate the associated discrete position within the media stream, in milliseconds from the
          # beginning of the stream, being associated with the time indicated by the UpdatedAt field. The Position shall
          # not be greater than the duration of the media if duration is specified. The Position shall not be greater
          # than the time difference between current time and start time of the media when start time is specified.
          #
          # A value of null shall indicate that playback position is not applicable for the current state of the media
          # playback (For example : Live media with no known duration and where seek is not supported).
          @[TLV::Field(tag: 1)]
          property position : UInt64?
        end

        # Input to the MediaPlayback seek command
        struct SkipRequest
          include TLV::Serializable

          # This shall indicate the position (in milliseconds) in the media to seek to. In case the position falls in
          # the middle of a frame, the server shall set the position to the beginning of that frame and set the
          # SampledPosition attribute on the cluster accordingly. If the position falls before the earliest valid
          # position or beyond the furthest valid position to which a client may seek back or forward to respectively,
          # the status of SEEK_OUT_OF_RANGE shall be returned and no change shall be made to the position of the
          # playback.
          property position : UInt64
        end
      end
    end
  end
end
