module Matter
  module Codec
    module DNSCodec
      MAX_MDNS_MESSAGE_SIZE = 1232

      alias Value = String | Array(String) | SrvRecordValue | Slice(UInt8)

      enum MessageType : UInt16
        Query             = 0x0000
        TruncatedQuery    = 0x0200
        Response          = 0x8400 # Authoritative Answer
        TruncatedResponse = 0x8600
      end

      enum RecordType : UInt16
        A    = 0x01
        PTR  = 0x0c
        TXT  = 0x10
        AAAA = 0x1c
        SRV  = 0x21
        NSEC = 0x2f
        ANY  = 0xff
      end

      enum RecordClass : UInt16
        IN  = 0x01
        ANY = 0xff
      end

      class Record
        getter name : String
        getter record_type : RecordType
        getter record_class : RecordClass
        getter? flush_cache : Bool
        getter ttl : UInt32
        getter value : Value

        def initialize(@name : String, @record_type : RecordType, @record_class : RecordClass, @ttl : UInt32, @value : Value, @flush_cache : Bool = false)
        end
      end

      class Query
        getter name : String
        getter record_type : RecordType
        getter record_class : RecordClass
        getter? unicast_response : Bool

        def initialize(@name : String, @record_type : RecordType, @record_class : RecordClass, @unicast_response : Bool = false)
        end
      end

      class Message
        getter transaction_id : UInt16
        getter message_type : MessageType
        getter queries : Array(Query)
        getter answers : Array(Record)
        getter authorities : Array(Record)
        getter additional_records : Array(Record)

        def initialize(@transaction_id : UInt16, @message_type : MessageType, @queries : Array(Query), @answers : Array(Record), @authorities : Array(Record), @additional_records : Array(Record))
        end
      end

      class MessagePartiallyPreEncoded
        getter transaction_id : UInt16
        getter message_type : MessageType
        getter queries : Array(Query)
        getter answers : Union(Array(Record), Array(Slice(UInt8)))
        getter authorities : Array(Record)
        getter additional_records : Union(Array(Record), Array(Slice(UInt8)))

        def initialize(@transaction_id : UInt16, @message_type : MessageType, @queries : Array(Query), @answers : Union(Array(Record), Array(Slice(UInt8))), @authorities : Array(Record), @additional_records : Union(Array(Record), Array(Slice(UInt8))))
        end
      end

      class SrvRecordValue
        getter priority : UInt16
        getter weight : UInt16
        getter port : UInt16
        getter target : String

        def initialize(@priority : UInt16, @weight : UInt16, @port : UInt16, @target : String)
        end
      end

      class PtrRecord < Record
        def initialize(name : String, ptr : String, ttl : UInt32 = 120, flush_cache : Bool = false)
          super(name: name, record_type: RecordType::PTR, record_class: RecordClass::IN, ttl: ttl, value: ptr, flush_cache: flush_cache)
        end
      end

      class ARecord < Record
        def initialize(name : String, ip : String, ttl : UInt32 = 120, flush_cache : Bool = false)
          super(name: name, record_type: RecordType::A, record_class: RecordClass::IN, ttl: ttl, value: ip, flush_cache: flush_cache)
        end
      end

      class AAAARecord < Record
        def initialize(name : String, ip : String, ttl : UInt32 = 120, flush_cache : Bool = false)
          super(name: name, record_type: RecordType::AAAA, record_class: RecordClass::IN, ttl: ttl, value: ip, flush_cache: flush_cache)
        end
      end

      class TxtRecord < Record
        def initialize(name : String, entries : Array(String), ttl : UInt32 = 120, flush_cache : Bool = false)
          super(name: name, record_type: RecordType::TXT, record_class: RecordClass::IN, ttl: ttl, value: entries, flush_cache: flush_cache)
        end
      end

      class SrvRecord < Record
        def initialize(name : String, srv : SrvRecordValue, ttl : UInt32 = 120, flush_cache : Bool = false)
          super(name: name, record_type: RecordType::SRV, record_class: RecordClass::IN, ttl: ttl, value: srv, flush_cache: flush_cache)
        end
      end

      module Base
        def decode(message : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Message?
          begin
            reader = IO::Memory.new

            reader.write(message)
            reader.rewind

            transaction_id = reader.read_bytes(UInt16, byte_format)
            message_type = reader.read_bytes(UInt16, byte_format)
            queries_count = reader.read_bytes(UInt16, byte_format)
            answers_count = reader.read_bytes(UInt16, byte_format)
            authorities_count = reader.read_bytes(UInt16, byte_format)
            additional_records_count = reader.read_bytes(UInt16, byte_format)

            queries = [] of Query
            answers = [] of Record
            authorities = [] of Record
            additional_records = [] of Record

            queries_count.times do
              queries.push(decode_query(reader, message, byte_format))
            end

            answers_count.times do
              answers.push(decode_record(reader, message, byte_format))
            end

            authorities_count.times do
              authorities.push(decode_record(reader, message, byte_format))
            end

            additional_records_count.times do
              additional_records.push(decode_record(reader, message, byte_format))
            end

            Message.new(transaction_id: transaction_id, message_type: MessageType.from_value(message_type.to_i), queries: queries, answers: answers, authorities: authorities, additional_records: additional_records)
          rescue exception
            Log.error(exception: exception) { exception.message }
          end
        end

        private def decode_query(reader : IO::Memory, message : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          name = decode_qname(reader, message)

          record_type = reader.read_bytes(UInt16, byte_format)
          class_integer = reader.read_bytes(UInt16, byte_format)
          unicast_response = (class_integer & 0x8000) != 0
          record_class = class_integer & 0x7fff

          Query.new(name: name, record_type: RecordType.from_value(record_type.to_i), record_class: RecordClass.from_value(record_class.to_i), unicast_response: unicast_response)
        end

        private def decode_record(reader : IO::Memory, message : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          name = decode_qname(reader, message)
          record_type = reader.read_bytes(UInt16, byte_format)
          class_integer = reader.read_bytes(UInt16, byte_format)
          flush_cache = (class_integer & 0x8000) != 0
          record_class = class_integer & 0x7fff
          ttl = reader.read_bytes(UInt32, byte_format)
          value_length = reader.read_bytes(UInt16, byte_format)
          value = Slice(UInt8).new(value_length)

          reader.read(value)

          decoded_value = decode_record_value(value, RecordType.from_value(record_type.to_i), message, byte_format)

          Record.new(name: name, record_type: RecordType.from_value(record_type.to_i), record_class: RecordClass.from_value(record_class.to_i), value: decoded_value, ttl: ttl, flush_cache: flush_cache)
        end

        private def decode_qname(reader : IO::Memory, message : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : String
          message_reader = IO::Memory.new
          name_items = [] of String

          message_reader.write(message)
          message_reader.rewind

          while true
            item_length = reader.read_bytes(UInt8, byte_format)

            break if item_length == 0

            if (item_length & 0xc0) != 0
              index_in_message = reader.read_bytes(UInt8, byte_format) | ((item_length & 0x3f) << 8)
              message_reader.seek(index_in_message)
              name_items.push(decode_qname(message_reader, message, byte_format))
              break
            end

            name_items.push(reader.read_string(item_length))
          end

          return name_items.join(".")
        end

        private def decode_srv_record(value : Slice(UInt8), message : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : SrvRecordValue
          reader = IO::Memory.new

          reader.write(value)
          reader.rewind

          priority = reader.read_bytes(UInt16, byte_format)
          weight = reader.read_bytes(UInt16, byte_format)
          port = reader.read_bytes(UInt16, byte_format)
          target = decode_qname(reader, message)

          SrvRecordValue.new(priority: priority, weight: weight, port: port, target: target)
        end

        private def decode_txt_record(value : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Array(String)
          reader = IO::Memory.new
          result = [] of String

          reader.write(value)
          reader.rewind

          bytes_read = 0

          while bytes_read < value.size
            length = reader.read_bytes(UInt8, byte_format)
            result.push(reader.read_string(length))

            bytes_read += length + 1
          end

          result
        end

        private def decode_aaaa_record(value : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : String
          reader = IO::Memory.new
          ip_items = [] of String

          reader.write(value)
          reader.rewind

          8.times do
            ip_items.push(reader.read_bytes(UInt16, byte_format).to_s(16))
          end

          ip_items.join(":").gsub(/\b:?(?:0+:?){2,}/, "::")
        end

        private def decode_a_record(value : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : String
          reader = IO::Memory.new

          reader.write(value)
          reader.rewind

          ip_items = [] of String

          4.times do
            ip_items.push(reader.read_bytes(UInt8, byte_format).to_s)
          end

          ip_items.join(".")
        end

        private def decode_record_value(value : Slice(UInt8), record_type : RecordType, message : Slice(UInt8), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          case record_type
          when RecordType::PTR
            reader = IO::Memory.new

            reader.write(value)
            reader.rewind

            return decode_qname(reader, message, byte_format)
          when RecordType::SRV
            return decode_srv_record(value, message, byte_format)
          when RecordType::TXT
            return decode_txt_record(value, byte_format)
          when RecordType::AAAA
            return decode_aaaa_record(value, byte_format)
          when RecordType::A
            return decode_a_record(value, byte_format)
          else
            # Unknown type don't decode
            return value
          end
        end

        def encode(message_type : MessageType, transaction_id : UInt16, queries : Array(Query), answers : Array(Record), authorities : Array(Record), additional_records : Array(Record), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Slice(UInt8)
          writer = IO::Memory.new

          if queries.size > 0 && message_type != MessageType::Query && message_type != MessageType::TruncatedQuery
            raise Exception.new("Queries can only be included in query messages!")
          end

          if authorities.size > 0
            raise Exception.new("Authority answers are not supported yet!")
          end

          byte_format.encode(transaction_id, writer)
          byte_format.encode(message_type.value, writer)
          byte_format.encode(queries.size.to_u16, writer)
          byte_format.encode(answers.size.to_u16, writer)
          byte_format.encode(authorities.size.to_u16, writer)
          byte_format.encode(additional_records.size.to_u16, writer)

          queries.each do |query|
            writer.write(encode_qname(query.name, byte_format))
            byte_format.encode(query.record_type.value, writer)
            byte_format.encode((query.record_class.value | (query.unicast_response? ? 0x8000 : 0)).to_u16, writer)
          end

          records = ([] of Record)
            .concat(answers)
            .concat(authorities)
            .concat(additional_records)

          records.each do |record_entry|
            writer.write(encode_record(record_entry, byte_format))
          end

          writer.rewind.to_slice
        end

        private def encode_record(record_entry : Record, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Slice(UInt8)
          writer = IO::Memory.new

          writer.write(encode_qname(record_entry.name, byte_format))
          byte_format.encode(record_entry.record_type.value, writer)
          byte_format.encode((record_entry.record_class.value | (record_entry.flush_cache? ? 0x8000 : 0)).to_u16, writer)
          byte_format.encode(record_entry.ttl, writer)

          encoded_value = encode_record_value(record_entry.value, RecordType.from_value(record_entry.record_type.to_i), byte_format)
          byte_format.encode(encoded_value.size.to_u16, writer)
          writer.write(encoded_value)

          writer.rewind.to_slice
        end

        private def encode_record_value(value : Value, record_type : RecordType, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian)
          case record_type
          when RecordType::PTR
            return encode_qname(value.to_s, byte_format)
          when RecordType::SRV
            return encode_srv_record(value.as(SrvRecordValue), byte_format) if value.is_a?(SrvRecordValue)
            raise Exception.new("Can not decode SrvRecordValue #{value}")
          when RecordType::TXT
            return encode_txt_record(value.as(Array(String)), byte_format) if value.is_a?(Array(String))
            raise Exception.new("Can not decode Array(String) #{value}")
          when RecordType::AAAA
            return encode_aaaa_record(value.to_s, byte_format)
          when RecordType::A
            return encode_a_record(value.to_s, byte_format)
          else
            return value if value.is_a?(Slice(UInt8))
            raise Exception.new("Unsupported record type #{typeof(value)}")
          end
        end

        private def encode_a_record(ip : String, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Slice(UInt8)
          raise Exception.new("Invalid A record value: #{ip}") unless ip.includes?(".")

          writer = IO::Memory.new

          ip.split(".").each do |part|
            byte_format.encode(UInt8.new(part), writer)
          end

          writer.rewind.to_slice
        end

        private def encode_aaaa_record(ip : String, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Slice(UInt8)
          raise Exception.new("Invalid AAAA record value: #{ip}") unless ip.includes?(":")

          writer = IO::Memory.new

          parts = ip.split(":")

          parts.each do |part|
            if part == ""
              compressed_parts = 8 - parts.size

              compressed_parts.times do
                byte_format.encode(UInt16.new(0), writer)
              end
            end

            byte_format.encode(UInt16.new(part, base: 16), writer)
          end

          writer.rewind.to_slice
        end

        private def encode_txt_record(entries : Array(String), byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Slice(UInt8)
          writer = IO::Memory.new

          entries.each do |entry|
            byte_format.encode(entry.to_slice.size.to_u8, writer)
            writer.write(entry.to_slice)
          end

          writer.rewind.to_slice
        end

        private def encode_srv_record(value : SrvRecordValue, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Slice(UInt8)
          writer = IO::Memory.new

          byte_format.encode(value.priority, writer)
          byte_format.encode(value.weight, writer)
          byte_format.encode(value.port, writer)
          writer.write(encode_qname(value.target, byte_format))

          writer.rewind.to_slice
        end

        private def encode_qname(qname : String, byte_format : IO::ByteFormat = IO::ByteFormat::BigEndian) : Slice(UInt8)
          writer = IO::Memory.new

          if qname.size > 0
            qname.split(".").each do |label|
              byte_format.encode(label.to_slice.size.to_u8, writer)
              writer.write(label.to_slice)
            end
          end

          byte_format.encode(UInt8.new(0), writer)

          writer.rewind.to_slice
        end
      end
    end
  end
end
