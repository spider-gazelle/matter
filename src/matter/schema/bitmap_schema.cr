# Bitmap Schema for Matter protocol
# Provides encoding/decoding of bitmaps with named bit fields
#
# Ported from matter.js BitmapSchema.ts

module Matter
  module Schema
    # Represents a single bit flag at a specific position
    record BitFlag, bit : Int32

    # Represents a multi-bit field starting at a position with a width
    record BitField, bit : Int32, width : Int32

    # Represents a multi-bit field that maps to an enum type
    record BitFieldEnum(E), bit : Int32, width : Int32

    # BitmapSchema provides encoding and decoding for bitmaps
    # with named fields at specific bit positions
    class BitmapSchema(T)
      # Field definition: name => bit position or field definition
      @fields : Hash(String, BitFlag | BitField)

      def initialize(@fields : Hash(String, BitFlag | BitField))
      end

      # Encode a named hash of field values to an integer bitmap
      def encode(values : Hash(String, Bool | Int32 | Int64)) : Int64
        result = 0_i64

        @fields.each do |name, field|
          value = values[name]?
          next if value.nil?

          case field
          when BitFlag
            if value.is_a?(Bool) && value
              result |= (1_i64 << field.bit)
            end
          when BitField
            if value.is_a?(Int32) || value.is_a?(Int64)
              int_value = value.to_i64
              mask = (1_i64 << field.width) - 1
              result |= ((int_value & mask) << field.bit)
            end
          end
        end

        result
      end

      # Decode an integer bitmap to a named hash of field values
      def decode(bitmap : Int32 | Int64) : Hash(String, Bool | Int32)
        result = {} of String => Bool | Int32
        bitmap_i64 = bitmap.to_i64

        @fields.each do |name, field|
          case field
          when BitFlag
            result[name] = (bitmap_i64 & (1_i64 << field.bit)) != 0
          when BitField
            mask = (1_i64 << field.width) - 1
            result[name] = ((bitmap_i64 >> field.bit) & mask).to_i32
          end
        end

        result
      end
    end

    # ByteArrayBitmapSchema works with byte arrays instead of integers
    # Used for bitmaps that span multiple bytes
    class ByteArrayBitmapSchema(T)
      @fields : Hash(String, BitFlag | BitField)

      def initialize(@fields : Hash(String, BitFlag | BitField))
      end

      # Encode a named hash of field values to a byte array
      def encode(values : Hash(String, Bool | Int32 | Int64)) : Bytes
        # Calculate required bytes based on highest bit
        max_bit = 0
        @fields.each do |_, field|
          case field
          when BitFlag
            max_bit = {max_bit, field.bit + 1}.max
          when BitField
            max_bit = {max_bit, field.bit + field.width}.max
          end
        end

        byte_count = (max_bit + 7) // 8
        result = Bytes.new(byte_count)

        @fields.each do |name, field|
          value = values[name]?
          next if value.nil?

          case field
          when BitFlag
            if value.is_a?(Bool) && value
              byte_index = field.bit // 8
              bit_in_byte = field.bit % 8
              result[byte_index] = result[byte_index] | (1_u8 << bit_in_byte)
            end
          when BitField
            if value.is_a?(Int32) || value.is_a?(Int64)
              int_value = value.to_i64
              # Write each bit of the field
              field.width.times do |i|
                bit_pos = field.bit + i
                if (int_value & (1_i64 << i)) != 0
                  byte_index = bit_pos // 8
                  bit_in_byte = bit_pos % 8
                  result[byte_index] = result[byte_index] | (1_u8 << bit_in_byte)
                end
              end
            end
          end
        end

        result
      end

      # Decode a byte array to a named hash of field values
      def decode(bitmap : Bytes) : Hash(String, Bool | Int32)
        result = {} of String => Bool | Int32

        @fields.each do |name, field|
          case field
          when BitFlag
            byte_index = field.bit // 8
            bit_in_byte = field.bit % 8
            if byte_index < bitmap.size
              result[name] = (bitmap[byte_index] & (1_u8 << bit_in_byte)) != 0
            else
              result[name] = false
            end
          when BitField
            value = 0_i64
            field.width.times do |i|
              bit_pos = field.bit + i
              byte_index = bit_pos // 8
              bit_in_byte = bit_pos % 8
              if byte_index < bitmap.size && (bitmap[byte_index] & (1_u8 << bit_in_byte)) != 0
                value |= (1_i64 << i)
              end
            end
            result[name] = value.to_i32
          end
        end

        result
      end
    end

    # Factory methods to create bitmap schemas easily
    module Bitmap
      def self.flag(bit : Int32) : BitFlag
        BitFlag.new(bit)
      end

      def self.field(bit : Int32, width : Int32) : BitField
        BitField.new(bit, width)
      end

      def self.schema(fields : Hash(String, BitFlag | BitField)) : BitmapSchema(Nil)
        BitmapSchema(Nil).new(fields)
      end

      def self.byte_array_schema(fields : Hash(String, BitFlag | BitField)) : ByteArrayBitmapSchema(Nil)
        ByteArrayBitmapSchema(Nil).new(fields)
      end
    end
  end
end
