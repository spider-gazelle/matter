require "tlv"

module Matter
  module Session
    module Case
      module Definitions
        Log = ::Log.for("matter.case")

        # CASE Sigma1 message
        # Sent by initiator (chip-tool) to begin CASE session establishment
        struct Sigma1
          # Initiator's random value (32 bytes, tag 1)
          property initiator_random : Bytes

          # Initiator's session ID (tag 2)
          property initiator_session_id : UInt16

          # Destination ID - compressed fabric ID + node ID (tag 3)
          property destination_id : Bytes

          # Initiator's ephemeral public key (65 bytes EC point, tag 4)
          property initiator_eph_pub_key : Bytes

          # Optional resumption ID (tag 5)
          property resumption_id : Bytes?

          # Optional initiator resume MIC (tag 6)
          property initiator_resume_mic : Bytes?

          def initialize(data : Bytes)
            reader = TLV::Reader.new(data)
            tlv_data = reader.get

            # Unwrap the anonymous structure (tagged with "Any")
            wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
            hash = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

            # Extract required fields - handle both direct Bytes and wrapped values
            random_value = hash[1_u8]
            Log.debug { "Sigma1 initiator_random type: #{random_value.class}, value: #{random_value.inspect}" }
            @initiator_random = case random_value
                                when Bytes then random_value
                                when Slice then random_value.to_a.to_unsafe.to_slice(random_value.size)
                                else            raise "Invalid initiator_random type: #{random_value.class}, inspect: #{random_value.inspect}"
                                end

            # Handle flexible integer types for session ID
            session_id_value = hash[2_u8]
            @initiator_session_id = case session_id_value
                                    when Int then session_id_value.to_u16
                                    else          raise "Invalid initiator_session_id type: #{session_id_value.class}"
                                    end

            dest_id_value = hash[3_u8]
            @destination_id = case dest_id_value
                              when Bytes then dest_id_value
                              when Slice then dest_id_value.to_a.to_unsafe.to_slice(dest_id_value.size)
                              else            raise "Invalid destination_id type: #{dest_id_value.class}"
                              end

            eph_key_value = hash[4_u8]
            @initiator_eph_pub_key = case eph_key_value
                                     when Bytes then eph_key_value
                                     when Slice then eph_key_value.to_a.to_unsafe.to_slice(eph_key_value.size)
                                     else            raise "Invalid initiator_eph_pub_key type: #{eph_key_value.class}"
                                     end

            # Extract optional fields
            if resume_id_value = hash[5_u8]?
              @resumption_id = case resume_id_value
                               when Bytes then resume_id_value
                               when Slice then resume_id_value.to_a.to_unsafe.to_slice(resume_id_value.size)
                               else            nil
                               end
            else
              @resumption_id = nil
            end

            if resume_mic_value = hash[6_u8]?
              @initiator_resume_mic = case resume_mic_value
                                      when Bytes then resume_mic_value
                                      when Slice then resume_mic_value.to_a.to_unsafe.to_slice(resume_mic_value.size)
                                      else            nil
                                      end
            else
              @initiator_resume_mic = nil
            end
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            data = {
              1_u8 => @initiator_random,
              2_u8 => @initiator_session_id,
              3_u8 => @destination_id,
              4_u8 => @initiator_eph_pub_key,
            } of TLV::Tag => TLV::Value

            if resumption = @resumption_id
              data[5_u8] = resumption
            end

            if resume_mic = @initiator_resume_mic
              data[6_u8] = resume_mic
            end

            writer.put(nil, data)
            io.rewind.to_slice
          end
        end

        # CASE Sigma2 message
        # Sent by responder (device) in response to Sigma1
        struct Sigma2
          # Responder's random value (32 bytes, tag 1)
          property responder_random : Bytes

          # Responder's session ID (tag 2)
          property responder_session_id : UInt16

          # Responder's ephemeral public key (65 bytes EC point, tag 3)
          property responder_eph_pub_key : Bytes

          # Encrypted responder certificate (tag 4)
          property encrypted2 : Bytes

          # Optional resumption ID (tag 5)
          property resumption_id : Bytes?

          # Optional responder resume MIC (tag 6)
          property responder_resume_mic : Bytes?

          def initialize(
            @responder_random : Bytes,
            @responder_session_id : UInt16,
            @responder_eph_pub_key : Bytes,
            @encrypted2 : Bytes,
            @resumption_id : Bytes? = nil,
            @responder_resume_mic : Bytes? = nil,
          )
          end

          # Constructor from TLV bytes
          def initialize(data : Bytes)
            reader = TLV::Reader.new(data)
            tlv_data = reader.get

            # Unwrap the anonymous structure
            wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
            hash = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

            # Extract required fields
            @responder_random = hash[1_u8].as(Bytes)

            session_id_value = hash[2_u8]
            @responder_session_id = case session_id_value
                                    when Int then session_id_value.to_u16
                                    else          raise "Invalid responder_session_id type: #{session_id_value.class}"
                                    end

            @responder_eph_pub_key = hash[3_u8].as(Bytes)
            @encrypted2 = hash[4_u8].as(Bytes)

            # Extract optional fields
            @resumption_id = hash[5_u8]?.try(&.as(Bytes))
            @responder_resume_mic = hash[6_u8]?.try(&.as(Bytes))
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            data = {
              1_u8 => @responder_random,
              2_u8 => @responder_session_id,
              3_u8 => @responder_eph_pub_key,
              4_u8 => @encrypted2,
            } of TLV::Tag => TLV::Value

            if resumption = @resumption_id
              data[5_u8] = resumption
            end

            if resume_mic = @responder_resume_mic
              data[6_u8] = resume_mic
            end

            writer.put(nil, data)
            io.rewind.to_slice
          end
        end

        # CASE Sigma3 message
        # Sent by initiator (chip-tool) to complete CASE session establishment
        struct Sigma3
          # Encrypted initiator certificate (tag 1)
          property encrypted3 : Bytes

          def initialize(@encrypted3 : Bytes)
          end

          # Constructor from TLV bytes
          def initialize(data : Bytes)
            reader = TLV::Reader.new(data)
            tlv_data = reader.get

            # Unwrap the anonymous structure
            wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
            hash = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

            # Extract required field
            @encrypted3 = hash[1_u8].as(Bytes)
          end

          # Encode to TLV bytes
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)
            writer.put(nil, {1_u8 => @encrypted3} of TLV::Tag => TLV::Value)
            io.rewind.to_slice
          end
        end

        # TLV structure for signed data in Sigma2
        # Used as input for signature generation
        struct SignedData
          property responder_noc : Bytes
          property responder_icac : Bytes?
          property responder_public_key : Bytes
          property initiator_public_key : Bytes

          def initialize(
            @responder_noc : Bytes,
            @responder_icac : Bytes?,
            @responder_public_key : Bytes,
            @initiator_public_key : Bytes,
          )
          end

          # Encode to TLV bytes for signature
          # TLV fields MUST be in tag order: 1, 2 (optional), 3, 4
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)

            # Build data in tag order to ensure correct TLV encoding
            data = {} of TLV::Tag => TLV::Value
            data[1_u8] = @responder_noc
            if icac = @responder_icac
              data[2_u8] = icac
            end
            data[3_u8] = @responder_public_key
            data[4_u8] = @initiator_public_key

            writer.put(nil, data)
            io.rewind.to_slice
          end
        end

        # TLV structure for encrypted data in Sigma2
        # This structure is TLV-encoded, then encrypted
        struct EncryptedDataSigma2
          property responder_noc : Bytes
          property responder_icac : Bytes?
          property signature : Bytes
          property resumption_id : Bytes

          def initialize(
            @responder_noc : Bytes,
            @responder_icac : Bytes?,
            @signature : Bytes,
            @resumption_id : Bytes,
          )
          end

          # Encode to TLV bytes for encryption
          # TLV fields MUST be in tag order: 1, 2 (optional), 3, 4
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)

            # Build data in tag order to ensure correct TLV encoding
            data = {} of TLV::Tag => TLV::Value
            data[1_u8] = @responder_noc
            if icac = @responder_icac
              data[2_u8] = icac
            end
            data[3_u8] = @signature
            data[4_u8] = @resumption_id

            writer.put(nil, data)
            io.rewind.to_slice
          end

          # Constructor from TLV bytes (after decryption)
          def self.from_bytes(data : Bytes) : EncryptedDataSigma2
            reader = TLV::Reader.new(data)
            tlv_data = reader.get

            # Unwrap the anonymous structure
            wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
            hash = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

            # Extract required fields
            responder_noc = hash[1_u8].as(Bytes)
            signature = hash[3_u8].as(Bytes)
            resumption_id = hash[4_u8].as(Bytes)

            # Extract optional field
            responder_icac = hash[2_u8]?.try(&.as(Bytes))

            new(responder_noc, responder_icac, signature, resumption_id)
          end
        end

        # TLV structure for encrypted data in Sigma3 (TBE_Data3)
        # This structure is decrypted from Sigma3.encrypted3
        struct EncryptedDataSigma3
          property responder_noc : Bytes   # Actually initiator's NOC (named responder_noc for consistency)
          property responder_icac : Bytes? # Actually initiator's ICAC
          property signature : Bytes

          def initialize(
            @responder_noc : Bytes,
            @responder_icac : Bytes?,
            @signature : Bytes,
          )
          end

          # Encode to TLV bytes for encryption
          # TLV fields MUST be in tag order: 1, 2 (optional), 3
          def to_bytes : Bytes
            io = IO::Memory.new
            writer = TLV::Writer.new(io)

            # Build data in tag order to ensure correct TLV encoding
            data = {} of TLV::Tag => TLV::Value
            data[1_u8] = @responder_noc
            if icac = @responder_icac
              data[2_u8] = icac
            end
            data[3_u8] = @signature

            writer.put(nil, data)
            io.rewind.to_slice
          end

          # Constructor from TLV bytes (after decryption)
          def self.from_bytes(data : Bytes) : EncryptedDataSigma3
            reader = TLV::Reader.new(data)
            tlv_data = reader.get

            # Unwrap the anonymous structure
            wrapper = tlv_data.as(Hash(TLV::Tag, TLV::Value))
            hash = wrapper["Any"].as(Hash(TLV::Tag, TLV::Value))

            # Extract required fields
            responder_noc = hash[1_u8].as(Bytes)
            signature = hash[3_u8].as(Bytes)

            # Extract optional field
            responder_icac = hash[2_u8]?.try(&.as(Bytes))

            new(responder_noc, responder_icac, signature)
          end
        end
      end
    end
  end
end
