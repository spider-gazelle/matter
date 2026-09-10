# Copyright 2022-2025 Matter.js Authors
# SPDX-License-Identifier: Apache-2.0
#
# Crystal port of matter.js AES-CCM mode
#
# NIST: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38c.pdf
# SJCL: https://github.com/bitwiseshiftleft/sjcl/blob/master/core/ccm.js
# OpenSSL: https://github.com/openssl/openssl/blob/master/crypto/modes/ccm128.c
#
# WARNING: Unaudited. Consider platform replacement if available.
#
# This AES-CCM implementation is tailored for Matter:
# * Only supports 2-byte length
# * Only supports 13-byte nonce
# * Stores the MIC in the ciphertext buffer following the ciphertext
# * Only 16-byte keys are legal

require "./aes"
require "./word_array"

module Matter::Crypto::AES
  # Matter-specific constants
  CRYPTO_AEAD_MIC_LENGTH_BYTES   = 16
  CRYPTO_AEAD_NONCE_LENGTH_BYTES = 13
  BYTES_IN_LENGTH                =  2 # NIST q parameter
  MAX_CIPHERTEXT_LENGTH          = 2 ** (BYTES_IN_LENGTH * 8)
  MAX_PLAINTEXT_LENGTH           = MAX_CIPHERTEXT_LENGTH - CRYPTO_AEAD_MIC_LENGTH_BYTES

  # AES-CCM implementation
  class Ccm
    @aes : Aes

    # Singleton buffers for temporary working data (reused to avoid GC)
    @computed_mic : WordArray
    @input_mic : WordArray
    @ctr_block : WordArray
    @temp_block1 : WordArray
    @temp_block2 : WordArray

    # Byte views of the buffers
    @computed_mic_bytes : Bytes
    @input_mic_bytes : Bytes
    @ctr_block_bytes : Bytes
    @temp_block1_bytes : Bytes
    @temp_block2_bytes : Bytes

    def initialize(key : Bytes)
      raise ArgumentError.new("AES-CCM key must be 16 bytes") unless key.size == 16

      @aes = Aes.new(key)

      # Allocate singleton buffers
      @computed_mic = WordArrayHelper.create(4)
      @input_mic = WordArrayHelper.create(4)
      @ctr_block = WordArrayHelper.create(4)
      @temp_block1 = WordArrayHelper.create(4)
      @temp_block2 = WordArrayHelper.create(4)

      # Create byte views (backed by the same memory)
      @computed_mic_bytes = Bytes.new(@computed_mic.to_unsafe.as(UInt8*), 16, read_only: false)
      @input_mic_bytes = Bytes.new(@input_mic.to_unsafe.as(UInt8*), 16, read_only: false)
      @ctr_block_bytes = Bytes.new(@ctr_block.to_unsafe.as(UInt8*), 16, read_only: false)
      @temp_block1_bytes = Bytes.new(@temp_block1.to_unsafe.as(UInt8*), 16, read_only: false)
      @temp_block2_bytes = Bytes.new(@temp_block2.to_unsafe.as(UInt8*), 16, read_only: false)
    end

    # Encrypt plaintext with optional additional authenticated data
    def encrypt(plaintext : Bytes, nonce : Bytes, aad : Bytes? = nil) : Bytes
      validate_nonce_and_aad(nonce, aad)

      pt_length = plaintext.size
      raise ArgumentError.new("Plaintext exceeds maximum length of #{MAX_PLAINTEXT_LENGTH}") if pt_length > MAX_PLAINTEXT_LENGTH

      # Allocate ciphertext output buffer (plaintext + tag)
      ct = Bytes.new(pt_length + CRYPTO_AEAD_MIC_LENGTH_BYTES)

      # Compute MIC using CBC-MAC
      cbc_mac(plaintext, nonce, aad, pt_length)

      # Encrypt using CTR mode
      ctr(plaintext, ct, nonce, pt_length, @computed_mic, @computed_mic_bytes, true)

      # Append encrypted MIC to ciphertext
      4.times do |i|
        WordArrayHelper.write_int32_be(ct, plaintext.size + i * 4, @computed_mic[i])
      end

      ct
    end

    # Decrypt ciphertext with optional additional authenticated data
    def decrypt(ciphertext : Bytes, nonce : Bytes, aad : Bytes? = nil) : Bytes
      validate_nonce_and_aad(nonce, aad)

      raise ArgumentError.new("Ciphertext exceeds maximum length") if ciphertext.size > MAX_CIPHERTEXT_LENGTH

      pt_length = ciphertext.size - CRYPTO_AEAD_MIC_LENGTH_BYTES
      raise ArgumentError.new("Ciphertext too short") if pt_length < 0

      # Extract MIC from ciphertext
      4.times do |i|
        @input_mic[i] = WordArrayHelper.read_int32_be(ciphertext, pt_length + i * 4)
      end

      # Allocate plaintext output buffer
      pt = Bytes.new(pt_length)

      # Decrypt using CTR mode (this also decrypts the MIC in place)
      ctr(ciphertext, pt, nonce, pt_length, @input_mic, @input_mic_bytes, false)

      # Compute expected MIC using CBC-MAC
      cbc_mac(pt, nonce, aad, pt_length)

      # Verify MIC matches
      4.times do |i|
        if @input_mic[i] != @computed_mic[i]
          raise Matter::AuthenticationError.new("Message authentication failed due to invalid signature")
        end
      end

      pt
    end

    # CBC-MAC MIC computation
    # Includes header generation then CBC-MAC passes on header, adata, and plaintext
    private def cbc_mac(pt : Bytes, nonce : Bytes, aad : Bytes?, pt_length : Int32)
      aad_length = aad ? aad.size : 0

      # Create the header: flag byte + nonce
      @computed_mic_bytes[0] = (((aad_length > 0 ? 1 : 0) << 6) |
                                ((CRYPTO_AEAD_MIC_LENGTH_BYTES - 2) << 2) |
                                (BYTES_IN_LENGTH - 1)).to_u8
      @computed_mic_bytes[1, nonce.size].copy_from(nonce)

      # Convert header to platform byte order
      WordArrayHelper.bytes_to_block(@computed_mic_bytes, @computed_mic)

      # Add plaintext length (in big-endian, last 2 bytes)
      @computed_mic[3] = (@computed_mic[3] & -0x10000) | pt_length

      # Start MAC computation (encrypt in place)
      @aes.encrypt(@computed_mic, @computed_mic)

      # Add additional authenticated data
      if aad_length > 0 && aad
        # Add length (2 bytes) + first 14 bytes of adata
        @temp_block1_bytes[0] = (aad_length >> 8).to_u8
        @temp_block1_bytes[1] = (aad_length & 0xFF).to_u8

        14.times do |i|
          @temp_block1_bytes[i + 2] = i < aad_length ? aad[i] : 0_u8
        end

        # Convert to word array and add
        WordArrayHelper.bytes_to_block(@temp_block1_bytes, @temp_block1)
        add_and_encrypt

        # Add remainder of adata
        if aad_length > 14
          i = 14
          while i < aad_length
            WordArrayHelper.bytes_to_block(aad, @temp_block1, i)
            add_and_encrypt
            i += 16
          end
        end
      end

      # Add plaintext
      if pt_length > 0
        i = 0
        while i < pt_length
          WordArrayHelper.bytes_to_block(pt, @temp_block1, i)
          add_and_encrypt
          i += 16
        end
      end
    end

    # XOR temp_block1 into computed_mic and encrypt
    private def add_and_encrypt
      @computed_mic[0] ^= @temp_block1[0]
      @computed_mic[1] ^= @temp_block1[1]
      @computed_mic[2] ^= @temp_block1[2]
      @computed_mic[3] ^= @temp_block1[3]
      @aes.encrypt(@computed_mic, @computed_mic)
    end

    # CTR mode encryption/decryption
    # Used for both encryption and decryption
    private def ctr(from_data : Bytes, to_data : Bytes, nonce : Bytes, data_length : Int32,
                    mic : WordArray, mic_bytes : Bytes, encrypting : Bool)
      # Initialize the counter (big endian)
      @ctr_block_bytes[0] = (BYTES_IN_LENGTH - 1).to_u8
      @ctr_block_bytes[1, 13].copy_from(nonce)
      @ctr_block_bytes[14] = 0_u8
      @ctr_block_bytes[15] = 0_u8

      # Convert to word array
      WordArrayHelper.bytes_to_block(@ctr_block_bytes, @ctr_block)

      # Encrypt the MIC
      @aes.encrypt(@ctr_block, @temp_block1)
      mic[0] ^= @temp_block1[0]
      mic[1] ^= @temp_block1[1]
      mic[2] ^= @temp_block1[2]
      mic[3] ^= @temp_block1[3]

      # Process the data
      i = 0
      while i < data_length
        @ctr_block[3] += 1

        # Convert input block to words
        WordArrayHelper.bytes_to_block(from_data, @temp_block1, i)

        # Encrypt counter
        @aes.encrypt(@ctr_block, @temp_block2)

        # XOR and copy to output
        4.times do |j|
          break if i >= data_length

          if i + 4 <= data_length
            # Full word
            result = @temp_block1[j] ^ @temp_block2[j]
            WordArrayHelper.write_int32_be(to_data, i, result)
          else
            # Partial word
            bytes_left = data_length - i
            bytes_left.times do |k|
              to_data[i + k] = (from_data[i + k].to_u32 ^ ((@temp_block2[j].to_u32! >> (24 - k * 8)) & 0xFF)).to_u8
            end
          end

          i += 4
        end
      end
    end

    private def validate_nonce_and_aad(nonce : Bytes, aad : Bytes?)
      raise ArgumentError.new("Nonce must be 13 bytes") unless nonce.size == CRYPTO_AEAD_NONCE_LENGTH_BYTES
      raise ArgumentError.new("AAD exceeds maximum length") if aad && aad.size > 0xFFFF
    end
  end
end
