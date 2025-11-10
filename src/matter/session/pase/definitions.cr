require "tlv"

module Matter
  module Session
    module Pase
      module Definitions
        # PBKDF Parameter Request message
        # Sent by commissioner to request PBKDF parameters from the device
        struct PbkdfParamRequest
          include TLV::Serializable

          # Initiator random (optional, tag 1)
          @[TLV::Field(tag: 1, optional: true)]
          property initiator_random : Bytes?

          # Initiator session ID (optional, tag 2)
          @[TLV::Field(tag: 2, optional: true)]
          property initiator_session_id : UInt16?

          # Passcode ID (optional, tag 3)
          @[TLV::Field(tag: 3, optional: true)]
          property passcode_id : UInt16?

          # Has PBKDF parameters (optional, tag 4)
          @[TLV::Field(tag: 4, optional: true)]
          property has_pbkdf_parameters : Bool?

          # MRP parameters (optional, tag 5) - we'll store as raw TLV for now
          @[TLV::Field(tag: 5, optional: true)]
          property mrp_parameters : Hash(String | Tuple(Int32 | Nil, Int32) | UInt8 | Nil, TLV::Value)?

          def initialize(
            @initiator_random = nil,
            @initiator_session_id = nil,
            @passcode_id = nil,
            @has_pbkdf_parameters = nil,
            @mrp_parameters = nil,
          )
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            data = {} of TLV::Tag => TLV::Value

            if random = @initiator_random
              data[1_u8] = random
            end

            if session_id = @initiator_session_id
              data[2_u8] = session_id
            end

            if passcode = @passcode_id
              data[3_u8] = passcode
            end

            if has_pbkdf = @has_pbkdf_parameters
              data[4_u8] = has_pbkdf
            end

            if mrp = @mrp_parameters
              data[5_u8] = mrp
            end

            writer.put(nil, data)
            io.rewind.to_slice
          end
        end

        # PBKDF Parameter Response message
        # Sent by device in response to PbkdfParamRequest
        # Note: Not using TLV::Serializable due to nested TLV::Value field
        struct PbkdfParamResponse
          # Initiator random (echo from request)
          property initiator_random : Bytes

          # Responder random (new 32-byte random)
          property responder_random : Bytes

          # Responder session ID
          property responder_session_id : UInt16

          # PBKDF parameters (nested structure)
          property pbkdf_parameters : TLV::Value?

          def initialize(
            @initiator_random : Bytes,
            @responder_random : Bytes,
            @responder_session_id : UInt16,
            iterations : UInt32? = nil,
            salt : Bytes? = nil,
          )
            if iterations && salt
              @pbkdf_parameters = {
                1_u8 => iterations,
                2_u8 => salt,
              } of TLV::Tag => TLV::Value
            else
              @pbkdf_parameters = nil
            end
          end

          # Constructor from TLV bytes - manual deserialization
          def initialize(data : Bytes)
            reader = TLV::Reader.new(data)
            tlv_data = reader.get

            # Unwrap the anonymous structure (tagged with "Any")
            wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
            hash = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

            # Extract required fields
            @initiator_random = hash[1_u8].as(Bytes)
            @responder_random = hash[2_u8].as(Bytes)
            @responder_session_id = hash[3_u8].as(UInt16)

            # Extract optional pbkdf_parameters
            @pbkdf_parameters = hash[4_u8]? if hash.has_key?(4_u8)
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            data = {
              1_u8 => @initiator_random,
              2_u8 => @responder_random,
              3_u8 => @responder_session_id,
            } of TLV::Tag => TLV::Value

            if pbkdf = @pbkdf_parameters
              data[4_u8] = pbkdf
            end

            writer.put(nil, data)
            io.rewind.to_slice
          end
        end

        # PASE Pake1 message
        # Sent by commissioner with their public key (pA)
        struct Pake1
          include TLV::Serializable

          # Commissioner's public key (X value, pA)
          @[TLV::Field(tag: 1)]
          property x : Bytes

          def initialize(@x : Bytes)
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            writer.put(nil, {1_u8 => @x} of TLV::Tag => TLV::Value)
            io.rewind.to_slice
          end
        end

        # PASE Pake2 message
        # Sent by device with their public key (pB) and confirmation (cB)
        struct Pake2
          include TLV::Serializable

          # Device's public key (Y value, pB)
          @[TLV::Field(tag: 1)]
          property y : Bytes

          # Device's confirmation value (cB, h_bx)
          @[TLV::Field(tag: 2)]
          property verifier : Bytes

          def initialize(@y : Bytes, @verifier : Bytes)
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            data = {
              1_u8 => @y,
              2_u8 => @verifier,
            } of TLV::Tag => TLV::Value
            writer.put(nil, data)
            io.rewind.to_slice
          end
        end

        # PASE Pake3 message
        # Sent by commissioner with their confirmation (cA)
        struct Pake3
          include TLV::Serializable

          # Commissioner's confirmation value (cA, h_ay)
          @[TLV::Field(tag: 1)]
          property verifier : Bytes

          def initialize(@verifier : Bytes)
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            writer.put(nil, {1_u8 => @verifier} of TLV::Tag => TLV::Value)
            io.rewind.to_slice
          end
        end
      end
    end
  end
end
