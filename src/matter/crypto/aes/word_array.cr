# Copyright 2022-2025 Matter.js Authors
# SPDX-License-Identifier: Apache-2.0
#
# Crystal port of matter.js WordArray helper for AES operations

module Matter::Crypto::AES
  # A 32-bit word array for AES algorithm.
  # Note that we use signed integers to match JavaScript bit shift semantics.
  alias WordArray = Slice(Int32)

  module WordArrayHelper
    # Create a new word array with specified length
    def self.create(length : Int32) : WordArray
      Slice(Int32).new(length, 0)
    end

    # Convert byte array to word array
    def self.from_bytes(bytes : Bytes, alignment : Int32 = 1) : WordArray
      input_bytes = bytes.size
      alloc_words = ((input_bytes / 4.0 / alignment).ceil * alignment).to_i
      result = create(alloc_words)

      # Convert full words from bytes to words (big-endian)
      i = 0
      while i + 4 <= input_bytes
        result[i // 4] = read_int32_be(bytes, i)
        i += 4
      end

      # If byte array is not aligned to words, compute final word manually
      if i < input_bytes
        result[i // 4] = read_partial_word(bytes, i, input_bytes - i)
      end

      result
    end

    # Copy bytes into a 4-word block. If input is too short, sets missing bytes to zero.
    def self.bytes_to_block(bytes : Bytes, block : WordArray, byte_offset : Int32 = 0)
      4.times do |i|
        offset = byte_offset + i * 4
        if offset + 4 <= bytes.size
          block[i] = read_int32_be(bytes, offset)
        elsif offset >= bytes.size
          block[i] = 0
        else
          block[i] = read_partial_word(bytes, offset)
        end
      end
    end

    # Read a word from a byte array that may be smaller than four bytes (big-endian)
    def self.read_partial_word(bytes : Bytes, offset : Int32, bytes_available : Int32? = nil) : Int32
      available = bytes_available || (bytes.size - offset)
      word = 0_u32

      4.times do |i|
        word = (word << 8)
        if i < available && offset + i < bytes.size
          word |= bytes[offset + i].to_u32
        end
      end

      word.to_i32!
    end

    # Write a partial word to a byte array (big-endian)
    def self.write_partial_word(word : Int32, bytes : Bytes, offset : Int32, bytes_available : Int32? = nil)
      available = bytes_available || [bytes.size - offset, 4].min
      w = word.to_u32!

      available.times do |i|
        if offset + i < bytes.size
          bytes[offset + i] = ((w >> (24 - i * 8)) & 0xFF).to_u8
        end
      end
    end

    # Read big-endian Int32 from bytes
    def self.read_int32_be(bytes : Bytes, offset : Int32) : Int32
      ((bytes[offset].to_u32 << 24) |
        (bytes[offset + 1].to_u32 << 16) |
        (bytes[offset + 2].to_u32 << 8) |
        bytes[offset + 3].to_u32).to_i32!
    end

    # Write big-endian Int32 to bytes
    def self.write_int32_be(bytes : Bytes, offset : Int32, value : Int32)
      v = value.to_u32!
      bytes[offset] = (v >> 24).to_u8
      bytes[offset + 1] = ((v >> 16) & 0xFF).to_u8
      bytes[offset + 2] = ((v >> 8) & 0xFF).to_u8
      bytes[offset + 3] = (v & 0xFF).to_u8
    end

    # Read platform-endian Int32 from bytes
    def self.read_int32_platform(bytes : Bytes, offset : Int32) : Int32
      io = IO::Memory.new(bytes[offset, 4])
      io.read_bytes(Int32, IO::ByteFormat::SystemEndian)
    end

    # Write platform-endian Int32 to bytes
    def self.write_int32_platform(bytes : Bytes, offset : Int32, value : Int32)
      io = IO::Memory.new(bytes[offset, 4])
      io.write_bytes(value, IO::ByteFormat::SystemEndian)
    end
  end
end
