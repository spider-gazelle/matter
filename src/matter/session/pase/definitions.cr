require "tlv"

module Matter
  module Session
    module Pase
      module Definitions
        # PBKDF Parameter Request message
        # Sent by commissioner to request PBKDF parameters from the device
        struct PbkdfParamRequest
          include TLV::Serializable

          # Initiator random value (optional)
          @[TLV::Field(tag: 0, optional: true)]
          property initiator_random : Bytes?

          # Initiator session ID (optional)
          @[TLV::Field(tag: 1, optional: true)]
          property initiator_session_id : UInt16?

          def initialize(@initiator_random = nil, @initiator_session_id = nil)
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            data = {} of TLV::Tag => TLV::Value

            if random = @initiator_random
              data[0_u8] = random
            end

            if session_id = @initiator_session_id
              data[1_u8] = session_id
            end

            writer.put(nil, data)
            io.rewind.to_slice
          end
        end

        # PBKDF Parameter Response message
        # Sent by device in response to PbkdfParamRequest
        struct PbkdfParamResponse
          include TLV::Serializable

          # PBKDF iterations count
          @[TLV::Field(tag: 0)]
          property iterations : UInt32

          # PBKDF salt
          @[TLV::Field(tag: 1)]
          property salt : Bytes

          # Responder session ID (optional)
          @[TLV::Field(tag: 2, optional: true)]
          property responder_session_id : UInt16?

          def initialize(@iterations : UInt32, @salt : Bytes, @responder_session_id = nil)
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            data = {
              0_u8 => @iterations,
              1_u8 => @salt,
            } of TLV::Tag => TLV::Value

            if session_id = @responder_session_id
              data[2_u8] = session_id
            end

            writer.put(nil, data)
            io.rewind.to_slice
          end
        end
      end
    end
  end
end
