module Matter
  # Fixed-width hexadecimal formatting helpers.
  #
  # `u8`..`u64` produce the conventional `0x`-prefixed, zero-padded, lowercase
  # form used in logs and error messages. `node_id` produces the 16 uppercase
  # digit, unprefixed form mandated for mDNS operational instance names and
  # hostnames; `u16_upper` produces the 4 uppercase digit form used for the
  # VID/PID components of attestation certificate subjects.
  module Hex
    PREFIX = "0x"

    U8_DIGITS  =  2
    U16_DIGITS =  4
    U32_DIGITS =  8
    U64_DIGITS = 16

    # The value is padded to *at least* the width; wider values keep every digit.
    def self.u8(value : Int) : String
      prefixed(value, U8_DIGITS)
    end

    def self.u16(value : Int) : String
      prefixed(value, U16_DIGITS)
    end

    def self.u32(value : Int) : String
      prefixed(value, U32_DIGITS)
    end

    def self.u64(value : Int) : String
      prefixed(value, U64_DIGITS)
    end

    # 16 uppercase hex digits, no prefix: the mDNS instance/hostname form.
    def self.node_id(value : UInt64) : String
      digits(value, U64_DIGITS).upcase
    end

    # 4 uppercase hex digits, no prefix: the DAC/PAI subject VID/PID form.
    def self.u16_upper(value : UInt16) : String
      digits(value, U16_DIGITS).upcase
    end

    private def self.prefixed(value : Int, width : Int) : String
      PREFIX + digits(value, width)
    end

    private def self.digits(value : Int, width : Int) : String
      value.to_s(16).rjust(width, '0')
    end
  end
end
