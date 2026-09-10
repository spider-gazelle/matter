module Matter
  module Codec
    module DERCodec
      OBJECT_ID_KEY = "_objectId"
      TAG_ID_KEY    = "_tag"
      BYTES_KEY     = "_bytes"

      CONSTRUCTED          = 0x20
      LONG_FORM_LENGTH     = 0x80
      OID_ARC_BITS         =    7
      OID_ARC_RADIX        = 1 << OID_ARC_BITS
      OID_ARC_MASK         = OID_ARC_RADIX - 1
      OID_FIRST_ARC_FACTOR = 40_u32
      OID_MAX_FIRST_ARC    =  2_u32
      OID_MIN_ARCS         =      2
      INTEGER_BYTES        = sizeof(UInt32)
      TAG_BYTES            = sizeof(UInt8)
      SHORT_HEADER_BYTES   = TAG_BYTES + sizeof(UInt8)

      alias Value = UInt8 | UInt16 | UInt32 | Slice(UInt8) | Array(Value) | Hash(String, Value)?

      enum Type : UInt8
        UnsignedInt      = 0x02
        OctetString      = 0x04
        ObjectIdentifier = 0x06
        Sequence         = 0x10
        Set              = 0x11
      end

      enum Class : UInt8
        ContextSpecific = 0x80
      end

      module Base
        extend self

        def encode(value : Value) : Slice(UInt8)
          case value
          when .is_a?(Array)
            encode_array(value)
          when .is_a?(Slice(UInt8))
            encode_slice(value.as(Slice(UInt8)))
          when .is_a?(Hash)
            if value
                 .as(Hash(String, Value))
                 .[TAG_ID_KEY]?
              return encode_ansi1(value[TAG_ID_KEY].as(UInt8), value[BYTES_KEY].as(Slice(UInt8)))
            end

            encode_hash(value)
          when .is_a?(UInt8)
            encode_unsigned_int(value.as(UInt8))
          when .is_a?(UInt16)
            encode_unsigned_int(value.as(UInt16))
          when .is_a?(UInt32)
            encode_unsigned_int(value.as(UInt32))
          when .nil?
            Slice(UInt8).new(1, 0)
          else
            raise Matter::CodecError.new("An unsupported type was passed to the encoder")
          end
        end

        private def encode_array(array : Array(Value)) : Slice(UInt8)
          encoded_entries = [] of Slice(UInt8)

          array.each do |entry|
            encoded_entries.push(encode(entry))
          end

          encode_ansi1((Type::Set.value | CONSTRUCTED).to_u8, Slice(UInt8).join(encoded_entries))
        end

        private def encode_slice(value : Slice(UInt8)) : Slice(UInt8)
          encode_ansi1(Type::OctetString.value, value)
        end

        private def encode_hash(hash : Hash(String, Value)) : Slice(UInt8)
          attributes = [] of Slice(UInt8)

          hash.keys.each do |key|
            attributes.push(encode(hash[key]))
          end

          encode_ansi1((Type::Sequence.value | CONSTRUCTED).to_u8, Slice(UInt8).join(attributes))
        end

        def encode_unsigned_int(value : UInt8 | UInt16 | UInt32, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          return encode_ansi1(Type::UnsignedInt.value, Slice(UInt8).new(1, 0)) if value == 0

          writer = IO::Memory.new(INTEGER_BYTES + TAG_BYTES)

          byte_format.encode(value.to_u32, writer)

          index = 0

          loop do
            writer.pos = index
            break if writer.read_bytes(UInt8, byte_format) != 0

            writer.pos = index + 1
            break if writer.read_bytes(UInt8, byte_format) >= LONG_FORM_LENGTH

            index += 1

            break if index == INTEGER_BYTES
          end

          array = writer.rewind.to_slice.to_a.[index..]
          slice = Slice(UInt8).new(array.size) { |i| array[i] }

          encode_ansi1(Type::UnsignedInt.value, slice)
        end

        def encode_length_bytes(value, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          return Slice(UInt8).new(1, 0) if value == 0

          slice = Slice(UInt8).new(INTEGER_BYTES + TAG_BYTES)
          writer = IO::Memory.new(slice)

          index = 0
          writer.pos = 1

          byte_format.encode(value.to_u32, writer)
          writer.rewind

          loop do
            break if writer.read_bytes(UInt8, byte_format) != 0_u8

            index += 1
            break if index == INTEGER_BYTES
          end

          length = slice.size - index
          writer.pos = index

          if length > 1 || writer.read_bytes(UInt8) >= LONG_FORM_LENGTH
            index -= 1
            writer.pos = index
            byte_format.encode(UInt8.new(LONG_FORM_LENGTH + length), writer)
          end

          array = writer.rewind.to_slice.to_a.[index..]
          Slice(UInt8).new(array.size) { |i| array[i] }
        end

        private def encode_ansi1(type : UInt8, data : Slice(UInt8)) : Slice(UInt8)
          Slice(UInt8).join([Slice(UInt8).new(1, type), encode_length_bytes(data.size), data])
        end

        # Parse OID from dotted decimal notation (e.g., "1.2.840.10045.4.3.2")
        # Returns array of UInt32 values representing each arc
        def parse_oid(oid : String) : Array(UInt32)
          oid.split('.').map(&.to_u32)
        end

        # Encode a single OID arc value using base-128 encoding
        # Values >= 128 are encoded in multiple bytes with continuation bits
        private def encode_base128(value : UInt32, io : IO::Memory)
          return io.write_byte(value.to_u8) if value < OID_ARC_RADIX

          # Calculate number of bytes needed (7 bits per byte)
          bytes_needed = 1
          temp = value
          while temp >= OID_ARC_RADIX
            temp >>= OID_ARC_BITS
            bytes_needed += 1
          end

          # Encode from most significant to least significant
          # All bytes except last have high bit set (0x80)
          bytes_needed.downto(1) do |i|
            shift = (i - 1) * OID_ARC_BITS
            byte = ((value >> shift) & OID_ARC_MASK).to_u8
            byte |= LONG_FORM_LENGTH if i > 1 # Set continuation bit except on last byte
            io.write_byte(byte)
          end
        end

        # Encode OID from dotted decimal notation or array of arcs
        # Returns DER-encoded OBJECT IDENTIFIER bytes
        def encode_oid(oid : String | Array(UInt32)) : Slice(UInt8)
          arcs = oid.is_a?(String) ? parse_oid(oid) : oid

          raise ArgumentError.new("OID must have at least 2 arcs") if arcs.size < OID_MIN_ARCS
          raise ArgumentError.new("First arc must be 0, 1, or 2") if arcs[0] > OID_MAX_FIRST_ARC
          raise ArgumentError.new("Second arc must be < 40 when first arc is 0 or 1") if arcs[0] < OID_MAX_FIRST_ARC && arcs[1] >= OID_FIRST_ARC_FACTOR

          io = IO::Memory.new

          # First two arcs are encoded as: (first * 40) + second
          first_byte = (arcs[0] * OID_FIRST_ARC_FACTOR + arcs[1]).to_u32
          encode_base128(first_byte, io)

          # Remaining arcs are encoded individually
          arcs[OID_MIN_ARCS..].each do |arc|
            encode_base128(arc, io)
          end

          # Wrap in DER OBJECT IDENTIFIER tag
          oid_bytes = io.to_slice
          encode_ansi1(Type::ObjectIdentifier.value, oid_bytes)
        end

        # Encode bytes as DER OCTET STRING
        # Returns DER-encoded OCTET STRING (tag 0x04)
        def encode_octet_string(data : Bytes) : Bytes
          encode_ansi1(Type::OctetString.value, data)
        end

        # Encode bytes as DER SEQUENCE
        # Returns DER-encoded SEQUENCE (tag 0x30 with constructed bit)
        def encode_sequence(data : Bytes) : Bytes
          encode_ansi1((Type::Sequence.value | CONSTRUCTED).to_u8, data)
        end
      end

      class ObjectId
        include Base

        getter value : Hash(String, Value) = {} of String => Value

        # Initialize ObjectId from either:
        # - Hex string (e.g., "2A8648CE3D0201") - legacy format
        # - Dotted decimal notation (e.g., "1.2.840.10045.2.1")
        def initialize(object_id : String)
          # Detect format: dotted decimal contains '.', hex does not
          if object_id.includes?('.')
            # Dotted decimal notation - use new OID encoder
            encoded = Base.encode_oid(object_id)
            # Strip off the DER tag and length, keep only the OID bytes
            # encoded[0] = 0x06 (OBJECT IDENTIFIER tag)
            # encoded[1] = length
            # encoded[2..] = actual OID bytes
            length = encoded[TAG_BYTES].to_i
            value[TAG_ID_KEY] = Type::ObjectIdentifier.value
            value[BYTES_KEY] = encoded[SHORT_HEADER_BYTES, length]
          else
            # Hex string - legacy format
            value[TAG_ID_KEY] = Type::ObjectIdentifier.value
            value[BYTES_KEY] = object_id.hexbytes
          end
        end
      end

      class Object
        getter value : Hash(String, Value) = {} of String => Value

        def initialize(object_id : String, content : Hash(String, Value) = {} of String => Value)
          value[OBJECT_ID_KEY] =
            ObjectId
              .new(object_id)
              .value

          value.merge!(content)
        end
      end

      class ContextTagged
        include Base

        getter value : Hash(String, Value) = {} of String => Value

        def initialize(tag_id : UInt8, sub : Value? = nil)
          value[TAG_ID_KEY] = tag_id | Class::ContextSpecific.value | CONSTRUCTED
          value[BYTES_KEY] = sub.nil? ? Slice(UInt8).empty : encode(sub)
        end
      end

      ECDSA_WITH_SHA256_X962 = -> {
        Object.new("2A8648CE3D040302").value
      }

      SHA256_CMS = -> {
        Object.new("608648016503040201").value
      }

      Pkcs7Data = ->(data : Value) {
        Object.new("2A864886F70D010701", {"value" => ContextTagged.new(0, data).value}).value
      }
    end
  end
end
