# Copyright 2022-2025 Matter.js Authors
# SPDX-License-Identifier: Apache-2.0
#
# Crystal AES implementation using OpenSSL
#
# Uses OpenSSL's proven AES-128-ECB cipher for block operations

require "openssl"
require "./word_array"

module Matter::Crypto::AES
  # AES implementation using OpenSSL's proven cipher
  class Aes
    @key : Bytes

    def initialize(key : Bytes)
      raise ArgumentError.new("AES key must be 16 bytes") unless key.size == 16
      @key = key
    end

    # Encrypt a block (16 bytes represented as 4 words)
    # Operates on word array and returns encrypted word array
    def encrypt(pt : WordArray, ct : WordArray? = nil) : WordArray
      output = ct || WordArrayHelper.create(4)

      # Convert words to bytes
      pt_bytes = Bytes.new(16)
      4.times do |i|
        WordArrayHelper.write_int32_be(pt_bytes, i * 4, pt[i])
      end

      # Encrypt using OpenSSL
      cipher = OpenSSL::Cipher.new("aes-128-ecb")
      cipher.encrypt
      cipher.padding = false
      cipher.key = @key
      ct_bytes = cipher.update(pt_bytes) + cipher.final

      # Convert bytes back to words
      4.times do |i|
        output[i] = WordArrayHelper.read_int32_be(ct_bytes, i * 4)
      end

      output
    end

    # Decrypt a block (16 bytes represented as 4 words)
    def decrypt(ct : WordArray, pt : WordArray? = nil) : WordArray
      output = pt || WordArrayHelper.create(4)

      # Convert words to bytes
      ct_bytes = Bytes.new(16)
      4.times do |i|
        WordArrayHelper.write_int32_be(ct_bytes, i * 4, ct[i])
      end

      # Decrypt using OpenSSL
      cipher = OpenSSL::Cipher.new("aes-128-ecb")
      cipher.decrypt
      cipher.padding = false
      cipher.key = @key
      pt_bytes = cipher.update(ct_bytes) + cipher.final

      # Convert bytes back to words
      4.times do |i|
        output[i] = WordArrayHelper.read_int32_be(pt_bytes, i * 4)
      end

      output
    end
  end
end
