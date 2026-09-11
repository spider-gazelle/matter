require "./cluster"
require "./definitions/identify"

module Matter
  module Cluster
    # Identify Cluster Implementation (0x0003)
    #
    # Provides an interface for a device to identify itself to a user
    # (e.g., by flashing a light, sounding a beep, displaying a message).
    #
    # Commonly required on many device types for commissioning and user interaction.
    #
    # Matter Spec: Application 1.2
    class IdentifyCluster < Base
      cluster 0x0003, revision: 6

      # Identify Type enum - indicates how the device identifies itself
      enum IdentifyType : UInt8
        None         = 0 # No identification method
        VisibleLight = 1 # Visible light (e.g., bulb flashes)
        VisibleLED   = 2 # Visible LED indicator
        AudibleBeep  = 3 # Audible beep/tone
        Display      = 4 # Display message
        Actuator     = 5 # Physical actuator (e.g., lock/unlock, open/close)
      end

      alias EffectIdentifier = Definitions::Identify::EffectIdentifier
      alias EffectVariant = Definitions::Identify::EffectVariant

      # Remaining identify time in seconds; volatile, so not persisted
      attribute 0x0000, :identify_time, UInt16, default: 0_u16, writable: true, persist: false
      attribute 0x0001, :identify_type, IdentifyType, default: IdentifyType::None, fixed: true

      command 0x00, :identify, request: Definitions::Identify::Request
      command 0x40, :trigger_effect, request: Definitions::Identify::TriggerEffectRequest

      # Whether the start / stop callbacks last saw an active identification
      @identifying = false

      @on_identify_started : Proc(Nil)?
      @on_identify_stopped : Proc(Nil)?
      @on_trigger_effect : Proc(EffectIdentifier, EffectVariant, Nil)?

      def initialize(endpoint_id : DataType::EndpointNumber, @identify_type : IdentifyType = IdentifyType::None)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
      end

      # A controller may start or stop identification by writing the time too
      after_write :identify_time do
        sync_identify_callbacks
      end

      # ------------------------------------------------------------------------
      # Commands
      # ------------------------------------------------------------------------

      def identify(request : Definitions::Identify::Request) : InteractionModel::Status
        self.identify_time = request.identify_time
        sync_identify_callbacks
        InteractionModel::Status.success
      end

      def trigger_effect(request : Definitions::Identify::TriggerEffectRequest) : InteractionModel::Status
        @on_trigger_effect.try &.call(request.effect_identifier, request.effect_variany)
        InteractionModel::Status.success
      end

      # ------------------------------------------------------------------------
      # Public Interface
      # ------------------------------------------------------------------------

      def identifying? : Bool
        @identify_time > 0
      end

      # Set callback for when identify starts
      def on_identify_started(&block : -> Nil)
        @on_identify_started = block
      end

      # Set callback for when identify stops
      def on_identify_stopped(&block : -> Nil)
        @on_identify_stopped = block
      end

      # Set callback for trigger effect
      def on_trigger_effect(&block : EffectIdentifier, EffectVariant -> Nil)
        @on_trigger_effect = block
      end

      # Counts the identify time down by one second; call once a second while
      # identifying.
      def tick : Nil
        return unless identifying?
        self.identify_time = @identify_time - 1
        sync_identify_callbacks
      end

      # Fires the started / stopped callback when the identifying state
      # flipped since the last call.
      private def sync_identify_callbacks : Nil
        return if @identifying == identifying?
        @identifying = identifying?
        @identifying ? @on_identify_started.try(&.call) : @on_identify_stopped.try(&.call)
      end
    end
  end
end
