module Matter
  module Codec
    module DERCodec
      OBJECT_ID_KEY = "_objectId"
      TAG_ID_KEY    = "_tag"
      BYTES_KEY     = "_bytes"
      ELEMENTS_KEY  = "_elements"
      BITS_PADDING  = "_padding"

      CONSTRUCTED = 0x20

      alias Value = UInt8 | UInt16 | UInt32 | String | Bool | Time | Slice(UInt8) | Array(Value) | Hash(String, Value)?

      enum Type : UInt8
        Boolean          = 0x01
        UnsignedInt      = 0x02
        BitString        = 0x03
        OctetString      = 0x04
        ObjectIdentifier = 0x06
        UTF8String       = 0x0c
        Sequence         = 0x10
        Set              = 0x11
        UtcDate          = 0x17
      end

      enum Class : UInt8
        Universal       = 0x00
        Application     = 0x40
        ContextSpecific = 0x80
        Private         = 0xc0
      end

      module Base
        extend self

        def encode(value : Value) : Slice(UInt8)
          case value
          when .is_a?(Array)
            encode_array(value)
          when .is_a?(Slice(UInt8))
            encode_slice(value.as(Slice(UInt8)))
          when .is_a?(Time)
            encode_time(value.as(Time))
          when .is_a?(Hash)
            if value
                 .as(Hash(String, Value))
                 .[TAG_ID_KEY]?
              if value[BITS_PADDING]?
                writer = IO::Memory.new
                byte_format = IO::ByteFormat::BigEndian

                byte_format.encode(value[BITS_PADDING].as(UInt8), writer)

                return encode_ansi1(value[TAG_ID_KEY].as(UInt8), Slice(UInt8).join([writer.rewind.to_slice, value.[BYTES_KEY].as(Slice(UInt8))]))
              else
                return encode_ansi1(value[TAG_ID_KEY].as(UInt8), value.[BYTES_KEY].as(Slice(UInt8)))
              end
            end

            encode_hash(value)
          when .is_a?(String)
            encode_string(value.as(String))
          when .is_a?(UInt8)
            encode_unsigned_int(value.as(UInt8))
          when .is_a?(UInt16)
            encode_unsigned_int(value.as(UInt16))
          when .is_a?(UInt32)
            encode_unsigned_int(value.as(UInt32))
          when .is_a?(Bool)
            encode_bool(value.as(Bool))
          when .nil?
            Slice(UInt8).new(1, 0)
          else
            raise Exception.new("An unsupported type was passed to the encoder")
          end
        end

        private def encode_time(value : Time) : Slice(UInt8)
          encode_ansi1(Type::UtcDate.value, value.to_rfc3339.gsub(/[-:.T]/, "").[2..14].to_slice)
        end

        private def encode_bool(value : Bool) : Slice(UInt8)
          encode_ansi1(Type::Boolean.value, value ? Slice(UInt8).new(1, 0xff) : Slice(UInt8).new(1, 0x00))
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

        private def encode_string(value : String) : Slice(UInt8)
          encode_ansi1(Type::UTF8String.value, value.to_slice)
        end

        def encode_unsigned_int(value : UInt8 | UInt16 | UInt32, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          return encode_ansi1(Type::UnsignedInt.value, Slice(UInt8).new(1, 0)) if value == 0

          writer = IO::Memory.new(5)

          byte_format.encode(value.to_u32, writer)

          index = 0

          loop do
            writer.pos = index
            break if writer.read_bytes(UInt8, byte_format) != 0

            writer.pos = index + 1
            break if writer.read_bytes(UInt8, byte_format) >= 0x80

            index += 1

            break if index == 4
          end

          array = writer.rewind.to_slice.to_a.[index..]
          slice = Slice(UInt8).new(array.size) { |i| array[i] }

          encode_ansi1(Type::UnsignedInt.value, slice)
        end

        def encode_length_bytes(value, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          return Slice(UInt8).new(1, 0) if value == 0

          slice = Slice(UInt8).new(5)
          writer = IO::Memory.new(slice)

          index = 0
          writer.pos = 1

          byte_format.encode(value.to_u32, writer)
          writer.rewind

          loop do
            break if writer.read_bytes(UInt8, byte_format) != 0_u8

            index += 1
            break if index == 4
          end

          length = slice.size - index
          writer.pos = index

          if length > 1 || writer.read_bytes(UInt8) >= 0x80
            index -= 1
            writer.pos = index
            byte_format.encode(UInt8.new(0x80 + length), writer)
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
          return io.write_byte(value.to_u8) if value < 128

          # Calculate number of bytes needed (7 bits per byte)
          bytes_needed = 1
          temp = value
          while temp >= 128
            temp >>= 7
            bytes_needed += 1
          end

          # Encode from most significant to least significant
          # All bytes except last have high bit set (0x80)
          bytes_needed.downto(1) do |i|
            shift = (i - 1) * 7
            byte = ((value >> shift) & 0x7f).to_u8
            byte |= 0x80 if i > 1 # Set continuation bit except on last byte
            io.write_byte(byte)
          end
        end

        # Encode OID from dotted decimal notation or array of arcs
        # Returns DER-encoded OBJECT IDENTIFIER bytes
        def encode_oid(oid : String | Array(UInt32)) : Slice(UInt8)
          arcs = oid.is_a?(String) ? parse_oid(oid) : oid

          raise ArgumentError.new("OID must have at least 2 arcs") if arcs.size < 2
          raise ArgumentError.new("First arc must be 0, 1, or 2") if arcs[0] > 2
          raise ArgumentError.new("Second arc must be < 40 when first arc is 0 or 1") if arcs[0] < 2 && arcs[1] >= 40

          io = IO::Memory.new

          # First two arcs are encoded as: (first * 40) + second
          first_byte = (arcs[0] * 40 + arcs[1]).to_u32
          encode_base128(first_byte, io)

          # Remaining arcs are encoded individually
          arcs[2..].each do |arc|
            encode_base128(arc, io)
          end

          # Wrap in DER OBJECT IDENTIFIER tag
          oid_bytes = io.to_slice
          encode_ansi1(Type::ObjectIdentifier.value, oid_bytes)
        end

        # Alias for consistency with other encoding methods
        def encode_object_identifier(oid : String | Array(UInt32)) : Slice(UInt8)
          encode_oid(oid)
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

        def decode(data : Slice(UInt8)) : Node
          reader = IO::Memory.new

          reader.write(data)
          reader.rewind

          decode_rec(reader)
        end

        private def decode_rec(reader : IO::Memory, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Node
          tag, slice = decode_ansi1(reader, byte_format)

          if tag == Type::BitString.value
            array = slice.to_a.[1..]
            data = Slice(UInt8).new(array.size) { |i| array[i] }

            return Node.new(tag_id: tag.as(UInt8), data: data, padding: array.first.to_u8)
          end

          if (tag & CONSTRUCTED) == 0
            return Node.new(tag_id: tag, data: slice)
          end

          elements = [] of Value

          elements_reader = IO::Memory.new
          elements_reader.write(reader.to_slice)

          while elements_reader.pos != elements_reader.size
            elements.push(decode_rec(elements_reader, byte_format).value)
          end

          Node.new(tag_id: tag, data: slice, elements: elements)
        end

        private def decode_ansi1(reader : IO::Memory, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Tuple(UInt8, Slice(UInt8))
          tag = reader.read_bytes(UInt8, byte_format)
          length = reader.read_bytes(UInt8, byte_format)

          if (length & 0x80) != 0
            sub = length & 0x7f
            length = 0

            loop do
              break if sub <= 0

              length = (length << 8) + reader.read_bytes(UInt8, byte_format)
              sub -= 1
            end
          end

          slice = Slice(UInt8).new(length)
          reader.read(slice)

          {tag, slice}
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
            length = encoded[1].to_i
            value[TAG_ID_KEY] = Type::ObjectIdentifier.value
            value[BYTES_KEY] = encoded[2, length]
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

      class ByteArray
        getter value : Hash(String, Value) = {} of String => Value

        def initialize(data : Slice(UInt8), padding : UInt8 = 0)
          value[TAG_ID_KEY] = Type::BitString.value
          value[BYTES_KEY] = data
          value[BITS_PADDING] = padding
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

      class ContextTaggedSlice
        getter value : Hash(String, Value) = {} of String => Value

        def initialize(tag_id : UInt8, data : Slice(UInt8))
          value[TAG_ID_KEY] = tag_id | Class::ContextSpecific.value
          value[BYTES_KEY] = data
        end
      end

      class Node
        getter value : Hash(String, Value) = {} of String => Value

        def initialize(tag_id : UInt8, data : Slice(UInt8), elements : Array(Value) = [] of Value, padding : UInt8? = nil)
          value[TAG_ID_KEY] = tag_id
          value[BYTES_KEY] = data
          value[ELEMENTS_KEY] = elements
          value[BITS_PADDING] = padding
        end
      end

      PUBLIC_KEY_EC_PRIME256V1_X962 = ->(key : Slice(UInt8)) {
        value = {
          "type" => {
            "algorithm" => ObjectId.new("2A8648CE3D0201").value.as(Matter::Codec::DERCodec::Value),   # EC Public Key
            "curve"     => ObjectId.new("2A8648CE3D030107").value.as(Matter::Codec::DERCodec::Value), # Curve P256_V1
          },
          "bytes" => ByteArray.new(key).value.as(Matter::Codec::DERCodec::Value),
        } of String => Value

        value.as(Matter::Codec::DERCodec::Value)
      }

      ECDSA_WITH_SHA256_X962 = -> {
        Object.new("2A8648CE3D040302").value
      }

      SHA256_CMS = -> {
        Object.new("608648016503040201").value
      }

      ORGANISATION_NAME_X520 = ->(name : String) {
        [Object.new("55040A", {"name" => name}).value] of Value
      }

      SUBJECT_KEY_IDENTIFIER_X509 = ->(identifier : Slice(UInt8)) {
        Object.new("551d0e", {"value" => Base.encode(identifier)}).value
      }

      AUTHORITY_KEY_IDENTIFIER_X509 = ->(identifier : Slice(UInt8)) {
        Object.new("551d23", {"value" => Base.encode({"id" => ContextTaggedSlice.new(0, identifier).value})}).value
      }

      BASIC_CONSTRAINTS_X509 = ->(constraints : Value) {
        Object.new("551d13", {"critical" => true, "value" => Base.encode(constraints)}).value
      }

      EXTENDED_KEY_USAGE_X509 = ->(client_auth : Bool, server_auth : Bool) {
        Object.new("551d25", {
          "critical" => true,
          "value"    => Base.encode({
            "client" => client_auth ? ObjectId.new("2b06010505070302").value : nil,
            "server" => server_auth ? ObjectId.new("2b06010505070301").value : nil,
          } of String => Value),
        }).value
      }

      KEY_USAGE_SIGNATURE_X509 = -> {
        Object.new("551d0f", {
          "critical" => true.as(Value),
          "value"    => Base.encode(ByteArray.new(Slice(UInt8).new(1, (0x03 << 1).to_u8), 1).value),
        } of String => Value).value
      }

      KEY_USAGE_SIGNATURE_CONTENT_COMMITTED_X509 = -> {
        Object.new("551d0f", {
          "critical" => true,
          "value"    => Base.encode(ByteArray.new(Slice(UInt8).new(1, (0x03 << 1).to_u8), 1).value),
        } of String => Value).value
      }

      Pkcs7Data = ->(data : Value) {
        Object.new("2A864886F70D010701", {"value" => ContextTagged.new(0, data).value}).value
      }

      Pkcs7SignedData = ->(data : Value) {
        Object.new("2a864886f70d010702", {"value" => ContextTagged.new(0, data).value}).value
      }
    end
  end
end
