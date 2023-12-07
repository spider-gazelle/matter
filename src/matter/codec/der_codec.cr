module Matter
  module Codec
    module DERCodec
      OBJECT_ID_KEY = "_objectId"
      TAG_ID_KEY    = "_tag"
      BYTES_KEY     = "_bytes"
      ELEMENTS_KEY  = "_elements"
      BITS_PADDING  = "_padding"

      CONSTRUCTED = 0x20

      alias Value = UInt8 | UInt16 | UInt32 | UInt32 | String | Bool | Time | Nil | Slice(UInt8) | Array(Value) | Hash(String, Value)

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
            return encode_array(value)
          when .is_a?(Slice(UInt8))
            return encode_slice(value.as(Slice(UInt8)))
          when .is_a?(Time)
            return encode_time(value.as(Time))
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

            return encode_hash(value)
          when .is_a?(String)
            return encode_string(value.as(String))
          when .is_a?(UInt8)
            return encode_unsigned_int(value.as(UInt8))
          when .is_a?(UInt16)
            return encode_unsigned_int(value.as(UInt16))
          when .is_a?(UInt32)
            return encode_unsigned_int(value.as(UInt32))
          when .is_a?(Bool)
            return encode_bool(value.as(Bool))
          when .is_a?(Nil)
            return Slice(UInt8).new(1, 0)
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
        getter value : Hash(String, Value) = {} of String => Value

        def initialize(object_id : String)
          chunks = object_id.split.map(&.to_u8(16))

          value[TAG_ID_KEY] = Type::ObjectIdentifier.value
          value[BYTES_KEY] = Slice(UInt8).new(chunks.size) { |i| chunks[i] }
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

        def initialize(tag_id : UInt8, value : Slice(UInt8))
          value[TAG_ID_KEY] = tag_id | Class::ContextSpecific.value
          value[BYTES_KEY] = value
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

      PublicKeyEcPrime256v1_X962 = ->(key : Slice(UInt8)) {
        value = {
          "type" => {
            "algorithm" => ObjectId.new("2A 86 48 CE 3D 02 01").value.as(Matter::Codec::DERCodec::Value),    # EC Public Key
            "curve"     => ObjectId.new("2A 86 48 CE 3D 03 01 07").value.as(Matter::Codec::DERCodec::Value), # Curve P256_V1
          },
          "bytes" => ByteArray.new(key).value.as(Matter::Codec::DERCodec::Value),
        } of String => Value

        value.as(Matter::Codec::DERCodec::Value)
      }

      EcdsaWithSHA256_X962 = ->{
        Object.new("2A 86 48 CE 3D 04 03 02").value
      }

      SHA256_CMS = ->{
        Object.new("60 86 48 01 65 03 04 02 01").value
      }

      OrganisationName_X520 = ->(name : String) {
        [Object.new("55 04 0A", {"name" => name}).value] of Value
      }

      SubjectKeyIdentifier_X509 = ->(identifier : Slice(UInt8)) {
        Object.new("55 1d 0e", {"value" => Base.encode(identifier)}).value
      }

      AuthorityKeyIdentifier_X509 = ->(identifier : Slice(UInt8)) {
        Object.new("55 1d 23", {"value" => Base.encode({"id" => ContextTaggedSlice.new(0, identifier).value})}).value
      }

      BasicConstraints_X509 = ->(constraints : Value) {
        Object.new("55 1d 13", {"critical" => true, "value" => Base.encode(constraints)}).value
      }

      ExtendedKeyUsage_X509 = ->(client_auth : Bool, server_auth : Bool) {
        Object.new("55 1d 25", {
          "critical" => true,
          "value"    => Base.encode({
            "client" => client_auth ? ObjectId.new("2b 06 01 05 05 07 03 02").value : nil,
            "server" => server_auth ? ObjectId.new("2b 06 01 05 05 07 03 01").value : nil,
          } of String => Value),
        }).value
      }

      KeyUsage_Signature_X509 = ->{
        Object.new("55 1d 0f", {
          "critical" => true.as(Value),
          "value"    => Base.encode(ByteArray.new(Slice(UInt8).new(1, (0x03 << 1).to_u8), 1).value),
        } of String => Value).value
      }

      KeyUsage_Signature_ContentCommited_X509 = ->{
        Object.new("55 1d 0f", {
          "critical" => true,
          "value"    => Base.encode(ByteArray.new(Slice(UInt8).new(1, (0x03 << 1).to_u8), 1).value),
        } of String => Value).value
      }

      Pkcs7Data = ->(data : Value) {
        Object.new("2A 86 48 86 F7 0D 01 07 01", {"value" => ContextTagged.new(0, data).value}).value
      }

      Pkcs7SignedData = ->(data : Value) {
        Object.new("2a 86 48 86 f7 0d 01 07 02", {"value" => ContextTagged.new(0, data).value}).value
      }
    end
  end
end
