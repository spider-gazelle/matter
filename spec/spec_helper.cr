require "spec"
require "../src/matter"

class MessageCodec
  include Matter::Codec::MessageCodec::Base

  def encode(message)
    encode_payload(message)
  end

  def decode(packet)
    decode_payload(packet)
  end
end

class DNSCodec
  include Matter::Codec::DNSCodec::Base

  def encode_message(message_type : Matter::Codec::DNSCodec::MessageType, transaction_id : UInt16, queries : Array(Matter::Codec::DNSCodec::Query) = [] of Matter::Codec::DNSCodec::Query, answers : Array(Matter::Codec::DNSCodec::Record) = [] of Matter::Codec::DNSCodec::Record, authorities : Array(Matter::Codec::DNSCodec::Record) = [] of Matter::Codec::DNSCodec::Record, additional_records : Array(Matter::Codec::DNSCodec::Record) = [] of Matter::Codec::DNSCodec::Record) : Matter::Codec::DNSCodec::Value
    encode(message_type, transaction_id, queries, answers, authorities, additional_records)
  end

  def decode_message(message)
    decode(message)
  end
end