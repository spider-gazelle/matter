require "./cluster"
require "tlv"
require "log"

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
      Log        = ::Log.for("matter.cluster.identify")
      CLUSTER_ID = 0x0003_u32

      # Attributes (using ATTR_ prefix for consistency)
      ATTR_IDENTIFY_TIME = 0x0000_u32
      ATTR_IDENTIFY_TYPE = 0x0001_u32

      # Global attributes (required on all clusters)
      CLUSTER_REVISION = 0xFFFD_u32
      FEATURE_MAP      = 0xFFFC_u32

      # Commands
      CMD_IDENTIFY       = 0x00_u32
      CMD_TRIGGER_EFFECT = 0x40_u32

      # Identify Type enum - indicates how the device identifies itself
      enum IdentifyType : UInt8
        None         = 0 # No identification method
        VisibleLight = 1 # Visible light (e.g., bulb flashes)
        VisibleLED   = 2 # Visible LED indicator
        AudibleBeep  = 3 # Audible beep/tone
        Display      = 4 # Display message
        Actuator     = 5 # Physical actuator (e.g., lock/unlock, open/close)
      end

      # Effect Identifier enum - visual/audible effects for identification
      enum EffectIdentifier : UInt8
        Blink         =   0 # Blink light
        Breathe       =   1 # Breathe effect (fade in/out)
        Okay          =   2 # "Okay" confirmation effect
        ChannelChange =  11 # Channel change effect
        FinishEffect  = 254 # Finish current effect
        StopEffect    = 255 # Stop current effect
      end

      # Effect Variant enum
      enum EffectVariant : UInt8
        Default = 0 # Default variant of the effect
      end

      # Attribute storage
      property identify_time : UInt16 # Remaining identify time in seconds
      property identify_type : IdentifyType

      # Callbacks
      @on_identify_started : Proc(Nil)?
      @on_identify_stopped : Proc(Nil)?
      @on_trigger_effect : Proc(EffectIdentifier, EffectVariant, Nil)?

      def initialize(endpoint_id : DataType::EndpointNumber,
                     @identify_type : IdentifyType = IdentifyType::None)
        super(endpoint_id, DataType::ClusterId.new(CLUSTER_ID))
        @identify_time = 0_u16
      end

      def name : String
        "Identify"
      end

      def attributes : Array(AttributeMetadata)
        [
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_IDENTIFY_TIME),
            "IdentifyTime",
            :uint16,
            writable: true
          ),
          AttributeMetadata.new(
            DataType::AttributeId.new(ATTR_IDENTIFY_TYPE),
            "IdentifyType",
            :uint8,
            writable: false
          ),
        ]
      end

      def commands : Array(CommandMetadata)
        [
          CommandMetadata.new(
            DataType::CommandId.new(CMD_IDENTIFY),
            "Identify"
          ),
          CommandMetadata.new(
            DataType::CommandId.new(CMD_TRIGGER_EFFECT),
            "TriggerEffect"
          ),
        ]
      end

      def read_attribute(attribute_id : UInt32, fabric_index : UInt8? = nil) : InteractionModel::Status | Bytes
        case attribute_id
        when ATTR_IDENTIFY_TIME
          @identify_time.to_tlv
        when ATTR_IDENTIFY_TYPE
          @identify_type.value.to_tlv
        when CLUSTER_REVISION
          4_u16.to_tlv # Identify cluster revision 4
        when FEATURE_MAP
          0_u32.to_tlv # No features for basic Identify
        else
          super
        end
      end

      def write_attribute(attribute_id : UInt32, value : Bytes) : InteractionModel::Status
        case attribute_id
        when ATTR_IDENTIFY_TIME
          begin
            parsed = TLV::Any.from_slice(value)
            new_time = case v = parsed.value
                       when Int
                         v.to_u16
                       else
                         return InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
                       end
            @identify_time = new_time
            increment_version
            InteractionModel::Status.new(InteractionModel::StatusCode::Success)
          rescue ex
            Log.error(exception: ex) { "IdentifyTime write error (bytes=#{value.hexstring})" }
            InteractionModel::Status.new(InteractionModel::StatusCode::InvalidDataType)
          end
        else
          super
        end
      end

      protected def handle_command(command_id : UInt32, fields : Bytes) : InteractionModel::Status | Cluster::CommandResponse
        case command_id
        when CMD_IDENTIFY
          handle_identify_command(fields)
        when CMD_TRIGGER_EFFECT
          handle_trigger_effect_command(fields)
        else
          super
        end
      end

      # Handle Identify command
      # Command fields: IdentifyTime (tag 0, uint16) - seconds to identify
      private def handle_identify_command(fields : Bytes) : InteractionModel::Status
        req = Definitions::Identify::Request.from_slice(fields)
        new_time = req.identify_time

        was_identifying = identifying?
        @identify_time = new_time
        increment_version

        # Trigger callbacks
        if new_time > 0 && !was_identifying
          @on_identify_started.try &.call
        elsif new_time == 0 && was_identifying
          @on_identify_stopped.try &.call
        end

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      rescue ex
        Log.error(exception: ex) { "Identify command TLV parsing error (bytes=#{fields.hexstring})" }
        InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
      end

      # Handle TriggerEffect command
      # Command fields: EffectIdentifier (tag 0, enum8), EffectVariant (tag 1, enum8)
      private def handle_trigger_effect_command(fields : Bytes) : InteractionModel::Status
        req = Definitions::Identify::TriggerEffectRequest.from_slice(fields)

        # Convert from Definitions enum to cluster enum
        effect = EffectIdentifier.from_value(req.effect_identifier.value)
        variant = EffectVariant.from_value(req.effect_variany.value)

        @on_trigger_effect.try &.call(effect, variant)

        InteractionModel::Status.new(InteractionModel::StatusCode::Success)
      rescue ex
        Log.error(exception: ex) { "TriggerEffect command TLV parsing error (bytes=#{fields.hexstring})" }
        InteractionModel::Status.new(InteractionModel::StatusCode::InvalidCommand)
      end

      # Check if device is currently identifying
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

      # Helper: Decrement identify time (call this periodically, e.g., every second)
      def tick
        if @identify_time > 0
          @identify_time -= 1
          increment_version

          if @identify_time == 0
            @on_identify_stopped.try &.call
          end
        end
      end
    end
  end
end
